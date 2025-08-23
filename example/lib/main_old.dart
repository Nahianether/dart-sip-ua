import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/providers.dart';
import 'src/auth_providers.dart';
import 'src/vpn_manager.dart';
import 'domain/entities/sip_account_entity.dart';
import 'domain/entities/call_entity.dart';
import 'screens/modern_dialer_screen.dart';
import 'screens/modern_login_screen.dart';
import 'screens/modern_call_screen.dart';
import 'data/services/ringtone_vibration_service.dart';
import 'data/services/connection_stability_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  final container = ProviderContainer();
  
  // Initialize SIP data source
  await container.read(sipDataSourceProvider).initialize();
  
  // Initialize ringtone and vibration service
  await RingtoneVibrationService().initialize();
  
  // Initialize connection stability service
  ConnectionStabilityService();
  
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: VoIPApp(),
    ),
  );
}

class VoIPApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch settings for theme
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final themeMode = settingsAsync.maybeWhen(
      data: (settings) => settings.themeMode,
      orElse: () => ThemeMode.system,
    );
    
    return MaterialApp(
      title: 'VoIP Phone',
      themeMode: themeMode,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: AppNavigator(),
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 4,
        color: Colors.grey[900],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey[800],
      ),
    );
  }
}

// Global navigator key for navigation from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class AppNavigator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Check auto-login first
    final autoLoginAsync = ref.watch(autoLoginProvider);
    final accountState = ref.watch(accountProvider);
    
    return autoLoginAsync.when(
      data: (savedCredentials) {
        return accountState.when(
          data: (account) {
            if (account != null) {
              // User is logged in, show dialer with call handling
              return _buildMainApp(context, ref);
            } else if (savedCredentials != null) {
              // Try auto-login with saved credentials
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _attemptAutoLogin(ref, savedCredentials);
              });
              return _buildLoadingScreen('Connecting...', true);
            } else {
              // No saved credentials, show login screen
              return ModernLoginScreen();
            }
          },
          loading: () => _buildLoadingScreen('Connecting...', true),
          error: (error, stack) => _buildErrorScreen(context, ref, error),
        );
      },
      loading: () => _buildLoadingScreen('Loading...', false),
      error: (error, stack) => ModernLoginScreen(), // Fallback to login on error
    );
  }

  Widget _buildMainApp(BuildContext context, WidgetRef ref) {
    return Consumer(
      builder: (context, ref, child) {
        // Listen to incoming calls and handle ringtone
        ref.listen<AsyncValue<CallEntity>>(incomingCallsProvider, (previous, next) {
          next.whenData((call) {
            if (call.direction == CallDirection.incoming) {
              _handleIncomingCall(context, call);
            }
          });
        });
        
        // Listen to call state changes
        ref.listen<CallEntity?>(callStateProvider, (previous, next) {
          if (next != null && previous == null) {
            // Call initiated, navigate to call screen
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ModernCallScreen(call: next),
              ),
            );
          } else if (next == null && previous != null) {
            // Call ended, stop ringtone and pop to dialer
            RingtoneVibrationService().stopRinging();
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        });
        
        return ModernDialerScreen();
      },
    );
  }

  Widget _buildLoadingScreen(String message, bool showProgress) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.blue.shade100],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Colors.blue, Colors.blueAccent],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.phone_in_talk,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 32),
              if (showProgress) CircularProgressIndicator(),
              if (showProgress) SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(BuildContext context, WidgetRef ref, Object error) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red.shade50, Colors.red.shade100],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 80),
                SizedBox(height: 24),
                Text(
                  'Connection Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  '$error',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.invalidate(accountProvider);
                    ref.invalidate(autoLoginProvider);
                  },
                  icon: Icon(Icons.refresh),
                  label: Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    // Clear credentials and go to login
                    await ref.read(loginActionProvider).logout();
                    ref.invalidate(autoLoginProvider);
                  },
                  child: Text('Sign In Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _attemptAutoLogin(WidgetRef ref, SipAccountEntity credentials) {
    // Auto-login is attempted by loading saved credentials,
    // but password is not saved for security, so go to login screen
    // with pre-filled fields except password
    ref.read(loginActionProvider).loadSavedCredentials(credentials);
  }

  void _handleIncomingCall(BuildContext context, CallEntity call) async {
    // Start ringtone and vibration
    await RingtoneVibrationService().startRinging();
    
    // Navigate to call screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ModernCallScreen(call: call),
        settings: RouteSettings(name: '/incoming-call'),
      ),
    );
  }
}

// Theme provider for backward compatibility
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class LoginScreenRiverpod extends ConsumerStatefulWidget {
  @override
  ConsumerState<LoginScreenRiverpod> createState() => _LoginScreenRiverpodState();
}

