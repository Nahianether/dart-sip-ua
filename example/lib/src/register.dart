import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:dart_sip_ua_example/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';

class RegisterWidget extends ConsumerStatefulWidget {
  final SIPUAHelper? _helper;

  RegisterWidget(this._helper, {Key? key}) : super(key: key);

  @override
  ConsumerState<RegisterWidget> createState() => _MyRegisterWidget();
}

class _MyRegisterWidget extends ConsumerState<RegisterWidget>
    implements SipUaHelperListener {
  final Map<String, String> _wsExtraHeaders = {};
  late SharedPreferences _preferences;
  bool _isInitialized = false;

  SIPUAHelper? get helper => widget._helper;

  @override
  void initState() {
    super.initState();
    print('RegisterWidget: Initializing without provider modifications');
    
    // Use post-frame callback to initialize after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAfterBuild();
    });
  }

  void _initializeAfterBuild() async {
    if (!mounted || _isInitialized) return;
    _isInitialized = true;
    
    try {
      _loadSettings();
    } catch (e) {
      print('❌ Error during initialization: $e');
    }
  }

  @override
  void dispose() {
    helper?.removeSipUaHelperListener(this);
    super.dispose();
  }

  void _loadSettings() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      
      // Load transport type from preferences
      String savedTransport = _preferences.getString('transport_type') ?? 'TransportType.WS';
      TransportType transport = savedTransport.contains('TCP') ? TransportType.TCP : TransportType.WS;
      
      if (mounted) {
        // Set transport type safely
        ref.read(transportTypeProvider.notifier).state = transport;
      }
      
      // Load controller values
      final portController = ref.read(portControllerProvider);
      final wsUriController = ref.read(wsUriControllerProvider);
      final sipUriController = ref.read(sipUriControllerProvider);
      final displayNameController = ref.read(displayNameControllerProvider);
      final passwordController = ref.read(passwordControllerProvider);
      final authorizationUserController = ref.read(authorizationUserControllerProvider);
      
      // Set default values based on transport type
      if (transport == TransportType.TCP) {
        portController.text = _preferences.getString('port') ?? '5060';
        wsUriController.text = _preferences.getString('server_url') ?? 'sip.ibos.io';
        sipUriController.text = _preferences.getString('sip_uri') ?? '564613@sip.ibos.io';
      } else {
        portController.text = _preferences.getString('port') ?? '8089';
        wsUriController.text = _preferences.getString('server_url') ?? 'wss://sip.ibos.io:8089/ws';
        sipUriController.text = _preferences.getString('sip_uri') ?? '564613@sip.ibos.io';
      }
      
      displayNameController.text = _preferences.getString('display_name') ?? '564613';
      passwordController.text = _preferences.getString('password') ?? 'iBOS123';
      authorizationUserController.text = _preferences.getString('auth_user') ?? '564613';
      
      print('📋 Settings loaded successfully');
    } catch (e) {
      print('❌ Error loading settings: $e');
    }
  }

  void _saveSettings() {
    try {
      if (!_isInitialized) return;
      
      final portController = ref.read(portControllerProvider);
      final wsUriController = ref.read(wsUriControllerProvider);
      final sipUriController = ref.read(sipUriControllerProvider);
      final displayNameController = ref.read(displayNameControllerProvider);
      final passwordController = ref.read(passwordControllerProvider);
      final authorizationUserController = ref.read(authorizationUserControllerProvider);
      final selectedTransport = ref.read(transportTypeProvider);
      
      _preferences.setString('port', portController.text);
      _preferences.setString('server_url', wsUriController.text);
      _preferences.setString('sip_uri', sipUriController.text);
      _preferences.setString('display_name', displayNameController.text);
      _preferences.setString('password', passwordController.text);
      _preferences.setString('auth_user', authorizationUserController.text);
      _preferences.setString('transport_type', selectedTransport.toString());
      
      print('💾 Settings saved');
    } catch (e) {
      print('❌ Error saving settings: $e');
    }
  }

  void _handleTransportChange(TransportType newTransport) {
    if (mounted && _isInitialized) {
      ref.read(transportTypeProvider.notifier).state = newTransport;
      _saveSettings();
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    print('Registration state: ${state.state}');
    
    if (state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      String errorMsg = 'Registration failed';
      if (state.cause != null) {
        final cause = state.cause.toString().toLowerCase();
        if (cause.contains('connection') || cause.contains('network')) {
          errorMsg = 'Network connection failed. Check server URL and internet connection.';
        } else if (cause.contains('unauthorized') || cause.contains('403') || cause.contains('401')) {
          errorMsg = 'Authentication failed. Check username and password.';
        } else if (cause.contains('timeout')) {
          errorMsg = 'Connection timeout. Server may be unreachable.';
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (mounted) {
      ref.read(registrationStateProvider.notifier).state = state;
    }
  }

  void _alert(BuildContext context, String alertFieldName) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
            title: Text('$alertFieldName is empty'),
            content: Text('Please enter $alertFieldName!'),
            actions: <Widget>[
              TextButton(
                child: Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ]);
      },
    );
  }

  void _register(BuildContext context) async {
    final wsUriController = ref.read(wsUriControllerProvider);
    final sipUriController = ref.read(sipUriControllerProvider);
    final portController = ref.read(portControllerProvider);
    final displayNameController = ref.read(displayNameControllerProvider);
    final passwordController = ref.read(passwordControllerProvider);
    final authorizationUserController = ref.read(authorizationUserControllerProvider);
    final selectedTransport = ref.read(transportTypeProvider);
    final currentUser = ref.read(sipUserCubitProvider);
    
    // Validation based on transport type
    if (selectedTransport == TransportType.WS) {
      if (wsUriController.text.trim().isEmpty) {
        _alert(context, "WebSocket URL");
        return;
      }
      if (!wsUriController.text.startsWith('ws://') && !wsUriController.text.startsWith('wss://')) {
        _alert(context, "WebSocket URL must start with ws:// or wss://");
        return;
      }
    } else if (selectedTransport == TransportType.TCP) {
      if (wsUriController.text.trim().isEmpty) {
        _alert(context, "Server Host/IP");
        return;
      }
      if (portController.text.trim().isEmpty) {
        _alert(context, "Port number");
        return;
      }
      try {
        int port = int.parse(portController.text);
        if (port < 1 || port > 65535) {
          _alert(context, "Port must be between 1 and 65535");
          return;
        }
      } catch (e) {
        _alert(context, "Port must be a valid number");
        return;
      }
    }
    
    if (sipUriController.text.trim().isEmpty) {
      _alert(context, "SIP URI");
      return;
    }
    
    if (passwordController.text.trim().isEmpty) {
      _alert(context, "Password");
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Connecting...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Establishing ${selectedTransport.toString().split('.').last} connection...'),
          ],
        ),
      ),
    );

    try {
      _saveSettings();
      
      String serverUrl = wsUriController.text.trim();
      
      currentUser.register(SipUser(
        selectedTransport: selectedTransport,
        wsExtraHeaders: _wsExtraHeaders,
        sipUri: sipUriController.text.trim(),
        wsUrl: serverUrl,
        port: portController.text.trim(),
        displayName: displayNameController.text.trim().isNotEmpty 
            ? displayNameController.text.trim() 
            : authorizationUserController.text.trim(),
        password: passwordController.text.trim(),
        authUser: authorizationUserController.text.trim().isNotEmpty 
            ? authorizationUserController.text.trim() 
            : sipUriController.text.trim().split('@')[0]
      ));
              
      // Close loading dialog
      Future.delayed(Duration(seconds: 2), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
      
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _disconnect() {
    final currentUser = ref.read(sipUserCubitProvider);
    currentUser.disconnect();
  }

  void _forceReconnect() {
    final currentUser = ref.read(sipUserCubitProvider);
    currentUser.forceReconnect();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Attempting to reconnect...'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _testConnectivity() async {
    final wsUriController = ref.read(wsUriControllerProvider);
    String wsUrl = wsUriController.text;
    if (wsUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enter WebSocket URL first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Testing WebSocket Connection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Testing WebSocket connection...'),
          ],
        ),
      ),
    );

    try {
      Uri uri = Uri.parse(wsUrl);
      String host = uri.host;
      int port = uri.port;
      
      Socket? socket;
      bool canConnect = false;
      String errorMessage = '';
      
      try {
        socket = await Socket.connect(host, port, timeout: Duration(seconds: 10));
        canConnect = true;
        socket.destroy();
      } catch (e) {
        canConnect = false;
        errorMessage = e.toString();
      }
      
      if (mounted) Navigator.pop(context);
      
      String resultMessage;
      if (canConnect) {
        resultMessage = '✅ WebSocket Server Reachable!\n';
        resultMessage += 'Host: $host\nPort: $port\n';
        resultMessage += 'Protocol: ${wsUrl.startsWith('wss://') ? 'Secure WebSocket (WSS)' : 'WebSocket (WS)'}\n\n';
        resultMessage += 'Basic TCP connectivity confirmed.';
      } else {
        resultMessage = '❌ WebSocket Connection Failed!\n';
        resultMessage += 'Cannot reach $host:$port\n\nError: $errorMessage';
      }
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('WebSocket Test Result'),
            content: SingleChildScrollView(child: Text(resultMessage)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error testing connection: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Future<void> _testTCPConnectivity() async {
    final wsUriController = ref.read(wsUriControllerProvider);
    final portController = ref.read(portControllerProvider);
    
    String host = wsUriController.text.trim();
    String portText = portController.text.trim();
    
    if (host.isEmpty || portText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enter both server host and port'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    int port;
    try {
      port = int.parse(portText);
      if (port < 1 || port > 65535) {
        throw Exception('Invalid port range');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enter a valid port number (1-65535)'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Testing TCP Connection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Testing TCP connection to $host:$port...'),
          ],
        ),
      ),
    );

    try {
      Socket? socket;
      bool canConnect = false;
      String errorMessage = '';
      
      try {
        socket = await Socket.connect(host, port, timeout: Duration(seconds: 10));
        canConnect = true;
        socket.destroy();
      } catch (e) {
        canConnect = false;
        errorMessage = e.toString();
      }
      
      if (mounted) Navigator.pop(context);
      
      String resultMessage;
      if (canConnect) {
        resultMessage = '✅ TCP Connection Successful!\n';
        resultMessage += 'Host: $host\nPort: $port\n';
        resultMessage += 'Protocol: ${port == 5061 ? 'Secure SIP (TLS)' : 'Standard SIP'}';
      } else {
        resultMessage = '❌ TCP Connection Failed!\n';
        resultMessage += 'Cannot reach $host:$port\n\nError: $errorMessage';
      }
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('TCP Test Result'),
            content: SingleChildScrollView(child: Text(resultMessage)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error testing TCP connection: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildTransportInfo() {
    final selectedTransport = ref.watch(transportTypeProvider);
    
    String infoTitle;
    String infoMessage;
    IconData infoIcon;
    Color infoColor;
    
    if (selectedTransport == TransportType.WS) {
      infoTitle = 'WebSocket Transport';
      infoMessage = '• Uses HTTP/HTTPS protocols\n• Better firewall compatibility\n• Good for web applications\n• URL format: wss://server:port/path';
      infoIcon = Icons.wifi;
      infoColor = Colors.blue;
    } else {
      infoTitle = 'TCP Transport';
      infoMessage = '• Direct TCP connection\n• Lower latency\n• Traditional SIP setup\n• Format: server:port (no protocol)';
      infoIcon = Icons.cable;
      infoColor = Colors.green;
    }
    
    return Container(
      margin: EdgeInsets.only(top: 8, bottom: 16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: infoColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: infoColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(infoIcon, color: infoColor, size: 20),
              SizedBox(width: 8),
              Text(
                infoTitle,
                style: TextStyle(
                  color: infoColor.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            infoMessage,
            style: TextStyle(
              color: infoColor.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registerState = ref.watch(registrationStateProvider) ?? helper!.registerState;
    final isPasswordVisible = ref.watch(passwordVisibilityProvider);
    final selectedTransport = ref.watch(transportTypeProvider);
    
    // Watch controllers but don't modify them in build
    final passwordController = ref.watch(passwordControllerProvider);
    final wsUriController = ref.watch(wsUriControllerProvider);
    final sipUriController = ref.watch(sipUriControllerProvider);
    final portController = ref.watch(portControllerProvider);
    final displayNameController = ref.watch(displayNameControllerProvider);
    final authorizationUserController = ref.watch(authorizationUserControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text("Account Settings", style: theme.textTheme.headlineMedium),
        centerTitle: true,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (registerState.state == RegistrationStateEnum.REGISTERED) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text('Disconnect'),
                    onPressed: _disconnect,
                  ),
                ),
              ] else if (registerState.state == RegistrationStateEnum.REGISTRATION_FAILED) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text('Register'),
                        onPressed: () => _register(context),
                      ),
                    ),
                    SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      ),
                      child: Icon(Icons.refresh),
                      onPressed: _forceReconnect,
                    ),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text('Register'),
                    onPressed: () => _register(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              child: Container(
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          registerState.state == RegistrationStateEnum.REGISTERED
                              ? Icons.check_circle
                              : registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                  ? Icons.error
                                  : Icons.pending,
                          color: registerState.state == RegistrationStateEnum.REGISTERED
                              ? Colors.green
                              : registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                  ? Colors.red
                                  : Colors.orange,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Status: ${registerState.state?.name ?? 'Unknown'}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (registerState.state == RegistrationStateEnum.REGISTERED) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Registration successful! Your account will auto-reconnect on restart.',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (registerState.state == RegistrationStateEnum.REGISTRATION_FAILED) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Registration failed. Please check your settings and try again.',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Transport Type Selection
            if (!kIsWeb) ...[
              Text(
                'Connection Type',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<TransportType>(
                      value: TransportType.TCP,
                      groupValue: selectedTransport,
                      onChanged: (value) => _handleTransportChange(value!),
                      title: Text('TCP'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<TransportType>(
                      value: TransportType.WS,
                      groupValue: selectedTransport,
                      onChanged: (value) => _handleTransportChange(value!),
                      title: Text('WebSocket'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              _buildTransportInfo(),
            ],
            
            // Server Configuration
            if (selectedTransport == TransportType.WS) ...[
              Text(
                'WebSocket URL',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: wsUriController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (value) {
                  // Auto-detect port from WebSocket URL
                  Future.microtask(() {
                    try {
                      if (value.startsWith('ws://') || value.startsWith('wss://')) {
                        Uri uri = Uri.parse(value);
                        if (uri.port != 80 && uri.port != 443) {
                          portController.text = uri.port.toString();
                        } else if (value.startsWith('wss://')) {
                          portController.text = '443';
                        } else {
                          portController.text = '80';
                        }
                      }
                    } catch (e) {
                      // Ignore parsing errors
                    }
                  });
                },
                decoration: InputDecoration(
                  hintText: 'wss://your-server.com:port/path',
                  helperText: 'Example: wss://sip.ibos.io:8089/ws',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _testConnectivity,
                  icon: Icon(Icons.network_ping, size: 18),
                  label: Text('Test Connection'),
                ),
              ),
              const SizedBox(height: 16),
            ] else if (selectedTransport == TransportType.TCP) ...[
              Text(
                'Server Host/IP',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: wsUriController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'server.example.com or 192.168.1.100',
                  helperText: 'Enter hostname or IP address (no protocol)',
                  prefixIcon: Icon(Icons.dns),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Port',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '5060 (standard) or 5061 (secure)',
                  helperText: 'Standard SIP: 5060, Secure SIP: 5061',
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _testTCPConnectivity,
                  icon: Icon(Icons.network_ping, size: 18),
                  label: Text('Test TCP Connection'),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // SIP Configuration
            Text(
              'SIP URI',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: sipUriController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'username@domain.com',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Authorization User',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: authorizationUserController,
              keyboardType: TextInputType.text,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'Optional: Different username for auth',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Password',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: passwordController,
              keyboardType: TextInputType.text,
              autocorrect: false,
              obscureText: !isPasswordVisible,
              decoration: InputDecoration(
                hintText: 'Enter your password',
                prefixIcon: Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    ref.read(passwordVisibilityProvider.notifier).state = !isPasswordVisible;
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Display Name',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: displayNameController,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                hintText: 'Your display name',
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  @override
  void callStateChanged(Call call, CallState state) {
    // NO OP
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void onNewMessage(SIPMessageRequest msg) {
    // NO OP
  }

  @override
  void onNewNotify(Notify ntf) {
    // NO OP
  }

  @override
  void onNewReinvite(ReInvite event) {
    // Handle re-invite events here if needed
  }
}