import '../entities/sip_account_entity.dart';
import '../entities/call_entity.dart';

abstract class StorageRepository {
  // Account Storage
  Future<void> saveAccount(SipAccountEntity account);
  Future<SipAccountEntity?> getStoredAccount();
  Future<void> deleteAccount();
  
  // Call History
  Future<void> saveCallRecord(CallEntity call);
  Future<List<CallEntity>> getCallHistory();
  Future<void> clearCallHistory();
  
  // App Settings
  Future<void> saveSetting(String key, dynamic value);
  Future<T?> getSetting<T>(String key);
  Future<void> deleteSetting(String key);
}