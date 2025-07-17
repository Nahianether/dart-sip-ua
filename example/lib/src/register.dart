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
  // Controllers are now provided by Riverpod providers
  final Map<String, String> _wsExtraHeaders = {
    // 'Origin': ' https://tryit.jssip.net',
    // 'Host': 'tryit.jssip.net:10443'
  };
  late SharedPreferences _preferences;

  SIPUAHelper? get helper => widget._helper;

  // SipUserCubit is now provided by Riverpod

  @override
  void initState() {
    super.initState();
    helper!.addSipUaHelperListener(this);
    _loadSettings();
    if (kIsWeb) {
      ref.read(transportTypeProvider.notifier).state = TransportType.WS;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void deactivate() {
    super.deactivate();
    helper!.removeSipUaHelperListener(this);
    _saveSettings();
  }

  void _loadSettings() async {
    _preferences = await SharedPreferences.getInstance();
    
    final portController = ref.read(portControllerProvider);
    final wsUriController = ref.read(wsUriControllerProvider);
    final sipUriController = ref.read(sipUriControllerProvider);
    final displayNameController = ref.read(displayNameControllerProvider);
    final passwordController = ref.read(passwordControllerProvider);
    final authorizationUserController = ref.read(authorizationUserControllerProvider);
    
    portController.text = _preferences.getString('port') ?? '5060';
    wsUriController.text = _preferences.getString('ws_uri') ?? 'wss://sip.ibos.io:8089/ws';
    sipUriController.text = _preferences.getString('sip_uri') ?? '564613@sip.ibos.io';
    displayNameController.text = _preferences.getString('display_name') ?? '564613';
    passwordController.text = _preferences.getString('password') ?? 'iBOS123';
    authorizationUserController.text = _preferences.getString('auth_user') ?? '564613';
  }

  void _saveSettings() {
    final portController = ref.read(portControllerProvider);
    final wsUriController = ref.read(wsUriControllerProvider);
    final sipUriController = ref.read(sipUriControllerProvider);
    final displayNameController = ref.read(displayNameControllerProvider);
    final passwordController = ref.read(passwordControllerProvider);
    final authorizationUserController = ref.read(authorizationUserControllerProvider);
    
    _preferences.setString('port', portController.text);
    _preferences.setString('ws_uri', wsUriController.text);
    _preferences.setString('sip_uri', sipUriController.text);
    _preferences.setString('display_name', displayNameController.text);
    _preferences.setString('password', passwordController.text);
    _preferences.setString('auth_user', authorizationUserController.text);
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    print('=== REGISTRATION STATE CHANGED ===');
    print('State: ${state.state}');
    print('Cause: ${state.cause}');
    if (state.cause != null) {
      print('Cause details: ${state.cause.toString()}');
      print('Cause type: ${state.cause.runtimeType}');
    }
    
    final wsUriController = ref.read(wsUriControllerProvider);
    final sipUriController = ref.read(sipUriControllerProvider);
    
    print('Registration attempt with server: ${wsUriController.text}');
    print('SIP URI: ${sipUriController.text}');
    
    // Show user-friendly error message
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    ref.read(registrationStateProvider.notifier).state = state;
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

  void _register(BuildContext context) {
    final wsUriController = ref.read(wsUriControllerProvider);
    final sipUriController = ref.read(sipUriControllerProvider);
    final portController = ref.read(portControllerProvider);
    final displayNameController = ref.read(displayNameControllerProvider);
    final passwordController = ref.read(passwordControllerProvider);
    final authorizationUserController = ref.read(authorizationUserControllerProvider);
    final selectedTransport = ref.read(transportTypeProvider);
    final currentUser = ref.read(sipUserCubitProvider);
    
    if (wsUriController.text == '') {
      _alert(context, "WebSocket URL");
    } else if (sipUriController.text == '') {
      _alert(context, "SIP URI");
    }

    _saveSettings();

    currentUser.register(SipUser(
        selectedTransport: selectedTransport,
        wsExtraHeaders: _wsExtraHeaders,
        sipUri: sipUriController.text,
        wsUrl: wsUriController.text,
        port: portController.text,
        displayName: displayNameController.text,
        password: passwordController.text,
        authUser: authorizationUserController.text));
  }

  void _disconnect() {
    final currentUser = ref.read(sipUserCubitProvider);
    currentUser.disconnect();
  }

  void _forceReconnect() {
    final currentUser = ref.read(sipUserCubitProvider);
    currentUser.forceReconnect();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Attempting to reconnect...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testConnectivity() async {
    final wsUriController = ref.read(wsUriControllerProvider);
    String wsUrl = wsUriController.text;
    if (wsUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter WebSocket URL first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Testing Connection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Testing connection to server...'),
          ],
        ),
      ),
    );

    try {
      // Extract host and port from WebSocket URL
      Uri uri = Uri.parse(wsUrl);
      String host = uri.host;
      int port = uri.port;
      
      print('Testing connection to $host:$port');
      
      // Test basic connectivity
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
      
      Navigator.pop(context); // Close loading dialog
      
      String resultMessage;
      
      if (canConnect) {
        resultMessage = '✅ Connection successful!\nServer is reachable at $host:$port';
      } else {
        resultMessage = '❌ Connection failed!\nCannot reach $host:$port\n\nError: $errorMessage\n\nTips:\n• Check if server is running\n• Verify URL is correct\n• Check firewall settings\n• Try from different network';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Connection Test Result'),
          content: SingleChildScrollView(
            child: Text(resultMessage),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
      
    } catch (e) {
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error testing connection: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registerState = ref.watch(registrationStateProvider) ?? helper!.registerState;
    final isPasswordVisible = ref.watch(passwordVisibilityProvider);
    final selectedTransport = ref.watch(transportTypeProvider);
    final passwordController = ref.watch(passwordControllerProvider);
    final wsUriController = ref.watch(wsUriControllerProvider);
    final sipUriController = ref.watch(sipUriControllerProvider);
    final portController = ref.watch(portControllerProvider);
    final displayNameController = ref.watch(displayNameControllerProvider);
    final authorizationUserController = ref.watch(authorizationUserControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Account Settings",
          style: theme.textTheme.headlineMedium,
        ),
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (registerState.state == RegistrationStateEnum.REGISTRATION_FAILED) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Registration failed. Please check your settings and try again.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!kIsWeb) ...[
              Text(
                'Connection Type',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<TransportType>(
                      value: TransportType.TCP,
                      groupValue: selectedTransport,
                      onChanged: (value) => ref.read(transportTypeProvider.notifier).state = value!,
                      title: Text('TCP'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<TransportType>(
                      value: TransportType.WS,
                      groupValue: selectedTransport,
                      onChanged: (value) => ref.read(transportTypeProvider.notifier).state = value!,
                      title: Text('WebSocket'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (selectedTransport == TransportType.WS) ...[
              Text(
                'WebSocket URL',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: wsUriController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'wss://your-server.com:port/path',
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
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (selectedTransport == TransportType.TCP) ...[
              Text(
                'Port',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '5060',
                  prefixIcon: Icon(Icons.settings_ethernet),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'SIP URI',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
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
    //NO OP
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