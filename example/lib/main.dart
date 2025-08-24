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
import 'src/persistent_background_service.dart';
import 'src/battery_optimization_helper.dart';
import 'data/models/sip_account_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize services
  final container = ProviderContainer();

  // Initialize Hive database
  await HiveService.initialize();

  // CRITICAL: Initialize SIP helper for WebRTC (calls) but NO registration
  // Background service handles registration, main app handles WebRTC media
  await container.read(sipDataSourceProvider).initializeWithoutRegistration();

  // Initialize ringtone and vibration service
  await RingtoneVibrationService().initialize();

  // Initialize connection stability service
  final connectionStability = ConnectionStabilityService();

  // CRITICAL: Initialize background permissions first
  print('🔋 Initializing background permissions for reliable VoIP operation...');
  final permissionsOk = await BatteryOptimizationHelper.initializeBackgroundPermissions();
  if (!permissionsOk) {
    print('⚠️ Some background permissions missing - app may not work reliably');
  }
  
  // Initialize and start background service for 24/7 SIP operation
  await PersistentBackgroundService.initializeService();
  await PersistentBackgroundService.startService();
  print('✅ Background service initialized and started for persistent SIP connection');

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

class VoIPApp extends ConsumerStatefulWidget {
  @override
  ConsumerState<VoIPApp> createState() => _VoIPAppState();
}

class _VoIPAppState extends ConsumerState<VoIPApp> with WidgetsBindingObserver {
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set up platform channel for incoming calls from background service
    _setupIncomingCallChannel();

    // Start heartbeat since app is launching (initially active)
    _startHeartbeat();
    
