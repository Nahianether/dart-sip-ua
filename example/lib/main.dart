import 'package:dart_sip_ua_example/src/providers.dart';
import 'package:dart_sip_ua_example/src/background_service.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:permission_handler/permission_handler.dart';

import 'src/about.dart';
import 'src/callscreen.dart';
import 'src/dialpad.dart';
import 'src/register.dart';
import 'src/debug_screen.dart';
import 'src/recent_calls.dart';
import 'src/home_screen.dart';
import 'src/vpn_config_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background service
  await BackgroundService.initializeService();
  
  // Request permissions early - and force native media access
  await _requestPermissions();
  
  // Additional iOS permission trigger
  await _triggerIOSPermissions();
  
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
      Permission.camera,         // For video calls
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

typedef PageContentBuilder = Widget Function([SIPUAHelper? helper, Object? arguments]);

// ignore: must_be_immutable
class MyApp extends ConsumerStatefulWidget {
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  Map<String, PageContentBuilder> routes = {
    '/': ([SIPUAHelper? helper, Object? arguments]) => HomeScreen(helper),
    '/dialpad': ([SIPUAHelper? helper, Object? arguments]) => DialPadWidget(helper),
    '/register': ([SIPUAHelper? helper, Object? arguments]) => RegisterWidget(helper),
    '/callscreen': ([SIPUAHelper? helper, Object? arguments]) => CallScreenWidget(helper, arguments as Call?),
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
        _handleAppResume();
        break;
      case AppLifecycleState.paused:
        print('⏸️ App paused - background');
        break;
      case AppLifecycleState.detached:
        print('🔌 App detached');
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
      
      print('🔍 Checking SIP connection status...');
      print('📊 Has saved user: ${sipUserCubit.state != null}');
      print('📊 Is registered: ${sipUserCubit.isRegistered}');
      print('📊 Helper registered: ${helper.registered}');
      
      // If we have a saved user but are not registered, attempt reconnection
      if (sipUserCubit.state != null && !helper.registered) {
        print('🔄 SIP connection lost, attempting auto-reconnection...');
        
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
      } else if (sipUserCubit.state != null && helper.registered) {
        print('✅ SIP connection is healthy');
      } else {
        print('ℹ️ No saved SIP user - manual connection required');
      }
      
    } catch (e) {
      print('❌ Error during app resume reconnection: $e');
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
