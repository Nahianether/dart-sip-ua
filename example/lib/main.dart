import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/providers.dart';
import 'src/auth_providers.dart';
import 'domain/entities/sip_account_entity.dart';
import 'domain/entities/call_entity.dart';
import 'screens/modern_dialer_screen.dart';
import 'screens/modern_login_screen.dart';
import 'screens/modern_call_screen.dart';
import 'data/services/ringtone_vibration_service.dart';
import 'data/services/connection_stability_service.dart';
import 'data/services/hive_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  final container = ProviderContainer();
  
  // Initialize Hive database
  await HiveService.initialize();
  
  // Initialize SIP data source
  await container.read(sipDataSourceProvider).initialize();
  
  // Initialize ringtone and vibration service
  await RingtoneVibrationService().initialize();
  
  // Initialize connection stability service  
  final connectionStability = ConnectionStabilityService();
  
  // Listen for network changes and trigger reconnection
  Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
    if (results.isNotEmpty && results.first != ConnectivityResult.none) {
      connectionStability.onNetworkChanged();
    }
  });
  
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
        
        // Listen to account provider errors
        ref.listen<AsyncValue<SipAccountEntity?>>(accountProvider, (previous, next) {
          next.whenOrNull(
            error: (error, stack) {
              // Show connection error dialog
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Connection Error'),
                  content: Text('Failed to connect to SIP server:\n\n$error'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // Go back to login screen
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => ModernLoginScreen()),
                          (route) => false,
                        );
                      },
                      child: Text('Back to Login'),
                    ),
                  ],
                ),
              );
            },
          );
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