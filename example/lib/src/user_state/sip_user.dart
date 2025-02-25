// ignore_for_file: public_member_api_docs, sort_constructors_first
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
}
