import 'dart:async';
import 'package:sip_ua/sip_ua.dart';
import '../models/sip_account_model.dart';
import '../models/call_model.dart';
import '../../domain/entities/call_entity.dart';
import '../../domain/entities/sip_account_entity.dart';
import '../services/ringtone_vibration_service.dart';
import '../services/call_log_service.dart';

abstract class SipDataSource {
  Future<void> initialize();
  Future<void> registerAccount(SipAccountModel account);
  Future<void> unregisterAccount();
  Future<SipAccountModel?> getCurrentAccount();
  Future<ConnectionStatus> getRegistrationStatus();
  Stream<ConnectionStatus> getConnectionStatusStream();
  
  Future<CallModel> makeCall(String number);
  Future<void> acceptCall(String callId);
  Future<void> rejectCall(String callId);
  Future<void> endCall(String callId);
  Stream<CallModel> getIncomingCallsStream();
  Stream<CallModel> getActiveCallsStream();
  
  Future<void> toggleMute(String callId);
  Future<void> toggleSpeaker(String callId);
  Future<void> sendDTMF(String callId, String digit);
  
  void dispose();
}

class SipUADataSource implements SipDataSource, SipUaHelperListener {
  late SIPUAHelper _sipHelper;
  SipAccountModel? _currentAccount;
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  final CallLogService _callLogService = CallLogService();
  
  final StreamController<ConnectionStatus> _connectionStatusController = 
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<CallModel> _incomingCallsController = 
      StreamController<CallModel>.broadcast();
  final StreamController<CallModel> _activeCallsController = 
      StreamController<CallModel>.broadcast();

  // Track call states for logging
  final Map<String, CallModel> _callHistory = {};

  @override
  Future<void> initialize() async {
    _sipHelper = SIPUAHelper();
    _sipHelper.addSipUaHelperListener(this);
  }

  @override
  Future<void> registerAccount(SipAccountModel account) async {
    _currentAccount = account;
    
    final settings = UaSettings();
    settings.transportType = TransportType.WS;
    settings.webSocketUrl = account.wsUrl;
    settings.webSocketSettings.extraHeaders = account.extraHeaders ?? {};
    settings.webSocketSettings.allowBadCertificate = true;
    
    settings.uri = account.sipUri;
    settings.registrarServer = account.domain;
    settings.authorizationUser = account.username;
    settings.password = account.password;
    settings.displayName = account.displayName ?? account.username;
    settings.userAgent = 'Android SIP Client';
    settings.dtmfMode = DtmfMode.RFC2833;
    settings.register = true;
    settings.register_expires = 600;
    settings.contact_uri = 'sip:${account.username}@${account.domain};transport=ws';
    settings.sessionTimers = true;
    
    // Set host from WebSocket URL
    try {
      final wsUri = Uri.parse(account.wsUrl);
      settings.host = wsUri.host.isNotEmpty ? wsUri.host : account.domain;
    } catch (e) {
      settings.host = account.domain;
    }
    
    await _sipHelper.start(settings);
  }

  @override
  Future<void> unregisterAccount() async {
    if (_sipHelper.registered) {
      await _sipHelper.unregister();
    }
    _sipHelper.stop();
    _currentAccount = null;
  }

  @override
  Future<SipAccountModel?> getCurrentAccount() async {
    return _currentAccount;
  }

  @override
  Future<ConnectionStatus> getRegistrationStatus() async {
    return _currentStatus;
  }

  @override
  Stream<ConnectionStatus> getConnectionStatusStream() {
    return _connectionStatusController.stream;
  }

  @override
  Future<CallModel> makeCall(String number) async {
    try {
      print('📞 Making call to: $number');
      final result = await _sipHelper.call(number, voiceOnly: true);
      
      // Wait a bit for the call to be registered in callStateChanged
      await Future.delayed(Duration(milliseconds: 500));
      
      // Get the actual call from the SIP helper - find most recent outgoing call
      Call? actualCall;
      String? callId;
      
      for (final entry in _activeCalls.entries) {
        final call = entry.value;
        if (call.direction == Direction.outgoing && 
            call.remote_identity?.contains(number) == true) {
          actualCall = call;
          callId = entry.key;
          break;
        }
      }
      
      // Fallback ID if not found
      callId ??= 'outgoing_${DateTime.now().millisecondsSinceEpoch}';
      
      print('📞 Call initiated with ID: $callId');
      
      return CallModel(
        id: callId,
        remoteIdentity: number,
        direction: CallDirection.outgoing,
        status: result ? CallStatus.connecting : CallStatus.failed,
        startTime: DateTime.now(),
      );
    } catch (e) {
      print('❌ Error making call: $e');
      return CallModel(
        id: 'failed_${DateTime.now().millisecondsSinceEpoch}',
        remoteIdentity: number,
        direction: CallDirection.outgoing,
        status: CallStatus.failed,
        startTime: DateTime.now(),
      );
    }
  }

