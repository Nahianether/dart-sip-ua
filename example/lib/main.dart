import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:dart_sip_ua_example/src/providers.dart';
import 'package:dart_sip_ua_example/src/persistent_background_service.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:permission_handler/permission_handler.dart';

import 'src/about.dart';
import 'src/unified_call_screen.dart';
import 'src/dialpad.dart';
import 'src/register.dart';
import 'src/debug_screen.dart';
import 'src/recent_calls.dart';
import 'src/home_screen.dart';
import 'src/vpn_config_screen.dart';
import 'src/vpn_manager.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // CRITICAL: Set main app active flag in SharedPreferences IMMEDIATELY
  print('🚨🚨 MAIN: Setting main app ACTIVE flag in SharedPreferences FIRST 🚨🚨');
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('main_app_is_active', true);
    print('💾 MAIN: SharedPreferences flag set - main_app_is_active = true');
  } catch (e) {
    print('❌ MAIN: Error setting SharedPreferences flag: $e');
  }
  
  // Initialize persistent background service AFTER setting the flag
  await PersistentBackgroundService.initializeService();
  
  // CRITICAL: Also mark main app as active in static variable
  print('🚨 MAIN: Marking app as ACTIVE to prevent background SIP conflicts');
  PersistentBackgroundService.setMainAppActive(true);
  print('🚨 MAIN: App marked as ACTIVE - background service should not register');
  
  // Request permissions early - and force native media access
  await _requestPermissions();
  
  // Additional iOS permission trigger
  await _triggerIOSPermissions();
  
  // Initialize and auto-connect VPN if configured
  await _initializeAndConnectVPN();
  
  Logger.level = Level.warning;
  if (WebRTC.platformIsDesktop) {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  }
  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}

Future<void> _requestPermissions() async {
  try {
    print('🔍 Starting permission requests...');
    
    // Essential permissions for SIP functionality
    final List<Permission> essentialPermissions = [
      Permission.microphone,     // Required for call audio
      Permission.notification,   // Required for incoming call alerts
    ];
    
    // Optional permissions for enhanced features
    final List<Permission> optionalPermissions = [
      Permission.contacts,       // For contact integration
      if (!kIsWeb) Permission.phone, // For native call handling
    ];
    
    // Check current status of all permissions
    print('📊 Checking current permission status...');
    for (final permission in [...essentialPermissions, ...optionalPermissions]) {
      final status = await permission.status;
      print('  ${permission.toString().split('.').last}: ${status.name}');
    }
    
    // Request essential permissions first
    print('🔒 Requesting essential permissions...');
    final Map<Permission, PermissionStatus> essentialResults = 
        await essentialPermissions.request();
    
    // Request optional permissions
    print('📋 Requesting optional permissions...');
    final Map<Permission, PermissionStatus> optionalResults = 
        await optionalPermissions.request();
    
    // Combine results
    final allResults = {...essentialResults, ...optionalResults};
    
    // Analyze results and provide user guidance
    final List<Permission> denied = [];
    final List<Permission> permanentlyDenied = [];
    final List<Permission> granted = [];
    
    allResults.forEach((permission, status) {
      switch (status) {
        case PermissionStatus.granted:
          granted.add(permission);
          break;
        case PermissionStatus.denied:
          denied.add(permission);
          break;
        case PermissionStatus.permanentlyDenied:
          permanentlyDenied.add(permission);
          break;
        case PermissionStatus.restricted:
        case PermissionStatus.limited:
          denied.add(permission);
          break;
        default:
          denied.add(permission);
      }
    });
    
    // Print detailed results
    print('✅ Permission Results Summary:');
    if (granted.isNotEmpty) {
      print('  ✅ Granted: ${granted.map((p) => p.toString().split('.').last).join(', ')}');
    }
    if (denied.isNotEmpty) {
      print('  ⚠️  Denied: ${denied.map((p) => p.toString().split('.').last).join(', ')}');
    }
    if (permanentlyDenied.isNotEmpty) {
      print('  ❌ Permanently Denied: ${permanentlyDenied.map((p) => p.toString().split('.').last).join(', ')}');
      print('  💡 To enable these permissions: Go to Settings → Apps → SIP Phone → Permissions');
    }
    
    // Check if essential permissions are missing
    final missingEssential = essentialPermissions.where((p) => 
        allResults[p] != PermissionStatus.granted).toList();
    
    if (missingEssential.isNotEmpty) {
      print('⚠️  WARNING: Missing essential permissions for full SIP functionality:');
      for (final permission in missingEssential) {
        final permName = permission.toString().split('.').last;
        if (permission == Permission.microphone) {
          print('  🎤 Microphone: Required for call audio');
        } else if (permission == Permission.notification) {
          print('  🔔 Notifications: Required for incoming call alerts');
        } else {
          print('  📱 $permName: Required for core functionality');
        }
      }
      print('  📖 Some features may not work until permissions are granted in Settings.');
    } else {
      print('🎉 All essential permissions granted! SIP phone is ready for full functionality.');
    }
    
    // Offer to open settings for permanently denied essential permissions
    final essentialPermanentlyDenied = permanentlyDenied.where((p) => 
        essentialPermissions.contains(p)).toList();
    
    if (essentialPermanentlyDenied.isNotEmpty) {
      print('🔧 To enable permanently denied permissions:');
      print('   1. Open device Settings');
      print('   2. Find "Apps" or "Application Manager"');
      print('   3. Select "SIP Phone"');
      print('   4. Tap "Permissions"');
      print('   5. Enable: ${essentialPermanentlyDenied.map((p) => p.toString().split('.').last).join(', ')}');
      
      // Show dialog offering to open app settings
      if (essentialPermanentlyDenied.isNotEmpty) {
        // Note: openAppSettings() call would be made from UI context, not here
        print('💡 Consider showing a dialog offering to open app settings');
      }
    }
    
  } catch (e) {
    print('❌ Error requesting permissions: $e');
    print('❌ Error details: ${e.toString()}');
  }
}

