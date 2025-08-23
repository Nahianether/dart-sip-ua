import 'dart:async';
import 'package:sip_ua/sip_ua.dart';
import '../models/sip_account_model.dart';
import '../models/call_model.dart';
import '../../domain/entities/call_entity.dart';
import '../../domain/entities/sip_account_entity.dart';
import '../services/ringtone_vibration_service.dart';
// import '../services/call_log_service.dart'; // Call logging handled by background service
import '../../src/persistent_background_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

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
  // Call logging now handled by background service
  // final CallLogService _callLogService = CallLogService();
  
  final StreamController<ConnectionStatus> _connectionStatusController = 
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<CallModel> _incomingCallsController = 
      StreamController<CallModel>.broadcast();
  final StreamController<CallModel> _activeCallsController = 
      StreamController<CallModel>.broadcast();

  // Track call states for logging (managed by background service)
  // final Map<String, CallModel> _callHistory = {};

  @override
  Future<void> initialize() async {
    _sipHelper = SIPUAHelper();
    _sipHelper.addSipUaHelperListener(this);
  }

  @override
  Future<void> registerAccount(SipAccountModel account) async {
    print('🔄 SipDataSource: Main app registering SIP directly');
    
    // Validate account data first
    if (account.wsUrl.isEmpty || account.username.isEmpty || account.password.isEmpty) {
      _currentStatus = ConnectionStatus.failed;
      _connectionStatusController.add(_currentStatus);
      throw Exception('Invalid account configuration: missing required fields');
    }
    
    _currentAccount = account;
    _currentStatus = ConnectionStatus.connecting;
    _connectionStatusController.add(_currentStatus);
    
    // CRITICAL FIX: Main app handles SIP directly, no background service conflict
    // Disable background service SIP when main app is active
    PersistentBackgroundService.setMainAppActive(true);
    
    try {
      // SIP helper should be initialized in initialize() method
      // No need to check for null as it's initialized as late

      // Stop any existing registration first
      if (_sipHelper.registered) {
        print('🔄 Stopping existing SIP registration');
        await _sipHelper.unregister();
        _sipHelper.stop();
        await Future.delayed(Duration(seconds: 1)); // Give time for cleanup
      }

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
      
      // Set host from WebSocket URL with error handling
      try {
        final wsUri = Uri.parse(account.wsUrl);
        if (wsUri.host.isEmpty) {
          throw Exception('Invalid WebSocket URL: empty host');
        }
        settings.host = wsUri.host;
        print('✅ Parsed host from WebSocket URL: ${settings.host}');
      } catch (e) {
        print('⚠️ Error parsing WebSocket URL: $e - falling back to domain');
        if (account.domain.isEmpty) {
          _currentStatus = ConnectionStatus.failed;
          _connectionStatusController.add(_currentStatus);
          throw Exception('Invalid configuration: both WebSocket URL and domain are invalid');
        }
        settings.host = account.domain;
      }
      
      print('🔄 Starting SIP registration with settings:');
      print('  - URI: ${settings.uri}');
      print('  - Host: ${settings.host}');
      print('  - WebSocket: ${settings.webSocketUrl}');
      print('  - Username: ${settings.authorizationUser}');
      
      // Add timeout to prevent hanging
      await _sipHelper.start(settings).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          print('❌ SIP registration timeout after 30 seconds');
          _currentStatus = ConnectionStatus.failed;
          _connectionStatusController.add(_currentStatus);
          throw TimeoutException('SIP registration timeout');
        },
      );
      print('✅ SIP registration started successfully');
      
    } catch (e) {
      print('❌ Error in main app SIP registration: $e');
      _currentStatus = ConnectionStatus.failed;
      _connectionStatusController.add(_currentStatus);
      
      // Cleanup on failure to prevent inconsistent state
      try {
        if (_sipHelper.registered) {
          await _sipHelper.unregister();
        }
        _sipHelper.stop();
        _currentAccount = null;
        print('🧹 Cleaned up SIP helper after registration failure');
      } catch (cleanupError) {
        print('⚠️ Error during cleanup after registration failure: $cleanupError');
      }
      
      rethrow;
    }
  }
  

  @override
  Future<void> unregisterAccount() async {
    print('🔄 SipDataSource: Main app unregistering SIP directly');
    
    try {
      // Stop SIP helper in main app
      if (_sipHelper.registered) {
        await _sipHelper.unregister();
        print('🔄 SIP unregistered from server');
      }
      _sipHelper.stop();
      print('🔄 SIP helper stopped');
      
      // Update local state
      _currentAccount = null;
      _currentStatus = ConnectionStatus.disconnected;
      _connectionStatusController.add(_currentStatus);
      
      // Allow background service to take over when app goes to background
      PersistentBackgroundService.setMainAppActive(false);
      
      print('✅ Main app SIP unregistration complete');
      
    } catch (e) {
      print('❌ Error in main app SIP unregistration: $e');
      _currentStatus = ConnectionStatus.failed;
      _connectionStatusController.add(_currentStatus);
    }
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
      print('📞 Making call via background service to: $number');
      
      // CRITICAL FIX: Delegate to background service
      final service = FlutterBackgroundService();
      service.invoke('makeCall', {'number': number});
      
      // Generate call ID for UI tracking
      final callId = 'outgoing_${DateTime.now().millisecondsSinceEpoch}';
      
      print('📞 Call request sent to background service with ID: $callId');
      
      return CallModel(
        id: callId,
        remoteIdentity: number,
        direction: CallDirection.outgoing,
        status: CallStatus.connecting,
        startTime: DateTime.now(),
      );
    } catch (e) {
      print('❌ Error requesting call via background service: $e');
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
    print('📞 Accepting call via background service: $callId');
    
    // Stop vibration when call is answered
    await RingtoneVibrationService().stopRinging();
    
    // CRITICAL FIX: Delegate to background service
    final service = FlutterBackgroundService();
    service.invoke('acceptCall', {'callId': callId});
    
    print('✅ Call accept request sent to background service');
  }

  @override
  Future<void> rejectCall(String callId) async {
    print('📞 Rejecting call via background service: $callId');
    
    // Stop vibration when call is rejected
    await RingtoneVibrationService().stopRinging();
    
    // CRITICAL FIX: Delegate to background service
    final service = FlutterBackgroundService();
    service.invoke('rejectCall', {'callId': callId});
    
    print('✅ Call reject request sent to background service');
  }

  @override
  Future<void> endCall(String callId) async {
    try {
      print('🔄 EndCall requested via background service for ID: $callId');
      
      // Stop vibration when call is ended
      await RingtoneVibrationService().stopRinging();
      
      // CRITICAL FIX: Delegate to background service
      final service = FlutterBackgroundService();
      service.invoke('endCall', {'callId': callId});
      
      // Clear local tracking
      _activeCalls.clear();
      
      print('✅ EndCall request sent to background service for $callId');
      
    } catch (e) {
      print('❌ Error requesting call end via background service: $e');
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
    print('📞 Sending DTMF via background service: $digit');
    
    // CRITICAL FIX: Delegate to background service
    final service = FlutterBackgroundService();
    service.invoke('sendDTMF', {'callId': callId, 'digit': digit});
  }

  @override
  void callStateChanged(Call call, CallState state) {
    final callId = call.id ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    
    print('📞 Call state changed: ID=$callId, State=${state.state}, Direction=${call.direction}');
    
    // Store/update active call with null safety
    if (call.id != null) {
      _activeCalls[callId] = call;
    }
    
    try {
      final callModel = _mapSipCallToCallModel(call, state, callId);
      
      if (call.direction == Direction.incoming && 
          state.state == CallStateEnum.CALL_INITIATION) {
        print('📞 Incoming call received: $callId');
        _incomingCallsController.add(callModel);
      } else {
        _activeCallsController.add(callModel);
      }
      
      // Clean up when call ends or fails
      if (state.state == CallStateEnum.ENDED || state.state == CallStateEnum.FAILED) {
        print('📞 Call ${state.state == CallStateEnum.ENDED ? "ended" : "failed"}: $callId - performing cleanup');
        _activeCalls.remove(callId);
        
        // Additional cleanup for failed calls
        if (state.state == CallStateEnum.FAILED) {
          print('📞 Call failed cleanup: removing any lingering call references');
          // Stop any ringtone/vibration
          RingtoneVibrationService().stopRinging().catchError((e) {
            print('⚠️ Error stopping ringtone/vibration during cleanup: $e');
          });
        }
      }
      
    } catch (e) {
      print('❌ Error handling call state change: $e');
    }
  }
  
  // Restore call mapping method with null safety
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
      startTime: DateTime.now(),
    );
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

  // Call mapping now handled by background service
  // CallModel _mapSipCallToCallModel(Call call, CallState state, String callId) { ... }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  // Call logging now handled by background service
  // Future<void> _logCallFromModel(CallModel callModel, CallState state) async { ... }

  // Call state mapping now handled by background service
  // CallStatus _mapCallStateToCallStatus(CallStateEnum state) { ... }


  @override
  void dispose() {
    _sipHelper.removeSipUaHelperListener(this);
    _connectionStatusController.close();
    _incomingCallsController.close();
    _activeCallsController.close();
  }
}