  // Store active calls
  final Map<String, Call> _activeCalls = {};

  @override
  Future<void> acceptCall(String callId) async {
    final call = _activeCalls[callId];
    if (call != null) {
      // Stop vibration when call is answered
      await RingtoneVibrationService().stopRinging();
      call.answer({'audio': true, 'video': false});
    }
  }

  @override
  Future<void> rejectCall(String callId) async {
    final call = _activeCalls[callId];
    if (call != null) {
      // Stop vibration when call is rejected
      await RingtoneVibrationService().stopRinging();
      call.hangup({'status_code': 486}); // Busy here
    }
  }

  @override
  Future<void> endCall(String callId) async {
    try {
      print('🔄 EndCall requested for ID: $callId');
      
      // Stop vibration when call is ended
      await RingtoneVibrationService().stopRinging();
      
      final call = _activeCalls[callId];
      if (call != null) {
        print('🔄 Found call, hanging up: $callId');
        call.hangup({'status_code': 200});
        
        // Wait a moment for the hangup to process
        await Future.delayed(Duration(milliseconds: 100));
        
        _activeCalls.remove(callId);
        print('✅ Call hung up and removed from active calls');
      } else {
        // If specific call not found, be more aggressive
        print('⚠️ Call ID $callId not found in active calls (${_activeCalls.keys.toList()})');
        
        // Try to hangup all active calls
        for (final entry in _activeCalls.entries) {
          try {
            print('🔄 Hanging up active call: ${entry.key}');
            entry.value.hangup({'status_code': 200});
          } catch (e) {
            print('❌ Error hanging up call ${entry.key}: $e');
          }
        }
        
        // Also terminate all sessions on the SIP helper
        _sipHelper.terminateSessions({'status_code': 200});
        _activeCalls.clear();
        print('🔄 Terminated all active sessions and calls');
      }
      
      // Additional cleanup: force terminate all sessions
      try {
        _sipHelper.terminateSessions({'status_code': 200});
        print('🔄 Force terminated all sessions via SIP helper');
      } catch (e) {
        print('ℹ️ SIP helper terminate sessions failed: $e');
      }
      
      // Final check: ensure no active calls remain
      if (_activeCalls.isNotEmpty) {
        print('⚠️ Warning: Active calls still remain after endCall: ${_activeCalls.keys.toList()}');
      }
      
      print('✅ EndCall completed for $callId');
      
    } catch (e) {
      print('❌ Error ending call: $e');
      
      // Ultimate fallback: force terminate everything
      try {
        _sipHelper.terminateSessions({'status_code': 200});
        _activeCalls.clear();
        print('🔄 Ultimate fallback: force terminated everything');
      } catch (fallbackError) {
        print('❌ Ultimate fallback failed: $fallbackError');
      }
    }
  }

  @override
  Stream<CallModel> getIncomingCallsStream() {
    return _incomingCallsController.stream;
  }

  @override
  Stream<CallModel> getActiveCallsStream() {
    return _activeCallsController.stream;
  }

  @override
  Future<void> toggleMute(String callId) async {
    // This would typically interact with media stream
    // For now, we'll leave it as a placeholder
  }

  @override
  Future<void> toggleSpeaker(String callId) async {
    // This would typically interact with audio routing
    // For now, we'll leave it as a placeholder
  }

  @override
  Future<void> sendDTMF(String callId, String digit) async {
    final call = _activeCalls[callId];
    if (call != null) {
      call.sendDTMF(digit);
    }
  }

