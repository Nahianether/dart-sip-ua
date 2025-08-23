import '../../domain/entities/sip_account_entity.dart';

class StoredCredentialsModel {
  String? id;
  
  late String username;
  late String password; // Now storing password for auto-login
  late String domain;
  late String wsUrl;
  String? displayName;
  bool isDefault = false;
  late DateTime createdAt;
  late DateTime updatedAt;

  StoredCredentialsModel() {
    final now = DateTime.now();
    createdAt = now;
    updatedAt = now;
  }

  factory StoredCredentialsModel.fromEntity(SipAccountEntity entity) {
    final model = StoredCredentialsModel()
      ..id = entity.id
      ..username = entity.username
      ..password = entity.password
      ..domain = entity.domain
      ..wsUrl = entity.wsUrl
      ..displayName = entity.displayName
      ..isDefault = false; // Set explicitly by the caller
    
    return model;
  }

  SipAccountEntity toEntity() {
    return SipAccountEntity(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      username: username,
      password: password, // Password is now stored for auto-login
      domain: domain,
      wsUrl: wsUrl,
      displayName: displayName ?? username,
    );
  }
}