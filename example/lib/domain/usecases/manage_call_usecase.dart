import '../repositories/sip_repository.dart';
import '../repositories/storage_repository.dart';
import '../entities/call_entity.dart';

class ManageCallUsecase {
  final SipRepository sipRepository;
  final StorageRepository storageRepository;

  ManageCallUsecase(this.sipRepository, this.storageRepository);

  Future<void> acceptCall(String callId) async {
    await sipRepository.acceptCall(callId);
  }

  Future<void> rejectCall(String callId) async {
    await sipRepository.rejectCall(callId);
  }

  Future<void> endCall(String callId) async {
    await sipRepository.endCall(callId);
  }

  Future<void> toggleMute(String callId) async {
    await sipRepository.toggleMute(callId);
  }

  Future<void> toggleSpeaker(String callId) async {
    await sipRepository.toggleSpeaker(callId);
  }

  Future<void> sendDTMF(String callId, String digit) async {
    if (!_isValidDTMFDigit(digit)) {
      throw ArgumentError('Invalid DTMF digit: $digit');
    }
    await sipRepository.sendDTMF(callId, digit);
  }

  Stream<CallEntity> getIncomingCalls() {
    return sipRepository.getIncomingCallsStream();
  }

  Stream<CallEntity> getActiveCalls() {
    return sipRepository.getActiveCallsStream();
  }

  Future<void> saveCallToHistory(CallEntity call) async {
    if (call.status == CallStatus.ended || call.status == CallStatus.failed) {
      await storageRepository.saveCallRecord(call);
    }
  }

  bool _isValidDTMFDigit(String digit) {
    const validDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '#'];
    return validDigits.contains(digit);
  }
}