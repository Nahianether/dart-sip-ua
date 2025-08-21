import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'user_state/sip_user.dart';

/// iOS Push Notification Service for VoIP background calling
/// This enables calls to work even when app is completely closed on iOS
class IOSPushService {
  static IOSPushService? _instance;
  static IOSPushService get instance => _instance ??= IOSPushService._();
  
  IOSPushService._();
  
  FirebaseMessaging? _messaging;
  SIPUAHelper? _tempSipHelper;
  bool _isInitialized = false;
  String? _pushToken;
  
  /// Initialize iOS push service for VoIP
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('🍎🔔 iOS PUSH: Initializing VoIP push service...');
    
    try {
      // Initialize Firebase
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      
      _messaging = FirebaseMessaging.instance;
      
      // Request VoIP permissions
      await _requestVoIPPermissions();
      
      // Initialize CallKit
      await _initializeCallKit();
      
      // Set up push handlers
      await _setupPushHandlers();
      
      // Get and save push token
      await _registerPushToken();
      
      _isInitialized = true;
      print('✅ iOS PUSH: VoIP push service initialized');
      
    } catch (e) {
      print('❌ iOS PUSH: Initialization failed: $e');
    }
  }
  
  /// Request VoIP-specific permissions
  Future<void> _requestVoIPPermissions() async {
    print('🔐 iOS PUSH: Requesting VoIP permissions...');
    
    NotificationSettings settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
      provisional: false,
    );
    
    print('📊 iOS PUSH: Permission status: ${settings.authorizationStatus}');
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ iOS PUSH: VoIP permissions granted');
    } else {
      print('❌ iOS PUSH: VoIP permissions denied');
    }
  }
  
  /// Initialize CallKit for native iOS call interface
  Future<void> _initializeCallKit() async {
    print('📞 iOS PUSH: Initializing CallKit...');
    
    // Listen for CallKit events
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event != null) {
        print('📞 iOS PUSH: CallKit event: ${event.event}');
        _handleCallKitEvent(event);
      }
    });
    
    print('✅ iOS PUSH: CallKit initialized');
  }
  
  /// Set up push notification handlers
  Future<void> _setupPushHandlers() async {
    print('🔔 iOS PUSH: Setting up push handlers...');
    
    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📱 iOS PUSH: Foreground push: ${message.data}');
      _handleVoIPPush(message);
    });
    
    // Background messages
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
    
    // App launched from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        print('🚀 iOS PUSH: App launched from push: ${message.data}');
        _handleVoIPPush(message);
      }
    });
    
    print('✅ iOS PUSH: Push handlers configured');
  }
  
  /// Register push token with your SIP server
  Future<void> _registerPushToken() async {
    print('🔄 iOS PUSH: Starting token registration process...');
    
    try {
      // Try multiple times to get the token
      String? token;
      int attempts = 0;
      const maxAttempts = 5;
      
      while (token == null && attempts < maxAttempts) {
        attempts++;
        print('🔄 iOS PUSH: Token attempt $attempts/$maxAttempts...');
        
        try {
          token = await _messaging!.getToken();
          if (token != null) {
            break;
          }
        } catch (e) {
          print('⚠️ iOS PUSH: Attempt $attempts failed: $e');
        }
        
        if (token == null && attempts < maxAttempts) {
          print('⏳ iOS PUSH: Waiting 2 seconds before retry...');
          await Future.delayed(Duration(seconds: 2));
        }
      }
      
      if (token != null) {
        _pushToken = token;
        print('📱 iOS PUSH: Got FCM token: ${token.substring(0, 20)}...');
        print('🔥🔥🔥 FIREBASE CONSOLE TOKEN: $token 🔥🔥🔥');
        print('📋 COPY THIS TOKEN FOR FIREBASE CONSOLE TESTING!');
        print('🧪 Go to Firebase Console → Cloud Messaging → Send message');
        print('🎯 Use this token to test VoIP push notifications!');
        print('🔥🔥🔥 FIREBASE CONSOLE TOKEN: $token 🔥🔥🔥');
        
        // Save token
        await _savePushToken(token);
        
        // Register with SIP server
        await _registerTokenWithSipServer(token);
        
      } else {
        print('❌ iOS PUSH: Failed to get FCM token after $maxAttempts attempts');
        print('💡 iOS PUSH: Token might be available later - check logs periodically');
      }
    } catch (e) {
      print('❌ iOS PUSH: Error getting push token: $e');
    }
  }
  
  /// Save push token locally
  Future<void> _savePushToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ios_push_token', token);
    print('💾 iOS PUSH: Token saved locally');
  }
  
  /// Register token with SIP server (YOU NEED TO IMPLEMENT THIS)
  Future<void> _registerTokenWithSipServer(String token) async {
    print('🌐 iOS PUSH: Registering token with SIP server...');
    
    final prefs = await SharedPreferences.getInstance();
    final savedUserJson = prefs.getString('websocket_sip_user');
    
    if (savedUserJson != null) {
      final sipUser = SipUser.fromJsonString(savedUserJson);
      
      // TODO: Replace this with actual API call to your SIP server
      print('📡 CRITICAL: You need to implement this API call:');
      print('📡 POST https://your-sip-server.com/api/register-push-token');
      print('📡 Body: {');
      print('📡   "user": "${sipUser.authUser}",');
      print('📡   "token": "$token",');
      print('📡   "platform": "ios"');
      print('📡 }');
      print('📡 This tells your SIP server to send push notifications to this device');
      print('📡 when calls arrive for user ${sipUser.authUser}');
      
      // Example implementation (replace with your server API):
      /*
      final response = await http.post(
        Uri.parse('https://your-sip-server.com/api/register-push-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user': sipUser.authUser,
          'token': token,
          'platform': 'ios',
        }),
      );
      
      if (response.statusCode == 200) {
        print('✅ iOS PUSH: Token registered with SIP server');
      } else {
        print('❌ iOS PUSH: Failed to register token: ${response.body}');
      }
      */
    }
  }
  
  /// Handle incoming VoIP push notification
  Future<void> _handleVoIPPush(RemoteMessage message) async {
    print('📞 iOS PUSH: Processing VoIP push...');
    print('📞 iOS PUSH: Data: ${message.data}');
    
    // Extract call information
    final callId = message.data['call_id'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    final caller = message.data['caller'] ?? 'Unknown Caller';
    final callerNumber = message.data['caller_number'] ?? caller;
    
    print('📞 iOS PUSH: Incoming call from $caller ($callerNumber)');
    
    // Show CallKit interface immediately
    await _showCallKitCall(callId, caller, callerNumber);
    
    // Wake up SIP connection
    await _wakeUpSipConnection();
  }
  
  /// Show native iOS CallKit interface
  Future<void> _showCallKitCall(String callId, String caller, String callerNumber) async {
    print('📞 iOS PUSH: Showing CallKit interface...');
    
    try {
      final callKitParams = CallKitParams(
        id: callId,
        nameCaller: caller,
        appName: 'SIP Phone',
        handle: callerNumber,
        type: 0,
        textAccept: 'Accept',
        textDecline: 'Decline',
        extra: <String, dynamic>{
          'caller': caller,
          'caller_number': callerNumber,
          'call_id': callId,
        },
      );
      
      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
      
      print('✅ iOS PUSH: CallKit interface displayed');
    } catch (e) {
      print('❌ iOS PUSH: Failed to show CallKit: $e');
    }
  }
  
  /// Wake up SIP connection when push arrives
  Future<void> _wakeUpSipConnection() async {
    print('🚀 iOS PUSH: Waking up SIP connection...');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('websocket_sip_user');
      
      if (savedUserJson == null) {
        print('❌ iOS PUSH: No SIP config found');
        return;
      }
      
      final sipUser = SipUser.fromJsonString(savedUserJson);
      print('📋 iOS PUSH: Loading SIP config for ${sipUser.authUser}');
      
      // Create temporary SIP helper
      _tempSipHelper = SIPUAHelper();
      final listener = VoIPSipListener();
      _tempSipHelper!.addSipUaHelperListener(listener);
      
      // Configure SIP settings
      UaSettings settings = UaSettings();
      settings.webSocketUrl = sipUser.wsUrl!;
      settings.uri = sipUser.sipUri ?? 'sip:${sipUser.authUser}@sip.ibos.io';
      settings.authorizationUser = sipUser.authUser;
      settings.password = sipUser.password;
      settings.displayName = sipUser.displayName;
      settings.userAgent = 'iOS VoIP Background';
      
      print('🔌 iOS PUSH: Starting SIP helper...');
      _tempSipHelper!.start(settings);
      
      // Register after short delay
      Timer(Duration(seconds: 2), () {
        print('📞 iOS PUSH: Registering with SIP server...');
        _tempSipHelper!.register();
      });
      
      print('✅ iOS PUSH: SIP wake-up initiated');
      
    } catch (e) {
      print('❌ iOS PUSH: SIP wake-up failed: $e');
    }
  }
  
  /// Handle CallKit events
  void _handleCallKitEvent(CallEvent event) {
    print('📞 iOS PUSH: CallKit event: ${event.event}');
    
    switch (event.event) {
      case Event.actionCallAccept:
        print('✅ iOS PUSH: User accepted call');
        // Navigate to call screen - will be handled by main app
        break;
        
      case Event.actionCallDecline:
        print('❌ iOS PUSH: User declined call');
        // Reject SIP call if active
        _tempSipHelper?.stop();
        _tempSipHelper = null;
        break;
        
      case Event.actionCallEnded:
        print('🔚 iOS PUSH: Call ended');
        // Clean up
        _tempSipHelper?.stop();
        _tempSipHelper = null;
        break;
        
      default:
        print('📞 iOS PUSH: Unhandled CallKit event: ${event.event}');
        break;
    }
  }
  
  /// Get current push token
  String? get pushToken => _pushToken;
  
  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}

