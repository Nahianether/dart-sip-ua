import 'package:dart_sip_ua_example/src/providers.dart';
import 'package:dart_sip_ua_example/src/background_service.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride, kIsWeb;
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize background service
  await BackgroundService.initializeService();
  
  // Request permissions early
  await _requestPermissions();
  
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
    
    // Check if contacts permission is available
    final contactsCurrentStatus = await Permission.contacts.status;
    print('📱 Contacts current status: ${contactsCurrentStatus.name}');
    
    // Request contacts permission
    final contactsStatus = await Permission.contacts.request();
    print('📞 Contacts permission: ${contactsStatus.name}');
    print('📞 Contacts permission details: ${contactsStatus.toString()}');
    
    // Request microphone permission (for calls)
    final microphoneStatus = await Permission.microphone.request();
    print('🎤 Microphone permission: ${microphoneStatus.name}');
    
    // Request camera permission (for video calls)
    final cameraStatus = await Permission.camera.request();
    print('📷 Camera permission: ${cameraStatus.name}');
    
    // Request phone permission (for call management)
    if (!kIsWeb) {
      final phoneStatus = await Permission.phone.request();
      print('📱 Phone permission: ${phoneStatus.name}');
    }
    
    // Show a summary
    print('✅ Permission summary:');
    print('  - Contacts: ${contactsStatus.name}');
    print('  - Microphone: ${microphoneStatus.name}');
    print('  - Camera: ${cameraStatus.name}');
    
    // Additional debug: Check if we can access contacts
    try {
      if (contactsStatus.isGranted) {
        print('🔄 Testing contacts access...');
        // This will help us know if contacts are truly accessible
        final hasPermission = await Permission.contacts.isGranted;
        print('📱 Has contacts permission: $hasPermission');
      }
    } catch (e) {
      print('❌ Error testing contacts: $e');
    }
    
  } catch (e) {
    print('❌ Error requesting permissions: $e');
    print('❌ Error details: ${e.toString()}');
  }
}

typedef PageContentBuilder = Widget Function([SIPUAHelper? helper, Object? arguments]);

// ignore: must_be_immutable
class MyApp extends ConsumerStatefulWidget {
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  Map<String, PageContentBuilder> routes = {
    '/': ([SIPUAHelper? helper, Object? arguments]) => DialPadWidget(helper),
    '/register': ([SIPUAHelper? helper, Object? arguments]) => RegisterWidget(helper),
    '/callscreen': ([SIPUAHelper? helper, Object? arguments]) => CallScreenWidget(helper, arguments as Call?),
    '/about': ([SIPUAHelper? helper, Object? arguments]) => AboutWidget(),
    '/debug': ([SIPUAHelper? helper, Object? arguments]) => DebugScreen(),
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
        print('App resumed - foreground');
        break;
      case AppLifecycleState.paused:
        print('App paused - background');
        break;
      case AppLifecycleState.detached:
        print('App detached');
        break;
      case AppLifecycleState.inactive:
        print('App inactive');
        break;
      case AppLifecycleState.hidden:
        print('App hidden');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeNotifierProvider);
    
    return MaterialApp(
      title: 'SIP Phone',
      debugShowCheckedModeBanner: false,
      theme: theme.currentTheme,
      initialRoute: '/',
      onGenerateRoute: _onGenerateRoute,
    );
  }
}