  @override
  void callStateChanged(Call call, CallState state) {
    final callId = call.id ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    
    print('📞 Call state changed: ID=$callId, State=${state.state}, Direction=${call.direction}');
    
    // Store/update active call with the actual SIP call ID
    _activeCalls[callId] = call;
    
    final callModel = _mapSipCallToCallModel(call, state, callId);
    
    // Store call in history for logging
    _callHistory[callId] = callModel;
    
    if (call.direction == Direction.incoming && 
        state.state == CallStateEnum.CALL_INITIATION) {
      print('📞 Incoming call received: $callId');
      _incomingCallsController.add(callModel);
    } else {
      _activeCallsController.add(callModel);
    }
    
    // Clean up and log call when ended
    if (state.state == CallStateEnum.ENDED) {
      print('📞 Call ended in callStateChanged: $callId');
      _activeCalls.remove(callId);
      
      // Log the call if it ended
      final finalCallModel = _callHistory[callId];
      if (finalCallModel != null) {
        _logCallFromModel(finalCallModel, state);
        _callHistory.remove(callId);
      }
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    print('📊 SIP Registration state changed: ${state.state}');
    
    ConnectionStatus status;
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        status = ConnectionStatus.registered;
        print('✅ SIP Registration successful - user registered');
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        status = ConnectionStatus.failed;
        print('❌ SIP Registration failed');
        break;
      case RegistrationStateEnum.UNREGISTERED:
        status = ConnectionStatus.disconnected;
        print('🔌 SIP Registration: unregistered');
        break;
      case RegistrationStateEnum.NONE:
      default:
        status = ConnectionStatus.disconnected;
        print('🔌 SIP Registration: none/default state');
        break;
    }
    
    print('📊 Connection status updated to: $status');
    _currentStatus = status;
    _connectionStatusController.add(status);
  }

  @override
  void transportStateChanged(TransportState state) {
    print('🌐 SIP Transport state changed: ${state.state}');
    
    ConnectionStatus status;
    switch (state.state) {
      case TransportStateEnum.CONNECTED:
        status = ConnectionStatus.connected;
        print('🔗 WebSocket transport fully connected');
        break;
      case TransportStateEnum.CONNECTING:
        status = ConnectionStatus.connecting;
        print('🔄 WebSocket transport connecting...');
        break;
      case TransportStateEnum.DISCONNECTED:
        status = ConnectionStatus.disconnected;
        print('🔌 WebSocket transport disconnected');
        break;
      default:
        status = ConnectionStatus.disconnected;
        print('🔌 WebSocket transport: default/unknown state');
        break;
    }
    
    print('📊 Transport status updated to: $status');
    _currentStatus = status;
    _connectionStatusController.add(status);
  }

  CallModel _mapSipCallToCallModel(Call call, CallState state, String callId) {
    CallStatus status;
    switch (state.state) {
      case CallStateEnum.STREAM:
        status = CallStatus.connected;
        break;
      case CallStateEnum.ENDED:
        status = CallStatus.ended;
        break;
      case CallStateEnum.FAILED:
        status = CallStatus.failed;
        break;
      case CallStateEnum.CALL_INITIATION:
        status = call.direction == Direction.incoming 
            ? CallStatus.ringing 
            : CallStatus.connecting;
        break;
      default:
        status = CallStatus.connecting;
        break;
    }

    return CallModel(
      id: callId,
      remoteIdentity: call.remote_identity ?? 'Unknown',
      direction: call.direction == Direction.incoming 
          ? CallDirection.incoming 
          : CallDirection.outgoing,
      status: status,
      startTime: DateTime.now(), // In real implementation, track actual start time
    );
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  Future<void> _logCallFromModel(CallModel callModel, CallState state) async {
    try {
      final callEntity = CallEntity(
        id: callModel.id,
        remoteIdentity: callModel.remoteIdentity,
        displayName: callModel.displayName,
        direction: callModel.direction,
        status: _mapCallStateToCallStatus(state.state),
        startTime: callModel.startTime,
        endTime: DateTime.now(),
        duration: callModel.startTime != null 
            ? DateTime.now().difference(callModel.startTime) 
            : Duration.zero,
      );
      
      await _callLogService.logCall(callEntity);
      print('✅ Call logged from SIP datasource: ${callModel.remoteIdentity}');
      
    } catch (e) {
      print('❌ Error logging call from SIP datasource: $e');
    }
  }

  CallStatus _mapCallStateToCallStatus(CallStateEnum state) {
    switch (state) {
      case CallStateEnum.CALL_INITIATION:
        return CallStatus.ringing;
      case CallStateEnum.CONNECTING:
        return CallStatus.connecting;
      case CallStateEnum.CONFIRMED:
      case CallStateEnum.STREAM:
        return CallStatus.connected;
      case CallStateEnum.ENDED:
        return CallStatus.ended;
      case CallStateEnum.FAILED:
        return CallStatus.failed;
      default:
        return CallStatus.disconnected;
    }
  }

  @override
  void dispose() {
    _sipHelper.removeSipUaHelperListener(this);
    _connectionStatusController.close();
    _incomingCallsController.close();
    _activeCallsController.close();
  }
}