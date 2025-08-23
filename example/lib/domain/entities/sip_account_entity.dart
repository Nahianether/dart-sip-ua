import 'package:equatable/equatable.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  registering,
  registered,
  failed
}

class SipAccountEntity extends Equatable {
  final String id;
  final String username;
  final String password;
  final String domain;
  final String wsUrl;
  final String? displayName;
  final Map<String, String>? extraHeaders;
  final ConnectionStatus status;
  final bool isDefault;

  const SipAccountEntity({
    required this.id,
    required this.username,
    required this.password,
    required this.domain,
    required this.wsUrl,
    this.displayName,
    this.extraHeaders,
    this.status = ConnectionStatus.disconnected,
    this.isDefault = false,
  });

  String get sipUri => 'sip:$username@$domain';

  SipAccountEntity copyWith({
    String? id,
    String? username,
    String? password,
    String? domain,
    String? wsUrl,
    String? displayName,
    Map<String, String>? extraHeaders,
    ConnectionStatus? status,
    bool? isDefault,
  }) {
    return SipAccountEntity(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      wsUrl: wsUrl ?? this.wsUrl,
      displayName: displayName ?? this.displayName,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      status: status ?? this.status,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  @override
  List<Object?> get props => [
        id,
        username,
        password,
        domain,
        wsUrl,
        displayName,
        extraHeaders,
        status,
        isDefault,
      ];
}