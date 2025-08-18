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

  bool get voiceOnly => call!.voiceOnly && !call!.remote_has_video;

  String? get remoteIdentity => call!.remote_identity;

  Direction? get direction => call!.direction;

  Call? get call => widget._call;

  @override
  initState() {
    super.initState();
    _initRenderers();
    helper!.addSipUaHelperListener(this);
    _initProximitySensor();
    // Don't start timer immediately - wait for call to be answered
  }

  @override
  deactivate() {
    super.deactivate();
    
    print('🔄 CallScreen deactivating...');
    
    try {
      helper!.removeSipUaHelperListener(this);
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
      if (callState.audio!) _audioMuted = true;
      if (callState.video!) _videoMuted = true;
      setState(() {});
      return;
    }

    if (callState.state == CallStateEnum.UNMUTED) {
      if (callState.audio!) _audioMuted = false;
      if (callState.video!) _videoMuted = false;
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
        // Add call completion to history with duration
        final callDuration = _callConfirmed && _callStartTime > 0
            ? (DateTime.now().millisecondsSinceEpoch ~/ 1000) - _callStartTime
            : 0;
        
        if (callState.state == CallStateEnum.FAILED) {
          // Failed call
          CallHistoryManager.addCall(
            number: remoteIdentity ?? 'Unknown',
            type: CallType.failed,
            duration: callDuration,
          );
        } else if (!_callConfirmed && direction == Direction.incoming) {
          // Missed incoming call
          CallHistoryManager.addCall(
            number: remoteIdentity ?? 'Unknown',
            type: CallType.missed,
          );
        }
        // Note: Outgoing calls are already tracked when initiated
        // Incoming calls are tracked when confirmed
        
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
    if (_isNavigatingBack) {
      print('🚫 Already navigating back, skipping duplicate call');
      return;
    }
    
    print('🔙 Starting navigation back to dialpad...');
    _isNavigatingBack = true;
    
    try {
      _timer.cancel();
    } catch (e) {
      print('Error canceling timer in _backToDialPad: $e');
    }
    
    _cleanUp();
    
    // Shorter delay for better UX
    Timer(Duration(milliseconds: 800), () {
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
  }

  void _handleAccept() async {
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

    call!.answer(helper!.buildCallOptions(!remoteHasVideo),
        mediaStream: mediaStream);
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
    if (voiceOnly) {
      setState(() {
        call!.voiceOnly = false;
      });
      helper!.renegotiate(
          call: call!,
          voiceOnly: false,
          done: (IncomingMessage? incomingMessage) {});
    } else {
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
    final hangupBtn = ActionButton(
      title: "hangup",
      onPressed: () => _handleHangup(),
      icon: Icons.call_end,
      fillColor: Colors.red,
    );

    final hangupBtnInactive = ActionButton(
      title: "hangup",
      onPressed: () {},
      icon: Icons.call_end,
      fillColor: Colors.grey,
    );

    final basicActions = <Widget>[];
    final advanceActions = <Widget>[];
    final advanceActions2 = <Widget>[];

    switch (_state) {
      case CallStateEnum.NONE:
      case CallStateEnum.CONNECTING:
        if (direction == Direction.incoming) {
          basicActions.add(ActionButton(
            title: "Accept",
            fillColor: Colors.green,
            icon: Icons.phone,
            onPressed: () => _handleAccept(),
          ));
          basicActions.add(hangupBtn);
        } else {
          basicActions.add(hangupBtn);
        }
        break;
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        {
          advanceActions.add(ActionButton(
            title: _audioMuted ? 'unmute' : 'mute',
            icon: _audioMuted ? Icons.mic_off : Icons.mic,
            checked: _audioMuted,
            onPressed: () => _muteAudio(),
          ));

          if (voiceOnly) {
            advanceActions.add(ActionButton(
              title: "keypad",
              icon: Icons.dialpad,
              onPressed: () => _handleKeyPad(),
            ));
          } else {
            advanceActions.add(ActionButton(
              title: "switch camera",
              icon: Icons.switch_video,
              onPressed: () => _switchCamera(),
            ));
          }

          if (voiceOnly) {
            advanceActions.add(ActionButton(
              title: _speakerOn ? 'speaker off' : 'speaker on',
              icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
              checked: _speakerOn,
              fillColor: _speakerOn ? Colors.blue : null,
              onPressed: () => _toggleSpeaker(),
            ));
            advanceActions2.add(ActionButton(
              title: 'request video',
              icon: Icons.videocam,
              onPressed: () => _handleVideoUpgrade(),
            ));
          } else {
            advanceActions.add(ActionButton(
              title: _videoMuted ? "camera on" : 'camera off',
              icon: _videoMuted ? Icons.videocam : Icons.videocam_off,
              checked: _videoMuted,
              onPressed: () => _muteVideo(),
            ));
          }

          basicActions.add(ActionButton(
            title: _hold ? 'unhold' : 'hold',
            icon: _hold ? Icons.play_arrow : Icons.pause,
            checked: _hold,
            onPressed: () => _handleHold(),
          ));

          basicActions.add(hangupBtn);

          if (_showNumPad) {
            basicActions.add(ActionButton(
              title: "back",
              icon: Icons.keyboard_arrow_down,
              onPressed: () => _handleKeyPad(),
            ));
          } else {
            basicActions.add(ActionButton(
              title: "transfer",
              icon: Icons.phone_forwarded,
              onPressed: () => _handleTransfer(),
            ));
          }
        }
        break;
      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        basicActions.add(hangupBtnInactive);
        break;
      case CallStateEnum.PROGRESS:
        basicActions.add(hangupBtn);
        break;
      default:
        print('Other state => $_state');
        break;
    }

    final actionWidgets = <Widget>[];

    if (_showNumPad) {
      actionWidgets.addAll(_buildNumPad());
    } else {
      if (advanceActions2.isNotEmpty) {
        actionWidgets.add(
          Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: advanceActions2),
          ),
        );
      }
      if (advanceActions.isNotEmpty) {
        actionWidgets.add(
          Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: advanceActions),
          ),
        );
      }
    }

    actionWidgets.add(
      Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: basicActions),
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
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        (voiceOnly ? 'VOICE CALL' : 'VIDEO CALL') +
                            (_hold
                                ? ' PAUSED BY ${_holdOriginator!.name}'
                                : ''),
                        style: TextStyle(fontSize: 24, color: textColor),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        '$remoteIdentity',
                        style: TextStyle(fontSize: 18, color: textColor),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: ValueListenableBuilder<String>(
                        valueListenable: _timeLabel,
                        builder: (context, value, child) {
                          return Text(
                            _timeLabel.value,
                            style: TextStyle(fontSize: 14, color: textColor),
                          );
                        },
                      ),
                    ),
                  )
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('[$direction] ${_state.name}'),
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
                  event.reject!.call({'status_code': 607});
                  Navigator.of(context).pop();
                },
              ),
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  event.accept!.call({});
                  setState(() {
                    call!.voiceOnly = false;
                    _resizeLocalVideo();
                  });
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
