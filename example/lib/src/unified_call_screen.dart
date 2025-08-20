import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

import 'widgets/action_button.dart';
import 'persistent_background_service.dart';

/// Unified call screen with all call states and controls in one place
/// Audio-only calls with state-based UI changes
class UnifiedCallScreen extends StatefulWidget {
  final SIPUAHelper? helper;
  final Call? call;

  const UnifiedCallScreen({
    Key? key,
    required this.helper,
    required this.call,
  }) : super(key: key);

  @override
  State<UnifiedCallScreen> createState() => _UnifiedCallScreenState();
}

class _UnifiedCallScreenState extends State<UnifiedCallScreen>
    implements SipUaHelperListener {
  // Call state management
  CallStateEnum _callState = CallStateEnum.NONE;
  bool _callConfirmed = false;
  int _callStartTime = 0;
  final ValueNotifier<String> _timeLabel = ValueNotifier<String>('00:00');
  Timer? _timer;
  bool _isNavigatingBack = false;

  // Audio controls
  bool _audioMuted = false;
  bool _speakerOn = false;
  bool _hold = false;
  Originator? _holdOriginator;

  // UI state
  bool _showKeypad = false;
  String _dtmfInput = '';

  // Proximity sensor
  StreamSubscription<int>? _proximitySubscription;

  // Getters
  SIPUAHelper? get helper => widget.helper;
  Call? get call => widget.call;
  String? get remoteIdentity => call?.remote_identity;
  Direction? get direction => call?.direction;

  @override
  void initState() {
    super.initState();
    _initializeCallScreen();
  }

  void _initializeCallScreen() {
    // Check if we need to use the background service's SIP helper for this call
    final backgroundHelper = PersistentBackgroundService.getBackgroundSipHelper();
    final activeCall = PersistentBackgroundService.getActiveCall();
    
    if (call != null && activeCall != null && call!.id == activeCall.id && backgroundHelper != null) {
      print('🔄 Using background SIP helper for active call: ${call!.id}');
      // Use the background service's SIP helper instead of the main app's
      try {
        backgroundHelper.addSipUaHelperListener(this);
        print('✅ Added listener to background SIP helper');
      } catch (e) {
        print('⚠️ Warning: Could not add listener to background helper: $e');
        // Fall back to main helper if available
        if (helper != null) {
          helper!.addSipUaHelperListener(this);
        }
      }
      PersistentBackgroundService.transferCallToMainApp();
    } else if (helper != null) {
      helper!.addSipUaHelperListener(this);
    }

    if (call != null) {
      _callState = call!.state;
      print('📞 Initial call state: $_callState');
      print('📞 Call source: ${call!.direction == Direction.incoming ? 'Incoming' : 'Outgoing'}');
      
      // If this is an incoming call that's already answered by background service,
      // update the state and start timer
      if (call!.direction == Direction.incoming && 
          (_callState == CallStateEnum.ACCEPTED || _callState == CallStateEnum.CONFIRMED)) {
        print('🔄 Taking over background-accepted call');
        _callConfirmed = true;
        _startTimer();
      }
    } else {
      print('⚠️ No call object provided to UnifiedCallScreen');
    }

    _initProximitySensor();
    print('🔊 Unified Call Screen initialized for ${remoteIdentity ?? 'Unknown'}');
    print('🔊 Call direction: $direction, State: $_callState');
  }

  void _initProximitySensor() {
    try {
      _proximitySubscription = ProximitySensor.events.listen((int event) {
        if (event > 0) {
          // Screen should turn off (proximity detected)
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
        } else {
          // Screen should turn on (no proximity)
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
        }
      });
    } catch (e) {
      print('❌ Proximity sensor not available: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
    _cleanup();
  }

  void _cleanup() {
    try {
      if (helper != null) {
        helper!.removeSipUaHelperListener(this);
      }
    } catch (e) {
      print('❌ Error removing SIP listener: $e');
    }

    try {
      _timer?.cancel();
    } catch (e) {
      print('❌ Error canceling timer: $e');
    }

    try {
      _proximitySubscription?.cancel();
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    } catch (e) {
      print('❌ Error cleaning up proximity sensor: $e');
    }
  }

  // Timer management
  void _startTimer() {
    _callStartTime = DateTime.now().millisecondsSinceEpoch;
    _timer?.cancel(); // Cancel any existing timer
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        final duration = Duration(
          milliseconds: DateTime.now().millisecondsSinceEpoch - _callStartTime,
        );
        _timeLabel.value = _formatDuration(duration);
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  // Call control actions
  void _handleAccept() async {
    if (call == null) return;

    try {
      // Audio-only call constraints
      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': false, // Always false for audio-only
      };

      call!.answer(mediaConstraints);
      print('✅ Audio call accepted');
    } catch (e) {
      print('❌ Error accepting call: $e');
      _showError('Failed to accept call: $e');
    }
  }

  void _handleDecline() {
    if (call == null) return;
    
    try {
      call!.hangup({'status_code': 486}); // Busy here
      print('✅ Call declined');
    } catch (e) {
      print('❌ Error declining call: $e');
    }
  }

  void _handleHangup() {
    if (call == null) return;

    try {
      _timer?.cancel();
    } catch (e) {
      print('❌ Error canceling timer: $e');
    }

    try {
      call!.hangup({'status_code': 200});
      print('✅ Call ended');
    } catch (e) {
      print('❌ Error ending call: $e');
    }

    // Backup navigation
    Timer(Duration(seconds: 2), () {
      if (mounted && !_isNavigatingBack) {
        _navigateBack();
      }
    });
  }

  void _toggleMute() {
    if (call == null) return;

    setState(() {
      _audioMuted = !_audioMuted;
    });

    try {
      call!.mute(_audioMuted, true); // mute audio, not video
      print('🔊 Audio ${_audioMuted ? 'muted' : 'unmuted'}');
    } catch (e) {
      print('❌ Error toggling mute: $e');
      // Revert state on error
      setState(() {
        _audioMuted = !_audioMuted;
      });
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _speakerOn = !_speakerOn;
    });

    try {
      // Note: SIP UA doesn't have enableSpeakerphone method
      // This would need to be handled differently or removed
      print('🔊 Speaker toggle requested: ${_speakerOn ? 'enabled' : 'disabled'}');
      // TODO: Implement speaker toggle functionality
    } catch (e) {
      print('❌ Error toggling speaker: $e');
      // Revert state on error
      setState(() {
        _speakerOn = !_speakerOn;
      });
    }
  }

  void _toggleHold() {
    if (call == null) return;

    setState(() {
      _hold = !_hold;
    });

    try {
      if (_hold) {
        call!.hold();
        print('⏸️ Call put on hold');
      } else {
        call!.unhold();
        print('▶️ Call resumed');
      }
    } catch (e) {
      print('❌ Error toggling hold: $e');
      // Revert state on error
      setState(() {
        _hold = !_hold;
      });
    }
  }

  void _toggleKeypad() {
    setState(() {
      _showKeypad = !_showKeypad;
    });
  }

  void _sendDTMF(String digit) {
    if (call == null) return;

    setState(() {
      _dtmfInput += digit;
    });

    try {
      call!.sendDTMF(digit);
      print('📱 DTMF sent: $digit');
    } catch (e) {
      print('❌ Error sending DTMF: $e');
    }
  }

  void _navigateBack() {
    if (_isNavigatingBack) return;
    _isNavigatingBack = true;

    print('🔙 Navigating back to dialpad');
    Navigator.of(context).pop();
  }

  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // UI State helpers
  String _getCallStateTitle() {
    switch (_callState) {
      case CallStateEnum.NONE:
      case CallStateEnum.CALL_INITIATION:
        return direction == Direction.incoming ? 'Incoming Call' : 'Calling...';
      case CallStateEnum.CONNECTING:
        return 'Connecting...';
      case CallStateEnum.PROGRESS:
        return direction == Direction.incoming ? 'Ringing' : 'Ringing...';
      case CallStateEnum.ACCEPTED:
        return 'Call Connected';
      case CallStateEnum.CONFIRMED:
        return _hold ? 'Call On Hold' : 'In Call';
      case CallStateEnum.ENDED:
        return 'Call Ended';
      case CallStateEnum.FAILED:
        return 'Call Failed';
      default:
        return 'Voice Call';
    }
  }

  String _getCallStateSubtitle() {
    if (_hold) {
      return 'Paused by ${_holdOriginator?.name ?? 'remote party'}';
    }
    
    switch (_callState) {
      case CallStateEnum.CONNECTING:
      case CallStateEnum.PROGRESS:
        return direction == Direction.incoming ? 
          'Swipe to answer or decline' : 'Waiting for answer...';
      case CallStateEnum.CONFIRMED:
        return 'Connected • Audio Only';
      case CallStateEnum.ENDED:
        return 'Call completed';
      case CallStateEnum.FAILED:
        return 'Connection failed';
      default:
        return 'Audio Call';
    }
  }

  Color _getStateColor() {
    if (_hold) return Colors.orange;
    
    switch (_callState) {
      case CallStateEnum.CONFIRMED:
        return Colors.green;
      case CallStateEnum.FAILED:
        return Colors.red;
      case CallStateEnum.ENDED:
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  bool _shouldShowCallControls() {
    // If we have a call object and it's not an incoming call waiting to be answered
    final hasCall = call != null;
    final isActiveCall = _callState == CallStateEnum.CONFIRMED || 
                        _callState == CallStateEnum.ACCEPTED ||
                        _callState == CallStateEnum.CONNECTING ||
                        _callState == CallStateEnum.STREAM;
    
    // Also show controls if this is a background call that was already answered
    final isBackgroundCall = hasCall && call!.direction == Direction.incoming && 
                           (_callState != CallStateEnum.NONE && 
                            _callState != CallStateEnum.CALL_INITIATION && 
                            _callState != CallStateEnum.PROGRESS);
    
    final shouldShow = hasCall && (isActiveCall || isBackgroundCall);
    
    print('🎛️ Call Controls Debug:');
    print('  - Has call: $hasCall (ID: ${call?.id})');
    print('  - Call state: $_callState');
    print('  - Call direction: ${call?.direction}');
    print('  - Call confirmed: $_callConfirmed');
    print('  - Is active: $isActiveCall');
    print('  - Is background: $isBackgroundCall');
    print('  - Should show: $shouldShow');
    
    return shouldShow;
  }

  bool _shouldShowIncomingControls() {
    final shouldShow = direction == Direction.incoming && 
                      (_callState == CallStateEnum.NONE ||
                       _callState == CallStateEnum.CALL_INITIATION ||
                       _callState == CallStateEnum.PROGRESS);
    print('📞 Should show incoming controls: $shouldShow (Direction: $direction, State: $_callState)');
    return shouldShow;
  }

  // SIP Event handlers
  @override
  void callStateChanged(Call call, CallState state) {
    print('📞 UnifiedCallScreen: Call state changed: ${state.state}');
    print('📞 Call ID: ${call.id}, Widget Call ID: ${this.call?.id}');
    print('📞 Call object match: ${call.id == this.call?.id}');
    
    if (!mounted) return;

    setState(() {
      _callState = state.state;
    });

    switch (state.state) {
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        if (!_callConfirmed) {
          _callConfirmed = true;
          _startTimer();
          print('⏱️ Call timer started');
        }
        break;
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        print('📞 Call ended, navigating back');
        Future.delayed(Duration(milliseconds: 1000), () {
          if (mounted && !_isNavigatingBack) {
            _navigateBack();
          }
        });
        break;
      default:
        break;
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    // Not needed for call screen
  }

  @override
  void transportStateChanged(TransportState state) {
    // Not needed for call screen  
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    // Not needed for call screen
  }

  @override
  void onNewNotify(Notify ntf) {
    // Not needed for call screen
  }

  @override
  void onNewReinvite(ReInvite event) {
    // For audio-only calls, we reject any video upgrade requests
    if (event.reject != null) {
      event.reject!.call({'status_code': 488}); // Not acceptable here
      print('📞 Video upgrade request rejected (audio-only app)');
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _getStateColor(),
        title: Column(
          children: [
            Text(
              _getCallStateTitle(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            if (_callConfirmed)
              ValueListenableBuilder<String>(
                valueListenable: _timeLabel,
                builder: (context, time, child) {
                  return Text(
                    time,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  );
                },
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.close, color: Colors.white),
            onPressed: _handleHangup,
            tooltip: 'End Call',
          ),
        ],
      ),
      body: Column(
        children: [
          // Main call info area
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Contact avatar
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _getStateColor().withValues(alpha: 0.2),
                      border: Border.all(
                        color: _getStateColor(),
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      Icons.person,
                      size: 60,
                      color: _getStateColor(),
                    ),
                  ),
                  SizedBox(height: 24),
                  
                  // Contact name
                  Text(
                    remoteIdentity ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  
                  // Call state subtitle
                  Text(
                    _getCallStateSubtitle(),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  // DTMF input display
                  if (_showKeypad && _dtmfInput.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _dtmfInput,
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Keypad (when visible)
          if (_showKeypad)
            Expanded(
              flex: 2,
              child: _buildKeypad(),
            ),

          // Bottom controls
          Expanded(
            flex: 1,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: _buildBottomControls(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad() {
    final keypadButtons = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];

    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Clear DTMF button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enter digits',
                style: TextStyle(color: Colors.white70),
              ),
              if (_dtmfInput.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _dtmfInput = '';
                    });
                  },
                  child: Text('Clear', style: TextStyle(color: Colors.blue)),
                ),
            ],
          ),
          SizedBox(height: 8),
          
          // Keypad grid
          Expanded(
            child: Column(
              children: keypadButtons.map((row) {
                return Expanded(
                  child: Row(
                    children: row.map((digit) {
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.all(4),
                          child: ElevatedButton(
                            onPressed: () => _sendDTMF(digit),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha:0.1),
                              foregroundColor: Colors.white,
                              shape: CircleBorder(),
                              padding: EdgeInsets.all(20),
                            ),
                            child: Text(
                              digit,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    print('🎛️ Building bottom controls...');
    print('🎛️ Call state: $_callState, Direction: $direction');
    
    // Incoming call controls
    if (_shouldShowIncomingControls()) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline button
          ActionButton(
            title: "Decline",
            icon: Icons.call_end,
            fillColor: Colors.red,
            onPressed: _handleDecline,
          ),
          // Accept button  
          ActionButton(
            title: "Accept",
            icon: Icons.call,
            fillColor: Colors.green,
            onPressed: _handleAccept,
          ),
        ],
      );
    }

    // In-call controls
    if (_shouldShowCallControls()) {
      return Column(
        children: [
          // First row of controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute button
              ActionButton(
                title: _audioMuted ? "Unmute" : "Mute",
                icon: _audioMuted ? Icons.mic_off : Icons.mic,
                fillColor: _audioMuted ? Colors.red : Colors.white.withValues(alpha:0.2),
                onPressed: _toggleMute,
              ),
              // Speaker button
              ActionButton(
                title: _speakerOn ? "Speaker" : "Speaker",
                icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                fillColor: _speakerOn ? Colors.blue : Colors.white.withValues(alpha:0.2),
                onPressed: _toggleSpeaker,
              ),
              // Hold button
              ActionButton(
                title: _hold ? "Unhold" : "Hold",
                icon: _hold ? Icons.play_arrow : Icons.pause,
                fillColor: _hold ? Colors.orange : Colors.white.withValues(alpha:0.2),
                onPressed: _toggleHold,
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // Second row of controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Keypad button
              ActionButton(
                title: _showKeypad ? "Hide" : "Keypad",
                icon: _showKeypad ? Icons.keyboard_hide : Icons.dialpad,
                fillColor: _showKeypad ? Colors.blue : Colors.white.withValues(alpha:0.2),
                onPressed: _toggleKeypad,
              ),
              // End call button
              ActionButton(
                title: "End Call",
                icon: Icons.call_end,
                fillColor: Colors.red,
                onPressed: _handleHangup,
              ),
            ],
          ),
        ],
      );
    }

    // Default/outgoing call controls
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ActionButton(
          title: "End Call",
          icon: Icons.call_end,
          fillColor: Colors.red,
          onPressed: _handleHangup,
        ),
      ],
    );
  }
}