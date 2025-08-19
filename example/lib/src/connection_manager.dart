import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'user_state/sip_user.dart';
import 'background_service.dart';
import 'vpn_manager.dart';

/// Manages persistent SIP connections with automatic reconnection
class ConnectionManager implements SipUaHelperListener {
  static final ConnectionManager _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  final Logger _logger = Logger();
  late SIPUAHelper _sipHelper;
  VPNManager? _vpnManager;
  Timer? _reconnectionTimer;
  Timer? _heartbeatTimer;
  SipUser? _currentUser;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  
  // Aggressive reconnection strategy for SIP calling app
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 50; // More attempts for calling app
  static const int _baseDelaySeconds = 1; // Faster initial retry
  static const int _maxDelaySeconds = 60; // Max 1 minute delay
  
  // Connection state
  bool _isConnecting = false;
  bool _shouldMaintainConnection = false;
  DateTime? _lastSuccessfulConnection;
  bool _hasNetworkConnectivity = true;
  Timer? _connectionMonitorTimer;
  Timer? _connectionTimeoutTimer;
  DateTime? _lastConnectionAttempt;
  
  // Callbacks for UI updates
  Function(RegistrationState)? onRegistrationStateChanged;
  Function(Call, CallState)? onCallStateChanged;
  Function(TransportState)? onTransportStateChanged;

  void initialize(SIPUAHelper sipHelper) {
    _logger.i('ConnectionManager: Initializing for persistent SIP connection...');
    _sipHelper = sipHelper;
    _setupNetworkMonitoring();
    
    // Initialize VPN Manager lazily
    _initializeVPN();
    
    // Check for saved connection and auto-connect if available
    _loadSavedConnectionAndAutoConnect();
  }
  
  Future<void> _initializeVPN() async {
    try {
      _vpnManager ??= VPNManager();
      await _vpnManager!.initialize();
      _logger.i('VPN Manager initialized successfully');
    } catch (e) {
      _logger.e('VPN Manager initialization failed: $e');
    }
  }

