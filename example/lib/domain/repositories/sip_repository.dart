import '../entities/call_entity.dart';
import '../entities/sip_account_entity.dart';

abstract class SipRepository {
  // Account Management
  Future<void> registerAccount(SipAccountEntity account);
  Future<void> unregisterAccount();
  Future<SipAccountEntity?> getCurrentAccount();
  Future<ConnectionStatus> getRegistrationStatus();
  Stream<ConnectionStatus> getConnectionStatusStream();
  Future<void> connect(SipAccountEntity account);
  Future<void> disconnect();
  
  // Call Management
  Future<CallEntity> makeCall(String number);
  Future<void> acceptCall(String callId);
  Future<void> rejectCall(String callId);
  Future<void> endCall(String callId);
  Stream<CallEntity> getIncomingCallsStream();
  Stream<CallEntity> getActiveCallsStream();
  
  // Audio Controls
  Future<void> toggleMute(String callId);
  Future<void> toggleSpeaker(String callId);
  Future<void> sendDTMF(String callId, String digit);
}