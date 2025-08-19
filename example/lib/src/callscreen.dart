import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'package:flutter/services.dart';

import 'widgets/action_button.dart';
import 'recent_calls.dart';

class CallScreenWidget extends StatefulWidget {
  final SIPUAHelper? _helper;
  final Call? _call;

  CallScreenWidget(this._helper, this._call, {Key? key}) : super(key: key);

  @override
  State<CallScreenWidget> createState() => _MyCallScreenWidget();
}

class _MyCallScreenWidget extends State<CallScreenWidget>
    implements SipUaHelperListener {
  RTCVideoRenderer? _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer? _remoteRenderer = RTCVideoRenderer();
  double? _localVideoHeight;
  double? _localVideoWidth;
  EdgeInsetsGeometry? _localVideoMargin;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _showNumPad = false;
  final ValueNotifier<String> _timeLabel = ValueNotifier<String>('00:00');
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _speakerOn = false;
  bool _hold = false;
  bool _mirror = true;
  Originator? _holdOriginator;
  bool _callConfirmed = false;
  CallStateEnum _state = CallStateEnum.NONE;
  int _callStartTime = 0;
  StreamSubscription<int>? _proximitySubscription;
  bool _isProximitySensorEnabled = false;
  bool _isNavigatingBack = false;

  late String _transferTarget;
  late Timer _timer;

  SIPUAHelper? get helper => widget._helper;

  bool get voiceOnly => call?.voiceOnly == true && call?.remote_has_video != true;

  String? get remoteIdentity => call?.remote_identity;

  Direction? get direction => call?.direction;

  Call? get call => widget._call;

  @override
  initState() {
    super.initState();
    _initRenderers();
    if (helper != null) {
      helper!.addSipUaHelperListener(this);
    }
    _initProximitySensor();
    // Don't start timer immediately - wait for call to be answered
  }

  @override
  deactivate() {
    super.deactivate();
    
    print('🔄 CallScreen deactivating...');
    
    try {
      if (helper != null) {
        helper!.removeSipUaHelperListener(this);
      }
    } catch (e) {
      print('Error removing SIP listener: $e');
    }
    
    try {
      _timer.cancel();
    } catch (e) {
      print('Error canceling timer in deactivate: $e');
    }
    
    try {
      _proximitySubscription?.cancel();
      _proximitySubscription = null;
      // Restore normal screen behavior
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      print('✅ Proximity sensor cleaned up');
    } catch (e) {
      print('Error cleaning up proximity sensor: $e');
    }
    
    try {
      _disposeRenderers();
    } catch (e) {
      print('Error disposing renderers: $e');
    }
    
    _cleanUp();
    print('✅ CallScreen deactivation complete');
  }

  void _initProximitySensor() {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android)) {
      try {
        print('🔍 Initializing proximity sensor...');
        _proximitySubscription = ProximitySensor.events.listen((int proximityValue) {
          // proximityValue: 0 = near (close to ear), 1 = far (away from ear)
          final isNear = proximityValue == 0;
          print('📱 Proximity sensor: ${isNear ? 'NEAR (screen off)' : 'FAR (screen on)'}');
          
          if (mounted && _callConfirmed) { // Only control screen during active call
            setState(() {
              _isProximitySensorEnabled = isNear;
            });
            
            // Control screen visibility based on proximity
            if (isNear) {
              // Hide UI when phone is near ear
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
            } else {
              // Show UI when phone is away from ear
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
            }
          }
        });
        print('✅ Proximity sensor initialized');
      } catch (e) {
        print('❌ Error initializing proximity sensor: $e');
      }
    } else {
      print('⚠️ Proximity sensor not supported on this platform');
    }
  }

  void _startTimer() {
    try {
      _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
        try {
          Duration duration = Duration(seconds: timer.tick);
          if (mounted) {
            _timeLabel.value = [duration.inMinutes, duration.inSeconds]
                .map((seg) => seg.remainder(60).toString().padLeft(2, '0'))
                .join(':');
          } else {
            timer.cancel();
          }
        } catch (e) {
          print('Error in timer tick: $e');
          timer.cancel();
        }
      });
    } catch (e) {
      print('Error starting timer: $e');
    }
  }

  void _initRenderers() async {
    if (_localRenderer != null) {
      await _localRenderer!.initialize();
    }
    if (_remoteRenderer != null) {
      await _remoteRenderer!.initialize();
    }
  }

  void _disposeRenderers() {
    try {
      if (_localRenderer != null) {
        _localRenderer!.dispose();
        _localRenderer = null;
      }
    } catch (e) {
      print('Error disposing local renderer: $e');
    }
    
    try {
      if (_remoteRenderer != null) {
        _remoteRenderer!.dispose();
        _remoteRenderer = null;
      }
    } catch (e) {
      print('Error disposing remote renderer: $e');
    }
  }

  @override
  void callStateChanged(Call call, CallState callState) {
    if (callState.state == CallStateEnum.HOLD ||
        callState.state == CallStateEnum.UNHOLD) {
      _hold = callState.state == CallStateEnum.HOLD;
      _holdOriginator = callState.originator;
      setState(() {});
      return;
    }

    if (callState.state == CallStateEnum.MUTED) {
      if (callState.audio == true) _audioMuted = true;
      if (callState.video == true) _videoMuted = true;
      setState(() {});
      return;
    }

    if (callState.state == CallStateEnum.UNMUTED) {
      if (callState.audio == true) _audioMuted = false;
      if (callState.video == true) _videoMuted = false;
      setState(() {});
      return;
    }

    if (callState.state != CallStateEnum.STREAM) {
      _state = callState.state;
    }

    switch (callState.state) {
      case CallStateEnum.STREAM:
        _handleStreams(callState);
        break;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        print('🔥🔥🔥 CALL ${callState.state} - Starting hangup process 🔥🔥🔥');
        
        // Add call completion to history with duration
        final callDuration = _callConfirmed && _callStartTime > 0
            ? (DateTime.now().millisecondsSinceEpoch ~/ 1000) - _callStartTime
            : 0;
        
        print('📊 Call duration: ${callDuration}s, confirmed: $_callConfirmed');
        
        if (callState.state == CallStateEnum.FAILED) {
          print('❌ Call failed - adding to history');
          // Failed call
          CallHistoryManager.addCall(
            number: remoteIdentity ?? 'Unknown',
            type: CallType.failed,
            duration: callDuration,
          );
        } else if (!_callConfirmed && direction == Direction.incoming) {
          print('📞 Missed incoming call - adding to history');
          // Missed incoming call
          CallHistoryManager.addCall(
            number: remoteIdentity ?? 'Unknown',
            type: CallType.missed,
          );
        }
        // Note: Outgoing calls are already tracked when initiated
        // Incoming calls are tracked when confirmed
        
        print('🔙 About to call _backToDialPad()...');
        _backToDialPad();
        break;
      case CallStateEnum.UNMUTED:
      case CallStateEnum.MUTED:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.PROGRESS:
      case CallStateEnum.ACCEPTED:
        break;
      case CallStateEnum.CONFIRMED:
        if (!_callConfirmed) {
          print('📞 Call confirmed - starting timer');
          setState(() => _callConfirmed = true);
          _callStartTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          _startTimer(); // Start timer only when call is actually answered
          
          // Add incoming call to history if this is an incoming call
          if (direction == Direction.incoming) {
            CallHistoryManager.addCall(
              number: remoteIdentity ?? 'Unknown',
              type: CallType.incoming,
            );
          }
        }
        break;
      case CallStateEnum.HOLD:
      case CallStateEnum.UNHOLD:
      case CallStateEnum.NONE:
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.REFER:
        break;
    }
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void registrationStateChanged(RegistrationState state) {}

  void _cleanUp() {
    try {
      if (_localStream != null) {
        _localStream?.getTracks().forEach((track) {
          try {
            track.stop();
          } catch (e) {
            print('Error stopping track: $e');
          }
        });
        
        try {
          _localStream!.dispose();
        } catch (e) {
          print('Error disposing stream: $e');
        }
        
        _localStream = null;
      }
    } catch (e) {
      print('Error in cleanup: $e');
    }
  }

  void _backToDialPad() {
    print('🔙🔙🔙 _backToDialPad() called 🔙🔙🔙');
    
    if (_isNavigatingBack) {
      print('🚫 Already navigating back, skipping duplicate call');
      return;
    }
    
    print('🔙 Starting navigation back to dialpad...');
    print('📊 Current state: mounted=$mounted, navigating=$_isNavigatingBack');
    _isNavigatingBack = true;
    
    try {
      _timer.cancel();
      print('⏰ Timer canceled successfully');
    } catch (e) {
      print('Error canceling timer in _backToDialPad: $e');
    }
    
    print('🧹 Calling _cleanUp()...');
    _cleanUp();
    print('✅ _cleanUp() completed');
    
    // Shorter delay for better UX
    print('⏰ Setting up 800ms delay timer for navigation...');
    Timer(Duration(milliseconds: 800), () {
      print('🔔 Navigation timer triggered!');
      print('📊 Timer check: mounted=$mounted, navigating=$_isNavigatingBack');
      
      try {
        if (mounted && _isNavigatingBack) {
          print('🔙 Executing navigation back to dialpad');
          Navigator.of(context).pop();
          print('✅ Successfully navigated back');
        } else {
          print('⚠️ Skipping navigation: mounted=$mounted, navigating=$_isNavigatingBack');
        }
      } catch (e) {
        print('❌ Error navigating back: $e');
        // Try to force navigation if regular pop fails
        try {
          if (mounted) {
            print('🚨 Trying force navigation with popUntil...');
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        } catch (e2) {
          print('❌ Emergency navigation also failed: $e2');
        }
      }
    });
  }

  void _handleStreams(CallState event) async {
    MediaStream? stream = event.stream;
    if (event.originator == Originator.local) {
      if (_localRenderer != null) {
        _localRenderer!.srcObject = stream;
      }

      if (!kIsWeb &&
          !WebRTC.platformIsDesktop &&
          event.stream?.getAudioTracks().isNotEmpty == true) {
        event.stream?.getAudioTracks().first.enableSpeakerphone(_speakerOn);
      }
      _localStream = stream;
    }
    if (event.originator == Originator.remote) {
      if (_remoteRenderer != null) {
        _remoteRenderer!.srcObject = stream;
      }
      _remoteStream = stream;
    }

    setState(() {
      _resizeLocalVideo();
    });
  }

  void _resizeLocalVideo() {
    _localVideoMargin = _remoteStream != null
        ? EdgeInsets.only(top: 15, right: 15)
        : EdgeInsets.all(0);
    _localVideoWidth = _remoteStream != null
        ? MediaQuery.of(context).size.width / 4
        : MediaQuery.of(context).size.width;
    _localVideoHeight = _remoteStream != null
        ? MediaQuery.of(context).size.height / 4
        : MediaQuery.of(context).size.height;
  }

  void _handleHangup() {
    print('📞 Hanging up call...');
    
    // Cancel timer first
    try {
      if (_timer.isActive) {
        _timer.cancel();
        print('✅ Timer canceled');
      }
    } catch (e) {
      print('❌ Error canceling timer: $e');
    }
    
    // Stop media streams before hanging up
    try {
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
        });
        _localStream = null;
        print('✅ Local stream stopped');
      }
      
      if (_remoteStream != null) {
        _remoteStream!.getTracks().forEach((track) {
          track.stop();
        });
        _remoteStream = null;
        print('✅ Remote stream stopped');
      }
    } catch (e) {
      print('❌ Error stopping streams: $e');
    }
    
    // Hangup the call
    try {
      if (call != null) {
        call!.hangup({'status_code': 603});
        print('✅ Call hangup request sent');
      }
    } catch (e) {
      print('❌ Error during hangup: $e');
    }
    
    // Let the call state change handler manage navigation back
    print('📞 Hangup initiated - waiting for call state change to handle navigation');
    
    // Add backup navigation in case call state change doesn't trigger
    Timer(Duration(seconds: 2), () {
      if (mounted && !_isNavigatingBack) {
        print('⏰ Backup navigation triggered - call state event may not have fired');
        print('🚨 Forcing navigation back to dialpad after 2 seconds');
        _backToDialPad();
      } else {
        print('✅ Normal navigation already handled or widget unmounted');
      }
    });
  }

  void _handleAccept() async {
    if (call == null) {
      print('❌ Cannot accept call - call object is null');
      return;
    }
    
    bool remoteHasVideo = call!.remote_has_video;
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': remoteHasVideo
          ? {
              'mandatory': <String, dynamic>{
                'minWidth': '640',
                'minHeight': '480',
                'minFrameRate': '30',
              },
              'facingMode': 'user',
              'optional': <dynamic>[],
            }
          : false
    };
    MediaStream mediaStream;

    if (kIsWeb && remoteHasVideo) {
      mediaStream =
          await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      MediaStream userStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      mediaStream.addTrack(userStream.getAudioTracks()[0], addToNative: true);
    } else {
      if (!remoteHasVideo) {
        mediaConstraints['video'] = false;
      }
      mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    }

    if (call != null && helper != null) {
      call!.answer(helper!.buildCallOptions(!remoteHasVideo),
          mediaStream: mediaStream);
    }
  }

  void _switchCamera() {
    if (_localStream != null) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
      setState(() {
        _mirror = !_mirror;
      });
    }
  }

  void _muteAudio() {
    print('🎤 Toggling mute: ${_audioMuted ? 'UNMUTING' : 'MUTING'}');
    
    try {
      if (_audioMuted) {
        // Unmute
        call!.unmute(true, false);
        setState(() {
          _audioMuted = false;
        });
        
        // Also enable audio tracks directly
        if (_localStream != null) {
          for (final track in _localStream!.getAudioTracks()) {
            track.enabled = true;
            print('✅ Enabled audio track: ${track.id}');
          }
        }
      } else {
        // Mute
        call!.mute(true, false);
        setState(() {
          _audioMuted = true;
        });
        
        // Also disable audio tracks directly
        if (_localStream != null) {
          for (final track in _localStream!.getAudioTracks()) {
            track.enabled = false;
            print('✅ Disabled audio track: ${track.id}');
          }
        }
      }
      print('🎤 Mute state changed to: ${_audioMuted ? 'MUTED' : 'UNMUTED'}');
    } catch (e) {
      print('❌ Error toggling mute: $e');
    }
  }

  void _muteVideo() {
    if (_videoMuted) {
      call!.unmute(false, true);
    } else {
      call!.mute(false, true);
    }
  }

  void _handleHold() {
    if (_hold) {
      call!.unhold();
    } else {
      call!.hold();
    }
  }

  void _handleTransfer() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Enter target to transfer.'),
          content: TextField(
            onChanged: (String text) {
              setState(() {
                _transferTarget = text;
              });
            },
            decoration: InputDecoration(
              hintText: 'URI or Username',
            ),
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Ok'),
              onPressed: () {
                call!.refer(_transferTarget);
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _handleDtmf(String tone) {
    print('Dtmf tone => $tone');
    call!.sendDTMF(tone);
  }

  void _handleKeyPad() {
    setState(() {
      _showNumPad = !_showNumPad;
    });
  }

  void _handleVideoUpgrade() {
    if (voiceOnly && call != null && helper != null) {
      setState(() {
        call!.voiceOnly = false;
      });
      helper!.renegotiate(
          call: call!,
          voiceOnly: false,
          done: (IncomingMessage? incomingMessage) {});
    } else if (call != null && helper != null) {
      helper!.renegotiate(
          call: call!,
          voiceOnly: true,
          done: (IncomingMessage? incomingMessage) {});
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
    });
    
    print('🔊 Toggling speaker: ${_speakerOn ? 'ON' : 'OFF'}');
    
    // Enable speaker on all available audio tracks
    final audioTracks = <MediaStreamTrack>[];
    
    // Collect all audio tracks
    if (_localStream != null) {
      audioTracks.addAll(_localStream!.getAudioTracks());
    }
    if (_remoteStream != null) {
      audioTracks.addAll(_remoteStream!.getAudioTracks());
    }
    
    // Apply speaker setting to all audio tracks
    for (final track in audioTracks) {
      try {
        if (!kIsWeb && !WebRTC.platformIsDesktop) {
          track.enableSpeakerphone(_speakerOn);
          print('✅ Applied speaker setting to track: ${track.id}');
        }
      } catch (e) {
        print('❌ Error toggling speaker on track ${track.id}: $e');
      }
    }
    
    // Additional iOS-specific audio session management
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        // Use WebRTC's native audio session management
        Helper.setSpeakerphoneOn(_speakerOn);
        print('✅ iOS speaker setting applied via Helper.setSpeakerphoneOn');
      } catch (e) {
        print('❌ Error with Helper.setSpeakerphoneOn: $e');
      }
    }
  }

  List<Widget> _buildNumPad() {
    final labels = [
      [
        {'1': ''},
        {'2': 'abc'},
        {'3': 'def'}
      ],
      [
        {'4': 'ghi'},
        {'5': 'jkl'},
        {'6': 'mno'}
      ],
      [
        {'7': 'pqrs'},
        {'8': 'tuv'},
        {'9': 'wxyz'}
      ],
      [
        {'*': ''},
        {'0': '+'},
        {'#': ''}
      ],
    ];

    return labels
        .map((row) => Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .map((label) => ActionButton(
                          title: label.keys.first,
                          subTitle: label.values.first,
                          onPressed: () => _handleDtmf(label.keys.first),
                          number: true,
                        ))
                    .toList())))
        .toList();
  }

  Widget _buildActionButtons() {
    final hangupBtn = AnimatedContainer(
      duration: Duration(milliseconds: 200),
      child: ActionButton(
        title: "End Call",
        onPressed: () => _handleHangup(),
        icon: Icons.call_end,
        fillColor: Colors.red.shade600,
      ),
    );

    final hangupBtnInactive = AnimatedContainer(
      duration: Duration(milliseconds: 200),
      child: ActionButton(
        title: "Call Ended",
        onPressed: () {},
        icon: Icons.call_end,
        fillColor: Colors.grey.shade400,
      ),
    );

    final basicActions = <Widget>[];
    final advanceActions = <Widget>[];
    final advanceActions2 = <Widget>[];

    switch (_state) {
      case CallStateEnum.NONE:
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.PROGRESS:
        if (direction == Direction.incoming) {
          // Incoming call - show Accept and Decline buttons
          basicActions.add(AnimatedScale(
            scale: 1.0,
            duration: Duration(milliseconds: 300),
            child: ActionButton(
              title: "Accept",
              fillColor: Colors.green.shade600,
              icon: Icons.phone_rounded,
              onPressed: () => _handleAccept(),
            ),
          ));
          basicActions.add(AnimatedScale(
            scale: 1.0,
            duration: Duration(milliseconds: 300),
            child: ActionButton(
              title: "Decline",
              fillColor: Colors.red.shade600,
              icon: Icons.call_end,
              onPressed: () => _handleHangup(),
            ),
          ));
        } else {
          // Outgoing call - show only End Call button
          basicActions.add(AnimatedScale(
            scale: 1.0,
            duration: Duration(milliseconds: 300),
            child: hangupBtn,
          ));
        }
        break;
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        {
          // Audio controls with smooth animations
          advanceActions.add(AnimatedSwitcher(
            duration: Duration(milliseconds: 250),
            child: ActionButton(
              key: ValueKey('mute_$_audioMuted'),
              title: _audioMuted ? 'Unmute' : 'Mute',
              icon: _audioMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              checked: _audioMuted,
              fillColor: _audioMuted ? Colors.red.shade400 : null,
              onPressed: () => _muteAudio(),
            ),
          ));

          if (voiceOnly) {
            // Keypad button for voice calls
            advanceActions.add(AnimatedContainer(
              duration: Duration(milliseconds: 200),
              child: ActionButton(
                title: "Keypad",
                icon: Icons.dialpad_rounded,
                checked: _showNumPad,
                fillColor: _showNumPad ? Colors.blue.shade400 : null,
                onPressed: () => _handleKeyPad(),
              ),
            ));
          } else {
            // Camera switch for video calls
            advanceActions.add(AnimatedContainer(
              duration: Duration(milliseconds: 200),
              child: ActionButton(
                title: "Switch Camera",
                icon: Icons.switch_camera_rounded,
                onPressed: () => _switchCamera(),
              ),
            ));
          }

          if (voiceOnly) {
            // Speaker controls for voice calls
            advanceActions.add(AnimatedSwitcher(
              duration: Duration(milliseconds: 250),
              child: ActionButton(
                key: ValueKey('speaker_$_speakerOn'),
                title: _speakerOn ? 'Speaker Off' : 'Speaker On',
                icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                checked: _speakerOn,
                fillColor: _speakerOn ? Colors.blue.shade400 : null,
                onPressed: () => _toggleSpeaker(),
              ),
            ));
            
            // Video request button
            advanceActions2.add(AnimatedContainer(
              duration: Duration(milliseconds: 200),
              child: ActionButton(
                title: 'Enable Video',
                icon: Icons.videocam_rounded,
                onPressed: () => _handleVideoUpgrade(),
              ),
            ));
          } else {
            // Video mute controls for video calls
            advanceActions.add(AnimatedSwitcher(
              duration: Duration(milliseconds: 250),
              child: ActionButton(
                key: ValueKey('video_$_videoMuted'),
                title: _videoMuted ? "Camera On" : 'Camera Off',
                icon: _videoMuted ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                checked: _videoMuted,
                fillColor: _videoMuted ? Colors.red.shade400 : null,
                onPressed: () => _muteVideo(),
              ),
            ));
          }

          // Hold/Resume button
          basicActions.add(AnimatedSwitcher(
            duration: Duration(milliseconds: 250),
            child: ActionButton(
              key: ValueKey('hold_$_hold'),
              title: _hold ? 'Resume' : 'Hold',
              icon: _hold ? Icons.play_arrow_rounded : Icons.pause_rounded,
              checked: _hold,
              fillColor: _hold ? Colors.orange.shade400 : null,
              onPressed: () => _handleHold(),
            ),
          ));

          basicActions.add(hangupBtn);

          if (_showNumPad) {
            basicActions.add(AnimatedContainer(
              duration: Duration(milliseconds: 200),
              child: ActionButton(
                title: "Hide Keypad",
                icon: Icons.keyboard_arrow_down_rounded,
                onPressed: () => _handleKeyPad(),
              ),
            ));
          } else {
            basicActions.add(AnimatedContainer(
              duration: Duration(milliseconds: 200),
              child: ActionButton(
                title: "Transfer",
                icon: Icons.phone_forwarded_rounded,
                onPressed: () => _handleTransfer(),
              ),
            ));
          }
        }
        break;
      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        basicActions.add(hangupBtnInactive);
        // Add manual back button as safety measure
        basicActions.add(AnimatedContainer(
          duration: Duration(milliseconds: 300),
          child: ActionButton(
            title: "Back to Dialpad",
            icon: Icons.arrow_back_rounded,
            fillColor: Colors.blue.shade600,
            onPressed: () {
              print('🔙 Manual "Back to Dialpad" button pressed');
              _backToDialPad();
            },
          ),
        ));
        break;
      default:
        print('Other state => $_state');
        break;
    }

    final actionWidgets = <Widget>[];

    if (_showNumPad) {
      actionWidgets.add(
        AnimatedSwitcher(
          duration: Duration(milliseconds: 400),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, 0.3),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              )),
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: Column(
            key: ValueKey('numpad'),
            children: _buildNumPad(),
          ),
        ),
      );
    } else {
      actionWidgets.add(
        AnimatedSwitcher(
          duration: Duration(milliseconds: 300),
          child: Column(
            key: ValueKey('controls'),
            children: [
              if (advanceActions2.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: advanceActions2.map((action) => 
                      AnimatedScale(
                        scale: 1.0,
                        duration: Duration(milliseconds: 150),
                        child: action,
                      )
                    ).toList(),
                  ),
                ),
              ],
              if (advanceActions.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: advanceActions.map((action) => 
                      AnimatedScale(
                        scale: 1.0,
                        duration: Duration(milliseconds: 150),
                        child: action,
                      )
                    ).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    actionWidgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: basicActions.map((action) => 
            AnimatedScale(
              scale: 1.0,
              duration: Duration(milliseconds: 150),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: action,
              ),
            )
          ).toList(),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.end,
      children: actionWidgets,
    );
  }

  Widget _buildContent() {
    Color? textColor = Theme.of(context).textTheme.bodyMedium?.color;
    final stackWidgets = <Widget>[];

    if (!voiceOnly && _remoteStream != null) {
      stackWidgets.add(
        Center(
          child: RTCVideoView(
            _remoteRenderer!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
      );
    }

    if (!voiceOnly && _localStream != null) {
      stackWidgets.add(
        AnimatedContainer(
          child: RTCVideoView(
            _localRenderer!,
            mirror: _mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
          height: _localVideoHeight,
          width: _localVideoWidth,
          alignment: Alignment.topRight,
          duration: Duration(milliseconds: 300),
          margin: _localVideoMargin,
        ),
      );
    }
    if (voiceOnly || !_callConfirmed) {
      stackWidgets.addAll(
        [
          Positioned(
            top: MediaQuery.of(context).size.height / 8,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  AnimatedContainer(
                    duration: Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: _hold 
                          ? Colors.orange.withValues(alpha: 0.2)
                          : _state == CallStateEnum.CONFIRMED
                              ? Colors.green.withValues(alpha: 0.1) 
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedSwitcher(
                      duration: Duration(milliseconds: 300),
                      child: Text(
                        _hold 
                            ? 'CALL PAUSED BY ${_holdOriginator?.name ?? 'UNKNOWN'}'
                            : voiceOnly 
                                ? 'VOICE CALL' 
                                : 'VIDEO CALL',
                        key: ValueKey('${_hold}_$voiceOnly'),
                        style: TextStyle(
                          fontSize: _hold ? 18 : 22,
                          fontWeight: FontWeight.w600,
                          color: _hold 
                              ? Colors.orange.shade700
                              : _state == CallStateEnum.CONFIRMED
                                  ? Colors.green.shade700
                                  : textColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  // Call state subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      _getCallStateSubtitle(),
                      style: TextStyle(
                        fontSize: 16,
                        color: textColor?.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  
                  // Remote identity with better formatting
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      remoteIdentity ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Timer - only show when call is confirmed
                  if (_callConfirmed) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: ValueListenableBuilder<String>(
                        valueListenable: _timeLabel,
                        builder: (context, value, child) {
                          return Text(
                            _timeLabel.value,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    // Show call state for non-confirmed calls
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _getCallStateColor().withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getCallStateDisplayText(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _getCallStateColor(),
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: stackWidgets,
    );
  }

  String _getCallStateTitle() {
    switch (_state) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
        return direction == Direction.incoming ? 'Incoming Call' : 'Calling...';
      case CallStateEnum.PROGRESS:
        return direction == Direction.incoming ? 'Ringing...' : 'Connecting...';
      case CallStateEnum.ACCEPTED:
        return 'Call Connected';
      case CallStateEnum.CONFIRMED:
        return _hold ? 'Call on Hold' : 'Call Active';
      case CallStateEnum.ENDED:
        return 'Call Ended';
      case CallStateEnum.FAILED:
        return 'Call Failed';
      default:
        return 'Call';
    }
  }

  String _getCallStateSubtitle() {
    switch (_state) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
        return direction == Direction.incoming ? 'Incoming call from' : 'Calling';
      case CallStateEnum.PROGRESS:
        return direction == Direction.incoming ? 'Call ringing' : 'Connecting to';
      case CallStateEnum.ACCEPTED:
        return 'Call connected with';
      case CallStateEnum.CONFIRMED:
        return _hold ? 'Call on hold with' : 'In call with';
      case CallStateEnum.ENDED:
        return 'Call ended with';
      case CallStateEnum.FAILED:
        return 'Call failed to';
      default:
        return '';
    }
  }

  String _getCallStateDisplayText() {
    switch (_state) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
        return direction == Direction.incoming ? 'Incoming...' : 'Calling...';
      case CallStateEnum.PROGRESS:
        return direction == Direction.incoming ? 'Ringing...' : 'Ringing...';
      case CallStateEnum.ACCEPTED:
        return 'Connected';
      case CallStateEnum.CONFIRMED:
        return _hold ? 'On Hold' : 'Active';
      case CallStateEnum.ENDED:
        return 'Ended';
      case CallStateEnum.FAILED:
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  Color _getCallStateColor() {
    switch (_state) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
        return direction == Direction.incoming ? Colors.blue : Colors.orange;
      case CallStateEnum.PROGRESS:
        return Colors.blue;
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        return _hold ? Colors.orange : Colors.green;
      case CallStateEnum.ENDED:
        return Colors.grey;
      case CallStateEnum.FAILED:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: AnimatedSwitcher(
          duration: Duration(milliseconds: 300),
          child: Text(
            _getCallStateTitle(),
            key: ValueKey(_state.name),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
        backgroundColor: _hold 
            ? Colors.orange.shade700
            : _state == CallStateEnum.CONFIRMED 
                ? Colors.green.shade700 
                : null,
        actions: [
          if (call != null || helper != null)
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () => _backToDialPad(),
              tooltip: 'End Call',
            ),
        ],
      ),
      body: _buildContent(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: 320,
        padding: EdgeInsets.only(bottom: 24.0),
        child: _buildActionButtons(),
      ),
    );
  }

  @override
  void onNewReinvite(ReInvite event) {
    if (event.accept == null) return;
    if (event.reject == null) return;
    if (voiceOnly && (event.hasVideo ?? false)) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Upgrade to video?'),
            content: Text('$remoteIdentity is inviting you to video call'),
            alignment: Alignment.center,
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  if (event.reject != null) {
                    event.reject!.call({'status_code': 607});
                  }
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  if (event.accept != null) {
                    event.accept!.call({});
                  }
                  if (call != null) {
                    setState(() {
                      call!.voiceOnly = false;
                    });
                    _resizeLocalVideo();
                  }
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    // NO OP
  }

  @override
  void onNewNotify(Notify ntf) {
    // NO OP
  }
}
