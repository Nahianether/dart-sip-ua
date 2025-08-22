import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'user_state/sip_user.dart';
import 'persistent_background_service.dart';
import 'vpn_manager.dart';
import 'ringtone_service.dart';

/// Simple WebSocket-only SIP connection manager
class WebSocketConnectionManager implements SipUaHelperListener {
  static final WebSocketConnectionManager _instance = WebSocketConnectionManager._internal();
  factory WebSocketConnectionManager() => _instance;
  WebSocketConnectionManager._internal();

  final Logger _logger = Logger();
  late SIPUAHelper _sipHelper;
  VPNManager? _vpnManager;
  Timer? _reconnectionTimer;
  SipUser? _currentUser;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  
  // Connection state tracking
  bool _isConnecting = false;
  bool _shouldMaintainConnection = false;
  bool _hasNetworkConnectivity = true;
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 10;
  
  // Callbacks for UI updates
  Function(RegistrationState)? onRegistrationStateChanged;
  Function(Call, CallState)? onCallStateChanged;
  Function(TransportState)? onTransportStateChanged;

  void initialize(SIPUAHelper sipHelper) {
    _logger.i('WebSocketConnectionManager: Initializing...');
    _sipHelper = sipHelper;
    _vpnManager = VPNManager();
    _setupNetworkMonitoring();
    _loadSavedConnectionAndAutoConnect();
  }
  
  VPNManager get vpnManager => _vpnManager ?? VPNManager();
  bool get isVpnConnected => _vpnManager?.isConnected ?? false;
  
