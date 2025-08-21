import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'user_state/sip_user.dart';

/// iOS VoIP Service using PushKit and CallKit for proper background call handling
class IOSVoIPService {
  static IOSVoIPService? _instance;
  static IOSVoIPService get instance => _instance ??= IOSVoIPService._();
  
  IOSVoIPService._();
  
  FirebaseMessaging? _messaging;
  SIPUAHelper? _tempSipHelper;
  bool _isInitialized = false;
  String? _pushToken;
  
  /// Initialize iOS VoIP service with Firebase and CallKit
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('🍎📞 iOS VoIP: Initializing VoIP service...');
    
    try {
      // Initialize Firebase
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      
      // Initialize Firebase Messaging for VoIP pushes
      _messaging = FirebaseMessaging.instance;
      
      // Request permissions
      await _requestVoIPPermissions();
      
      // Initialize CallKit
      await _initializeCallKit();
      
      // Set up push notification handlers
      await _setupPushHandlers();
      
      // Get and register push token
      await _registerPushToken();
      
      _isInitialized = true;
      print('✅ iOS VoIP: Service initialized successfully');
      
    } catch (e) {
      print('❌ iOS VoIP: Initialization failed: $e');
    }
  }
  
  /// Request VoIP-specific permissions
  Future<void> _requestVoIPPermissions() async {
    print('🔐 iOS VoIP: Requesting VoIP permissions...');
    
    // Request notification permissions
    NotificationSettings settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );
    
    print('📊 iOS VoIP: Notification permission: ${settings.authorizationStatus}');
  }
  
  /// Initialize CallKit for native iOS call interface
  Future<void> _initializeCallKit() async {
    print('📞 iOS VoIP: Initializing CallKit...');
    
    // Listen for CallKit events
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event != null) {
        print('📞 iOS VoIP: CallKit event: ${event.event}');
        _handleCallKitEvent(event);
      }
    });
    
    print('✅ iOS VoIP: CallKit initialized');
  }
  
  /// Set up push notification handlers
  Future<void> _setupPushHandlers() async {
    print('🔔 iOS VoIP: Setting up push notification handlers...');
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📱 iOS VoIP: Foreground push received: ${message.data}');
      _handleIncomingVoIPPush(message);
    });
    
    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
    
    // Handle app launched from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        print('🚀 iOS VoIP: App launched from push: ${message.data}');
        _handleIncomingVoIPPush(message);
      }
    });
    
    print('✅ iOS VoIP: Push handlers configured');
  }
  
  /// Register push token with SIP server
  Future<void> _registerPushToken() async {
    try {
      String? token = await _messaging!.getAPNSToken();
      if (token != null) {
        _pushToken = token;
        print('📱 iOS VoIP: Got APNS token: ${token.substring(0, 20)}...');
        
        // Save token for SIP server registration
        await _savePushToken(token);
        
        // TODO: Send token to SIP server
        await _registerTokenWithSipServer(token);
        
      } else {
        print('⚠️ iOS VoIP: No APNS token available');
      }
    } catch (e) {
      print('❌ iOS VoIP: Error getting push token: $e');
    }
  }
  
  /// Save push token to SharedPreferences
  Future<void> _savePushToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ios_voip_push_token', token);
    print('💾 iOS VoIP: Push token saved');
  }
  
  /// Register push token with SIP server
  Future<void> _registerTokenWithSipServer(String token) async {
    print('🌐 iOS VoIP: Registering push token with SIP server...');
    
    // TODO: Implement API call to register token with your SIP server
    // This would typically be a REST API call like:
    // POST /api/voip/register
    // { "user": "564612", "platform": "ios", "token": token }
    
    print('📡 iOS VoIP: Push token registration would happen here');
    print('📡 iOS VoIP: Token: $token');
    
    // For now, just log what needs to be implemented
    final prefs = await SharedPreferences.getInstance();
    final savedUserJson = prefs.getString('websocket_sip_user');
    if (savedUserJson != null) {
      final sipUser = SipUser.fromJsonString(savedUserJson);
      print('📡 iOS VoIP: Would register token for user: ${sipUser.authUser}');
      print('📡 iOS VoIP: SIP server should send push to this token when calls arrive');
    }
  }
  
  /// Handle incoming VoIP push notification
  Future<void> _handleIncomingVoIPPush(RemoteMessage message) async {
    print('📞 iOS VoIP: Processing incoming VoIP push...');
    print('📞 iOS VoIP: Push data: ${message.data}');
    
    // Extract call information from push
    final callId = message.data['call_id'] ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    final caller = message.data['caller'] ?? 'Unknown Caller';
    final callerNumber = message.data['caller_number'] ?? caller;
    
    print('📞 iOS VoIP: Incoming call from $caller ($callerNumber), ID: $callId');
    
    // Show CallKit incoming call screen immediately
    await _showCallKitIncomingCall(callId, caller, callerNumber);
    
    // Wake up SIP connection to handle the actual call
    await _wakeUpSipConnection();
  }
  
  /// Show CallKit incoming call interface
  Future<void> _showCallKitIncomingCall(String callId, String caller, String callerNumber) async {
    print('📞 iOS VoIP: Showing CallKit incoming call...');
    
    final callKitParams = CallKitParams(
      id: callId,
      nameCaller: caller,
      appName: 'SIP Phone',
      handle: callerNumber,
      type: 0, // Audio call
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{
        'caller': caller,
        'caller_number': callerNumber,
        'sip_call': true,
      },
    );
    
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
      print('✅ iOS VoIP: CallKit incoming call displayed');
    } catch (e) {
      print('❌ iOS VoIP: Failed to show CallKit call: $e');
    }
  }
  
  /// Wake up SIP connection when push notification arrives
  Future<void> _wakeUpSipConnection() async {
    print('🚀 iOS VoIP: Waking up SIP connection...');
    
    try {
      // Load SIP configuration
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('websocket_sip_user');
      
      if (savedUserJson == null) {
        print('❌ iOS VoIP: No SIP configuration found');
        return;
      }
      
      final sipUser = SipUser.fromJsonString(savedUserJson);
      print('📋 iOS VoIP: Loaded SIP user: ${sipUser.authUser}');
      
      // Create temporary SIP helper for this call
      _tempSipHelper = SIPUAHelper();
      
      // Add listener for call events
      final listener = VoIPSipListener();
      _tempSipHelper!.addSipUaHelperListener(listener);
      
      // Configure and start SIP
      UaSettings settings = UaSettings();
      settings.webSocketUrl = sipUser.wsUrl!;
      settings.uri = sipUser.sipUri ?? 'sip:${sipUser.authUser}@sip.ibos.io';
      settings.authorizationUser = sipUser.authUser;
      settings.password = sipUser.password;
      settings.displayName = sipUser.displayName;
      settings.userAgent = 'SIP Phone iOS VoIP';
      
      print('🔌 iOS VoIP: Starting SIP helper...');
      _tempSipHelper!.start(settings);
      
      // Register with short delay
      Timer(Duration(seconds: 2), () {
        print('📞 iOS VoIP: Registering with SIP server...');
        _tempSipHelper!.register();
      });
      
      print('✅ iOS VoIP: SIP connection wake-up initiated');
      
    } catch (e) {
      print('❌ iOS VoIP: Failed to wake up SIP connection: $e');
    }
  }
  
  /// Handle CallKit events (accept, decline, etc.)
  void _handleCallKitEvent(CallEvent event) {
    print('📞 iOS VoIP: Handling CallKit event: ${event.event}');
    
    switch (event.event) {
      case Event.actionCallAccept:
        print('✅ iOS VoIP: User accepted call');
        _handleCallAccepted(event);
        break;
        
      case Event.actionCallDecline:
        print('❌ iOS VoIP: User declined call');
        _handleCallDeclined(event);
        break;
        
      case Event.actionCallEnded:
        print('🔚 iOS VoIP: Call ended');
        _handleCallEnded(event);
        break;
        
      default:
        print('📞 iOS VoIP: Unhandled CallKit event: ${event.event}');
    }
  }
  
  /// Handle call accepted by user
  void _handleCallAccepted(CallEvent event) {
    print('✅ iOS VoIP: Processing call acceptance...');
    
    // Navigate to call screen
    // TODO: Navigate to unified call screen
    print('🚀 iOS VoIP: Should navigate to call screen now');
  }
  
  /// Handle call declined by user
  void _handleCallDeclined(CallEvent event) {
    print('❌ iOS VoIP: Processing call decline...');
    
    // Reject the SIP call if active
    // TODO: Reject SIP call through tempSipHelper
    print('📞 iOS VoIP: Should reject SIP call now');
  }
  
  /// Handle call ended
  void _handleCallEnded(CallEvent event) {
    print('🔚 iOS VoIP: Processing call end...');
    
    // Clean up temporary SIP helper
    _tempSipHelper?.stop();
    _tempSipHelper = null;
    
    print('🧹 iOS VoIP: Cleaned up temporary SIP connection');
  }
  
  /// Get current push token
  String? getPushToken() => _pushToken;
  
  /// Check if VoIP service is initialized
  bool get isInitialized => _isInitialized;
}