  void _setupNetworkMonitoring() {
    // Start with assuming connectivity is available
    _hasNetworkConnectivity = true;
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool hasConnectivity = results.isNotEmpty && 
          results.any((result) => result != ConnectivityResult.none);
      
      _logger.i('Network connectivity changed: $hasConnectivity (was: $_hasNetworkConnectivity)');
      
      // Only act on significant connectivity changes, not initial false negatives
      if (!_hasNetworkConnectivity && hasConnectivity) {
        // Network restored - attempt immediate reconnection
        _logger.i('Network restored, attempting immediate reconnection');
        _hasNetworkConnectivity = true;
        if (_shouldMaintainConnection && !_sipHelper.registered && !_isConnecting) {
          _reconnectionAttempts = 0; // Reset attempts on network restore
          Future.delayed(Duration(seconds: 2), () => _connectWithRetry());
        }
      } else if (_hasNetworkConnectivity && !hasConnectivity) {
        // Network lost - but only if we've been running for a while
        _logger.w('Network connectivity lost');
        _hasNetworkConnectivity = false;
        _stopReconnectionTimer(); // Don't waste attempts when no network
      }
      
      _hasNetworkConnectivity = hasConnectivity;
    });
  }

  /// Start maintaining persistent connection
  Future<void> startPersistentConnection(SipUser user) async {
    _logger.i('🔄 Starting persistent connection for user: ${user.authUser}');
    
    // Stop any existing connection first to avoid conflicts
    if (_sipHelper.registered) {
      _logger.i('🛑 Stopping existing connection to avoid conflicts...');
      try {
        await _sipHelper.unregister();
        _sipHelper.stop();
        await Future.delayed(Duration(milliseconds: 1000)); // Wait for clean shutdown
      } catch (e) {
        _logger.w('Warning during connection cleanup: $e');
      }
    }
    
    _currentUser = user;
    _shouldMaintainConnection = true;
    _reconnectionAttempts = 0;
    
    // Add SIP listener only when actually managing connection
    _sipHelper.addSipUaHelperListener(this);
    
    await _saveConnectionSettings(user);
    await _connectWithRetry();
    _startHeartbeat();
  }

  /// Stop maintaining persistent connection
  Future<void> stopPersistentConnection() async {
    _logger.i('Stopping persistent connection');
    _shouldMaintainConnection = false;
    _stopReconnectionTimer();
    _stopHeartbeat();
    _stopConnectionTimeout();
    _isConnecting = false;
    
    // Remove SIP listener
    _sipHelper.removeSipUaHelperListener(this);
    
    if (_sipHelper.registered) {
      await _sipHelper.unregister();
    }
    _sipHelper.stop();
    
    await _clearConnectionSettings();
    BackgroundService.stopService();
  }

  /// Force immediate reconnection
  Future<void> forceReconnect() async {
    if (_currentUser == null) {
      _logger.w('Cannot reconnect: No saved user');
      return;
    }
    
    _logger.i('Force reconnecting...');
    _reconnectionAttempts = 0;
    await _connectWithRetry();
  }
  
  /// Configure VPN for secure SIP connection
  Future<void> configureVPN({
    required String serverAddress,
    required String username,
    required String password,
    String? customConfig,
    bool enableAutoConnect = true,
  }) async {
    try {
      _logger.i('Configuring VPN for secure SIP connection...');
      
      // Ensure VPN manager is initialized
      _vpnManager ??= VPNManager();
      
      await _vpnManager!.configureVPN(
        serverAddress: serverAddress,
        username: username,
        password: password,
        customConfig: customConfig,
      );
      
      _vpnManager!.enableAutoConnect(enableAutoConnect);
      
      _logger.i('VPN configuration completed');
    } catch (e) {
      _logger.e('VPN configuration failed: $e');
      rethrow;
    }
  }
  
  /// Test VPN connection
  Future<bool> testVPNConnection() async {
    try {
      _logger.i('Testing VPN connection...');
      return await _connectVPN();
    } catch (e) {
      _logger.e('VPN test failed: $e');
      return false;
    }
  }
  
  /// Disconnect VPN
  Future<void> disconnectVPN() async {
    try {
      _logger.i('Disconnecting VPN...');
      _vpnManager ??= VPNManager();
      await _vpnManager!.disconnect();
    } catch (e) {
      _logger.e('VPN disconnect failed: $e');
    }
  }

  /// Check if connection is active
  bool get isConnected => _sipHelper.registered;
  
  /// Check if should maintain connection
  bool get shouldMaintainConnection => _shouldMaintainConnection;
  
  /// Get VPN manager for configuration
  VPNManager get vpnManager {
    _vpnManager ??= VPNManager();
    return _vpnManager!;
  }
  
  /// Get comprehensive connection status for monitoring
  Map<String, dynamic> getConnectionStatus() {
    final now = DateTime.now();
    return {
      'isConnected': _sipHelper.registered,
      'shouldMaintainConnection': _shouldMaintainConnection,
      'isConnecting': _isConnecting,
      'hasNetworkConnectivity': _hasNetworkConnectivity,
      'reconnectionAttempts': _reconnectionAttempts,
      'maxReconnectionAttempts': _maxReconnectionAttempts,
      'lastSuccessfulConnection': _lastSuccessfulConnection?.toIso8601String(),
      'lastConnectionAttempt': _lastConnectionAttempt?.toIso8601String(),
      'secondsSinceLastConnection': _lastSuccessfulConnection != null 
          ? now.difference(_lastSuccessfulConnection!).inSeconds 
          : null,
      'secondsSinceLastAttempt': _lastConnectionAttempt != null 
          ? now.difference(_lastConnectionAttempt!).inSeconds 
          : null,
      'hasCurrentUser': _currentUser != null,
      'currentUserName': _currentUser?.authUser,
    };
  }
  
  /// Force immediate connection status check and report
  void performConnectionStatusCheck() {
    final status = getConnectionStatus();
    _logger.i('📊 CONNECTION STATUS REPORT:');
    status.forEach((key, value) {
      _logger.i('  $key: $value');
    });
    
    // Force immediate action if needed
    if (status['shouldMaintainConnection'] == true && 
        status['isConnected'] == false && 
        status['isConnecting'] == false) {
      _logger.w('🚨 Status check reveals disconnected state - forcing reconnection');
      _connectWithRetry();
    }
  }

  Future<void> _connectWithRetry() async {
    if (_isConnecting || _currentUser == null) {
      _logger.d('Skipping connection attempt - Connecting: $_isConnecting, Has user: ${_currentUser != null}');
      return;
    }
    
    // Check network connectivity first
    if (!_hasNetworkConnectivity) {
      _logger.w('No network connectivity, skipping connection attempt');
      return;
    }
    
    _lastConnectionAttempt = DateTime.now();
    _isConnecting = true;
    _stopReconnectionTimer();
    
    // Start connection timeout timer (30 seconds)
    _startConnectionTimeout();
    
    _logger.i('🔄 Starting connection attempt ${_reconnectionAttempts + 1}');
    _logger.i('📊 User: ${_currentUser!.authUser}, Server: ${_currentUser!.wsUrl}');
    
    try {
      // Force stop any existing connection first
      if (_sipHelper.registered) {
        _logger.i('🛑 Stopping existing connection before retry...');
        await _sipHelper.unregister();
        _sipHelper.stop();
        await Future.delayed(Duration(milliseconds: 500)); // Short delay
      }
      
      // Step 1: Connect VPN if configured and enabled
      if (_vpnManager?.isConfigured == true && _vpnManager?.shouldAutoConnect == true) {
        _logger.i('🔐 VPN auto-connect enabled, connecting VPN first...');
        final vpnConnected = await _connectVPN();
        if (!vpnConnected) {
          throw Exception('VPN connection failed - cannot establish secure SIP connection');
        }
      } else {
        _logger.i('🔍 VPN not configured or auto-connect disabled, proceeding with direct SIP connection');
      }
      
      // Step 2: Connect SIP
      await _connect(_currentUser!);
      _logger.i('✅ Connection attempt completed');
    } catch (e) {
      _logger.e('❌ Connection failed: $e');
      _scheduleReconnection();
    }
    
    _stopConnectionTimeout();
    _isConnecting = false;
  }
  
  void _startConnectionTimeout() {
    _stopConnectionTimeout();
    _connectionTimeoutTimer = Timer(Duration(seconds: 30), () {
      if (_isConnecting) {
        _logger.e('⏰ Connection timeout after 30 seconds');
        _isConnecting = false;
        _stopConnectionTimeout();
        
        // Force stop the helper and try again
        try {
          _sipHelper.stop();
        } catch (e) {
          _logger.w('Error stopping SIP helper on timeout: $e');
        }
        
        _scheduleReconnection();
      }
    });
  }
  
  void _stopConnectionTimeout() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
  }
  
  Future<bool> _connectVPN() async {
    try {
      _logger.i('🔐 Attempting VPN connection...');
      
      // Ensure VPN manager is initialized
      _vpnManager ??= VPNManager();
      
      if (_vpnManager!.isConnected) {
        _logger.i('✅ VPN already connected');
        return true;
      }
      
      final success = await _vpnManager!.connect();
      if (success) {
        // Wait for VPN to establish connection
        int attempts = 0;
        while (!_vpnManager!.isConnected && attempts < 30) { // Wait up to 15 seconds
          await Future.delayed(Duration(milliseconds: 500));
          attempts++;
        }
        
        if (_vpnManager!.isConnected) {
          _logger.i('✅ VPN connected successfully');
          return true;
        } else {
          _logger.e('❌ VPN connection timeout');
          return false;
        }
      } else {
        _logger.e('❌ VPN connection failed');
        return false;
      }
    } catch (e) {
      _logger.e('❌ VPN connection error: $e');
      return false;
    }
  }

  Future<void> _connect(SipUser user) async {
    _logger.i('🔌 Attempting SIP connection...');
    _logger.i('📋 Connection details:');
    _logger.i('   User: ${user.authUser}');
    _logger.i('   Server: ${user.wsUrl}');
    _logger.i('   Transport: ${user.selectedTransport}');
    
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
    } else if (user.wsUrl?.isNotEmpty == true) {
      // Try to extract domain from WebSocket URL
      try {
        final uri = Uri.parse(user.wsUrl!);
        domain = uri.host;
      } catch (e) {
        _logger.w('Failed to parse domain from WebSocket URL: $e');
        domain = 'localhost'; // fallback
      }
    }
    
    String properSipUri = 'sip:$username@$domain';
    
    _logger.i('📊 Parsed connection details:');
    _logger.i('   SIP URI: $properSipUri');
    _logger.i('   Domain: $domain');
    _logger.i('   Username: $username');
    
    // Configure settings with robust connection parameters
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
    settings.register_expires = 300; // Shorter expiry for more frequent registration refreshes
    settings.contact_uri = null;
    
    if (user.selectedTransport != TransportType.WS && user.port.isNotEmpty) {
      settings.port = user.port;
      _logger.i('   Port: ${user.port}');
    }
    
    _logger.i('🚀 Starting SIP connection with URI: ${settings.uri} via ${settings.webSocketUrl}');
    
    try {
      await _sipHelper.start(settings);
      _logger.i('✅ SIP helper started successfully');
    } catch (e) {
      _logger.e('❌ SIP helper start failed: $e');
      rethrow;
    }
  }

  void _scheduleReconnection() {
    if (!_shouldMaintainConnection) return;
    
    // Don't schedule reconnection if no network connectivity
    if (!_hasNetworkConnectivity) {
      _logger.w('No network connectivity, skipping reconnection schedule');
      return;
    }
    
    _reconnectionAttempts++;
    
    if (_reconnectionAttempts > _maxReconnectionAttempts) {
      _logger.e('Max reconnection attempts ($_maxReconnectionAttempts) reached for SIP calling app. This indicates a serious connectivity issue.');
      // For a calling app, we should continue trying but with longer delays
      _shouldMaintainConnection = true; // Keep trying for calling app
      return;
    }
    
    // Exponential backoff with jitter
    int delay = _calculateBackoffDelay(_reconnectionAttempts);
    
    _logger.w('Scheduling reconnection attempt $_reconnectionAttempts in $delay seconds');
    
    _reconnectionTimer = Timer(Duration(seconds: delay), () {
      if (_shouldMaintainConnection && _hasNetworkConnectivity) {
        _connectWithRetry();
      }
    });
  }

  int _calculateBackoffDelay(int attempt) {
    // Exponential backoff: 2^attempt * base + random jitter
    int exponentialDelay = (pow(2, attempt) * _baseDelaySeconds).round();
    int jitter = Random().nextInt(5); // 0-4 seconds of jitter
    int totalDelay = exponentialDelay + jitter;
    
    return totalDelay.clamp(_baseDelaySeconds, _maxDelaySeconds);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    
    // More frequent health checks for SIP calling app
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_shouldMaintainConnection) {
        _logger.d('🔍 Connection health check - Registered: ${_sipHelper.registered}, Connecting: $_isConnecting');
        _checkConnectionHealth();
        
        // Ensure we're always connected
        if (!_sipHelper.registered && !_isConnecting) {
          _logger.w('❌ Not registered during health check - attempting reconnection');
          _connectWithRetry();
        }
      }
    });
    
    // Start additional connection monitor
    _startConnectionMonitor();
  }
  
  void _startConnectionMonitor() {
    _stopConnectionMonitor();
    
    // Ultra-frequent monitoring for critical SIP calling app
    _connectionMonitorTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (_shouldMaintainConnection) {
        _performCriticalConnectionCheck();
      }
    });
  }
  
  void _stopConnectionMonitor() {
    _connectionMonitorTimer?.cancel();
    _connectionMonitorTimer = null;
  }
  
  void _performCriticalConnectionCheck() {
    final now = DateTime.now();
    final isRegistered = _sipHelper.registered;
    
    _logger.d('🔍 CRITICAL CHECK - Registered: $isRegistered, Should maintain: $_shouldMaintainConnection, Connecting: $_isConnecting');
    
    if (!isRegistered && _shouldMaintainConnection && !_isConnecting) {
      // Check if we've been disconnected for too long
      if (_lastSuccessfulConnection != null) {
        final timeSinceLastConnection = now.difference(_lastSuccessfulConnection!);
        if (timeSinceLastConnection.inSeconds > 120) { // 2 minutes without connection
          _logger.e('🚨 CRITICAL: No connection for ${timeSinceLastConnection.inSeconds} seconds - forcing immediate reconnection');
          _reconnectionAttempts = 0; // Reset attempts for critical reconnection
          _connectWithRetry();
        }
      }
      
      // Check if last attempt was too long ago
      if (_lastConnectionAttempt != null) {
        final timeSinceLastAttempt = now.difference(_lastConnectionAttempt!);
        if (timeSinceLastAttempt.inSeconds > 90) { // 1.5 minutes since last attempt
          _logger.w('⏰ Last connection attempt was ${timeSinceLastAttempt.inSeconds} seconds ago - forcing new attempt');
          _connectWithRetry();
        }
      } else {
        // No attempt recorded yet
        _logger.w('🔄 No connection attempts recorded - starting first attempt');
        _connectWithRetry();
      }
    }
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _stopConnectionMonitor();
  }

  void _checkConnectionHealth() {
    // If we haven't had a successful connection recently and should maintain connection,
    // attempt reconnection
    if (_shouldMaintainConnection && 
        !_sipHelper.registered && 
        _lastSuccessfulConnection != null) {
      
      final timeSinceLastConnection = DateTime.now().difference(_lastSuccessfulConnection!);
      
      if (timeSinceLastConnection.inMinutes > 5) {
        _logger.w('Connection health check failed. Attempting reconnection...');
        _connectWithRetry();
      }
    }
  }

  void _stopReconnectionTimer() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
  }

  Future<void> _saveConnectionSettings(SipUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('persistent_sip_user', user.toJsonString());
    await prefs.setBool('should_maintain_connection', true);
  }

  Future<void> _clearConnectionSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('persistent_sip_user');
    await prefs.setBool('should_maintain_connection', false);
  }

  Future<void> _loadSavedConnectionAndAutoConnect() async {
    try {
      _logger.i('ConnectionManager: Checking for saved connection settings...');
      
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('persistent_sip_user');
      final shouldMaintain = prefs.getBool('should_maintain_connection') ?? false;
      
      if (savedUserJson != null && shouldMaintain) {
        _logger.i('ConnectionManager: Found saved connection, scheduling auto-connect...');
        final sipUser = SipUser.fromJsonString(savedUserJson);
        
        // Add delay to prevent interference with app startup
        Future.delayed(Duration(seconds: 3), () async {
          if (_shouldMaintainConnection == false) { // Only connect if not already started
            _logger.i('ConnectionManager: Starting delayed auto-connect...');
            await startPersistentConnection(sipUser);
          } else {
            _logger.i('ConnectionManager: Connection already managed, skipping auto-connect');
          }
        });
      } else {
        _logger.i('ConnectionManager: No saved connection found');
      }
    } catch (e) {
      _logger.e('ConnectionManager: Error loading saved connection: $e');
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    _logger.i('📞 Registration state changed: ${state.state}');
    
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _logger.i('✅ Successfully registered to SIP server!');
        _logger.i('🎉 Connection is now active and ready for calls');
        _reconnectionAttempts = 0; // Reset on successful registration
        _lastSuccessfulConnection = DateTime.now();
        _isConnecting = false; // Clear connecting flag
        BackgroundService.startService();
        break;
        
      case RegistrationStateEnum.UNREGISTERED:
        _logger.w('🔌 Unregistered from SIP server');
        if (_shouldMaintainConnection && !_isConnecting) {
          _logger.i('🔄 Auto-reconnection enabled, scheduling reconnection...');
          _scheduleReconnection();
        } else {
          _logger.i('ℹ️ Auto-reconnection disabled or already connecting');
        }
        break;
        
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _logger.e('❌ Registration failed: ${state.cause}');
        _logger.e('💡 This usually means incorrect credentials or server issues');
        if (_shouldMaintainConnection && !_isConnecting) {
          _logger.i('🔄 Scheduling reconnection attempt...');
          _scheduleReconnection();
        }
        break;
        
      default:
        _logger.d('📋 Registration state: ${state.state}');
    }
    
    // Notify UI
    onRegistrationStateChanged?.call(state);
  }

  @override
  void transportStateChanged(TransportState state) {
    _logger.i('Transport state changed: ${state.state}');
    
    switch (state.state) {
      case TransportStateEnum.DISCONNECTED:
        _logger.w('Transport disconnected. Checking if reconnection needed...');
        if (_shouldMaintainConnection && !_isConnecting) {
          _scheduleReconnection();
        }
        break;
        
      case TransportStateEnum.CONNECTED:
        _logger.i('Transport connected successfully');
        break;
        
      default:
        _logger.d('Transport state: ${state.state}');
    }
    
    // Notify UI
    onTransportStateChanged?.call(state);
  }

  @override
  void callStateChanged(Call call, CallState state) {
    _logger.i('🔔 ConnectionManager: Call state changed: ${state.state}');
    _logger.i('📞 Call ID: ${call.id}, Direction: ${call.direction}');
    
    // Forward the call state to UI listeners
    onCallStateChanged?.call(call, state);
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    _logger.d('New SIP message received');
  }

  @override
  void onNewNotify(Notify ntf) {
    _logger.d('New SIP notify received');
  }

  @override
  void onNewReinvite(ReInvite event) {
    _logger.d('New SIP re-invite received');
  }

  void dispose() {
    _stopReconnectionTimer();
    _stopHeartbeat();
    _connectivitySubscription.cancel();
    _sipHelper.removeSipUaHelperListener(this);
  }
}