/// Background message handler
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  print('📱 iOS PUSH: Background message received: ${message.data}');
  
  // Initialize service if needed
  if (!IOSPushService.instance.isInitialized) {
    await IOSPushService.instance.initialize();
  }
  
  // Handle the push
  await IOSPushService.instance._handleVoIPPush(message);
}

/// Simple SIP listener for VoIP calls
class VoIPSipListener implements SipUaHelperListener {
  @override
  void callStateChanged(Call call, CallState state) {
    print('📞 VoIP SIP: Call ${call.id} state: ${state.state}');
  }
  
  @override
  void registrationStateChanged(RegistrationState state) {
    print('📡 VoIP SIP: Registration: ${state.state}');
    
    if (state.state == RegistrationStateEnum.REGISTERED) {
      print('✅ VoIP SIP: Successfully registered for background calls');
    }
  }
  
  @override
  void transportStateChanged(TransportState state) {
    print('🔌 VoIP SIP: Transport: ${state.state}');
  }
  
  @override
  void onNewMessage(SIPMessageRequest msg) {
    print('💬 VoIP SIP: Message received');
  }
  
  @override
  void onNewNotify(Notify ntf) {
    print('🔔 VoIP SIP: Notify received');
  }
  
  @override
  void onNewReinvite(ReInvite event) {
    print('🔄 VoIP SIP: ReInvite received');
  }
}