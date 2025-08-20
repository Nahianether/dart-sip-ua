import 'package:bloc/bloc.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:dart_sip_ua_example/src/persistent_background_service.dart';
import 'package:dart_sip_ua_example/src/websocket_connection_manager.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SipUserCubit extends Cubit<SipUser?> implements SipUaHelperListener {
  final SIPUAHelper sipHelper;
  late final WebSocketConnectionManager _connectionManager;
  bool _isRegistered = false;
  
  SipUserCubit({required this.sipHelper}) : super(null) {
    // DO NOT add SIP listener here - let ConnectionManager handle it exclusively
    _connectionManager = WebSocketConnectionManager();
    _connectionManager.initialize(sipHelper);
    
    // Set up callbacks from ConnectionManager to update UI
    _connectionManager.onRegistrationStateChanged = (state) {
      registrationStateChanged(state);
    };
    _connectionManager.onCallStateChanged = (call, state) {
      print('🔔 SipUserCubit: Forwarding call state from ConnectionManager: ${state.state}');
      callStateChanged(call, state);
      
      // The call state is already forwarded by ConnectionManager to all listeners
      // No need to manually call sipHelper methods - it handles the events automatically
    };
    _connectionManager.onTransportStateChanged = (state) {
      transportStateChanged(state);
    };
    
    _loadSavedUser();
  }

  void register(SipUser user) {
    print('=== STARTING PERSISTENT SIP CONNECTION ===');
    print('User: ${user.authUser}');
    print('Server: ${user.wsUrl}');
    
    emit(user);
    
    // Use ConnectionManager for persistent connection
    _connectionManager.startPersistentConnection(user);
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
        print('SipUserCubit: Found saved user ${sipUser.authUser}, will be managed by ConnectionManager auto-connect...');
        
        // Don't start connection here - let ConnectionManager handle auto-connect
        // This prevents duplicate connection attempts
        print('SipUserCubit: Connection will be handled by ConnectionManager delayed auto-connect');
        
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
      print('🔌 User-initiated disconnect - stopping persistent connection');
      // Stop persistent connection through ConnectionManager
      await _connectionManager.stopPersistentConnection();
      await _clearSavedUser(); // Clear data for manual disconnect
      emit(null);
      print('Disconnected and cleared saved registration');
    }
  }
  
  /// Clear saved user data - only call for permanent disconnects
  Future<void> permanentDisconnect() async {
    print('🚫 Permanent disconnect - clearing saved user data');
    await _clearSavedUser();
    emit(null);
  }
  
  /// Force reconnection 
  Future<void> forceReconnect() async {
    if (state != null) {
      print('🔄 Force reconnecting via ConnectionManager...');
      await _connectionManager.forceReconnect();
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
        PersistentBackgroundService.startService();
        print('Registration successful - saved user data and started background service');
      }
    } else if (state.state == RegistrationStateEnum.UNREGISTERED ||
               state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      _isRegistered = false; // Mark as not registered but keep user data
      // ConnectionManager will handle reconnection attempts automatically
      
      // Stop background service when unregistered
      PersistentBackgroundService.stopService();
      print('Registration failed/unregistered - ConnectionManager will handle reconnection');
    }
  }

  @override
  void callStateChanged(Call call, CallState state) {
    print('🔔 SipUserCubit: Call state changed: ${state.state}');
    print('📞 Call ID: ${call.id}, Direction: ${call.direction}');
    // This is handled by ConnectionManager callbacks, but kept for debugging
  }

  @override
  void transportStateChanged(TransportState state) {
    print('SipUserCubit: Transport state changed to ${state.state}');
    
    if (state.state == TransportStateEnum.DISCONNECTED && this.state != null) {
      print('🔌 Transport disconnected - ConnectionManager will handle reconnection');
      _isRegistered = false;
    }
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