Future<void> _triggerIOSPermissions() async {
  // Only on iOS devices
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  
  try {
    print('📱 Triggering iOS native permission requests...');
    
    // Try to trigger native media access early in app lifecycle
    try {
      print('🔄 Attempting early microphone access...');
      final audioStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      
      // Keep stream for a moment
      await Future.delayed(Duration(milliseconds: 100));
      
      // Stop all tracks
      audioStream.getTracks().forEach((track) => track.stop());
      print('✅ Early microphone access completed');
      
    } catch (e) {
      print('⚠️ Early microphone access failed: $e');
    }
    
    // Small delay
    await Future.delayed(Duration(milliseconds: 200));
    
    try {
      print('🔄 Attempting early camera access...');
      final videoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': true,
      });
      
      // Keep stream for a moment
      await Future.delayed(Duration(milliseconds: 100));
      
      // Stop all tracks
      videoStream.getTracks().forEach((track) => track.stop());
      print('✅ Early camera access completed');
      
    } catch (e) {
      print('⚠️ Early camera access failed: $e');
    }
    
    print('📱 iOS native permission trigger completed');
    
  } catch (e) {
    print('❌ iOS permission trigger error: $e');
  }
}

Future<void> _initializeAndConnectVPN() async {
  try {
    print('🔐 Initializing VPN manager on app startup...');
    
    // Create and initialize VPN manager
    final vpnManager = VPNManager();
    await vpnManager.initialize();
    
    print('📊 VPN Status:');
    print('  - Configured: ${vpnManager.isConfigured}');
    print('  - Auto-connect enabled: ${vpnManager.shouldAutoConnect}');
    print('  - Currently connected: ${vpnManager.isConnected}');
    
    // Auto-connect if configured and enabled
    if (vpnManager.isConfigured && vpnManager.shouldAutoConnect && !vpnManager.isConnected) {
      print('🚀 Starting VPN auto-connect...');
      
      try {
        final success = await vpnManager.connect();
        if (success) {
          print('✅ VPN auto-connect successful!');
        } else {
          print('❌ VPN auto-connect failed');
        }
      } catch (e) {
        print('❌ VPN auto-connect error: $e');
      }
    } else if (!vpnManager.isConfigured) {
      print('ℹ️ VPN not configured - skipping auto-connect');
    } else if (!vpnManager.shouldAutoConnect) {
      print('ℹ️ VPN auto-connect disabled - skipping');
    } else if (vpnManager.isConnected) {
      print('✅ VPN already connected');
    }
    
  } catch (e) {
    print('❌ VPN initialization error: $e');
    print('💡 VPN functionality will be disabled');
  }
}

typedef PageContentBuilder = Widget Function([SIPUAHelper? helper, Object? arguments]);

// ignore: must_be_immutable
class MyApp extends ConsumerStatefulWidget {
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  static const _incomingCallChannel = MethodChannel('sip_phone/incoming_call');
  