  void _setupNetworkMonitoring() {
    _hasNetworkConnectivity = true;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool hasConnectivity = results.isNotEmpty && 
          results.any((result) => result != ConnectivityResult.none);
      
      if (!_hasNetworkConnectivity && hasConnectivity) {
        _logger.i('Network restored, attempting reconnection');
        _hasNetworkConnectivity = true;
        if (_shouldMaintainConnection && !_sipHelper.registered && !_isConnecting) {
          _reconnectionAttempts = 0;
          Future.delayed(Duration(seconds: 2), () => _connectWithRetry());
        }
      }
      _hasNetworkConnectivity = hasConnectivity;
    });
  }

  /// Start maintaining persistent WebSocket connection
  Future<void> startPersistentConnection(SipUser user) async {
    _logger.i('🔄 Starting persistent WebSocket connection for user: ${user.authUser}');
    
    // Stop any existing connection first
    if (_sipHelper.registered) {
      _logger.i('🛑 Stopping existing connection...');
      try {
        await _sipHelper.unregister();
        _sipHelper.stop();
        await Future.delayed(Duration(milliseconds: 1000));
      } catch (e) {
        _logger.w('Warning during connection cleanup: $e');
      }
    }
    
    _currentUser = user;
    _shouldMaintainConnection = true;
    _reconnectionAttempts = 0;
    
    _sipHelper.addSipUaHelperListener(this);
    await _saveConnectionSettings(user);
    await _connectWithRetry();
    
    // Update background service with new user configuration
    await PersistentBackgroundService.updateSipUserInService(user);
  }

  Future<void> _connectWithRetry() async {
    if (_isConnecting || _currentUser == null) return;
    if (!_hasNetworkConnectivity) {
      _logger.w('No network connectivity, skipping connection attempt');
      return;
    }
    
    _isConnecting = true;
    _logger.i('🔄 Starting WebSocket connection attempt ${_reconnectionAttempts + 1}');
    
    try {
      if (_sipHelper.registered) {
        await _sipHelper.unregister();
        _sipHelper.stop();
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      await _connectWebSocket(_currentUser!);
      _logger.i('✅ WebSocket connection attempt completed');
    } catch (e) {
      _logger.e('❌ WebSocket connection failed: $e');
      _scheduleReconnection();
    }
    
    _isConnecting = false;
  }

  Future<void> _connectWebSocket(SipUser user) async {
    _logger.i('🔌 Attempting WebSocket SIP connection...');
    _logger.i('📋 Connection details:');
    _logger.i('   User: ${user.authUser}');
    _logger.i('   WebSocket URL: ${user.wsUrl}');
    
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
    } else if (user.wsUrl != null && user.wsUrl!.isNotEmpty) {
      try {
        final uri = Uri.parse(user.wsUrl!);
        domain = uri.host;
      } catch (e) {
        _logger.w('Failed to parse domain from WebSocket URL: $e');
        domain = 'localhost';
      }
    }
    
    String properSipUri = 'sip:$username@$domain';
    
    // Validation
    if (username.isEmpty || domain.isEmpty) {
      throw Exception('Invalid SIP configuration: Username or domain is empty');
    }
    
    // Configure WebSocket settings
    final serverUrl = user.wsUrl ?? '';
    settings.transportType = TransportType.WS;
    settings.webSocketUrl = serverUrl;
    settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
    settings.webSocketSettings.allowBadCertificate = true;
    
    // Auto-correct WebSocket URL format
    if (!serverUrl.startsWith('ws://') && !serverUrl.startsWith('wss://')) {
      String correctedUrl = serverUrl.contains(':443') || serverUrl.toLowerCase().contains('secure') 
          ? 'wss://$serverUrl' 
          : 'ws://$serverUrl';
      _logger.i('Corrected WebSocket URL: $correctedUrl');
      settings.webSocketUrl = correctedUrl;
    }
    
    // Set SIP settings
    settings.uri = properSipUri;
    settings.registrarServer = domain;
    settings.authorizationUser = username;
    settings.password = user.password;
    settings.displayName = user.displayName.isNotEmpty ? user.displayName : username;
    settings.userAgent = 'Flutter WebSocket SIP Client';
    settings.dtmfMode = DtmfMode.RFC2833;
    settings.register = true;
    settings.register_expires = 600; // Increase to 10 minutes for stability
    
    // CRITICAL: Set fixed contact URI to prevent random SIP IDs
    // This prevents the library from generating random tokens
    settings.contact_uri = 'sip:$username@$domain;transport=ws';
    
    // Debug logging
    _logger.i('🔧 SIP Settings configured:');
    _logger.i('   URI: ${settings.uri}');
    _logger.i('   AuthUser: ${settings.authorizationUser}');
    _logger.i('   Contact URI: ${settings.contact_uri}');
    _logger.i('   Display: ${settings.displayName}');
    
    // Enable session timers for connection stability
    settings.sessionTimers = true;
    
    // Set host from WebSocket URL
    try {
      Uri wsUri = Uri.parse(settings.webSocketUrl!);
      settings.host = wsUri.host.isNotEmpty ? wsUri.host : domain;
    } catch (e) {
      settings.host = domain;
    }
    
    _logger.i('🚀 Starting WebSocket SIP connection to: ${settings.webSocketUrl}');
    
    try {
      await _sipHelper.start(settings);
      _logger.i('✅ WebSocket SIP connection started successfully');
    } catch (e) {
      _logger.e('❌ WebSocket SIP connection failed: $e');
      
      // WebSocket-specific error handling
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('handshake') || errorMsg.contains('upgrade')) {
        _logger.e('WebSocket handshake failed - check server support');
      } else if (errorMsg.contains('connection refused')) {
        _logger.e('WebSocket connection refused - check server and port');
      }
      
      rethrow;
    }
  }

  void _scheduleReconnection() {
    if (!_shouldMaintainConnection) return;
    if (!_hasNetworkConnectivity) return;
    
    _reconnectionAttempts++;
    if (_reconnectionAttempts > _maxReconnectionAttempts) {
      _logger.e('Max reconnection attempts reached');
      return;
    }
    
    int delay = 5 + (_reconnectionAttempts * 2); // Progressive delay
    _logger.w('Scheduling reconnection in $delay seconds');
    
    _reconnectionTimer = Timer(Duration(seconds: delay), () {
      if (_shouldMaintainConnection && _hasNetworkConnectivity) {
        _connectWithRetry();
      }
    });
  }

  /// Stop maintaining connection
  Future<void> stopPersistentConnection() async {
    _logger.i('Stopping persistent WebSocket connection');
    _shouldMaintainConnection = false;
    _reconnectionTimer?.cancel();
    _isConnecting = false;
    
    _sipHelper.removeSipUaHelperListener(this);
    
    if (_sipHelper.registered) {
      await _sipHelper.unregister();
    }
    _sipHelper.stop();
    
    await _clearConnectionSettings();
    PersistentBackgroundService.stopService();
  }

  /// Force reconnection
  Future<void> forceReconnect() async {
    if (_currentUser == null) return;
    _logger.i('Force reconnecting...');
    _reconnectionAttempts = 0;
    await _connectWithRetry();
  }

  bool get isConnected => _sipHelper.registered;
  bool get shouldMaintainConnection => _shouldMaintainConnection;

  Map<String, dynamic> getConnectionStatus() {
    return {
      'isConnected': _sipHelper.registered,
      'shouldMaintainConnection': _shouldMaintainConnection,
      'isConnecting': _isConnecting,
      'hasNetworkConnectivity': _hasNetworkConnectivity,
      'reconnectionAttempts': _reconnectionAttempts,
      'maxReconnectionAttempts': _maxReconnectionAttempts,
      'vpnConnected': _vpnManager?.isConnected ?? false,
      'currentUser': _currentUser?.authUser ?? 'None',
      'wsUrl': _currentUser?.wsUrl ?? 'None',
    };
  }

  void performConnectionStatusCheck() {
    final status = getConnectionStatus();
    _logger.i('📊 WEBSOCKET CONNECTION STATUS REPORT:');
    status.forEach((key, value) {
      _logger.i('  $key: $value');
    });
    
    // Force immediate action if needed
    if (status['shouldMaintainConnection'] == true && 
        status['isConnected'] == false && 
        status['isConnecting'] == false) {
      _logger.w('🚨 Status check reveals disconnected state - forcing WebSocket reconnection');
      if (_hasNetworkConnectivity) {
        _connectWithRetry();
      }
    }
  }

  Future<void> _saveConnectionSettings(SipUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('websocket_sip_user', user.toJsonString());
    await prefs.setBool('should_maintain_websocket_connection', true);
  }

  Future<void> _clearConnectionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('websocket_sip_user');
    await prefs.setBool('should_maintain_websocket_connection', false);
  }

  Future<void> _loadSavedConnectionAndAutoConnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('websocket_sip_user');
      final shouldMaintain = prefs.getBool('should_maintain_websocket_connection') ?? false;
      
      if (savedUserJson != null && shouldMaintain) {
        _logger.i('Found saved WebSocket connection, scheduling auto-connect...');
        final sipUser = SipUser.fromJsonString(savedUserJson);
        
        Future.delayed(Duration(seconds: 3), () async {
          if (!_shouldMaintainConnection) {
            await startPersistentConnection(sipUser);
          }
        });
      }
    } catch (e) {
      _logger.e('Error loading saved WebSocket connection: $e');
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    _logger.i('WebSocket Registration: ${state.state}');
    
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _logger.i('✅ WebSocket SIP Registration Successful!');
        _reconnectionAttempts = 0;
        PersistentBackgroundService.startService();
        break;
        
      case RegistrationStateEnum.UNREGISTERED:
        _logger.w('🔌 Unregistered from WebSocket SIP server');
        if (_shouldMaintainConnection && !_isConnecting) {
          _scheduleReconnection();
        }
        break;
        
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _logger.e('❌ WebSocket Registration Failed');
        if (_shouldMaintainConnection && !_isConnecting) {
          _scheduleReconnection();
        }
        break;
        
      case RegistrationStateEnum.NONE:
        _logger.i('Registration state: NONE');
        break;
        
      case null:
        _logger.w('Registration state is null');
        break;
    }
    
    onRegistrationStateChanged?.call(state);
  }

  @override
  void transportStateChanged(TransportState state) {
    _logger.i('WebSocket Transport state: ${state.state}');
    
    if (state.state == TransportStateEnum.DISCONNECTED) {
      if (_shouldMaintainConnection && !_isConnecting && _reconnectionTimer == null) {
        _logger.i('WebSocket transport disconnected, scheduling reconnection...');
        _scheduleReconnection();
      }
    }
    
    onTransportStateChanged?.call(state);
  }

  @override
  void callStateChanged(Call call, CallState state) {
    _logger.i('WebSocket Call state: ${state.state}');
    
    // CRITICAL: Handle incoming calls here!
    print('🔍 Checking call: State=${state.state}, Direction=${call.direction}');
    if (state.state == CallStateEnum.CALL_INITIATION && call.direction == Direction.incoming) {
      print('🚨🚨🚨 INCOMING CALL DETECTED in WebSocketConnectionManager! 🚨🚨🚨');
      print('📞 Call ID: ${call.id}');
      print('📞 Remote identity: ${call.remote_identity}');
      print('📞 Direction: ${call.direction}');
      
      // Start ringing immediately
      print('🔔 Starting ringtone...');
      RingtoneService.startRinging();
      
      // Trigger the incoming call UI
      print('📞 Triggering incoming call screen...');
      _triggerIncomingCallScreen(call);
    } else {
      print('❌ Call does not match incoming criteria: State=${state.state}, Direction=${call.direction}');
    }
    
    onCallStateChanged?.call(call, state);
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}


  // Callback for incoming call navigation
  static Function(Call)? _onIncomingCallCallback;
  
  static void setIncomingCallCallback(Function(Call) callback) {
    _onIncomingCallCallback = callback;
  }

  void _triggerIncomingCallScreen(Call call) async {
    print('📞🔥 ACTIVE APP: _triggerIncomingCallScreen called for call: ${call.id}');
    print('📱 ACTIVE APP: Navigating directly to call screen - NO NOTIFICATION NEEDED');
    
    try {
      // CRITICAL: Since main app is active, use callback for direct navigation
      if (_onIncomingCallCallback != null) {
        print('🚀 ACTIVE APP: Using callback for direct navigation to call screen: ${call.remote_identity}');
        _onIncomingCallCallback!(call);
        print('✅ ACTIVE APP: Callback executed successfully');
      } else {
        print('❌ ACTIVE APP: No navigation callback available');
        
        // Fallback: Use platform channel but mark as active app
        const MethodChannel incomingCallChannel = MethodChannel('sip_phone/incoming_call');
        
        await incomingCallChannel.invokeMethod('handleIncomingCall', {
          'caller': call.remote_identity ?? 'Unknown',
          'callId': call.id,
          'fromNotification': false,
          'fromBackground': false,
          'fromActiveApp': true,
          'showIncomingCallScreen': true,
        });
        
        print('📞 ACTIVE APP: Fallback platform channel call made');
      }
    } catch (e) {
      print('❌ ACTIVE APP: Error triggering incoming call screen: $e');
    }
  }

  void dispose() {
    _reconnectionTimer?.cancel();
    _connectivitySubscription.cancel();
    _sipHelper.removeSipUaHelperListener(this);
  }
}