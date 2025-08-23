import '../../domain/entities/call_entity.dart';
import '../../domain/entities/sip_account_entity.dart';
import '../../domain/repositories/sip_repository.dart';
import '../datasources/sip_datasource.dart';
import '../models/sip_account_model.dart';

class SipRepositoryImpl implements SipRepository {
  final SipDataSource _sipDataSource;

  SipRepositoryImpl(this._sipDataSource);

  @override
  Future<void> registerAccount(SipAccountEntity account) async {
    final accountModel = SipAccountModel.fromEntity(account);
    await _sipDataSource.registerAccount(accountModel);
  }

  @override
  Future<void> unregisterAccount() async {
    await _sipDataSource.unregisterAccount();
  }

  @override
  Future<SipAccountEntity?> getCurrentAccount() async {
    return await _sipDataSource.getCurrentAccount();
  }

  @override
  Future<ConnectionStatus> getRegistrationStatus() async {
    return await _sipDataSource.getRegistrationStatus();
  }

  @override
  Stream<ConnectionStatus> getConnectionStatusStream() {
    return _sipDataSource.getConnectionStatusStream();
  }

  @override
  Future<void> connect(SipAccountEntity account) async {
    final accountModel = SipAccountModel.fromEntity(account);
    await _sipDataSource.registerAccount(accountModel);
  }

  @override
  Future<void> disconnect() async {
    await _sipDataSource.unregisterAccount();
  }

  @override
  Future<CallEntity> makeCall(String number) async {
    final callModel = await _sipDataSource.makeCall(number);
    return callModel;
  }

  @override
  Future<void> acceptCall(String callId) async {
    await _sipDataSource.acceptCall(callId);
  }

  @override
  Future<void> rejectCall(String callId) async {
    await _sipDataSource.rejectCall(callId);
  }

  @override
  Future<void> endCall(String callId) async {
    await _sipDataSource.endCall(callId);
  }

  @override
  Stream<CallEntity> getIncomingCallsStream() {
    return _sipDataSource.getIncomingCallsStream();
  }

  @override
  Stream<CallEntity> getActiveCallsStream() {
    return _sipDataSource.getActiveCallsStream();
  }

  @override
  Future<void> toggleMute(String callId) async {
    await _sipDataSource.toggleMute(callId);
  }

  @override
  Future<void> toggleSpeaker(String callId) async {
    await _sipDataSource.toggleSpeaker(callId);
  }

  @override
  Future<void> sendDTMF(String callId, String digit) async {
    await _sipDataSource.sendDTMF(callId, digit);
  }
}