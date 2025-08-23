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
  
  // Improved reconnection strategy for stability
  int _reconnectionAttempts = 0;
  static const int _maxReconnectionAttempts = 20; // Reduced attempts to prevent spam
  static const int _baseDelaySeconds = 10; // Longer initial delay for stability
  static const int _maxDelaySeconds = 300; // Max 5 minutes delay
  static const int _minConnectionDuration = 30; // Minimum seconds to consider connection stable
  
  // Connection state tracking
  bool _isConnecting = false;
  bool _shouldMaintainConnection = false;
  DateTime? _lastSuccessfulConnection;
  DateTime? _connectionStartTime;
  bool _hasNetworkConnectivity = true;
  Timer? _connectionMonitorTimer;
  Timer? _connectionTimeoutTimer;
  DateTime? _lastConnectionAttempt;
  int _consecutiveFailures = 0;
  
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
      _logger.i('🔐 Initializing VPN Manager...');
      _vpnManager ??= VPNManager();
      await _vpnManager!.initialize();
      _logger.i('✅ VPN Manager initialized successfully');
      
      // Configure VPN with the provided settings
      await _configureVPNSettings();
      _logger.i('✅ VPN configuration completed');
    } catch (e) {
      _logger.e('❌ VPN Manager initialization failed: $e');
      // Don't throw, just log the error
    }
  }

  Future<void> _configureVPNSettings() async {
    try {
      if (_vpnManager != null) {
        // Always configure VPN with default settings to ensure it's available
        // Your VPN configuration
        const String vpnConfig = '''client
server-poll-timeout 4
nobind
remote 172.17.0.2 1194 udp
remote 172.17.0.2 1194 udp
remote 172.17.0.2 443 tcp
remote 172.17.0.2 1194 udp
remote 172.17.0.2 1194 udp
remote 172.17.0.2 1194 udp
remote 172.17.0.2 1194 udp
remote 172.17.0.2 1194 udp
dev tun
dev-type tun
remote-cert-tls server
tls-version-min 1.2
reneg-sec 604800
tun-mtu 1420
auth-user-pass
verb 3
push-peer-info

<ca>
-----BEGIN CERTIFICATE-----
MIIBeDCB/6ADAgECAgRopCUBMAoGCCqGSM49BAMCMBUxEzARBgNVBAMMCk9wZW5W
UE4gQ0EwHhcNMjUwODE4MDcxNzIxWhcNMzUwODE3MDcxNzIxWjAVMRMwEQYDVQQD
DApPcGVuVlBOIENBMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERwio5P+58s7hBqNm
rRQq3jZWePPy6xRQ/2Z4zxlD+3mYU0d0YYvb2T6usZ/Fbjf6lQki79qdL1Y1IGYA
PxuDchsyqZxx6s9hbYPYfuGKLdK2pnioIfs4z9z8fRcpLSu2oyAwHjAPBgNVHRMB
Af8EBTADAQH/MAsGA1UdDwQEAwIBBjAKBggqhkjOPQQDAgNoADBlAjEA946I2iu6
btTJsqlJfpG954Hn0hUwrU2AubPuu/WWq3x6RgvAVCNEFwpCVpSTwE7MAjBUSEgV
HjnHK9UK/A/pwHQgkIZgIoMrHmn4DZD5uSmhDlRRJLB0O4UwAYhw1aFWWA0=
-----END CERTIFICATE-----
</ca>
<cert>
-----BEGIN CERTIFICATE-----
MIIBnzCCASagAwIBAgIIeEf3MLQNtpMwCgYIKoZIzj0EAwIwFTETMBEGA1UEAwwK
T3BlblZQTiBDQTAeFw0yNTA4MTgxMDIzNTJaFw0zNTA4MTcxMDIzNTJaMBMxETAP
BgNVBAMMCGludGlzaGFyMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEwt+tPL+wivoI
OVXYXAhIq8UILSk+gnq4TGr9eNbxt4wtLlOd1vIIxhspWQkJa4pidzXSLKUZ0ZWQ
7bfRPji8k2M1yTckQCM3pJMNzCgImcvKf0oMcTHzXIf6ukffQxzCo0UwQzAMBgNV
HRMBAf8EAjAAMAsGA1UdDwQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAjARBglg
hkgBhvhCAQEEBAMCB4AwCgYIKoZIzj0EAwIDZwAwZAIwYqyRPMtrTDAlJv+ENJ5j
1MF7GWO709jmF5zXmpH+ngfa2U8ZFK+Q/iJNEQrR5x3TAjAMHwHSjycyU3Z/DLH7
KBVcSGfyo39j7EogW0gwLhLfCy1XjDj8ixgfrkBJR5ACKM8=
-----END CERTIFICATE-----
</cert>
<key>
-----BEGIN PRIVATE KEY-----
MIG2AgEAMBAGByqGSM49AgEGBSuBBAAiBIGeMIGbAgEBBDCGdYrbfb2X2+g0dWkF
Qn3gIKNQL5n79HWT0+avA4gHZ/nt1Pfsl3/VU93cdJkfCL6hZANiAATC3608v7CK
+gg5VdhcCEirxQgtKT6CerhMav141vG3jC0uU53W8gjGGylZCQlrimJ3NdIspRnR
lZDtt9E+OLyTYzXJNyRAIzekkw3MKAiZy8p/SgxxMfNch/q6R99DHMI=
-----END PRIVATE KEY-----
</key>
<tls-crypt-v2>
-----BEGIN OpenVPN tls-crypt-v2 client key-----
Q+qYsAOw+yINhlZxS8dKNQkCCsGC7e49sKmEC4mPpNOz2zCK9l7X08UuE6TnhD1h
B/0Uwo/5mIfXdDMegUxC73JEOfWF+clZ3aSrtUGgv1j5xs/GlIjkxqR63Ve3qt4I
QFBdv7IHodKCVEaWROiMdhSwISpO74kUjk+auaRBmJR8dhEIJDBPMd9yhOI238FY
Vp4BH10OCdrEunodQdqp6jDMkYMToW5Q4ZM4/mI1Y4H0f1zbbBeDLi76RPAo2ifu
x/Cz9cZeNcG3r+1LM7+YeCK/2M2VCtp0M6rrquMzA1LYdIiAleiUTtFnpPKQ6Gec
iV3jsXMcfq/mxC5sCidxIK12kcTVYxJYmWHOOlmC/TpOEPU93oX+f7T+WRIb+taf
qg5XPLE9DIsHG2k4BAwqpQiJ4OxsCHMhWipzobnXxD5MzewFiMs4LHSQYDYZ9YlU
+i2XFgFqURgRXUpNx3Y3ORYhgpSJGWpOZYmjqr6EHE8t9RyyKJAyJRdV3xc7A17Z
2Ruz1aARDk+6E9psZK0HZuTIKLlyMHba9ZL7VWCUjWplGlF4FUXDR7RdmhyHIELl
KCf216h5/+a6HZLrmk5ViDi5fJo+T2nhf7r97L+fFD0wBqQvicjmhLDNMw8w0m+0
eDSHhxeRCmuF9nIklHEvarC3eFQetiNTdUfQr4o0Q16qxuDi9FA52vRbKmu7gwgP
z4fB2SFUiE0i9Ujch4Gs/Tk3kzqwmX+RfdsMLqYX4WKqPYC1QM4coSUBrRWwa96K
shWr8WQLs62E90vQhhZbhAB+PW6GhwkBWQ==
-----END OpenVPN tls-crypt-v2 client key-----
</tls-crypt-v2>''';
        
        await _vpnManager!.configureVPN(
          serverAddress: '10.209.99.108',
          username: 'intishar',
          password: 'ibos@123',
          customConfig: vpnConfig,
        );
        
        // Enable auto-connect by default
        _vpnManager!.enableAutoConnect(true);
        _logger.i('VPN configured with custom settings and auto-connect enabled');
      }
    } catch (e) {
      _logger.e('VPN configuration failed: $e');
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
      
      // Save settings immediately for persistence
      await _vpnManager!.saveSettings();
      _logger.i('VPN configuration completed and settings saved');
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

  /// Auto-connect VPN before SIP connection if configured
  Future<void> _autoConnectVPNFirst() async {
    try {
      _logger.i('🔐 Auto-connecting VPN before SIP connection...');
      
      // Ensure VPN manager is initialized
      if (_vpnManager == null) {
        _logger.i('🔐 Initializing VPN manager for auto-connect...');
        await _initializeVPN();
      }
      
      if (_vpnManager == null) {
        _logger.w('❌ VPN manager not available for auto-connect');
        return;
      }
      
      // Check if VPN should auto-connect
      if (!_vpnManager!.shouldAutoConnect) {
        _logger.i('ℹ️ VPN auto-connect disabled - skipping VPN connection');
        return;
      }
      
      // Check if VPN is already connected
      if (_vpnManager!.isConnected) {
        _logger.i('✅ VPN already connected - no need to auto-connect');
        return;
      }
      
      // Check if VPN is configured
      if (!_vpnManager!.isConfigured) {
        _logger.w('⚠️ VPN not configured - cannot auto-connect');
        return;
      }
      
      _logger.i('🔐 Starting VPN auto-connect...');
      final success = await _vpnManager!.connect();
      
      if (success) {
        _logger.i('✅ VPN auto-connect successful');
      } else {
        _logger.w('❌ VPN auto-connect failed');
      }
    } catch (e) {
      _logger.e('❌ VPN auto-connect error: $e');
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

  /// Check if VPN is connected and required for SIP operations
  bool get isVPNConnectedForSIP {
    final vpn = vpnManager;
    return vpn.isConnected;
  }

  /// Suggest optimal transport type based on server URL
  TransportType suggestTransportType(String serverUrl) {
    if (serverUrl.startsWith('ws://') || serverUrl.startsWith('wss://')) {
      return TransportType.WS;
    } else if (serverUrl.startsWith('sips://') || serverUrl.contains(':5061')) {
      return TransportType.TCP; // Use TCP for TLS (secure TCP)
    } else if (serverUrl.startsWith('sip://') || serverUrl.contains(':5060')) {
      return TransportType.TCP;
    } else {
      // Default based on compatibility
      return TransportType.WS; // WebSocket is most compatible
    }
  }

  /// Validate transport configuration
  Map<String, dynamic> validateTransportConfig(String serverUrl, TransportType transportType) {
    final suggested = suggestTransportType(serverUrl);
    final isOptimal = suggested == transportType;
    
    String recommendation;
    if (isOptimal) {
      recommendation = 'Transport type matches URL format - optimal configuration';
    } else {
      recommendation = 'URL format suggests $suggested, but $transportType is selected. This may work if server supports both.';
    }
    
    // Additional validation based on transport type
    List<String> warnings = [];
    if (transportType == TransportType.WS) {
      if (!serverUrl.startsWith('ws://') && !serverUrl.startsWith('wss://')) {
        warnings.add('WebSocket transport requires URL starting with ws:// or wss://');
      }
    } else if (transportType == TransportType.TCP) {
      if (serverUrl.startsWith('ws://') || serverUrl.startsWith('wss://')) {
        warnings.add('TCP transport typically uses sip:// URLs or host:port format');
      }
    }
    
    return {
      'isOptimal': isOptimal,
      'currentTransport': transportType,
      'suggestedTransport': suggested,
      'serverUrl': serverUrl,
      'recommendation': recommendation,
      'warnings': warnings,
    };
  }
  
  /// Get comprehensive connection status for monitoring
  Map<String, dynamic> getConnectionStatus() {
    final now = DateTime.now();
    final connectionDuration = _connectionStartTime != null 
        ? now.difference(_connectionStartTime!).inSeconds 
        : 0;
    
    return {
      'isConnected': _sipHelper.registered,
      'shouldMaintainConnection': _shouldMaintainConnection,
      'isConnecting': _isConnecting,
      'hasNetworkConnectivity': _hasNetworkConnectivity,
      'reconnectionAttempts': _reconnectionAttempts,
      'maxReconnectionAttempts': _maxReconnectionAttempts,
      'consecutiveFailures': _consecutiveFailures,
      'connectionDuration': connectionDuration,
      'connectionStable': connectionDuration >= _minConnectionDuration,
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
      'vpnConnected': _vpnManager?.isConnected ?? false,
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
      
      // VPN connection for WebSocket (optional)
      if (_vpnManager?.isConfigured == true && _vpnManager?.shouldAutoConnect == true) {
        _logger.i('🔐 VPN auto-connect enabled, connecting VPN first...');
        final vpnConnected = await _connectVPN();
        if (!vpnConnected) {
          _logger.w('❌ VPN connection failed, but proceeding with direct connection');
        } else {
          _logger.i('✅ VPN connected successfully');
        }
      } else {
        _logger.i('ℹ️ Using direct WebSocket connection (no VPN)');
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
      
      // Ensure VPN manager is properly initialized
      if (_vpnManager == null) {
        _logger.i('🔐 VPN Manager not initialized, initializing now...');
        await _initializeVPN();
      }
      
      // Check if VPN manager is still null after initialization
      if (_vpnManager == null) {
        _logger.e('❌ VPN Manager failed to initialize');
        return false;
      }
      
      // Check if already connected
      if (_vpnManager!.isConnected) {
        _logger.i('✅ VPN already connected');
        return true;
      }
      
      // Check if VPN is configured
      if (!_vpnManager!.isConfigured) {
        _logger.e('❌ VPN not configured');
        return false;
      }
      
      _logger.i('🔐 Starting VPN connection...');
      final success = await _vpnManager!.connect();
      
      if (success) {
        // Wait for VPN to establish connection
        _logger.i('🔐 Waiting for VPN connection to establish...');
        int attempts = 0;
        const maxAttempts = 60; // Wait up to 30 seconds
        
        while (!_vpnManager!.isConnected && attempts < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 500));
          attempts++;
          if (attempts % 10 == 0) {
            _logger.i('🔐 VPN connection attempt ${attempts ~/ 2} seconds...');
          }
        }
        
        if (_vpnManager!.isConnected) {
          _logger.i('✅ VPN connected successfully');
          return true;
        } else {
          _logger.e('❌ VPN connection timeout after ${maxAttempts ~/ 2} seconds');
          return false;
        }
      } else {
        _logger.e('❌ VPN connection initiation failed');
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
    final transportType = user.selectedTransport;
    final serverUrl = user.wsUrl ?? '';
    
    _logger.i('🚀 Transport configuration:');
    _logger.i('   Transport Type: $transportType');
    _logger.i('   Server URL: $serverUrl');
    
    // Validate transport configuration (informational only)
    final validation = validateTransportConfig(serverUrl, transportType);
    _logger.i('📋 Transport Configuration Analysis:');
    _logger.i('   Selected: ${validation['currentTransport']}');
    _logger.i('   ${validation['recommendation']}');
    
    final warnings = validation['warnings'] as List<String>;
    if (warnings.isNotEmpty) {
      _logger.w('⚠️ Configuration Notes:');
      for (final warning in warnings) {
        _logger.w('   - $warning');
      }
    }
    
    // Configure transport based on user selection with enhanced validation
    settings.transportType = transportType;
    
    if (transportType == TransportType.WS) {
      // WebSocket Transport Configuration
      _logger.i('🔌 Configuring WebSocket transport...');
      settings.webSocketUrl = serverUrl;
      settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
      settings.webSocketSettings.allowBadCertificate = true;
      
      // Validate and correct WebSocket URL format
      if (!serverUrl.startsWith('ws://') && !serverUrl.startsWith('wss://')) {
        _logger.w('⚠️ WebSocket URL missing protocol, attempting to correct');
        _logger.w('   Original URL: $serverUrl');
        
        // Auto-correct by adding wss:// protocol
        String correctedUrl;
        if (serverUrl.contains(':443') || serverUrl.contains('wss') || serverUrl.toLowerCase().contains('secure')) {
          correctedUrl = 'wss://$serverUrl';
        } else {
          correctedUrl = 'ws://$serverUrl';
        }
        
        _logger.i('   Corrected URL: $correctedUrl');
        settings.webSocketUrl = correctedUrl;
      }
      
      _logger.i('   WebSocket URL: ${settings.webSocketUrl}');
      
    } else {
      // TCP Transport Configuration  
      _logger.i('🔌 Configuring TCP transport...');
      settings.tcpSocketSettings.allowBadCertificate = true;
      
      // Clean up server URL for TCP - remove any protocol prefixes
      String cleanHost = serverUrl;
      
      // Remove protocols if present
      if (cleanHost.startsWith('sip://')) {
        cleanHost = cleanHost.replaceFirst('sip://', '');
      } else if (cleanHost.startsWith('sips://')) {
        cleanHost = cleanHost.replaceFirst('sips://', '');
      } else if (cleanHost.startsWith('ws://')) {
        cleanHost = cleanHost.replaceFirst('ws://', '');
        _logger.w('⚠️ WebSocket URL provided for TCP transport, extracting host');
      } else if (cleanHost.startsWith('wss://')) {
        cleanHost = cleanHost.replaceFirst('wss://', '');
        _logger.w('⚠️ WebSocket URL provided for TCP transport, extracting host');
      }
      
      // Remove path component if present (e.g., "host:port/path" -> "host:port")
      if (cleanHost.contains('/')) {
        cleanHost = cleanHost.split('/')[0];
      }
      
      _logger.i('   Cleaned host string: $cleanHost');
      
      // Parse host and port
      if (cleanHost.contains(':')) {
        final parts = cleanHost.split(':');
        settings.host = parts[0].trim();
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          settings.port = parts[1].trim();
        }
      } else {
        // No port in URL, use the host and get port from user input or default
        settings.host = cleanHost.trim();
      }
      
      // Set port from user input if available, otherwise use defaults
      if (user.port.isNotEmpty) {
        settings.port = user.port.trim();
        _logger.i('   Using user-provided port: ${user.port}');
      } else if (settings.port == null || settings.port!.isEmpty) {
        // Use default ports based on security
        if (serverUrl.contains('sips://') || serverUrl.contains(':5061')) {
          settings.port = '5061'; // Secure SIP
        } else {
          settings.port = '5060'; // Standard SIP
        }
        _logger.i('   Using default port: ${settings.port}');
      }
      
      _logger.i('   Final TCP config: ${settings.host}:${settings.port}');
      
      // Validate host is not empty
      if (settings.host == null || settings.host!.isEmpty) {
        throw Exception('Invalid TCP configuration: Host cannot be empty');
      }
      
      // Validate port is numeric and in valid range
      if (settings.port != null && settings.port!.isNotEmpty) {
        try {
          int portNum = int.parse(settings.port!);
          if (portNum < 1 || portNum > 65535) {
            throw Exception('Port must be between 1 and 65535, got: $portNum');
          }
        } catch (e) {
          throw Exception('Invalid port number: ${settings.port} ($e)');
        }
      }
    }
    
    // Set common SIP settings
    settings.uri = properSipUri;
    settings.registrarServer = domain;
    settings.realm = null;
    settings.authorizationUser = username;
    settings.password = user.password;
    settings.displayName = user.displayName.isNotEmpty == true ? user.displayName : username;
    settings.userAgent = 'Flutter SIP Client v2.0';
    settings.dtmfMode = DtmfMode.RFC2833;
    settings.register = true;
    settings.register_expires = 300; // 5 minutes - balanced between too frequent and too long
    settings.contact_uri = null;
    
    // Finalize host settings for WebSocket (TCP already configured above)
    if (settings.transportType == TransportType.WS) {
      // For WebSocket, derive host from WebSocket URL for SIP registration
      try {
        Uri wsUri = Uri.parse(settings.webSocketUrl ?? '');
        String wsHost = wsUri.host;
        if (wsHost.isNotEmpty) {
          // Use WebSocket host if available, otherwise fall back to domain
          settings.host = wsHost;
          _logger.i('   Using WebSocket host for registration: $wsHost');
        } else {
          settings.host = domain;
          _logger.i('   Using SIP domain for registration: $domain');
        }
      } catch (e) {
        settings.host = domain;
        _logger.w('   Failed to parse WebSocket URL, using SIP domain: $domain');
      }
    }
    
    // Final validation
    if (settings.host == null || settings.host!.isEmpty) {
      throw Exception('Host configuration is empty - cannot establish connection');
    }
    
    _logger.i('📋 Final connection settings:');
    _logger.i('   Transport: ${settings.transportType}');
    _logger.i('   Host: ${settings.host}');
    _logger.i('   Port: ${settings.port ?? 'default'}');
    _logger.i('   WebSocket URL: ${settings.webSocketUrl ?? 'none'}');
    
    final connectionEndpoint = settings.transportType == TransportType.WS 
        ? settings.webSocketUrl 
        : '${settings.host}:${settings.port ?? 'default'}';
    _logger.i('🚀 Starting SIP connection with URI: ${settings.uri} via $connectionEndpoint');
    
    try {
      await _sipHelper.start(settings);
      _logger.i('✅ SIP helper started successfully');
    } catch (e) {
      _logger.e('❌ SIP helper start failed: $e');
      
      // Enhanced error handling with specific troubleshooting
      final errorMsg = e.toString().toLowerCase();
      String errorType = 'Connection Error';
      
      if (settings.transportType == TransportType.TCP) {
        errorType = 'TCP Connection Error';
        _logger.e('🔧 TCP Connection Troubleshooting:');
        _logger.e('   Configuration: ${settings.host}:${settings.port}');
        _logger.e('   Transport: ${settings.transportType}');
        
        if (errorMsg.contains('connection refused') || errorMsg.contains('refused')) {
          _logger.e('❌ Connection Refused:');
          _logger.e('   - SIP server may not be running on ${settings.host}:${settings.port}');
          _logger.e('   - Port ${settings.port} may be closed or blocked');
          _logger.e('   - Check if correct SIP port (5060/5061)');
        } else if (errorMsg.contains('timeout') || errorMsg.contains('unreachable')) {
          _logger.e('❌ Connection Timeout:');
          _logger.e('   - Server ${settings.host} may be unreachable');
          _logger.e('   - Network/firewall may be blocking connection');
          _logger.e('   - Check hostname/IP address is correct');
        } else if (errorMsg.contains('host') || errorMsg.contains('resolve')) {
          _logger.e('❌ Host Resolution Error:');
          _logger.e('   - Hostname ${settings.host} cannot be resolved');
          _logger.e('   - Check DNS settings or use IP address');
          _logger.e('   - Verify hostname spelling');
        }
        
        _logger.e('🔍 TCP Troubleshooting Steps:');
        _logger.e('   1. Test basic connectivity: telnet ${settings.host} ${settings.port}');
        _logger.e('   2. Verify SIP server is running and listening on port ${settings.port}');
        _logger.e('   3. Check firewall rules on both client and server');
        _logger.e('   4. Contact SIP provider to confirm TCP settings');
        
      } else if (settings.transportType == TransportType.WS) {
        errorType = 'WebSocket Connection Error';
        _logger.e('🔧 WebSocket Connection Troubleshooting:');
        _logger.e('   URL: ${settings.webSocketUrl}');
        _logger.e('   Transport: ${settings.transportType}');
        
        if (errorMsg.contains('handshake') || errorMsg.contains('upgrade')) {
          _logger.e('❌ WebSocket Handshake Failed:');
          _logger.e('   - Server may not support WebSocket connections');
          _logger.e('   - WebSocket path may be incorrect (try /ws or /websocket)');
          _logger.e('   - SSL/TLS certificate issues for wss:// URLs');
        } else if (errorMsg.contains('connection refused')) {
          _logger.e('❌ WebSocket Connection Refused:');
          _logger.e('   - WebSocket server not running on specified port');
          _logger.e('   - Port may be closed or blocked');
          _logger.e('   - Check if WebSocket is enabled on SIP server');
        }
        
        _logger.e('🔍 WebSocket Troubleshooting Steps:');
        _logger.e('   1. Verify WebSocket URL format: wss://server:port/path');
        _logger.e('   2. Check if server supports WebSocket SIP transport');
        _logger.e('   3. Test WebSocket connection with browser developer tools');
        _logger.e('   4. Verify SSL certificate for wss:// URLs');
      }
      
      // General connectivity suggestions
      _logger.e('🔍 General Troubleshooting:');
      _logger.e('   - Check internet connectivity');
      _logger.e('   - Verify SIP server credentials (username/password)');
      _logger.e('   - Try different network (mobile data vs WiFi)');
      _logger.e('   - Contact SIP provider for correct connection settings');
      
      if (_vpnManager?.isConnected == true) {
        _logger.e('   - VPN is connected - check if VPN allows SIP traffic');
      } else {
        _logger.e('   - Consider connecting VPN if required by provider');
      }
      
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
    // Base exponential backoff
    int exponentialDelay = (pow(2, attempt) * _baseDelaySeconds).round();
    
    // Add stability penalty for consecutive failures
    int stabilityPenalty = _consecutiveFailures * 30; // 30 seconds per consecutive failure
    
    // Add jitter to prevent thundering herd
    int jitter = Random().nextInt(10); // 0-9 seconds of jitter
    
    int totalDelay = exponentialDelay + stabilityPenalty + jitter;
    
    _logger.i('🔄 Reconnection delay calculation:');
    _logger.i('   Base delay: ${exponentialDelay}s');
    _logger.i('   Stability penalty: ${stabilityPenalty}s ($_consecutiveFailures failures)');
    _logger.i('   Jitter: ${jitter}s');
    _logger.i('   Total delay: ${totalDelay}s');
    
    return totalDelay.clamp(_baseDelaySeconds, _maxDelaySeconds);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    
    // Balanced health checks to avoid connection spam
    _heartbeatTimer = Timer.periodic(Duration(seconds: 120), (timer) {
      if (_shouldMaintainConnection) {
        _logger.d('🔍 Connection health check - Registered: ${_sipHelper.registered}, Connecting: $_isConnecting');
        _checkConnectionHealth();
        
        // Only reconnect if we haven't been connected for a significant time
        if (!_sipHelper.registered && !_isConnecting) {
          final timeSinceLastConnection = _lastSuccessfulConnection != null 
              ? DateTime.now().difference(_lastSuccessfulConnection!).inMinutes
              : 999;
          
          if (timeSinceLastConnection > 2) { // Only if disconnected for more than 2 minutes
            _logger.w('❌ Not registered for $timeSinceLastConnection minutes - attempting reconnection');
            _connectWithRetry();
          }
        }
      }
    });
    
    // Start additional connection monitor
    _startConnectionMonitor();
  }
  
  void _startConnectionMonitor() {
    _stopConnectionMonitor();
    
    // Balanced monitoring to prevent connection spam
    _connectionMonitorTimer = Timer.periodic(Duration(seconds: 60), (timer) {
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
            
            // Auto-connect VPN first, then SIP
            await _autoConnectVPNFirst();
            
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
    _logger.i('📞 Registration: ${state.state}');
    
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        _logger.i('✅ SIP Registration Successful!');
        _logger.i('🎉 Ready for calls');
        
        // Track successful connection
        final now = DateTime.now();
        _lastSuccessfulConnection = now;
        _connectionStartTime = now;
        _reconnectionAttempts = 0; // Reset on successful registration
        _consecutiveFailures = 0; // Reset failure counter
        _isConnecting = false; // Clear connecting flag
        
        BackgroundService.startService();
        break;
        
      case RegistrationStateEnum.UNREGISTERED:
        _logger.w('🔌 Unregistered from SIP server');
        
        // Check connection stability before reconnecting
        if (_connectionStartTime != null) {
          final connectionDuration = DateTime.now().difference(_connectionStartTime!).inSeconds;
          if (connectionDuration < _minConnectionDuration) {
            _consecutiveFailures++;
            _logger.w('⚠️ Connection was unstable (lasted only ${connectionDuration}s). Consecutive failures: $_consecutiveFailures');
            
            // If we have many consecutive short-lived connections, increase delay significantly
            if (_consecutiveFailures >= 3) {
              _logger.w('🚨 Multiple consecutive unstable connections detected. Using extended delay.');
            }
          } else {
            _logger.i('ℹ️ Connection was stable (lasted ${connectionDuration}s). Resetting failure counter.');
            _consecutiveFailures = 0;
          }
        }
        
        if (_shouldMaintainConnection && !_isConnecting) {
          _logger.i('🔄 Auto-reconnection enabled, scheduling reconnection...');
          _scheduleReconnection();
        } else {
          _logger.i('ℹ️ Auto-reconnection disabled or already connecting');
        }
        break;
        
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _consecutiveFailures++;
        final cause = state.cause?.toString() ?? 'Unknown error';
        _logger.e('❌ Registration Failed: $cause');
        
        // Analyze failure cause for better user feedback
        if (cause.contains('401') || cause.contains('403') || cause.contains('Unauthorized')) {
          _logger.e('🔐 Authentication Error - Check username/password');
        } else if (cause.contains('timeout') || cause.contains('network')) {
          _logger.e('🌐 Network Error - Check connectivity and server URL');
        } else if (cause.contains('404') || cause.contains('Not Found')) {
          _logger.e('🔍 SIP URI Error - Check if SIP address exists on server');
        } else {
          _logger.e('⚠️ Server Error - Contact SIP provider');
        }
        
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
        
        // Only schedule reconnection if we don't have a reconnection timer already running
        if (_shouldMaintainConnection && !_isConnecting && _reconnectionTimer == null) {
          // Add a small delay to avoid immediate reconnection on transport disconnect
          _logger.i('🔄 Scheduling reconnection after transport disconnect...');
          _scheduleReconnection();
        } else if (_reconnectionTimer != null) {
          _logger.i('ℹ️ Reconnection already scheduled, skipping duplicate');
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
    _vpnManager?.dispose();
  }
}