import 'dart:convert';
import '../../domain/entities/sip_account_entity.dart';

class SipAccountModel extends SipAccountEntity {
  const SipAccountModel({
    required super.id,
    required super.username,
    required super.password,
    required super.domain,
    required super.wsUrl,
    super.displayName,
    super.extraHeaders,
    super.status,
    super.isDefault,
  });

  // Convert from entity
  factory SipAccountModel.fromEntity(SipAccountEntity entity) {
    return SipAccountModel(
      id: entity.id,
      username: entity.username,
      password: entity.password,
      domain: entity.domain,
      wsUrl: entity.wsUrl,
      displayName: entity.displayName,
      extraHeaders: entity.extraHeaders,
      status: entity.status,
      isDefault: entity.isDefault,
    );
  }

  // Convert from JSON
  factory SipAccountModel.fromJson(Map<String, dynamic> json) {
    return SipAccountModel(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      password: json['password'] ?? '',
      domain: json['domain'] ?? '',
      wsUrl: json['wsUrl'] ?? '',
      displayName: json['displayName'],
      extraHeaders: json['extraHeaders'] != null 
          ? Map<String, String>.from(json['extraHeaders'])
          : null,
      status: _connectionStatusFromString(json['status']),
      isDefault: json['isDefault'] ?? false,
    );
  }

  // Convert from JSON string
  factory SipAccountModel.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString);
    return SipAccountModel.fromJson(json);
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'domain': domain,
      'wsUrl': wsUrl,
      'displayName': displayName,
      'extraHeaders': extraHeaders,
      'status': status.name,
      'isDefault': isDefault,
    };
  }

  // Convert to JSON string
  String toJsonString() {
    return jsonEncode(toJson());
  }

  static ConnectionStatus _connectionStatusFromString(String? status) {
    switch (status) {
      case 'connecting':
        return ConnectionStatus.connecting;
      case 'connected':
        return ConnectionStatus.connected;
      case 'registering':
        return ConnectionStatus.registering;
      case 'registered':
        return ConnectionStatus.registered;
      case 'failed':
        return ConnectionStatus.failed;
      default:
        return ConnectionStatus.disconnected;
    }
  }
}