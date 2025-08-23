import '../../domain/entities/sip_account_entity.dart';

class StoredCredentialsModel {
  String? id;
  
  late String username;
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
      password: '', // Password is not stored for security
      domain: domain,
      wsUrl: wsUrl,
      displayName: displayName ?? username,
    );
  }
}