class _LoginScreenRiverpodState extends ConsumerState<LoginScreenRiverpod> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _domainController = TextEditingController();
  final _wsUrlController = TextEditingController();
  final _displayNameController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    _wsUrlController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider);
    
    // Listen to account state changes
    ref.listen<AsyncValue<SipAccountEntity?>>(accountProvider, (previous, next) {
      next.whenData((account) {
        if (account != null) {
          // Login successful, navigation will happen automatically
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connected successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      });
      
      next.whenOrNull(
        error: (error, stackTrace) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login failed: $error'),
              backgroundColor: Colors.red,
            ),
          );
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Android SIP Client'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Text(
                'SIP Account Setup',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value?.isEmpty == true) {
                    return 'Username is required';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
                validator: (value) {
                  if (value?.isEmpty == true) {
                    return 'Password is required';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              
              TextFormField(
                controller: _domainController,
                decoration: InputDecoration(
                  labelText: 'Domain',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.domain),
                ),
                validator: (value) {
                  if (value?.isEmpty == true) {
                    return 'Domain is required';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              
              TextFormField(
                controller: _wsUrlController,
                decoration: InputDecoration(
                  labelText: 'WebSocket URL',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                  hintText: 'wss://example.com:8089/ws',
                ),
                validator: (value) {
                  if (value?.isEmpty == true) {
                    return 'WebSocket URL is required';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: 'Display Name (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge),
                ),
              ),
              SizedBox(height: 32),
              
              ElevatedButton(
                onPressed: accountState.isLoading ? null : _onLoginPressed,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
                child: accountState.isLoading
                    ? CircularProgressIndicator()
                    : Text(
                        'Connect',
                        style: TextStyle(fontSize: 18),
                      ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onLoginPressed() {
    if (_formKey.currentState?.validate() == true) {
      final account = SipAccountEntity(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        username: _usernameController.text,
        password: _passwordController.text,
        domain: _domainController.text,
        wsUrl: _wsUrlController.text,
        displayName: _displayNameController.text.isEmpty 
            ? null 
            : _displayNameController.text,
        isDefault: true,
      );

      ref.read(accountProvider.notifier).login(account);
    }
  }
}

class DialerScreenRiverpod extends ConsumerStatefulWidget {
  @override
  ConsumerState<DialerScreenRiverpod> createState() => _DialerScreenRiverpodState();
}

class _DialerScreenRiverpodState extends ConsumerState<DialerScreenRiverpod> {
  final TextEditingController _phoneController = TextEditingController();
  String _currentNumber = '';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionStatus = ref.watch(connectionStatusProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Android SIP Client'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () {
              ref.read(accountProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status
          connectionStatus.when(
            data: (status) => Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              color: _getStatusColor(status),
              child: Text(
                _getStatusText(status),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            loading: () => Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              color: Colors.grey,
              child: Text(
                'Connecting...',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
            error: (error, stack) => Container(
              width: double.infinity,
              padding: EdgeInsets.all(16),
              color: Colors.red,
              child: Text(
                'Connection Error',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          
          // VPN Status Indicator
          Consumer(
            builder: (context, ref, child) {
              final vpnStatus = ref.watch(vpnStatusProvider);
              return Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                color: _getVPNStatusColor(vpnStatus).withValues(alpha: 0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getVPNStatusIcon(vpnStatus),
                      color: _getVPNStatusColor(vpnStatus),
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      _getVPNStatusText(vpnStatus),
                      style: TextStyle(
                        color: _getVPNStatusColor(vpnStatus),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Phone Number Display
          Container(
            padding: EdgeInsets.all(24),
            child: TextField(
              controller: _phoneController,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
              decoration: InputDecoration(
                hintText: 'Enter phone number',
                border: InputBorder.none,
              ),
              readOnly: true,
            ),
          ),
          
          // Dialpad
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              padding: EdgeInsets.all(16),
              children: [
                _buildDialpadButton('1', ''),
                _buildDialpadButton('2', 'ABC'),
                _buildDialpadButton('3', 'DEF'),
                _buildDialpadButton('4', 'GHI'),
                _buildDialpadButton('5', 'JKL'),
                _buildDialpadButton('6', 'MNO'),
                _buildDialpadButton('7', 'PQRS'),
                _buildDialpadButton('8', 'TUV'),
                _buildDialpadButton('9', 'WXYZ'),
                _buildDialpadButton('*', ''),
                _buildDialpadButton('0', '+'),
                _buildDialpadButton('#', ''),
              ],
            ),
          ),
          
          // Call Controls
          Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Backspace
                IconButton(
                  onPressed: _currentNumber.isNotEmpty ? _onBackspace : null,
                  icon: Icon(Icons.backspace, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    minimumSize: Size(60, 60),
                  ),
                ),
                
                // Call Button
                IconButton(
                  onPressed: _currentNumber.isNotEmpty ? _onCallPressed : null,
                  icon: Icon(Icons.phone, size: 32),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: Size(80, 80),
                  ),
                ),
                
                // Clear
                IconButton(
                  onPressed: _currentNumber.isNotEmpty ? _onClear : null,
                  icon: Icon(Icons.clear, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    minimumSize: Size(60, 60),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialpadButton(String number, String letters) {
    return Padding(
      padding: EdgeInsets.all(4),
      child: ElevatedButton(
        onPressed: () => _onNumberPressed(number),
        style: ElevatedButton.styleFrom(
          shape: CircleBorder(),
          padding: EdgeInsets.zero,
          minimumSize: Size(70, 70),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              number,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300),
            ),
            if (letters.isNotEmpty)
              Text(
                letters,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
          ],
        ),
      ),
    );
  }

  void _onNumberPressed(String number) {
    setState(() {
      _currentNumber += number;
      _phoneController.text = _currentNumber;
    });
  }

  void _onBackspace() {
    if (_currentNumber.isNotEmpty) {
      setState(() {
        _currentNumber = _currentNumber.substring(0, _currentNumber.length - 1);
        _phoneController.text = _currentNumber;
      });
    }
  }

  void _onClear() {
    setState(() {
      _currentNumber = '';
      _phoneController.text = '';
    });
  }

  void _onCallPressed() {
    if (_currentNumber.isNotEmpty) {
      ref.read(callStateProvider.notifier).makeCall(_currentNumber);
    }
  }

  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.registered:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.registering:
        return Colors.orange;
      case ConnectionStatus.failed:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.registered:
        return '✅ Connected - Ready for calls';
      case ConnectionStatus.connecting:
        return '🔄 Connecting...';
      case ConnectionStatus.registering:
        return '🔄 Registering...';
      case ConnectionStatus.connected:
        return '🔗 Connected';
      case ConnectionStatus.failed:
        return '❌ Connection failed';
      default:
        return '⚪ Disconnected';
    }
  }
  
  // VPN Status Helper Methods
  Color _getVPNStatusColor(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return Colors.green;
      case VpnConnectionStatus.connecting:
        return Colors.orange;
      case VpnConnectionStatus.error:
      case VpnConnectionStatus.denied:
        return Colors.red;
      case VpnConnectionStatus.disconnected:
        return Colors.grey;
    }
  }
  
  IconData _getVPNStatusIcon(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return Icons.vpn_lock;
      case VpnConnectionStatus.connecting:
        return Icons.sync;
      case VpnConnectionStatus.error:
      case VpnConnectionStatus.denied:
        return Icons.error;
      case VpnConnectionStatus.disconnected:
        return Icons.vpn_key_off;
    }
  }
  
  String _getVPNStatusText(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return '🔒 VPN Secured';
      case VpnConnectionStatus.connecting:
        return '🔄 Securing connection...';
      case VpnConnectionStatus.error:
        return '❌ VPN Error';
      case VpnConnectionStatus.denied:
        return '🚫 VPN Access Denied';
      case VpnConnectionStatus.disconnected:
        return '🔓 VPN Disconnected';
    }
  }
}

class CallScreenRiverpod extends ConsumerStatefulWidget {
  final CallEntity call;
  
  const CallScreenRiverpod({super.key, required this.call});

  @override
  ConsumerState<CallScreenRiverpod> createState() => _CallScreenRiverpodState();
}

class _CallScreenRiverpodState extends ConsumerState<CallScreenRiverpod> {
  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);
    
    // Listen to call state changes
    ref.listen<CallEntity?>(callStateProvider, (previous, next) {
      if (next == null || next.status == CallStatus.ended) {
        Navigator.of(context).pop();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Spacer(),
              
              // Caller Info
              CircleAvatar(
                radius: 80,
                backgroundColor: Colors.grey[300],
                child: Icon(
                  Icons.person,
                  size: 80,
                  color: Colors.grey[600],
                ),
              ),
              
              SizedBox(height: 24),
              
              Text(
                widget.call.displayName ?? widget.call.remoteIdentity,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: 8),
              
              Text(
                widget.call.remoteIdentity,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 18,
                ),
              ),
              
              SizedBox(height: 16),
              
              Text(
                _getCallStatusText(callState),
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 16,
                ),
              ),
              
              Spacer(),
              
              // Call Controls
              if (widget.call.direction == CallDirection.incoming && 
                  (callState?.status == CallStatus.ringing || callState == null))
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Reject Button
                    _buildCallButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      onPressed: () {
                        ref.read(callStateProvider.notifier).rejectCall(widget.call.id);
                      },
                    ),
                    
                    // Accept Button
                    _buildCallButton(
                      icon: Icons.call,
                      color: Colors.green,
                      onPressed: () {
                        ref.read(callStateProvider.notifier).acceptCall(widget.call.id);
                      },
                    ),
                  ],
                )
              else
                // End Call Button
                _buildCallButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  onPressed: () {
                    ref.read(callStateProvider.notifier).endCall(widget.call.id);
                  },
                ),
              
              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _getCallStatusText(CallEntity? call) {
    if (call == null) {
      return widget.call.direction == CallDirection.incoming 
          ? 'Incoming call' 
          : 'Connecting...';
    }
    
    switch (call.status) {
      case CallStatus.ringing:
        return widget.call.direction == CallDirection.incoming
            ? 'Incoming call'
            : 'Ringing...';
      case CallStatus.connected:
        return 'Connected';
      case CallStatus.connecting:
        return 'Connecting...';
      default:
        return 'Call in progress';
    }
  }

  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        iconSize: 32,
        padding: EdgeInsets.all(20),
      ),
    );
  }
}