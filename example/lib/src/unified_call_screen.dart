import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

import 'widgets/action_button.dart';
import 'persistent_background_service.dart';
import 'ringtone_service.dart';

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

class _UnifiedCallScreenState extends State<UnifiedCallScreen> implements SipUaHelperListener {
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

  // Get the current active call (could be from widget or background service)
  Call? get currentCall {
    final activeCall = PersistentBackgroundService.getActiveCall();
    final incomingCall = PersistentBackgroundService.getIncomingCall();
    // Prioritize background calls since they're more likely to be the active incoming call
    return incomingCall ?? activeCall ?? call;
  }

  String? get remoteIdentity => currentCall?.remote_identity;
  Direction? get direction => currentCall?.direction;

  @override
  void initState() {
    super.initState();
    _initializeCallScreen();
    _enableFullScreenMode();
  }

  void _enableFullScreenMode() {
    try {
      // Enable full screen mode for incoming calls
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersive,
        overlays: [SystemUiOverlay.top], // Keep status bar for better UX
      );
      print('📱 Full screen mode enabled for call screen');
    } catch (e) {
      print('❌ Error enabling full screen mode: $e');
      // Fallback to manual mode
      try {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top],
        );
        print('📱 Fallback to manual UI mode');
      } catch (fallbackError) {
        print('❌ Fallback UI mode also failed: $fallbackError');
      }
    }
  }

  void _initializeCallScreen() {
    // Check if we need to use the background service's SIP helper for this call
    final backgroundHelper = PersistentBackgroundService.getBackgroundSipHelper();
    final activeCall = PersistentBackgroundService.getActiveCall();
    final incomingCall = PersistentBackgroundService.getIncomingCall();

    // Try to find the correct call and helper - prioritize background calls
    final callToUse = incomingCall ?? activeCall ?? call;
    final helperToUse = backgroundHelper ?? helper;

    print('🔍 CALL SCREEN INITIALIZATION DEBUG:');
    print('  Background helper available: ${backgroundHelper != null}');
    print('  Main helper available: ${helper != null}');
    print('  Background active call: ${activeCall?.id} (${activeCall?.state})');
    print('  Background incoming call: ${incomingCall?.id} (${incomingCall?.state})');
    print('  Widget call: ${call?.id} (${call?.state})');
    print('  Selected call: ${callToUse?.id} (${callToUse?.state})');
    print('  Selected helper: ${helperToUse?.hashCode}');

    if (callToUse != null && helperToUse != null) {
      print('🔄 Using SIP helper for call: ${callToUse.id}');
      print('🔄 Call state: ${callToUse.state}, Direction: ${callToUse.direction}');
      print('🔄 Call remote: ${callToUse.remote_identity}');

      try {
        // Always add listener to the helper we're using
        helperToUse.addSipUaHelperListener(this);
        print('✅ Added listener to primary SIP helper');

        // Also add listener to main helper if using background helper
        if (backgroundHelper != null && helper != null && backgroundHelper != helper) {
          helper!.addSipUaHelperListener(this);
          print('✅ Also added listener to main SIP helper');
        }
      } catch (e) {
        print('⚠️ Warning: Could not add listener to helper: $e');
      }

      // Transfer control from background to main app
      if (backgroundHelper != null && incomingCall != null) {
        print('🔄 Transferring incoming call from background to main app');
        PersistentBackgroundService.transferCallToMainApp();
      }
    } else {
      print('⚠️ No call or helper available');
      print('  CallToUse: ${callToUse?.id}');
      print('  HelperToUse available: ${helperToUse != null}');

      // Still add listeners to available helpers
      if (backgroundHelper != null) {
        try {
          backgroundHelper.addSipUaHelperListener(this);
          print('✅ Added listener to background helper');
        } catch (e) {
          print('⚠️ Could not add listener to background helper: $e');
        }
      }
      if (helper != null) {
        try {
          helper!.addSipUaHelperListener(this);
          print('✅ Added listener to main helper');
        } catch (e) {
          print('⚠️ Could not add listener to main helper: $e');
        }
      }
    }

    // Use the call from background service if our widget call is null
    final currentCall = call ?? activeCall ?? incomingCall;

    print('🔍 CALL RESOLUTION DEBUG:');
    print('  Widget call: ${call?.id} (${call?.direction}, ${call?.state})');
    print('  Active call: ${activeCall?.id} (${activeCall?.direction}, ${activeCall?.state})');
    print('  Incoming call: ${incomingCall?.id} (${incomingCall?.direction}, ${incomingCall?.state})');
    print('  Final call: ${currentCall?.id} (${currentCall?.direction}, ${currentCall?.state})');

    if (currentCall != null) {
      _callState = currentCall.state;
      print('📞 Initial call state: $_callState');
      print('📞 Call source: ${currentCall.direction == Direction.incoming ? 'Incoming' : 'Outgoing'}');
      print('📞 Call ID: ${currentCall.id}, Remote: ${currentCall.remote_identity}');

      // Start ringing for incoming calls that are still ringing
      if (currentCall.direction == Direction.incoming &&
          (_callState == CallStateEnum.CALL_INITIATION ||
              _callState == CallStateEnum.PROGRESS ||
              _callState == CallStateEnum.NONE)) {
        print('🔔 Starting ringtone for incoming call (state: $_callState)');
        RingtoneService.startRinging();
      }

      // If this is an incoming call that's already answered by background service,
      // update the state and start timer
      if (currentCall.direction == Direction.incoming &&
          (_callState == CallStateEnum.ACCEPTED || _callState == CallStateEnum.CONFIRMED)) {
        print('🔄 Taking over background-accepted call');
        _callConfirmed = true;
        _startTimer();
        RingtoneService.stopRinging(); // Stop ringing if call already answered
      }
    } else {
      print('⚠️ No call object available to UnifiedCallScreen');
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
      // Stop ringing on cleanup
      RingtoneService.stopRinging();
    } catch (e) {
      print('❌ Error stopping ringtone: $e');
    }

    try {
      if (helper != null) {
        helper!.removeSipUaHelperListener(this);
      }

      // Also try to remove from background helper if it exists
      final backgroundHelper = PersistentBackgroundService.getBackgroundSipHelper();
      if (backgroundHelper != null) {
        backgroundHelper.removeSipUaHelperListener(this);
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
      // Restore normal UI mode
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      print('📱 UI mode restored to normal');
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
    print('🟢 ACCEPT BUTTON PRESSED');

    try {
      // Get the SIP helper - prefer background helper if available
      final backgroundHelper = PersistentBackgroundService.getBackgroundSipHelper();
      final helperToUse = backgroundHelper ?? helper;

      if (helperToUse == null) {
        print('❌ No SIP helper available');
        _showError('No SIP connection available');
        return;
      }

      // Get the active call from background service or widget - prioritize background calls
      final activeCall = PersistentBackgroundService.getActiveCall();
      final incomingCall = PersistentBackgroundService.getIncomingCall();
      final currentCall = incomingCall ?? activeCall ?? call;

      print('🔍 ACCEPT DEBUG:');
      print('  Helper: ${helperToUse.hashCode} (background: ${backgroundHelper != null})');
      print('  Widget call: ${call?.id} (state: ${call?.state})');
      print('  Active call: ${activeCall?.id} (state: ${activeCall?.state})');
      print('  Incoming call: ${incomingCall?.id} (state: ${incomingCall?.state})');
      print('  Using call: ${currentCall?.id} (state: ${currentCall?.state})');

      if (currentCall == null) {
        print('❌ No call available to accept');
        _showError('No active call found to accept');
        return;
      }

      // Stop ringing immediately
      print('🔇 Stopping ringtone...');
      RingtoneService.stopRinging();

      // Audio-only call constraints
      final mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': false, // Always false for audio-only
      };

      print('📞 Accepting call ${currentCall.id} with constraints: $mediaConstraints');
      print('📞 Call remote identity: ${currentCall.remote_identity}');
      print('📞 Call current state: ${currentCall.state}');
      print('📞 Call direction: ${currentCall.direction}');

      // Use the call's answer method
      currentCall.answer(mediaConstraints);
      print('✅ Audio call accepted for ${currentCall.remote_identity}');

      // Don't immediately update UI state - wait for SIP events
      // The callStateChanged handler will update the state appropriately
      print('⏳ Waiting for SIP state change events...');
    } catch (e) {
      print('❌ Error accepting call: $e');
      _showError('Failed to accept call: $e');
    }
  }

  void _handleDecline() {
    print('🔴 DECLINE BUTTON PRESSED');

    try {
      // Get the SIP helper - prefer background helper if available
      final backgroundHelper = PersistentBackgroundService.getBackgroundSipHelper();
      final helperToUse = backgroundHelper ?? helper;

      if (helperToUse == null) {
        print('❌ No SIP helper available');
        _showError('No SIP connection available');
        return;
      }

      // Get the active call from background service or widget - prioritize background calls
      final activeCall = PersistentBackgroundService.getActiveCall();
      final incomingCall = PersistentBackgroundService.getIncomingCall();
      final currentCall = incomingCall ?? activeCall ?? call;

      print('🔍 DECLINE DEBUG:');
      print('  Helper: ${helperToUse.hashCode} (background: ${backgroundHelper != null})');
      print('  Widget call: ${call?.id} (state: ${call?.state})');
      print('  Active call: ${activeCall?.id} (state: ${activeCall?.state})');
      print('  Incoming call: ${incomingCall?.id} (state: ${incomingCall?.state})');
      print('  Using call: ${currentCall?.id} (state: ${currentCall?.state})');

      if (currentCall == null) {
        print('❌ No call available to decline');
        _showError('No active call found to decline');
        return;
      }

      // Stop ringing immediately
      print('🔇 Stopping ringtone...');
      RingtoneService.stopRinging();

      print('📞 Declining call ${currentCall.id}');
      print('📞 Call remote identity: ${currentCall.remote_identity}');
      print('📞 Call current state: ${currentCall.state}');
      print('📞 Call direction: ${currentCall.direction}');

      // For incoming calls, send busy/decline response
      if (currentCall.direction == Direction.incoming) {
        currentCall.hangup({'status_code': 486}); // Busy here
        print('✅ Incoming call declined with 486 Busy Here');
      } else {
        currentCall.hangup({'status_code': 200}); // Normal hangup for outgoing calls
        print('✅ Outgoing call terminated with 200 OK');
      }

      print('✅ Call declined for ${currentCall.remote_identity}');

      // Clear any forwarded call from background service
      PersistentBackgroundService.clearForwardedCall();

      // Update UI state immediately
      if (mounted) {
        setState(() {
          _callState = CallStateEnum.ENDED;
        });
      }

      // Navigate back immediately for decline (user expects immediate response)
      if (!_isNavigatingBack) {
        print('🔙 Navigating back immediately after decline');
        _navigateBack();
      }
    } catch (e) {
      print('❌ Error declining call: $e');
      _showError('Failed to decline call: $e');
    }
  }

  void _handleHangup() {
    // Get the active call from background service or widget
    final activeCall = PersistentBackgroundService.getActiveCall();
    final incomingCall = PersistentBackgroundService.getIncomingCall();
    final currentCall = call ?? activeCall ?? incomingCall;

    try {
      _timer?.cancel();
    } catch (e) {
      print('❌ Error canceling timer: $e');
    }

    try {
      if (currentCall != null) {
        currentCall.hangup({'status_code': 200});
        print('✅ Call ended for ${currentCall.remote_identity}');
      } else {
        print('⚠️ No call to hang up');
      }
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
    // Get the active call from background service or widget
    final activeCall = PersistentBackgroundService.getActiveCall();
    final incomingCall = PersistentBackgroundService.getIncomingCall();
    final currentCall = call ?? activeCall ?? incomingCall;

    if (currentCall == null) return;

    setState(() {
      _audioMuted = !_audioMuted;
    });

    try {
      currentCall.mute(_audioMuted, true); // mute audio, not video
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
    // Get the active call from background service or widget
    final activeCall = PersistentBackgroundService.getActiveCall();
    final incomingCall = PersistentBackgroundService.getIncomingCall();
    final currentCall = call ?? activeCall ?? incomingCall;

    if (currentCall == null) return;

    setState(() {
      _hold = !_hold;
    });

    try {
      if (_hold) {
        currentCall.hold();
        print('⏸️ Call put on hold');
      } else {
        currentCall.unhold();
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
    // Get the active call from background service or widget
    final activeCall = PersistentBackgroundService.getActiveCall();
    final incomingCall = PersistentBackgroundService.getIncomingCall();
    final currentCall = call ?? activeCall ?? incomingCall;

    if (currentCall == null) return;

    setState(() {
      _dtmfInput += digit;
    });

    try {
      currentCall.sendDTMF(digit);
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
        return direction == Direction.incoming ? 'Swipe to answer or decline' : 'Waiting for answer...';
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
    final isBackgroundCall = hasCall &&
        call!.direction == Direction.incoming &&
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
    print('📞 Current call: ${currentCall?.id}, Remote: ${currentCall?.remote_identity}');
    print('📞 Widget call: ${call?.id}, Background active: ${PersistentBackgroundService.getActiveCall()?.id}');
    print('📞 Background incoming: ${PersistentBackgroundService.getIncomingCall()?.id}');
    return shouldShow;
  }

  // SIP Event handlers
  @override
  void callStateChanged(Call call, CallState state) {
    print('📞 UnifiedCallScreen: Call state changed: ${state.state}');
    print('📞 Call ID: ${call.id}, Widget Call ID: ${this.call?.id}');
    print('📞 Call remote: ${call.remote_identity}');
    print('📞 Call direction: ${call.direction}');

    // Check if this is the call we're handling
    final activeCall = PersistentBackgroundService.getActiveCall();
    final incomingCall = PersistentBackgroundService.getIncomingCall();
    final currentCall = this.call ?? activeCall ?? incomingCall;

    final isRelevantCall = call.id == currentCall?.id || call.id == this.call?.id;

    print('📞 Current call: ${currentCall?.id}');
    print('📞 Is relevant call: $isRelevantCall');

    if (!mounted || !isRelevantCall) {
      print('📞 Ignoring call state change - not mounted or not relevant call');
      return;
    }

    // Update state
    setState(() {
      _callState = state.state;
    });

    switch (state.state) {
      case CallStateEnum.ACCEPTED:
        print('📞 Call ACCEPTED - stopping ringtone, starting timer');
        RingtoneService.stopRinging();
        if (!_callConfirmed) {
          _callConfirmed = true;
          _startTimer();
          print('⏱️ Call timer started for accepted call');
        }
        break;
      case CallStateEnum.CONFIRMED:
        print('📞 Call CONFIRMED - ensuring timer is running');
        RingtoneService.stopRinging();
        if (!_callConfirmed) {
          _callConfirmed = true;
          _startTimer();
          print('⏱️ Call timer started for confirmed call');
        }
        break;
      case CallStateEnum.FAILED:
        print('📞 Call FAILED - stopping ringtone, navigating back');
        RingtoneService.stopRinging();
        Future.delayed(Duration(milliseconds: 1500), () {
          if (mounted && !_isNavigatingBack) {
            _navigateBack();
          }
        });
        break;
      case CallStateEnum.ENDED:
        print('📞 Call ENDED - stopping ringtone, navigating back');
        RingtoneService.stopRinging();
        Future.delayed(Duration(milliseconds: 1000), () {
          if (mounted && !_isNavigatingBack) {
            _navigateBack();
          }
        });
        break;
      default:
        print('📞 Call state: ${state.state} - no special handling');
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
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _getStateColor().withValues(alpha: 0.8),
              Colors.black87,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Status bar with call info
              Container(
                padding: EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.white),
                      onPressed: _handleHangup,
                      tooltip: 'End Call',
                    ),
                  ],
                ),
              ),
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
                            color: Colors.white.withValues(alpha: 0.1),
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
        ),
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
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
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
                fillColor: _audioMuted ? Colors.red : Colors.white.withValues(alpha: 0.2),
                onPressed: _toggleMute,
              ),
              // Speaker button
              ActionButton(
                title: _speakerOn ? "Speaker" : "Speaker",
                icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                fillColor: _speakerOn ? Colors.blue : Colors.white.withValues(alpha: 0.2),
                onPressed: _toggleSpeaker,
              ),
              // Hold button
              ActionButton(
                title: _hold ? "Unhold" : "Hold",
                icon: _hold ? Icons.play_arrow : Icons.pause,
                fillColor: _hold ? Colors.orange : Colors.white.withValues(alpha: 0.2),
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
                fillColor: _showKeypad ? Colors.blue : Colors.white.withValues(alpha: 0.2),
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
