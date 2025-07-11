// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'package:sip_ua/sip_ua.dart';

class SipUser {
  final String port;
  final String displayName;
  final String? wsUrl;
  final String? sipUri;
  final String password;
  final String authUser;
  final TransportType selectedTransport;
  final Map<String, String>? wsExtraHeaders;

  SipUser({
    required this.port,
    required this.displayName,
    required this.password,
    required this.authUser,
    required this.selectedTransport,
    this.wsExtraHeaders,
    this.wsUrl,
    this.sipUri,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SipUser &&
        other.port == port &&
        other.displayName == displayName &&
        other.wsUrl == wsUrl &&
        other.sipUri == sipUri &&
        other.selectedTransport == selectedTransport &&
        other.wsExtraHeaders == wsExtraHeaders &&
        other.password == password &&
        other.authUser == authUser;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      port,
      displayName,
      wsUrl,
      sipUri,
      password,
      wsExtraHeaders,
      selectedTransport,
      authUser,
    ]);
  }

  SipUser copyWith({
    String? port,
    String? displayName,
    String? wsUrl,
    String? sipUri,
    String? password,
    String? authUser,
    TransportType? selectedTransport,
    Map<String, String>? wsExtraHeaders,
  }) {
    return SipUser(
      port: port ?? this.port,
      displayName: displayName ?? this.displayName,
      wsUrl: wsUrl ?? this.wsUrl,
      sipUri: sipUri ?? this.sipUri,
      password: password ?? this.password,
      authUser: authUser ?? this.authUser,
      selectedTransport: selectedTransport ?? this.selectedTransport,
      wsExtraHeaders: wsExtraHeaders ?? this.wsExtraHeaders,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'port': port,
      'displayName': displayName,
      'wsUrl': wsUrl,
      'sipUri': sipUri,
      'password': password,
      'authUser': authUser,
      'selectedTransport': selectedTransport.index,
      'wsExtraHeaders': wsExtraHeaders,
    };
  }

  factory SipUser.fromJson(Map<String, dynamic> json) {
    return SipUser(
      port: json['port'] ?? '',
      displayName: json['displayName'] ?? '',
      wsUrl: json['wsUrl'],
      sipUri: json['sipUri'],
      password: json['password'] ?? '',
      authUser: json['authUser'] ?? '',
      selectedTransport: TransportType.values[json['selectedTransport'] ?? 0],
      wsExtraHeaders: json['wsExtraHeaders'] != null 
        ? Map<String, String>.from(json['wsExtraHeaders'])
        : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());
  
  factory SipUser.fromJsonString(String jsonString) => 
    SipUser.fromJson(jsonDecode(jsonString));
}
