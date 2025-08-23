import '../../domain/entities/sip_account_entity.dart';
import '../../domain/entities/call_entity.dart';
import '../../domain/repositories/storage_repository.dart';
import '../datasources/local_storage_datasource.dart';
import '../models/sip_account_model.dart';
import '../models/call_model.dart';

class StorageRepositoryImpl implements StorageRepository {
  final LocalStorageDataSource _localStorageDataSource;

  StorageRepositoryImpl(this._localStorageDataSource);

  @override
  Future<void> saveAccount(SipAccountEntity account) async {
    final accountModel = SipAccountModel.fromEntity(account);
    await _localStorageDataSource.saveAccount(accountModel);
  }

  @override
  Future<SipAccountEntity?> getStoredAccount() async {
    return await _localStorageDataSource.getAccount();
  }

  @override
  Future<void> deleteAccount() async {
    await _localStorageDataSource.deleteAccount();
  }

  @override
  Future<void> saveCallRecord(CallEntity call) async {
    final callModel = CallModel.fromEntity(call);
    await _localStorageDataSource.saveCallRecord(callModel);
  }

  @override
  Future<List<CallEntity>> getCallHistory() async {
    final callModels = await _localStorageDataSource.getCallHistory();
    return callModels.cast<CallEntity>();
  }

  @override
  Future<void> clearCallHistory() async {
    await _localStorageDataSource.clearCallHistory();
  }

  @override
  Future<void> saveSetting(String key, dynamic value) async {
    await _localStorageDataSource.saveSetting(key, value);
  }

  @override
  Future<T?> getSetting<T>(String key) async {
    return await _localStorageDataSource.getSetting<T>(key);
  }

  @override
  Future<void> deleteSetting(String key) async {
    await _localStorageDataSource.deleteSetting(key);
  }
}