  Map<String, PageContentBuilder> routes = {
    '/': ([SIPUAHelper? helper, Object? arguments]) => HomeScreen(helper),
    '/dialpad': ([SIPUAHelper? helper, Object? arguments]) => DialPadWidget(helper),
    '/register': ([SIPUAHelper? helper, Object? arguments]) => RegisterWidget(helper),
    '/callscreen': ([SIPUAHelper? helper, Object? arguments]) => UnifiedCallScreen(helper: helper, call: arguments as Call?),
    '/about': ([SIPUAHelper? helper, Object? arguments]) => AboutWidget(),
    '/debug': ([SIPUAHelper? helper, Object? arguments]) => DebugScreen(),
    '/recent': ([SIPUAHelper? helper, Object? arguments]) => RecentCallsScreen(helper: helper),
    '/vpn-config': ([SIPUAHelper? helper, Object? arguments]) => VPNConfigScreen(),
  };

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final String? name = settings.name;
    final PageContentBuilder? pageContentBuilder = routes[name!];
    if (pageContentBuilder != null) {
      final helper = ref.read(sipHelperProvider);
      if (settings.arguments != null) {
        final Route route =
            MaterialPageRoute<Widget>(builder: (context) => pageContentBuilder(helper, settings.arguments));
        return route;
      } else {
        final Route route = MaterialPageRoute<Widget>(builder: (context) => pageContentBuilder(helper));
        return route;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Mark main app as active on startup (redundant but ensures consistency)
    print('📱 STARTUP: Setting main app as ACTIVE');
    _setMainAppActiveWithPrefs(true);
    print('📱 STARTUP: Main app marked as ACTIVE');
    
    // Set up platform channel listener for incoming calls
    _setupIncomingCallChannel();
    
    // Check for incoming calls on app start
    _checkForIncomingCallsOnStart();
  }
  
  void _setupIncomingCallChannel() {
    _incomingCallChannel.setMethodCallHandler((call) async {
      print('📱 Platform channel received: ${call.method}');
      
      if (call.method == 'handleIncomingCall') {
        final caller = call.arguments['caller'] as String?;
        final callId = call.arguments['callId'] as String?;
        
        print('📞 Platform channel incoming call: $caller, callId: $callId');
        
        // Check for background calls and navigate
        await _handleIncomingCallFromPlatform(caller, callId);
      }
    });
  }
  
  Future<void> _handleIncomingCallFromPlatform(String? caller, String? callId) async {
    print('📱 Handling incoming call from platform: $caller');
    
    try {
      // Small delay to ensure app is ready
      await Future.delayed(Duration(milliseconds: 500));
      
      // Check for background calls
      final activeCall = PersistentBackgroundService.getActiveCall();
      final incomingCall = PersistentBackgroundService.getIncomingCall();
      
      print('📊 Platform call lookup: activeCall=${activeCall?.id}, incomingCall=${incomingCall?.id}');
      
      final callToShow = activeCall ?? incomingCall;
      
      if (callToShow != null) {
        print('🚀 Platform: Navigating to call screen for ${callToShow.remote_identity}');
        
        if (mounted && navigatorKey.currentContext != null) {
          Navigator.of(navigatorKey.currentContext!).pushNamedAndRemoveUntil(
            '/callscreen',
            (route) => false,
            arguments: callToShow,
          );
          
          // Hide notification
          await PersistentBackgroundService.hideIncomingCallNotification();
        }
      } else {
        print('⚠️ Platform: No matching call found for platform launch');
      }
    } catch (e) {
      print('❌ Error handling platform incoming call: $e');
    }
  }
  
  void _setMainAppActiveWithPrefs(bool isActive) async {
    try {
      // Set both SharedPreferences and static variable
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('main_app_is_active', isActive);
      print('💾 Main app active status saved to SharedPreferences: $isActive');
      
      // Also set static variable
      PersistentBackgroundService.setMainAppActive(isActive);
    } catch (e) {
      print('❌ Error setting main app active with prefs: $e');
      // Fallback to just static variable
      PersistentBackgroundService.setMainAppActive(isActive);
    }
  }
  
  void _checkForIncomingCallsOnStart() async {
    // Small delay to allow providers to initialize
    await Future.delayed(Duration(milliseconds: 1000));
    
    print('🔍 Checking for incoming calls on app start...');
    
    try {
      final hasIncoming = PersistentBackgroundService.hasIncomingCall();
      final activeCall = PersistentBackgroundService.getActiveCall();
      
      print('📊 App start call status: hasIncoming=$hasIncoming, activeCall=${activeCall?.id}');
      
      if (hasIncoming || activeCall != null) {
        final callToShow = PersistentBackgroundService.getIncomingCall() ?? activeCall;
        if (callToShow != null) {
          print('🔔 Found call on app start: ${callToShow.remote_identity} (State: ${callToShow.state})');
          
          // Navigate to call screen immediately
          if (mounted && navigatorKey.currentContext != null) {
            print('🚀 Navigating to call screen for background call on startup');
            Navigator.of(navigatorKey.currentContext!).pushNamedAndRemoveUntil(
              '/callscreen', 
              (route) => false, // Remove all previous routes
              arguments: callToShow,
            );
            
            // Hide notification since app is now handling the call
            await PersistentBackgroundService.hideIncomingCallNotification();
          }
        }
      } else {
        print('ℹ️ No incoming calls found on app start');
      }
      
      // Start listening for background service forwarded calls
      _startBackgroundServiceListener();
      
    } catch (e) {
      print('❌ Error checking for incoming calls on start: $e');
    }
  }
  
  void _startBackgroundServiceListener() {
    print('🔗🔗🔗 Starting background service direct listener... 🔗🔗🔗');
    
    try {
      final bgService = FlutterBackgroundService();
      print('📡 Background service instance: ${bgService.hashCode}');
      
      // Listen directly to background service events
      bgService.on('callForwardedToMainApp').listen((event) {
        print('📞📞📞 RECEIVED CALL FORWARDED FROM BACKGROUND SERVICE: $event 📞📞📞');
        
        if (event != null && event is Map<String, dynamic>) {
          final caller = event['caller'] as String? ?? 'Unknown';
          final callId = event['callId'] as String? ?? 'unknown';
          final direction = event['direction'] as String? ?? 'Direction.incoming';
          
          print('📞 Forwarded call from: $caller (ID: $callId)');
          
          // Create a synthetic call object since we can't access the background service call
          // The main app will listen to SIP events and get the real call object
          print('🔄 Looking for call in main app SIP helper...');
          
          final helper = ref.read(sipHelperProvider);
          print('📊 Main app SIP helper status:');
          print('  - Registered: ${helper.registered}');
          print('  - Helper ready: ${helper != null}');
          
          // The background service call should also appear in main app if both are registered
          // Let's try to trigger the main app to handle incoming calls
          _triggerIncomingCallCheck();
          
          // Get the forwarded call object (async)
          _handleForwardedCallAsync();
        } else {
          print('❌ Invalid event data: $event');
        }
      }, onError: (error) {
        print('❌ Error in background service listener: $error');
      }, onDone: () {
        print('🔚 Background service listener stream closed');
      });
      
      print('✅✅✅ Background service listener active ✅✅✅');
      
      // Also start polling as backup
      print('🔄 Starting polling fallback as backup...');
      _startPollingFallback();
      
    } catch (e) {
      print('❌❌❌ Error setting up background service listener: $e ❌❌❌');
      
      // Fallback to polling if direct communication fails
      _startPollingFallback();
    }
  }
  
  void _startPollingFallback() {
    print('🔄🔄🔄 Using polling fallback for background service communication 🔄🔄🔄');
    
    Timer.periodic(Duration(milliseconds: 1000), (timer) {
      if (!mounted) {
        print('📱 Polling stopped - widget unmounted');
        timer.cancel();
        return;
      }
      
      // Only check when main app is active
      if (!PersistentBackgroundService.isMainAppActive()) {
        // print('📱 Polling skipped - main app not active');
        return;
      }
      
      // Check for new incoming calls from background service
      final hasIncoming = PersistentBackgroundService.hasIncomingCall();
      if (hasIncoming) {
        final incomingCall = PersistentBackgroundService.getIncomingCall();
        if (incomingCall != null) {
          print('📞📞📞 POLLING DETECTED FORWARDED CALL: ${incomingCall.remote_identity} 📞📞📞');
          print('📞 Call ID: ${incomingCall.id}');
          print('📞 Call state: ${incomingCall.state}');
          print('📞 Call direction: ${incomingCall.direction}');
          
          timer.cancel(); // Stop polling since we're handling the call
          
          if (mounted && navigatorKey.currentContext != null) {
            print('🚀🚀🚀 NAVIGATING TO CALL SCREEN FOR FORWARDED CALL 🚀🚀🚀');
            Navigator.of(navigatorKey.currentContext!).pushNamedAndRemoveUntil(
              '/callscreen',
              (route) => false,
              arguments: incomingCall,
            );
            
            PersistentBackgroundService.hideIncomingCallNotification();
          } else {
            print('❌ Cannot navigate - app not ready');
            print('  - Mounted: $mounted');
            print('  - Context: ${navigatorKey.currentContext != null}');
          }
        } else {
          print('❌ hasIncomingCall=true but getIncomingCall returned null');
        }
      } else {
        // print('📱 Polling check - no incoming calls');
      }
    });
  }
  
  void _handleForwardedCallAsync() async {
    print('🔄 Handling forwarded call asynchronously...');
    
    try {
      final forwardedCall = await PersistentBackgroundService.getForwardedCall();
      if (forwardedCall != null && mounted && navigatorKey.currentContext != null) {
        print('🚀 Using forwarded call object: ${forwardedCall.remote_identity}');
        
        // Clear the forwarded call so it's not used again
        await PersistentBackgroundService.clearForwardedCall();
        
        Navigator.of(navigatorKey.currentContext!).pushNamedAndRemoveUntil(
          '/callscreen',
          (route) => false,
          arguments: forwardedCall,
        );
        
        // Hide notification since app is now handling the call
        PersistentBackgroundService.hideIncomingCallNotification();
      } else {
        print('❌ No forwarded call found in async check');
        print('  - Forwarded call: ${forwardedCall?.remote_identity}');
        print('  - Mounted: $mounted');  
        print('  - Context ready: ${navigatorKey.currentContext != null}');
        
        // Fallback: Try delayed check
        _triggerIncomingCallCheck();
      }
    } catch (e) {
      print('❌ Error handling forwarded call async: $e');
    }
  }
  
  void _triggerIncomingCallCheck() {
    print('🔄 Triggering incoming call check in main app...');
    
    try {
      // Check if main app SIP helper has any calls
      final helper = ref.read(sipHelperProvider);
      if (helper != null) {
        print('📞 Main app helper found, checking for calls...');
        // The SIP helper should receive the same incoming call event
        // Let's just wait a moment for it to arrive
        Timer(Duration(milliseconds: 500), () async {
          final forwardedCall = await PersistentBackgroundService.getForwardedCall();
          if (forwardedCall != null && mounted && navigatorKey.currentContext != null) {
            print('🚀 Delayed call check found forwarded call: ${forwardedCall.remote_identity}');
            
            // Clear the forwarded call so it's not used again
            await PersistentBackgroundService.clearForwardedCall();
            
            Navigator.of(navigatorKey.currentContext!).pushNamedAndRemoveUntil(
              '/callscreen',
              (route) => false,
              arguments: forwardedCall,
            );
            PersistentBackgroundService.hideIncomingCallNotification();
          } else {
            print('❌ Delayed check still no forwarded call found');
          }
        });
      }
    } catch (e) {
      print('❌ Error in triggerIncomingCallCheck: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('🔄 App resumed - checking SIP connection...');
        print('📱 RESUME: Setting main app as ACTIVE');
        _setMainAppActiveWithPrefs(true);
        print('📱 RESUME: Main app marked as ACTIVE');
        _handleAppResume();
        break;
      case AppLifecycleState.paused:
        print('⏸️ App paused - transferring to background service');
        print('📱 PAUSE: Setting main app as BACKGROUND');
        _setMainAppActiveWithPrefs(false);
        print('📱 PAUSE: Main app marked as BACKGROUND');
        _transferToBackgroundService();
        break;
      case AppLifecycleState.detached:
        print('🔌 App detached - background service taking over');
        break;
      case AppLifecycleState.inactive:
        print('💤 App inactive');
        break;
      case AppLifecycleState.hidden:
        print('👻 App hidden');
        break;
    }
  }

  void _handleAppResume() async {
    try {
      // Small delay to allow UI to settle
      await Future.delayed(Duration(milliseconds: 500));
      
      final sipUserCubit = ref.read(sipUserCubitProvider);
      final helper = ref.read(sipHelperProvider);
      
      print('🔍 Checking connections on app resume...');
      
      // Check and reconnect VPN first if needed
      await _checkAndReconnectVPN();
      
      print('📊 SIP Status:');
      print('📊 Has saved user: ${sipUserCubit.state != null}');
      print('📊 Is registered: ${sipUserCubit.isRegistered}');
      print('📊 Helper registered: ${helper.registered}');
      
      // Check for incoming calls from background service first
      print('📞 Checking for background incoming calls on resume...');
      final hasIncoming = PersistentBackgroundService.hasIncomingCall();
      final activeCall = PersistentBackgroundService.getActiveCall();
      
      print('📊 Background call status: hasIncoming=$hasIncoming, activeCall=${activeCall?.id}');
      
      if (hasIncoming || activeCall != null) {
        final callToShow = PersistentBackgroundService.getIncomingCall() ?? activeCall;
        if (callToShow != null) {
          print('🔔 Found call from background service: ${callToShow.remote_identity} (State: ${callToShow.state})');
          
          // Navigate to call screen immediately
          if (mounted && navigatorKey.currentContext != null) {
            print('🚀 Navigating to call screen for background call');
            Navigator.of(navigatorKey.currentContext!).pushNamedAndRemoveUntil(
              '/callscreen', 
              (route) => false, // Remove all previous routes
              arguments: callToShow,
            );
            
            // Hide notification since app is now handling the call
            await PersistentBackgroundService.hideIncomingCallNotification();
          }
          return; // Don't do other connection checks if handling incoming call
        }
      }
      
      // Take back SIP control from background service only if no active calls
      if (sipUserCubit.state != null) {
        // Check if background service has active calls first
        if (PersistentBackgroundService.hasIncomingCall() || 
            PersistentBackgroundService.getActiveCall() != null) {
          print('📞 Background service has active calls - NOT taking control yet');
          // Let background service continue handling the call
          return; 
        }
        
        if (!helper.registered) {
          print('🔄 Taking back SIP control from background service...');
          
          // Small delay to let background service finish any pending operations
          await Future.delayed(Duration(milliseconds: 1000));
          
          // Try to reconnect with saved user
          await sipUserCubit.forceReconnect();
          
          // Show a brief status message to user
          if (mounted) {
            // Note: This would show briefly if the user is on the dialpad
            ScaffoldMessenger.of(navigatorKey.currentContext ?? context).showSnackBar(
              SnackBar(
                content: Text('Reconnecting to SIP server...'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          print('✅ SIP connection is already healthy');
        }
      } else {
        print('ℹ️ No saved SIP user - manual connection required');
      }
      
    } catch (e) {
      print('❌ Error during app resume reconnection: $e');
    }
  }

  void _transferToBackgroundService() async {
    try {
      print('🔄 App going to background - transferring SIP control to background service');
      
      final sipUserCubit = ref.read(sipUserCubitProvider);
      final helper = ref.read(sipHelperProvider);
      
      // CRITICAL: Unregister main app to avoid SIP conflicts
      // Only background service should be registered when app is closed
      if (helper.registered && sipUserCubit.state != null) {
        print('📴 Unregistering main app SIP helper to prevent conflicts');
        await helper.unregister();
        await Future.delayed(Duration(milliseconds: 1000)); // Give time to unregister
        print('✅ Main app SIP helper unregistered');
      }
      
      print('📞 Background service will be sole SIP handler when app is closed');
      
    } catch (e) {
      print('❌ Error in background transfer: $e');
    }
  }

  Future<void> _checkAndReconnectVPN() async {
    try {
      print('🔐 Checking VPN connection on app resume...');
      
      // Create VPN manager instance
      final vpnManager = VPNManager();
      await vpnManager.initialize();
      
      print('📊 VPN Resume Status:');
      print('  - Configured: ${vpnManager.isConfigured}');
      print('  - Auto-connect enabled: ${vpnManager.shouldAutoConnect}');
      print('  - Currently connected: ${vpnManager.isConnected}');
      
      // Auto-reconnect VPN if configured, enabled, and not connected
      if (vpnManager.isConfigured && vpnManager.shouldAutoConnect && !vpnManager.isConnected) {
        print('🔄 VPN disconnected, attempting reconnection...');
        
        try {
          final success = await vpnManager.connect();
          if (success) {
            print('✅ VPN auto-reconnect successful!');
          } else {
            print('❌ VPN auto-reconnect failed');
          }
        } catch (e) {
          print('❌ VPN auto-reconnect error: $e');
        }
      } else if (vpnManager.isConnected) {
        print('✅ VPN connection is healthy');
      } else if (!vpnManager.shouldAutoConnect) {
        print('ℹ️ VPN auto-connect disabled');
      }
      
    } catch (e) {
      print('❌ Error checking VPN on app resume: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeNotifierProvider);
    
    return MaterialApp(
      title: 'SIP Phone',
      debugShowCheckedModeBanner: false,
      theme: theme.currentTheme,
      navigatorKey: navigatorKey,
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }
}
