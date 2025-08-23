import 'dart:async';
import 'package:sip_ua/sip_ua.dart';
import '../models/sip_account_model.dart';
import '../models/call_model.dart';
import '../../domain/entities/call_entity.dart';
import '../../domain/entities/sip_account_entity.dart';

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
  
  final StreamController<ConnectionStatus> _connectionStatusController = 
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<CallModel> _incomingCallsController = 
      StreamController<CallModel>.broadcast();
  final StreamController<CallModel> _activeCallsController = 
      StreamController<CallModel>.broadcast();

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
    final result = await _sipHelper.call(number, voiceOnly: true);
    
    return CallModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      remoteIdentity: number,
      direction: CallDirection.outgoing,
      status: result ? CallStatus.connecting : CallStatus.failed,
      startTime: DateTime.now(),
    );
  }

  // Store active calls
  final Map<String, Call> _activeCalls = {};

  @override
  Future<void> acceptCall(String callId) async {
    final call = _activeCalls[callId];
    if (call != null) {
      call.answer({'audio': true, 'video': false});
    }
  }

  @override
  Future<void> rejectCall(String callId) async {
    final call = _activeCalls[callId];
    if (call != null) {
      call.hangup({'status_code': 486}); // Busy here
    }
  }

  @override
  Future<void> endCall(String callId) async {
    final call = _activeCalls[callId];
    if (call != null) {
      call.hangup({'status_code': 200});
      _activeCalls.remove(callId);
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
    final callId = call.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // Store/update active call
    _activeCalls[callId] = call;
    
    final callModel = _mapSipCallToCallModel(call, state, callId);
    
    if (call.direction == Direction.incoming && 
        state.state == CallStateEnum.CALL_INITIATION) {
      _incomingCallsController.add(callModel);
    } else {
      _activeCallsController.add(callModel);
    }
    
    // Clean up call when ended
    if (state.state == CallStateEnum.ENDED) {
      _activeCalls.remove(callId);
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    ConnectionStatus status;
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        status = ConnectionStatus.registered;
        break;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        status = ConnectionStatus.failed;
        break;
      case RegistrationStateEnum.UNREGISTERED:
        status = ConnectionStatus.disconnected;
        break;
      case RegistrationStateEnum.NONE:
      default:
        status = ConnectionStatus.disconnected;
        break;
    }
    _currentStatus = status;
    _connectionStatusController.add(status);
  }

  @override
  void transportStateChanged(TransportState state) {
    ConnectionStatus status;
    switch (state.state) {
      case TransportStateEnum.CONNECTED:
        status = ConnectionStatus.connected;
        break;
      case TransportStateEnum.CONNECTING:
        status = ConnectionStatus.connecting;
        break;
      case TransportStateEnum.DISCONNECTED:
        status = ConnectionStatus.disconnected;
        break;
      default:
        status = ConnectionStatus.disconnected;
        break;
    }
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

  @override
  void dispose() {
    _sipHelper.removeSipUaHelperListener(this);
    _connectionStatusController.close();
    _incomingCallsController.close();
    _activeCallsController.close();
  }
}