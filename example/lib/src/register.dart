import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user_cubit.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class RegisterWidget extends StatefulWidget {
  final SIPUAHelper? _helper;

  RegisterWidget(this._helper, {Key? key}) : super(key: key);

  @override
  State<RegisterWidget> createState() => _MyRegisterWidget();
}

class _MyRegisterWidget extends State<RegisterWidget>
    implements SipUaHelperListener {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _wsUriController = TextEditingController();
  final TextEditingController _sipUriController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _authorizationUserController =
      TextEditingController();
  final Map<String, String> _wsExtraHeaders = {
    // 'Origin': ' https://tryit.jssip.net',
    // 'Host': 'tryit.jssip.net:10443'
  };
  late SharedPreferences _preferences;
  late RegistrationState _registerState;

  TransportType _selectedTransport = TransportType.TCP;

  SIPUAHelper? get helper => widget._helper;

  late SipUserCubit currentUser;

  @override
  void initState() {
    super.initState();
    _registerState = helper!.registerState;
    helper!.addSipUaHelperListener(this);
    _loadSettings();
    if (kIsWeb) {
      _selectedTransport = TransportType.WS;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _wsUriController.dispose();
    _sipUriController.dispose();
    _displayNameController.dispose();
    _authorizationUserController.dispose();
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
    setState(() {
      _portController.text = _preferences.getString('port') ?? '5060';
      _wsUriController.text =
          _preferences.getString('ws_uri') ?? 'wss://sip.ibos.io:8089/ws';
      _sipUriController.text =
          _preferences.getString('sip_uri') ?? '564613@sip.ibos.io';
      _displayNameController.text =
          _preferences.getString('display_name') ?? '564613';
      _passwordController.text = _preferences.getString('password') ?? 'iBOS123';
      _authorizationUserController.text =
          _preferences.getString('auth_user') ?? '564613';
    });
  }

  void _saveSettings() {
    _preferences.setString('port', _portController.text);
    _preferences.setString('ws_uri', _wsUriController.text);
    _preferences.setString('sip_uri', _sipUriController.text);
    _preferences.setString('display_name', _displayNameController.text);
    _preferences.setString('password', _passwordController.text);
    _preferences.setString('auth_user', _authorizationUserController.text);
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    print('=== REGISTRATION STATE CHANGED ===');
    print('State: ${state.state}');
    print('Cause: ${state.cause}');
    if (state.cause != null) {
      print('Cause details: ${state.cause.toString()}');
    }
    setState(() {
      _registerState = state;
    });
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
    if (_wsUriController.text == '') {
      _alert(context, "WebSocket URL");
    } else if (_sipUriController.text == '') {
      _alert(context, "SIP URI");
    }

    _saveSettings();

    currentUser.register(SipUser(
        selectedTransport: _selectedTransport,
        wsExtraHeaders: _wsExtraHeaders,
        sipUri: _sipUriController.text,
        wsUrl: _wsUriController.text,
        port: _portController.text,
        displayName: _displayNameController.text,
        password: _passwordController.text,
        authUser: _authorizationUserController.text));
  }

  void _disconnect() {
    currentUser.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    currentUser = context.watch<SipUserCubit>();

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
              if (_registerState.state == RegistrationStateEnum.REGISTERED) ...[
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
                          _registerState.state == RegistrationStateEnum.REGISTERED
                              ? Icons.check_circle
                              : _registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                  ? Icons.error
                                  : Icons.pending,
                          color: _registerState.state == RegistrationStateEnum.REGISTERED
                              ? Colors.green
                              : _registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                  ? Colors.red
                                  : Colors.orange,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Status: ${_registerState.state?.name ?? 'Unknown'}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_registerState.state == RegistrationStateEnum.REGISTERED) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Registration successful! Your account will auto-reconnect on restart.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_registerState.state == RegistrationStateEnum.REGISTRATION_FAILED) ...[
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
                      groupValue: _selectedTransport,
                      onChanged: (value) => setState(() {
                        _selectedTransport = value!;
                      }),
                      title: Text('TCP'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<TransportType>(
                      value: TransportType.WS,
                      groupValue: _selectedTransport,
                      onChanged: (value) => setState(() {
                        _selectedTransport = value!;
                      }),
                      title: Text('WebSocket'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
            if (_selectedTransport == TransportType.WS) ...[
              Text(
                'WebSocket URL',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _wsUriController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  hintText: 'wss://your-server.com:port/path',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_selectedTransport == TransportType.TCP) ...[
              Text(
                'Port',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _portController,
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
              controller: _sipUriController,
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
              controller: _authorizationUserController,
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
              controller: _passwordController,
              keyboardType: TextInputType.text,
              autocorrect: false,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Enter your password',
                prefixIcon: Icon(Icons.lock),
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
              controller: _displayNameController,
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