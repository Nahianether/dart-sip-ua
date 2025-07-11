import 'package:bloc/bloc.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:dart_sip_ua_example/src/background_service.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SipUserCubit extends Cubit<SipUser?> implements SipUaHelperListener {
  final SIPUAHelper sipHelper;
  bool _isRegistered = false;
  
  SipUserCubit({required this.sipHelper}) : super(null) {
    sipHelper.addSipUaHelperListener(this);
    _loadSavedUser();
  }

  void register(SipUser user) {
    UaSettings settings = UaSettings();
    
    // Parse SIP URI to get username and domain
    String sipUri = user.sipUri ?? '';
    String username = user.authUser;
    String domain = '';
    
    // Debug input values
    print('=== SIP REGISTRATION DEBUG ===');
    print('Input SIP URI: $sipUri');
    print('Input Auth User: $username');
    print('Input WS URL: ${user.wsUrl}');
    
    if (sipUri.contains('@')) {
      final parts = sipUri.split('@');
      if (parts.length > 1) {
        username = parts[0].replaceAll('sip:', '');
        domain = parts[1];
      }
    } else if (sipUri.isNotEmpty) {
      domain = sipUri;
    }
    
    // Debug parsed values
    print('Parsed username: $username');
    print('Parsed domain: $domain');
    
    // Construct proper SIP URI
    String properSipUri = 'sip:$username@$domain';
    print('Constructed SIP URI: $properSipUri');
    
    // WebSocket configuration
    settings.webSocketUrl = user.wsUrl ?? '';
    settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
    settings.webSocketSettings.allowBadCertificate = true;
    settings.tcpSocketSettings.allowBadCertificate = true;
    settings.transportType = user.selectedTransport;
    
    // SIP configuration matching web client exactly
    settings.uri = properSipUri;
    settings.host = domain;
    settings.registrarServer = domain;
    settings.realm = null; // Let server challenge determine it
    settings.authorizationUser = username;
    settings.password = user.password;
    settings.displayName = user.displayName;
    settings.userAgent = 'JsSIP 3.10.0';
    settings.dtmfMode = DtmfMode.RFC2833;
    settings.register = true;
    settings.register_expires = 600;
    
    // Try using null contact_uri and let the library generate it like web client
    settings.contact_uri = null;
    
    // Debug final settings
    print('Final Settings:');
    print('  uri: ${settings.uri}');
    print('  host: ${settings.host}');
    print('  registrarServer: ${settings.registrarServer}');
    print('  realm: ${settings.realm} (null = server will determine)');
    print('  authorizationUser: ${settings.authorizationUser}');
    print('  webSocketUrl: ${settings.webSocketUrl}');
    print('  contact_uri: ${settings.contact_uri}');
    print('  via_host will be set to: ${settings.host}');
    print('  domain extracted: $domain');
    
    // Set port if provided and not using WebSocket
    if (user.selectedTransport != TransportType.WS && user.port.isNotEmpty) {
      settings.port = user.port;
    }
    
    // Simple debug logging
    print('=== FINAL SIP SETTINGS ===');
    print('URI: ${settings.uri}');
    print('WebSocket URL: ${settings.webSocketUrl}');
    print('Auth User: ${settings.authorizationUser}');
    print('Password: ${settings.password}');
    print('Realm: ${settings.realm}');
    print('==========================');

    print('=== STARTING SIP HELPER ===');
    
    emit(user);
    sipHelper.start(settings);
  }

  Future<void> _loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUserJson = prefs.getString('registered_sip_user');
    final isRegistered = prefs.getBool('is_registered') ?? false;
    
    if (savedUserJson != null && isRegistered) {
      try {
        final sipUser = SipUser.fromJsonString(savedUserJson);
        emit(sipUser);
        // Auto-reconnect if was previously registered
        print('Auto-reconnecting to SIP server...');
        register(sipUser);
      } catch (e) {
        print('Error loading saved user: $e');
        await _clearSavedUser();
      }
    }
  }

  Future<void> _saveUser(SipUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('registered_sip_user', user.toJsonString());
  }

  Future<void> _markAsRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_registered', true);
    _isRegistered = true;
  }

  Future<void> _clearSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('registered_sip_user');
    await prefs.setBool('is_registered', false);
    _isRegistered = false;
  }

  Future<void> disconnect() async {
    if (state != null) {
      sipHelper.stop();
      await _clearSavedUser();
      // Stop background service when manually disconnecting
      BackgroundService.stopService();
      emit(null);
      print('Disconnected and cleared saved registration');
    }
  }

  bool get isRegistered => _isRegistered;

  @override
  void registrationStateChanged(RegistrationState state) {
    print('SipUserCubit: Registration state changed to ${state.state}');
    
    if (state.state == RegistrationStateEnum.REGISTERED) {
      if (this.state != null) {
        _markAsRegistered();
        _saveUser(this.state!);
        // Start background service when successfully registered
        BackgroundService.startService();
        print('Registration successful - saved user data and started background service');
      }
    } else if (state.state == RegistrationStateEnum.UNREGISTERED ||
               state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      _clearSavedUser();
      // Stop background service when unregistered
      BackgroundService.stopService();
      print('Registration failed/unregistered - cleared saved data and stopped background service');
    }
  }

  @override
  void callStateChanged(Call call, CallState state) {
    // No-op for now
  }

  @override
  void transportStateChanged(TransportState state) {
    // No-op for now
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    // No-op for now
  }

  @override
  void onNewNotify(Notify ntf) {
    // No-op for now
  }

  @override
  void onNewReinvite(ReInvite event) {
    // No-op for now
  }

  @override
  Future<void> close() {
    sipHelper.removeSipUaHelperListener(this);
    return super.close();
  }

  // void register(SipUser user) {
  //   UaSettings settings = UaSettings();
  //   settings.port = user.port; // Default port if unset
  //   settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
  //   settings.webSocketSettings.allowBadCertificate = true;
  //   settings.tcpSocketSettings.allowBadCertificate = true;
  //   settings.transportType = user.selectedTransport; // Default to WebSocket

  //   // Ensure sipUri is properly formatted
  //   String sipUri = user.sipUri ?? '';
  //   if (!sipUri.contains('@')) {
  //     sipUri = 'sip:${user.authUser ?? '7000'}@$sipUri'; // Fallback to authUser
  //   }
  //   settings.uri = sipUri;
  //   settings.webSocketUrl = user.wsUrl ?? 'wss://pbx.ibos.io:8089/ws'; // Your WebSocket URL

  //   // Safely extract host
  //   final uriParts = sipUri.split('@');
  //   settings.host = uriParts.length > 1 ? uriParts[1] : uriParts[0]; // Fallback to full string if no '@'

  //   settings.authorizationUser = user.authUser ?? '7000'; // Your user
  //   settings.password = user.password ?? 'wss#7000'; // Your password
  //   settings.displayName = user.displayName ?? 'User 7000';
  //   settings.userAgent = 'Dart SIP Client v1.0.0';
  //   settings.dtmfMode = DtmfMode.RFC2833;
  //   settings.contact_uri = 'sip:$sipUri';

  //   emit(user); // Update state with corrected URI
  //   sipHelper.start(settings);
  // }
}
