import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:logger/logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'user_state/sip_user.dart';
import 'background_service.dart';

/// Manages persistent SIP connections with automatic reconnection
class ConnectionManager implements SipUaHelperListener {
  static final ConnectionManager _instance = ConnectionManager._internal();
  factory ConnectionManager() => _instance;
  ConnectionManager._internal();

  final Logger _logger = Logger();
  late SIPUAHelper _sipHelper;
  Timer? _reconnectionTimer;
  Timer? _heartbeatTimer;
  SipUser? _currentUser;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  
  // Reconnection strategy
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 10;
  static const int _baseDelaySeconds = 2;
  static const int _maxDelaySeconds = 300; // 5 minutes
  
  // Connection state
  bool _isConnecting = false;
  bool _shouldMaintainConnection = false;
  DateTime? _lastSuccessfulConnection;
  bool _hasNetworkConnectivity = true;
  
  // Callbacks for UI updates
  Function(RegistrationState)? onRegistrationStateChanged;
  Function(Call, CallState)? onCallStateChanged;
  Function(TransportState)? onTransportStateChanged;

  void initialize(SIPUAHelper sipHelper) {
    _logger.i('ConnectionManager: Initializing...');
    _sipHelper = sipHelper;
    _setupNetworkMonitoring();
    
    // Do NOT add SIP listener or auto-connect - let SipUserCubit manage the connection
    // ConnectionManager will only handle reconnection logic when explicitly called
  }

  void _setupNetworkMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final bool hasConnectivity = results.isNotEmpty && 
          results.any((result) => result != ConnectivityResult.none);
      
      _logger.i('Network connectivity changed: $hasConnectivity (was: $_hasNetworkConnectivity)');
      
      if (!_hasNetworkConnectivity && hasConnectivity) {
        // Network restored - attempt immediate reconnection
        _logger.i('Network restored, attempting immediate reconnection');
        _hasNetworkConnectivity = true;
        if (_shouldMaintainConnection && !_sipHelper.registered) {
          _reconnectionAttempts = 0; // Reset attempts on network restore
          _connectWithRetry();
        }
      } else if (_hasNetworkConnectivity && !hasConnectivity) {
        // Network lost
        _logger.w('Network connectivity lost');
        _hasNetworkConnectivity = false;
        _stopReconnectionTimer(); // Don't waste attempts when no network
      }
      
      _hasNetworkConnectivity = hasConnectivity;
    });
  }

  /// Start maintaining persistent connection
  Future<void> startPersistentConnection(SipUser user) async {
    _logger.i('Starting persistent connection for user: ${user.authUser}');
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

  /// Check if connection is active
  bool get isConnected => _sipHelper.registered;
  
  /// Check if should maintain connection
  bool get shouldMaintainConnection => _shouldMaintainConnection;

  Future<void> _connectWithRetry() async {
    if (_isConnecting || _currentUser == null) return;
    
    _isConnecting = true;
    _stopReconnectionTimer();
    
    try {
      await _connect(_currentUser!);
    } catch (e) {
      _logger.e('Connection failed: $e');
      _scheduleReconnection();
    }
    
    _isConnecting = false;
  }

  Future<void> _connect(SipUser user) async {
    _logger.i('Attempting SIP connection...');
    
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
    
    // Enhanced connection settings for stability (commented out if not supported)
    // settings.session_timers = true;
    // settings.session_timers_refresh_method = SipMethod.UPDATE;
    
    if (user.selectedTransport != TransportType.WS && user.port.isNotEmpty) {
      settings.port = user.port;
    }
    
    _logger.i('Connecting with settings: ${settings.uri} via ${settings.webSocketUrl}');
    await _sipHelper.start(settings);
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
      _logger.e('Max reconnection attempts reached. Stopping auto-reconnection.');
      _shouldMaintainConnection = false;
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
    
    // Send periodic OPTIONS to maintain connection
    _heartbeatTimer = Timer.periodic(Duration(seconds: 60), (timer) {
      if (_sipHelper.registered && _shouldMaintainConnection) {
        _logger.d('Sending heartbeat...');
        // The SIP library should handle keep-alive automatically,
        // but we can monitor connection state here
        _checkConnectionHealth();
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    // DISABLED: Auto-connection is now handled by SipUserCubit only
    // This prevents competing SIP UA instances and connection loops
    _logger.i('ConnectionManager: Auto-connection disabled - SipUserCubit handles connection management');
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    _logger.i('Registration state changed: ${state.state}');
    
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _logger.i('Successfully registered!');
        _reconnectionAttempts = 0; // Reset on successful registration
        _lastSuccessfulConnection = DateTime.now();
        BackgroundService.startService();
        break;
        
      case RegistrationStateEnum.UNREGISTERED:
        _logger.w('Unregistered. Attempting reconnection if needed...');
        if (_shouldMaintainConnection && !_isConnecting) {
          _scheduleReconnection();
        }
        break;
        
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _logger.e('Registration failed: ${state.cause}');
        if (_shouldMaintainConnection && !_isConnecting) {
          _scheduleReconnection();
        }
        break;
        
      default:
        _logger.d('Registration state: ${state.state}');
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
    _logger.i('Call state changed: ${state.state}');
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