/// Background message handler for Firebase push notifications
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  print('📱 iOS VoIP: Background push received: ${message.data}');
  
  // Initialize service if needed
  if (!IOSVoIPService.instance.isInitialized) {
    await IOSVoIPService.instance.initialize();
  }
  
  // Handle the VoIP push
  await IOSVoIPService.instance._handleIncomingVoIPPush(message);
}

/// Simple SIP listener for VoIP calls
class VoIPSipListener implements SipUaHelperListener {
  @override
  void callStateChanged(Call call, CallState state) {
    print('📞 VoIP SIP: Call ${call.id} state changed to ${state.state}');
    
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        print('📞 VoIP SIP: Call initiating...');
        break;
      case CallStateEnum.STREAM:
        print('📞 VoIP SIP: Incoming call detected');
        // The CallKit interface should already be showing
        break;
      case CallStateEnum.CONNECTING:
        print('📞 VoIP SIP: Call connecting...');
        break;
      case CallStateEnum.PROGRESS:
        print('📞 VoIP SIP: Call in progress...');
        break;
      case CallStateEnum.CONFIRMED:
        print('✅ VoIP SIP: Call confirmed and active');
        break;
      case CallStateEnum.ACCEPTED:
        print('✅ VoIP SIP: Call accepted');
        break;
      case CallStateEnum.ENDED:
        print('🔚 VoIP SIP: Call ended');
        break;
      case CallStateEnum.FAILED:
        print('❌ VoIP SIP: Call failed');
        break;
      default:
        print('📞 VoIP SIP: Unhandled call state: ${state.state}');
    }
  }
  
  @override
  void registrationStateChanged(RegistrationState state) {
    print('📡 VoIP SIP: Registration state: ${state.state}');
  }
  
  @override
  void transportStateChanged(TransportState state) {
    print('🔌 VoIP SIP: Transport state: ${state.state}');
  }
  
  @override
  void onNewMessage(SIPMessageRequest msg) {
    print('💬 VoIP SIP: New message received');
  }
  
  @override
  void onNewNotify(Notify ntf) {
    print('🔔 VoIP SIP: New notify received');
  }
  
  @override
  void onNewReinvite(ReInvite event) {
    print('🔄 VoIP SIP: ReInvite received');
  }
}