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
    print('=== STARTING SIP CONNECTION ===');
    print('User: ${user.authUser}');
    print('Server: ${user.wsUrl}');
    
    emit(user);
    
    // Direct SIP registration without ConnectionManager
    _registerSip(user);
  }
  
  void _registerSip(SipUser user) {
    UaSettings settings = UaSettings();
    
    // Parse SIP URI
    String sipUri = user.sipUri ?? '';
    String username = user.authUser;
    String domain = '';
    
    if (sipUri.contains('@')) {
      final parts = sipUri.split('@');
      if (parts.length > 1) {
        username = parts[0].replaceAll('sip:', '');
        domain = parts[1];
      }
    }
    
    String properSipUri = 'sip:$username@$domain';
    
    // Configure settings
    settings.webSocketUrl = user.wsUrl ?? '';
    settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
    settings.webSocketSettings.allowBadCertificate = true;
    settings.tcpSocketSettings.allowBadCertificate = true;
    settings.transportType = user.selectedTransport;
    settings.uri = properSipUri;
    settings.host = domain;
    settings.registrarServer = domain;
    settings.realm = null;
    settings.authorizationUser = username;
    settings.password = user.password;
    settings.displayName = user.displayName;
    settings.userAgent = 'Flutter SIP Client v1.0.0';
    settings.dtmfMode = DtmfMode.RFC2833;
    settings.register = true;
    settings.register_expires = 300;
    settings.contact_uri = null;
    
    if (user.selectedTransport != TransportType.WS && user.port.isNotEmpty) {
      settings.port = user.port;
    }
    
    print('Starting SIP with settings: ${settings.uri} via ${settings.webSocketUrl}');
    sipHelper.start(settings);
  }

  Future<void> _loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUserJson = prefs.getString('registered_sip_user');
    final isRegistered = prefs.getBool('is_registered') ?? false;
    
    print('SipUserCubit: Loading saved user - found: ${savedUserJson != null}, registered: $isRegistered');
    
    if (savedUserJson != null && isRegistered) {
      try {
        final sipUser = SipUser.fromJsonString(savedUserJson);
        emit(sipUser);
        print('SipUserCubit: Found saved user ${sipUser.authUser}, auto-connecting...');
        
        // Auto-reconnect to maintain persistent connection
        _registerSip(sipUser);
        
      } catch (e) {
        print('Error loading saved user: $e');
        await _clearSavedUser();
      }
    } else {
      print('SipUserCubit: No saved user or not registered');
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
      // Direct disconnect without ConnectionManager
      if (sipHelper.registered) {
        await sipHelper.unregister();
      }
      sipHelper.stop();
      await _clearSavedUser();
      emit(null);
      print('Disconnected and cleared saved registration');
    }
  }
  
  /// Force reconnection 
  Future<void> forceReconnect() async {
    if (state != null) {
      print('Force reconnecting...');
      if (sipHelper.registered) {
        await sipHelper.unregister();
      }
      sipHelper.stop();
      await Future.delayed(Duration(seconds: 1));
      _registerSip(state!);
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
