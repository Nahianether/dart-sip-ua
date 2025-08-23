import '../entities/sip_account_entity.dart';
import '../repositories/sip_repository.dart';
import '../repositories/storage_repository.dart';

class ManageAccountUsecase {
  final SipRepository sipRepository;
  final StorageRepository storageRepository;

  ManageAccountUsecase(this.sipRepository, this.storageRepository);

  Future<void> loginAccount(SipAccountEntity account) async {
    // Validate account details
    if (account.username.isEmpty || account.password.isEmpty || account.domain.isEmpty) {
      throw ArgumentError('Username, password, and domain are required');
    }

    // Register with SIP server
    await sipRepository.registerAccount(account);
    
    // Save account locally
    await storageRepository.saveAccount(account);
  }

  Future<void> logoutAccount() async {
    await sipRepository.unregisterAccount();
    await storageRepository.deleteAccount();
  }

  Future<SipAccountEntity?> getCurrentAccount() async {
    return await sipRepository.getCurrentAccount();
  }

  Future<SipAccountEntity?> getStoredAccount() async {
    return await storageRepository.getStoredAccount();
  }

  Stream<ConnectionStatus> getConnectionStatus() {
    return sipRepository.getConnectionStatusStream();
  }

  Future<bool> hasStoredAccount() async {
    final account = await storageRepository.getStoredAccount();
    return account != null;
  }
}