    // CRITICAL: Check and prompt for background permissions
    _checkBackgroundPermissions();
  }
  
  void _checkBackgroundPermissions() async {
    print('🔋 Checking background permissions on app start...');
    
    // Give the app a moment to fully initialize
    await Future.delayed(Duration(seconds: 2));
    
    final permissionsOk = await BatteryOptimizationHelper.initializeBackgroundPermissions();
    
    if (!permissionsOk && mounted) {
      print('⚠️ Background permissions missing - showing setup dialog');
      // Show dialog after a short delay to ensure UI is ready
      await Future.delayed(Duration(seconds: 1));
      if (mounted) {
        await BatteryOptimizationHelper.showBatteryOptimizationDialog(context);
      }
    } else {
      print('✅ All background permissions are properly configured');
    }
  }

  @override
  void dispose() {
    _stopHeartbeat();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App RESUMED - syncing SIP state from background service');
        PersistentBackgroundService.setMainAppActive(true);
        _startHeartbeat();
        // CRITICAL: Sync SIP state from background service on resume
        _syncSipStateFromBackground();
        break;
      case AppLifecycleState.paused:
        print('📱 App PAUSED - transferring SIP to background service');
        // CRITICAL FIX: When paused (like in recent apps), background service should handle calls
        PersistentBackgroundService.setMainAppActive(false);
        _stopHeartbeat();
        break;
      case AppLifecycleState.inactive:
        print('📱 App INACTIVE - transitioning to background service');
        // App is becoming inactive (could be temporary), transfer to background
        PersistentBackgroundService.setMainAppActive(false);
        _stopHeartbeat();
        break;
      case AppLifecycleState.detached:
        print('📱 App DETACHED - background service active');
        PersistentBackgroundService.setMainAppActive(false);
        _stopHeartbeat();
        break;
      case AppLifecycleState.hidden:
        print('📱 App HIDDEN - main app maintains SIP');
        // CRITICAL FIX: Don't let background service take over
        _stopHeartbeat();
        break;
    }
  }

  void _setupIncomingCallChannel() {
    // CRITICAL FIX: Enhanced platform channel handling
    const platform = MethodChannel('sip_phone/incoming_call');
    platform.setMethodCallHandler((call) async {
      print('📞📞📞 PLATFORM CHANNEL CALL RECEIVED 📞📞📞');
      print('📞 Method: ${call.method}');
      print('📞 Arguments: ${call.arguments}');
      
      if (call.method == 'handleIncomingCall') {
        final caller = call.arguments['caller'] as String? ?? 'Unknown';
        final callId = call.arguments['callId'] as String? ?? '';
        final fromBackground = call.arguments['fromBackground'] as bool? ?? false;

        print('📞 Platform channel: Incoming call from $caller (ID: $callId, FromBackground: $fromBackground)');

        if (fromBackground) {
          // This is a call from the background service, navigate to call screen
          _navigateToIncomingCall(caller, callId);
        }
      } else if (call.method == 'forceOpenAppForCall') {
        final caller = call.arguments['caller'] as String? ?? 'Unknown';
        final callId = call.arguments['callId'] as String? ?? '';
        
        print('🚀 FORCE OPEN APP for call from: $caller (ID: $callId)');
        _navigateToIncomingCall(caller, callId);
      }
    });
    
    // CRITICAL FIX: Setup background service event listeners
    _setupBackgroundServiceListeners();
  }
  
  void _setupBackgroundServiceListeners() {
    print('📱 Setting up background service event listeners...');
    
    final service = FlutterBackgroundService();
    
    service.on('incomingCall').listen((event) {
      if (event != null) {
        final data = event;
        final caller = data['caller'] as String? ?? 'Unknown';
        final callId = data['callId'] as String? ?? '';
        
        print('🔔 Background service: Incoming call from $caller (ID: $callId)');
        _navigateToIncomingCall(caller, callId);
      }
    });
    
    service.on('callAccepted').listen((event) {
      if (event != null) {
        final data = event;
        final caller = data['caller'] as String? ?? 'Unknown';
        final callId = data['callId'] as String? ?? '';
        
        print('✅ Background service: Call accepted from $caller (ID: $callId)');
        _navigateToActiveCall(caller, callId);
      }
    });
    
    service.on('callDeclined').listen((event) {
      if (event != null) {
        final data = event;
        final caller = data['caller'] as String? ?? 'Unknown';
        final callId = data['callId'] as String? ?? '';
        
        print('❌ Background service: Call declined from $caller (ID: $callId)');
        // Navigate back to dialer
        final context = navigatorKey.currentContext;
        if (context != null) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    });
    
    service.on('currentSipState').listen((event) {
      if (event != null) {
        final data = event;
        final isRegistered = data['isRegistered'] as bool? ?? false;
        final hasIncomingCall = data['hasIncomingCall'] as bool? ?? false;
        final hasActiveCall = data['hasActiveCall'] as bool? ?? false;
        final incomingCallerId = data['incomingCallerId'] as String?;
        final activeCallerId = data['activeCallerId'] as String?;
        
        print('🔄 SIP state sync from background: registered=$isRegistered, incoming=$hasIncomingCall, active=$hasActiveCall');
        print('🔄 Callers: incoming=${incomingCallerId ?? 'none'}, active=${activeCallerId ?? 'none'}');
        
        // Update UI state based on background SIP state
        // This ensures the foreground UI reflects the background SIP reality
        if (hasIncomingCall && incomingCallerId != null) {
          print('📞 UI sync: Detected incoming call from $incomingCallerId');
          // The UI should already be updated by the incomingCall event, but this provides backup sync
        }
        
        if (hasActiveCall && activeCallerId != null) {
          print('📞 UI sync: Detected active call with $activeCallerId');
          // Ensure UI shows the active call screen
        }
        
        if (!hasIncomingCall && !hasActiveCall) {
          print('📞 UI sync: No active calls - should show dialer');
          // Ensure UI shows the dialer
        }
      }
    });
    
    service.on('initiateSipCallWithWebRTC').listen((event) {
      if (event != null) {
        final data = event;
        final number = data['number'] as String? ?? '';
        final sipHelper = data['sipHelper'] as String? ?? '';
        
        print('📞 Main app coordinating WebRTC call with background SIP: $number');
        print('📞 SIP registration handled by: $sipHelper');
        
        _handleSipCallWithWebRTC(number);
      }
    });

    service.on('sipCredentialsForCall').listen((event) {
      if (event != null) {
        final data = event;
        final number = data['number'] as String? ?? '';
        final credentials = data['credentials'] as Map<String, dynamic>? ?? {};
        
        print('📞 Received SIP credentials from background service for call to: $number');
        _makeCallWithCredentials(number, credentials);
      }
    });

    service.on('forwardCallToMainApp').listen((event) {
      if (event != null) {
        final data = event;
        final action = data['action'] as String? ?? '';
        
        print('🔄 Background service forwarding call action to main app: $action');
        
        switch (action) {
          case 'makeCall':
            final number = data['number'] as String? ?? '';
            print('📞 Main app handling make call to: $number');
            _handleMakeCallInMainApp(number);
            break;
            
          case 'acceptCall':
            final callId = data['callId'] as String? ?? '';
            final caller = data['caller'] as String? ?? 'Unknown';
            print('📞 Main app handling accept call from: $caller (ID: $callId)');
            _handleAcceptCallInMainApp(callId, caller);
            break;
            
          default:
            print('⚠️ Unknown call action forwarded: $action');
        }
      }
    });
    
    print('✅ Background service event listeners setup complete');
  }

  void _navigateToIncomingCall(String caller, String callId) {
    print('📞📞📞 NAVIGATING TO INCOMING CALL SCREEN 📞📞📞');
    print('📞 Caller: $caller, CallID: $callId');
    
    final context = navigatorKey.currentContext;
    if (context != null) {
      // CRITICAL FIX: Always create call entity for incoming call UI
      // The background service handles the actual SIP call object
      final callEntity = CallEntity(
        id: callId,
        remoteIdentity: caller,
        direction: CallDirection.incoming,
        status: CallStatus.ringing,
        startTime: DateTime.now(),
      );
      
      print('📞 Created call entity for UI: ${callEntity.remoteIdentity}');
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ModernCallScreen(call: callEntity),
          settings: RouteSettings(name: '/incoming-call'),
        ),
      );
      
      print('✅ Navigated to incoming call screen');
    } else {
      print('❌ No navigation context available!');
    }
  }
  
  void _navigateToActiveCall(String caller, String callId) {
    print('📞 Navigating to active call screen for: $caller');
    
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Create call entity for active call UI
      final callEntity = CallEntity(
        id: callId,
        remoteIdentity: caller,
        direction: CallDirection.incoming,
        status: CallStatus.connected,
        startTime: DateTime.now(),
      );
      
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ModernCallScreen(call: callEntity),
          settings: RouteSettings(name: '/active-call'),
        ),
      );
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat(); // Stop any existing timer

    // Update main app status every 30 seconds while active
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      PersistentBackgroundService.setMainAppActive(true);
      print('💓 Main app heartbeat - confirming active status');
    });

    print('💓 Main app heartbeat started (30s interval)');
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    print('💔 Main app heartbeat stopped');
  }

  void _syncSipStateFromBackground() async {
    print('🔄 Syncing SIP state from background service on app resume');
    
    try {
      final service = FlutterBackgroundService();
      service.invoke('syncSipState');
      print('✅ SIP state sync request sent to background service');
    } catch (e) {
      print('❌ Failed to sync SIP state from background: $e');
    }
  }

  void _handleMakeCallInMainApp(String number) async {
    print('📞 Main app received call request for: $number');
    
    try {
      // Main app should configure its SIP helper with the same registration as background service
      // and then coordinate the call with proper WebRTC context
      
      // For now, let's use the providers system to make the call properly
      final container = ProviderContainer();
      
      // Check if we have an active SIP connection via providers
      final callStateNotifier = container.read(callStateProvider.notifier);
      
      print('📞 Main app attempting to make call through providers system');
      await callStateNotifier.makeCall(number);
      print('✅ Call initiated successfully through providers system');
      
    } catch (e) {
      print('❌ Error making call in main app: $e');
      
      // Fallback: Try to notify user of the issue
      print('📞 Call failed - will try alternative approach');
    }
  }

  void _handleSipCallWithWebRTC(String number) async {
    print('📞 Main app handling WebRTC call with background SIP credentials to: $number');
    
    try {
      final container = ProviderContainer();
      
      // CRITICAL FIX: Request SIP credentials from background service to make call in main app
      // This avoids WebRTC context issues while using background service's registration
      print('📞 Requesting SIP credentials from background service for WebRTC call');
      
      final service = FlutterBackgroundService();
      service.invoke('getSipCredentialsForCall', {
        'number': number,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      // The background service will respond with credentials, then main app makes the call
      print('✅ SIP credentials requested from background service');
      
    } catch (e) {
      print('❌ Error requesting SIP credentials from background service: $e');
      
      // Notify background service of failure
      final service = FlutterBackgroundService();
      service.invoke('callInitiated', {
        'number': number,
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  void _makeCallWithCredentials(String number, Map<String, dynamic> credentials) async {
    print('📞 Main app making WebRTC call with background SIP credentials to: $number');
    
    try {
      final container = ProviderContainer();
      
      // Get the main app's SIP data source (initialized for WebRTC operations)
      final sipDataSource = container.read(sipDataSourceProvider);
      
      // Create a temporary SIP account with the background service's credentials
      final sipAccount = SipAccountModel(
        id: credentials['id'] ?? 'temp_call_account',
        username: credentials['username'] ?? '',
        password: credentials['password'] ?? '',
        domain: credentials['domain'] ?? '',
        wsUrl: credentials['wsUrl'] ?? '',
        displayName: credentials['displayName'],
        extraHeaders: credentials['extraHeaders'] != null 
          ? Map<String, String>.from(credentials['extraHeaders']) 
          : null,
      );
      
      print('📞 Temporarily registering main app SIP helper with background credentials');
      
      // Register the main app's SIP helper with the background service's credentials
      await sipDataSource.registerAccount(sipAccount);
      
      // Small delay to ensure registration completes
      await Future.delayed(Duration(milliseconds: 500));
      
      // Now make the call with proper WebRTC context
      print('📞 Making WebRTC-enabled call in main app using background credentials');
      final callStateNotifier = container.read(callStateProvider.notifier);
      await callStateNotifier.makeCall(number);
      
      print('✅ WebRTC call initiated successfully in main app');
      
    } catch (e) {
      print('❌ Error making WebRTC call with credentials: $e');
      
      // Notify background service of failure
      final service = FlutterBackgroundService();
      service.invoke('callInitiated', {
        'number': number,
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  void _handleAcceptCallInMainApp(String callId, String caller) async {
    print('📞 Main app accepting call from: $caller (ID: $callId)');
    
    try {
      // Navigate to call screen and handle accept there
      _navigateToIncomingCall(caller, callId);
      print('✅ Navigated to call screen for accept');
      
    } catch (e) {
      print('❌ Error handling accept call in main app: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            print(
                '🔍 Account state check: account=${account?.username ?? 'null'}, savedCreds=${savedCredentials?.username ?? 'null'}');
            print('🔍 Account state AsyncValue type: ${accountState.runtimeType}');

            if (account != null) {
              // User is logged in, show dialer with call handling
              print('✅ User logged in, showing main app for: ${account.username}@${account.domain}');
              return _buildMainApp(context, ref);
            } else if (savedCredentials != null) {
              // Saved credentials found with password - attempt auto-login
              if (savedCredentials.password.isNotEmpty) {
                print('🔄 Auto-login triggered - account state is null but credentials exist');
                // Trigger auto-login immediately without postFrameCallback
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _attemptAutoLogin(ref, savedCredentials);
                });
                return _buildLoadingScreen('Auto-connecting...', true);
              } else {
                // Password missing - show login screen with pre-filled data
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _loadSavedCredentialsToForm(ref, savedCredentials);
                });
                return ModernLoginScreen();
              }
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

  Future<void> _attemptAutoLogin(WidgetRef ref, SipAccountEntity credentials) async {
    print('🔄 Attempting auto-login with saved credentials: ${credentials.username}@${credentials.domain}');

    try {
      // Directly attempt login with the saved account
      await ref.read(accountProvider.notifier).login(credentials);
      print('✅ Auto-login completed successfully');

      // The account state should now be updated automatically
      print('🔄 Account login completed - UI should rebuild automatically');
    } catch (e) {
      print('❌ Auto-login failed: $e');
      // On failure, invalidate providers to show login screen
      ref.invalidate(accountProvider);
      ref.invalidate(autoLoginProvider);
    }
  }

  void _loadSavedCredentialsToForm(WidgetRef ref, SipAccountEntity credentials) {
    // Load saved credentials to login form (password missing)
    print('ℹ️ Auto-filling login form with saved credentials (password required)');
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
