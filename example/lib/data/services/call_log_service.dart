import '../models/call_log_model.dart' as Models;
import '../../domain/entities/call_entity.dart' as Entities;
import 'hive_service.dart';
import 'contacts_service.dart';

class CallLogService {
  static final CallLogService _instance = CallLogService._();
  factory CallLogService() => _instance;
  CallLogService._();

  final HiveService _hiveService = HiveService.instance;
  final ContactsService _contactsService = ContactsService();

  Future<void> logCall(Entities.CallEntity call) async {
    try {
      // Get contact name if available
      final contact = await _contactsService.getContactByPhone(call.remoteIdentity);
      
      final callLog = Models.CallLogModel()
        ..callId = call.id
        ..phoneNumber = call.remoteIdentity
        ..contactName = contact?.displayName ?? call.displayName
        ..direction = call.direction == Entities.CallDirection.incoming 
            ? Models.CallDirection.incoming 
            : Models.CallDirection.outgoing
        ..type = Models.CallType.voice
        ..status = _mapCallStatus(call.status)
        ..startTime = call.startTime
        ..endTime = call.endTime
        ..duration = call.duration?.inSeconds
        ..missed = call.status == Entities.CallStatus.failed;

      await _hiveService.saveCallLog(callLog);
      print('✅ Call logged: ${call.remoteIdentity}');
      
    } catch (e) {
      print('❌ Error logging call: $e');
    }
  }

  Future<List<Models.CallLogModel>> getRecentCalls({int limit = 50}) async {
    return await _hiveService.getCallLogs(limit: limit);
  }

  Future<List<Models.CallLogModel>> getCallHistory(String phoneNumber) async {
    return await _hiveService.getCallLogsByNumber(phoneNumber);
  }

  Future<void> clearCallHistory() async {
    await _hiveService.clearAllCallLogs();
  }

  Future<void> cleanupOldCalls(int maxDays) async {
    await _hiveService.deleteOldCallLogs(maxDays);
  }

  Future<int> getCallCount() async {
    return await _hiveService.getCallLogCount();
  }

  Models.CallStatus _mapCallStatus(Entities.CallStatus entityStatus) {
    switch (entityStatus) {
      case Entities.CallStatus.connecting:
        return Models.CallStatus.connecting;
      case Entities.CallStatus.ringing:
        return Models.CallStatus.ringing;
      case Entities.CallStatus.connected:
        return Models.CallStatus.connected;
      case Entities.CallStatus.disconnected:
        return Models.CallStatus.ended;
      case Entities.CallStatus.failed:
        return Models.CallStatus.failed;
      case Entities.CallStatus.ended:
        return Models.CallStatus.ended;
    }
  }
}