import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_state/sip_user.dart';

/// Persistent background service that maintains SIP connection
/// and handles incoming calls even when app is closed/locked
@pragma('vm:entry-point')
class PersistentBackgroundService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  static SIPUAHelper? _backgroundSipHelper;
  static Timer? _keepAliveTimer;
  static Timer? _reconnectionTimer;
  static ServiceInstance? _serviceInstance;
  static SipUser? _currentSipUser;
  static bool _isServiceRunning = false;
  static Call? _currentIncomingCall;
  static Call? _currentActiveCall;
  static bool _isMainAppActive = true; // Track if main app is in foreground
  static Call? _forwardedCall; // Call forwarded to main app

  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Initialize notifications first
    await _initializeNotifications();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'persistent_sip_service',
        initialNotificationTitle: 'SIP Phone Active',
        initialNotificationContent: 'Ready to receive calls',
        foregroundServiceNotificationId: 888,
        autoStartOnBoot: true, // Start service on device boot
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    
    print('🔄 Persistent Background Service configured');
  }

  @pragma('vm:entry-point')
  static Future<void> _initializeNotifications() async {
    // Android notification channel for incoming calls
    const AndroidNotificationChannel incomingCallChannel = AndroidNotificationChannel(
      'incoming_calls_channel',
      'Incoming Calls',
      description: 'Notifications for incoming SIP calls',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('phone_ringing'),
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // Android notification channel for service status
    const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
      'persistent_sip_service',
      'SIP Service',
      description: 'Persistent SIP connection service',
      importance: Importance.low,
      showBadge: false,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(incomingCallChannel);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(serviceChannel);

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true, // For critical incoming call alerts
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    print('📱 Background notifications initialized');
  }

  @pragma('vm:entry-point')
  static void _onNotificationTap(NotificationResponse response) {
    print('📱 Notification tapped: ${response.payload}');
    
    // Handle notification actions
    if (response.actionId == 'accept_call') {
      print('✅ Accept call action tapped');
      _handleAcceptCallFromNotification(response.payload);
    } else if (response.actionId == 'decline_call') {
      print('❌ Decline call action tapped');
      _handleDeclineCallFromNotification(response.payload);
    } else if (response.payload?.contains('incoming_call') == true) {
      print('🔔 Incoming call notification tapped - opening app');
      _openAppForIncomingCall(response.payload);
    }
  }

  @pragma('vm:entry-point')
  static void _handleAcceptCallFromNotification(String? payload) {
    print('📞 Accepting call from notification');
    
    if (_currentIncomingCall != null) {
      try {
        // Accept with audio-only constraints
        final mediaConstraints = <String, dynamic>{
          'audio': true,
          'video': false,
        };
        _currentIncomingCall!.answer(mediaConstraints);
        print('✅ Call accepted from notification');
        
        // Move to active call
        _currentActiveCall = _currentIncomingCall;
        _currentIncomingCall = null;
        
        // Open the app to show call screen
        _openAppForIncomingCall(payload);
      } catch (e) {
        print('❌ Error accepting call from notification: $e');
      }
    }
  }

  @pragma('vm:entry-point')
  static void _handleDeclineCallFromNotification(String? payload) {
    print('📞 Declining call from notification');
    
    if (_currentIncomingCall != null) {
      try {
        _currentIncomingCall!.hangup({'status_code': 486}); // Busy here
        print('✅ Call declined from notification');
        _currentIncomingCall = null;
        hideIncomingCallNotification();
      } catch (e) {
        print('❌ Error declining call from notification: $e');
      }
    }
  }

  @pragma('vm:entry-point')
  static void _forwardCallToMainApp(Call call) async {
    print('🔄🔄🔄 Forwarding call to active main app: ${call.remote_identity} 🔄🔄🔄');
    
    try {
      // Store the call for main app to access
      _forwardedCall = call;
      print('📞 Stored forwarded call in memory: ${call.remote_identity} (ID: ${call.id})');
      
      // CRITICAL: Also store in SharedPreferences for cross-process access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('forwarded_call_id', call.id ?? 'unknown');
      await prefs.setString('forwarded_call_caller', call.remote_identity ?? 'Unknown');
      await prefs.setString('forwarded_call_direction', call.direction.toString());
      await prefs.setString('forwarded_call_state', call.state.toString());
      await prefs.setInt('forwarded_call_timestamp', DateTime.now().millisecondsSinceEpoch);
      print('💾 Stored forwarded call in SharedPreferences');
      
      // Send event to main app using FlutterBackgroundService
      final service = FlutterBackgroundService();
      print('📡 Service instance: ${service.hashCode}');
      
      final eventData = {
        'caller': call.remote_identity ?? 'Unknown',
        'callId': call.id ?? 'unknown',
        'direction': call.direction.toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      print('📤 Sending event data: $eventData');
      
      service.invoke('callForwardedToMainApp', eventData);
      
      print('✅✅✅ Call forwarded to main app via service communication ✅✅✅');
      
      // Also try to trigger via service instance if available
      if (_serviceInstance != null) {
        print('📡 Also sending via service instance...');
        _serviceInstance!.invoke('callForwardedToMainApp', eventData);
        print('✅ Sent via service instance too');
      }
      
    } catch (e) {
      print('❌❌❌ Error forwarding call to main app: $e ❌❌❌');
    }
  }
  
  @pragma('vm:entry-point')
  static void _forceOpenApp(Call call) {
    print('📱 Force opening app for incoming call from ${call.remote_identity}');
    
    try {
      // Use service instance to send message to main app
      _serviceInstance?.invoke('forceOpenApp', {
        'caller': call.remote_identity ?? 'Unknown',
        'callId': call.id ?? 'unknown',
        'direction': call.direction.toString(),
      });
    } catch (e) {
      print('❌ Error force opening app: $e');
    }
  }
  
  @pragma('vm:entry-point')
  static void _openAppForIncomingCall(String? payload) {
    print('📱 Opening app for incoming call - using notification tap');
    // The user will tap the notification to open the app
    // This is simpler and more reliable than platform channels
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    
    print('📱 iOS background service activated');
    return true;
  }

  @pragma('vm:entry-point')  
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    
    if (_isServiceRunning) {
      print('⚠️ Service already running, ignoring duplicate start');
      return;
    }
    
    _serviceInstance = service;
    _isServiceRunning = true;
    print('🚀 Persistent background service started');
    print('📱 Main app active status on service start: $_isMainAppActive');
    
    // Load and start SIP connection
    await _initializePersistentSipConnection(service);
    
    // Set up service control listeners
    service.on('stopService').listen((event) {
      _stopPersistentService();
      service.stopSelf();
    });
    
    service.on('updateSipUser').listen((event) async {
      final data = event!['sipUser'] as String;
      final sipUser = SipUser.fromJsonString(data);
      await _updateSipConnection(sipUser);
    });
    
    service.on('forwardCallToMainApp').listen((event) {
      print('🔄 Background service received forward call to main app request');
      final data = event as Map<String, dynamic>;
      final caller = data['caller'] as String;
      final callId = data['callId'] as String;
      
      // This will be handled by the main app - just log for now
      print('📞 Call forwarded to main app: $caller (ID: $callId)');
    });
    
    service.on('forceOpenApp').listen((event) {
      print('📱 Background service received force open app request');
      final data = event as Map<String, dynamic>;
      final caller = data['caller'] as String;
      final callId = data['callId'] as String;
      
      // Show urgent notification to force user attention
      showIncomingCallNotification(
        caller: '🚨 URGENT: $caller calling! TAP TO ANSWER',
        callId: callId,
      );
    });
    
    // Update service notification status
    _updateServiceNotification('SIP Phone Ready', 'Connected and ready to receive calls');
  }

  @pragma('vm:entry-point')
  static Future<void> _initializePersistentSipConnection(ServiceInstance service) async {
    try {
      print('🔄 Initializing persistent SIP connection in background...');
      
      // CRITICAL: Double-check main app active status from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final mainAppActiveFromPrefs = prefs.getBool('main_app_is_active') ?? false;
      print('🚨 SharedPreferences main app active status: $mainAppActiveFromPrefs');
      print('🚨 Static variable main app active status: $_isMainAppActive');
      
      // If either check says main app is active, DO NOT start background SIP
      if (_isMainAppActive || mainAppActiveFromPrefs) {
        print('🚨🚨 MAIN APP IS ACTIVE - ABORTING BACKGROUND SIP INITIALIZATION 🚨🚨');
        _updateServiceNotification(
          'SIP Phone (Main App Active)', 
          'Main app handling calls - background service standby'
        );
        return; // EXIT EARLY - do not initialize SIP at all
      }
      
      // Add startup delay to ensure main app has fully started
      print('⏳ Adding startup delay to prevent conflicts with main app...');
      await Future.delayed(Duration(seconds: 5));
      
      // Check again after delay
      final mainAppActiveAfterDelay = prefs.getBool('main_app_is_active') ?? false;
      if (_isMainAppActive || mainAppActiveAfterDelay) {
        print('🚨 Main app became active during startup delay - aborting background SIP');
        _updateServiceNotification(
          'SIP Phone (Main App Active)', 
          'Main app handling calls - background service standby'
        );
        return;
      }
      
      // Load saved SIP user configuration
      final savedUserJson = prefs.getString('websocket_sip_user'); // Use WebSocket user
      final shouldMaintain = prefs.getBool('should_maintain_websocket_connection') ?? false;
      
      if (savedUserJson == null || !shouldMaintain) {
        print('⚠️ No saved SIP user configuration found');
        _updateServiceNotification('SIP Phone', 'Not configured');
        return;
      }
      
      _currentSipUser = SipUser.fromJsonString(savedUserJson);
      print('📋 Loaded SIP user: ${_currentSipUser!.authUser}');
      
      // Initialize SIP helper for background operation
      _backgroundSipHelper = SIPUAHelper();
      final listener = PersistentSipListener(service);
      print('🔗 Adding background SIP listener...');
      _backgroundSipHelper!.addSipUaHelperListener(listener);
      print('✅ Background SIP listener added successfully');
      
      // Final check before connecting
      final finalCheck = prefs.getBool('main_app_is_active') ?? false;
      if (!_isMainAppActive && !finalCheck) {
        print('📞 Final check passed - starting background SIP connection');
        await _connectSipInBackground(_currentSipUser!);
        
        // Set up keep-alive and health monitoring
        _startKeepAliveTimer();
        _startHealthMonitoring();
      } else {
        print('📱 Final check failed - main app became active');
        _updateServiceNotification(
          'SIP Phone (Main App Active)', 
          'Main app handling calls - background service standby'
        );
      }
      
      print('✅ Persistent SIP connection initialized successfully');
      
    } catch (e) {
      print('❌ Error initializing persistent SIP connection: $e');
      _updateServiceNotification('SIP Phone Error', 'Failed to connect: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _connectSipInBackground(SipUser user) async {
    try {
      print('🔌 Connecting SIP in background...');
      
      if (_backgroundSipHelper == null) {
        print('❌ SIP helper not initialized');
        return;
      }
      
      // Disconnect if already connected
      if (_backgroundSipHelper!.registered) {
        await _backgroundSipHelper!.unregister();
        _backgroundSipHelper!.stop();
        await Future.delayed(Duration(seconds: 1));
      }
      
      UaSettings settings = UaSettings();
      
      // Parse SIP configuration
      String sipUri = user.sipUri ?? '';
      String username = user.authUser;
      String domain = '';
      
      if (sipUri.contains('@')) {
        final parts = sipUri.split('@');
        if (parts.length > 1) {
          username = parts[0].replaceAll('sip:', '');
          domain = parts[1];
        }
      } else if (user.wsUrl != null && user.wsUrl!.isNotEmpty) {
        try {
          final uri = Uri.parse(user.wsUrl!);
          domain = uri.host;
        } catch (e) {
          print('⚠️ Failed to parse domain from WebSocket URL: $e');
          domain = 'localhost';
        }
      }
      
      String properSipUri = 'sip:$username@$domain';
      
      // Configure WebSocket settings for background
      settings.transportType = TransportType.WS;
      settings.webSocketUrl = user.wsUrl ?? '';
      settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
      settings.webSocketSettings.allowBadCertificate = true;
      // Note: pingInterval may not be available in all versions
      
      // SIP settings
      settings.uri = properSipUri;
      settings.registrarServer = domain;
      settings.authorizationUser = username;
      settings.password = user.password;
      settings.displayName = user.displayName.isNotEmpty ? user.displayName : username;
      settings.userAgent = 'Flutter SIP Background Service v1.0.0';
      settings.dtmfMode = DtmfMode.RFC2833;
      settings.register = true;
      settings.register_expires = 300;
      
      // Host configuration
      try {
        Uri wsUri = Uri.parse(settings.webSocketUrl!);
        settings.host = wsUri.host.isNotEmpty ? wsUri.host : domain;
      } catch (e) {
        settings.host = domain;
      }
      
      print('🚀 Starting background SIP connection to: ${settings.webSocketUrl}');
      print('📋 SIP URI: $properSipUri');
      
      await _backgroundSipHelper!.start(settings);
      print('✅ Background SIP connection started');
      
    } catch (e) {
      print('❌ Background SIP connection failed: $e');
      _updateServiceNotification('SIP Connection Failed', e.toString());
      _scheduleReconnection();
    }
  }

  @pragma('vm:entry-point')
  static void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      // Check if main app is still active before doing keep-alive
      try {
        final prefs = await SharedPreferences.getInstance();
        final mainAppActive = prefs.getBool('main_app_is_active') ?? false;
        
        if (_isMainAppActive || mainAppActive) {
          print('📱 Keep-alive check: Main app is active - background SIP should not be running');
          if (_backgroundSipHelper?.registered == true) {
            print('🚨 Background SIP is registered but main app is active - unregistering');
            await _backgroundSipHelper!.unregister();
          }
          _updateServiceNotification(
            'SIP Phone (Main App Active)', 
            'Main app handling calls - background service standby'
          );
          return;
        }
      } catch (e) {
        print('❌ Error checking main app status in keep-alive: $e');
      }
      
      if (_backgroundSipHelper?.registered == true) {
        print('💓 Background SIP keep-alive check: Connected');
        print('📊 Background SIP Helper Status:');
        print('  - Registered: ${_backgroundSipHelper?.registered}');
        print('  - WebSocket URL: ${_currentSipUser?.wsUrl}');
        print('  - Background helper ready: ${_backgroundSipHelper != null}');
        print('  - Service running: $_isServiceRunning');
        _updateServiceNotification('SIP Phone Active', 
            'Connected • Ready for calls • ${DateTime.now().toString().substring(11, 16)}');
      } else {
        print('⚠️ Background SIP keep-alive check: Disconnected');
        _updateServiceNotification('SIP Phone Reconnecting', 'Attempting to reconnect...');
        if (_currentSipUser != null) {
          _connectSipInBackground(_currentSipUser!);
        }
      }
    });
  }

  @pragma('vm:entry-point')
  static void _startHealthMonitoring() {
    Timer.periodic(Duration(minutes: 1), (timer) async {
      if (!_isServiceRunning) {
        timer.cancel();
        return;
      }
      
      try {
        // Check if main app is active before health monitoring
        final prefs = await SharedPreferences.getInstance();
        final mainAppActive = prefs.getBool('main_app_is_active') ?? false;
        
        if (_isMainAppActive || mainAppActive) {
          print('📱 Health check: Main app is active - background SIP should not be running');
          if (_backgroundSipHelper?.registered == true) {
            print('🚨 Health check found background SIP registered with active main app - unregistering');
            await _backgroundSipHelper!.unregister();
          }
          return;
        }
        
        if (_backgroundSipHelper?.registered != true && _currentSipUser != null) {
          print('🔄 Health check: SIP not registered, attempting reconnection');
          _connectSipInBackground(_currentSipUser!);
        } else {
          print('✅ Health check: SIP connection healthy');
        }
      } catch (e) {
        print('❌ Health check error: $e');
      }
    });
  }

  @pragma('vm:entry-point')
  static void _scheduleReconnection() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer(Duration(seconds: 10), () {
      if (_currentSipUser != null && _isServiceRunning) {
        print('🔄 Attempting scheduled reconnection...');
        _connectSipInBackground(_currentSipUser!);
      }
    });
  }

  @pragma('vm:entry-point')
  static Future<void> _updateSipConnection(SipUser newUser) async {
    print('🔄 Updating SIP connection with new user configuration');
    _currentSipUser = newUser;
    await _connectSipInBackground(newUser);
  }

  @pragma('vm:entry-point')
  static void _updateServiceNotification(String title, String content) {
    // Update service notification via service instance
    _serviceInstance?.invoke('updateNotification', {
      'title': title,
      'content': content,
    });
  }

  @pragma('vm:entry-point')
  static Future<void> showIncomingCallNotification({
    required String caller,
    required String callId,
  }) async {
    print('🔔 Showing incoming call notification for: $caller');
    
    final androidDetails = AndroidNotificationDetails(
      'incoming_calls_channel',
      'Incoming Calls',
      channelDescription: 'Notifications for incoming SIP calls',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true, // Show as full screen on lock screen
      ongoing: true, // Cannot be dismissed
      autoCancel: false,
      showWhen: true,
      when: null,
      usesChronometer: false,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('phone_ringing'),
      enableVibration: true,
      ticker: 'Incoming call from $caller',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'accept_call',
          'Accept',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          'decline_call',
          'Decline',
          cancelNotification: true,
        ),
      ],
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'phone_ringing.caf',
      interruptionLevel: InterruptionLevel.critical,
      categoryIdentifier: 'INCOMING_CALL',
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      999, // Fixed ID for incoming calls
      'Incoming Call',
      'Call from $caller',
      notificationDetails,
      payload: 'incoming_call:$callId',
    );
    
    print('✅ Incoming call notification displayed');
  }

  @pragma('vm:entry-point')
  static Future<void> hideIncomingCallNotification() async {
    await _notificationsPlugin.cancel(999);
    print('📱 Incoming call notification hidden');
  }

  @pragma('vm:entry-point')
  static void _stopPersistentService() {
    print('🛑 Stopping persistent background service');
    
    _isServiceRunning = false;
    _keepAliveTimer?.cancel();
    _reconnectionTimer?.cancel();
    
    try {
      if (_backgroundSipHelper?.registered == true) {
        _backgroundSipHelper?.unregister();
      }
      _backgroundSipHelper?.stop();
      _backgroundSipHelper = null;
    } catch (e) {
      print('❌ Error stopping SIP helper: $e');
    }
    
    print('✅ Persistent service stopped');
  }

  // Public API methods
  @pragma('vm:entry-point')
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    await service.startService();
    print('🚀 Background service start requested');
  }

  @pragma('vm:entry-point')
  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
    print('🛑 Background service stop requested');
  }

  @pragma('vm:entry-point')
  static Future<void> updateSipUserInService(SipUser sipUser) async {
    final service = FlutterBackgroundService();
    service.invoke('updateSipUser', {
      'sipUser': sipUser.toJsonString(),
    });
    print('🔄 SIP user update sent to background service');
  }

  @pragma('vm:entry-point')
  static bool isServiceRunning() {
    return _isServiceRunning;
  }

  @pragma('vm:entry-point')
  static List<Call> getActiveCalls() {
    final activeCalls = <Call>[];
    if (_currentIncomingCall != null) activeCalls.add(_currentIncomingCall!);
    if (_currentActiveCall != null) activeCalls.add(_currentActiveCall!);
    return activeCalls;
  }

  @pragma('vm:entry-point')
  static bool hasIncomingCall() {
    return _currentIncomingCall != null;
  }

  @pragma('vm:entry-point')
  static Call? getIncomingCall() {
    return _currentIncomingCall;
  }

  @pragma('vm:entry-point')
  static Call? getActiveCall() {
    return _currentActiveCall ?? _currentIncomingCall;
  }

  @pragma('vm:entry-point')
  static SIPUAHelper? getBackgroundSipHelper() {
    return _backgroundSipHelper;
  }

  @pragma('vm:entry-point')
  static void transferCallToMainApp() {
    print('🔄 Transferring call from background to main app');
    // The main app will use the same SIP helper instance
    // This ensures the call continues seamlessly
  }

  @pragma('vm:entry-point')
  static void setMainAppActive(bool isActive) async {
    _isMainAppActive = isActive;
    print('📱 Main app status changed: ${isActive ? "ACTIVE" : "BACKGROUND"}');
    
    // CRITICAL: Also store in SharedPreferences for cross-process communication
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('main_app_is_active', isActive);
      print('💾 Main app active status saved to SharedPreferences: $isActive');
    } catch (e) {
      print('❌ Error saving main app status to SharedPreferences: $e');
    }
    
    if (isActive) {
      // Main app is active - temporarily unregister background service to let main app handle calls
      _temporarilyUnregisterForMainApp();
    } else {
      // Main app went to background - re-register background service
      _reregisterAfterMainAppBackground();
    }
  }
  
  @pragma('vm:entry-point')
  static void _temporarilyUnregisterForMainApp() async {
    try {
      if (_backgroundSipHelper != null && _backgroundSipHelper!.registered) {
        print('📴 Temporarily unregistering background SIP helper for main app');
        await _backgroundSipHelper!.unregister();
        
        // Update notification
        _updateServiceNotification(
          'SIP Phone (Main App Active)', 
          'Main app handling calls - background service standby'
        );
        
        print('✅ Background SIP helper temporarily unregistered');
      }
    } catch (e) {
      print('❌ Error temporarily unregistering background SIP helper: $e');
    }
  }
  
  @pragma('vm:entry-point')
  static void _reregisterAfterMainAppBackground() async {
    try {
      if (_backgroundSipHelper != null && !_backgroundSipHelper!.registered && _currentSipUser != null) {
        print('🔄 Re-registering background SIP helper after main app background');
        
        // Small delay to ensure main app has unregistered first
        await Future.delayed(Duration(seconds: 2));
        
        await _connectSipInBackground(_currentSipUser!);
        print('✅ Background SIP helper re-registered successfully');
      }
    } catch (e) {
      print('❌ Error re-registering background SIP helper: $e');
    }
  }

  @pragma('vm:entry-point')
  static bool isMainAppActive() {
    return _isMainAppActive;
  }

  @pragma('vm:entry-point')
  static Future<Call?> getForwardedCall() async {
    try {
      // First try memory (same process)
      if (_forwardedCall != null) {
        print('📞 Found forwarded call in memory: ${_forwardedCall!.remote_identity}');
        return _forwardedCall;
      }
      
      // Try SharedPreferences (cross-process)
      final prefs = await SharedPreferences.getInstance();
      final callId = prefs.getString('forwarded_call_id');
      
      if (callId != null) {
        final caller = prefs.getString('forwarded_call_caller') ?? 'Unknown';
        final direction = prefs.getString('forwarded_call_direction') ?? 'Direction.incoming';
        final state = prefs.getString('forwarded_call_state') ?? 'CallStateEnum.CALL_INITIATION';
        final timestamp = prefs.getInt('forwarded_call_timestamp') ?? 0;
        
        print('📞 Found forwarded call in SharedPreferences: $caller (ID: $callId)');
        print('  - Direction: $direction');
        print('  - State: $state');
        print('  - Timestamp: $timestamp');
        
        // Return the actual call object if it exists in our static variables
        if (_currentIncomingCall != null && _currentIncomingCall!.id == callId) {
          print('🎯 Matched with current incoming call');
          return _currentIncomingCall;
        }
        
        if (_currentActiveCall != null && _currentActiveCall!.id == callId) {
          print('🎯 Matched with current active call');
          return _currentActiveCall;
        }
        
        print('⚠️ Call found in prefs but no matching call object in memory');
        return null;
      }
      
      print('📞 No forwarded call found in memory or SharedPreferences');
      return null;
      
    } catch (e) {
      print('❌ Error getting forwarded call: $e');
      return null;
    }
  }

  @pragma('vm:entry-point')
  static Future<void> clearForwardedCall() async {
    try {
      _forwardedCall = null;
      
      // Clear from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('forwarded_call_id');
      await prefs.remove('forwarded_call_caller');
      await prefs.remove('forwarded_call_direction');
      await prefs.remove('forwarded_call_state');
      await prefs.remove('forwarded_call_timestamp');
      
      print('📞 Cleared forwarded call from memory and SharedPreferences');
    } catch (e) {
      print('❌ Error clearing forwarded call: $e');
    }
  }
}

/// Listener for SIP events in background service
class PersistentSipListener implements SipUaHelperListener {
  final ServiceInstance service;
  
  PersistentSipListener(this.service);

  @override
  void callStateChanged(Call call, CallState state) {
    print('🔔🔔🔔 Background: Call state changed to ${state.state} 🔔🔔🔔');
    print('📞 Background Call Details:');
    print('  - Call ID: ${call.id}');
    print('  - Remote: ${call.remote_identity}'); 
    print('  - Local: ${call.local_identity}');
    print('  - Direction: ${call.direction}');
    print('  - State: ${state.state}');
    print('🔔🔔🔔 End Background Call Details 🔔🔔🔔');
    
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
        // Incoming call detected
        final caller = call.remote_identity ?? 'Unknown Number';
        print('🔔 Background: Incoming call from $caller');
        
        // Store the incoming call reference
        PersistentBackgroundService._currentIncomingCall = call;
        
        PersistentBackgroundService.showIncomingCallNotification(
          caller: caller,
          callId: call.id ?? 'unknown',
        );
        
        // If main app is active, let it handle the call directly 
        if (PersistentBackgroundService._isMainAppActive) {
          print('📱 Main app is active - letting main app SIP helper handle call');
          print('📱 Background service will NOT interfere with main app call handling');
          // Do NOT store or forward the call - let main app handle it directly
          return; // Exit early, don't process further
        } else {
          print('📱 Main app is background - background service handling call');
          // Force open the app immediately for incoming calls
          PersistentBackgroundService._forceOpenApp(call);
        }
        
        // Auto-answer after 15 seconds ONLY if main app is NOT active
        // If main app is active, let user manually accept/decline
        Timer(Duration(seconds: 15), () {
          // Check if main app is active first
          if (PersistentBackgroundService._isMainAppActive) {
            print('📱 Main app is active - NOT auto-answering (user should handle manually)');
            return;
          }
          
          if (call.state == CallStateEnum.CALL_INITIATION || 
              call.state == CallStateEnum.PROGRESS) {
            print('⏰ Background: Checking if call needs auto-answer (app is closed)');
            print('📊 Background: Call state is still ${call.state}');
            
            try {
              // Check if call is still valid before answering
              if (call.state == CallStateEnum.CALL_INITIATION || 
                  call.state == CallStateEnum.PROGRESS) {
                // Answer the call to prevent it from failing
                final mediaConstraints = <String, dynamic>{
                  'audio': true,
                  'video': false,
                };
                call.answer(mediaConstraints);
                print('✅ Background call auto-answered after 15s timeout');
              } else {
                print('ℹ️ Call state changed, no auto-answer needed: ${call.state}');
                return;
              }
              
              // Move to active call
              PersistentBackgroundService._currentActiveCall = call;
              PersistentBackgroundService._currentIncomingCall = null;
              
              // Show notification indicating call was automatically answered
              PersistentBackgroundService._updateServiceNotification(
                'Call Auto-Answered', 
                'Active call with $caller - tap app to access controls'
              );
              
              // Keep a simple notification for the active call
              PersistentBackgroundService.showIncomingCallNotification(
                caller: 'Active: $caller (Tap to open)',
                callId: call.id ?? 'unknown',
              );
            } catch (e) {
              print('❌ Error auto-answering background call: $e');
              // Don't re-throw, just log the error
            }
          } else {
            print('📞 Background: Call state changed to ${call.state}, no auto-answer needed');
          }
        });
        break;
        
      case CallStateEnum.PROGRESS:
        print('📞 Background: Call ringing...');
        break;
        
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        print('✅ Background: Call connected');
        // Move to active call if it was incoming
        if (PersistentBackgroundService._currentIncomingCall?.id == call.id) {
          PersistentBackgroundService._currentActiveCall = call;
          PersistentBackgroundService._currentIncomingCall = null;
        }
        // Update notification to show active call
        final caller = call.remote_identity ?? 'Unknown Number';
        PersistentBackgroundService.showIncomingCallNotification(
          caller: '📞 Active: $caller (Tap to open)',
          callId: call.id ?? 'unknown',
        );
        break;
        
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        print('📞 Background: Call ended/failed');
        // Clear call references
        if (PersistentBackgroundService._currentIncomingCall?.id == call.id) {
          PersistentBackgroundService._currentIncomingCall = null;
        }
        if (PersistentBackgroundService._currentActiveCall?.id == call.id) {
          PersistentBackgroundService._currentActiveCall = null;
        }
        // Call ended, hide notification
        PersistentBackgroundService.hideIncomingCallNotification();
        break;
        
      default:
        print('📞 Background: Call state ${state.state} for ${call.remote_identity}');
        break;
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    print('📋📋📋 Background: Registration state changed to ${state.state} 📋📋📋');
    
    switch (state.state) {
      case RegistrationStateEnum.REGISTERED:
        print('✅ Background: Successfully registered to SIP server');
        PersistentBackgroundService._updateServiceNotification(
          'SIP Phone Active', 
          'Connected and ready to receive calls'
        );
        break;
        
      case RegistrationStateEnum.REGISTRATION_FAILED:
        print('❌ Background: SIP registration failed');
        PersistentBackgroundService._updateServiceNotification(
          'SIP Phone Error', 
          'Registration failed - retrying...'
        );
        break;
        
      case RegistrationStateEnum.UNREGISTERED:
        print('⚠️ Background: SIP unregistered');
        PersistentBackgroundService._updateServiceNotification(
          'SIP Phone Disconnected', 
          'Connection lost - reconnecting...'
        );
        break;
        
      default:
        print('📋 Background: Registration state ${state.state}');
        break;
    }
  }

  @override
  void transportStateChanged(TransportState state) {
    print('🌐🌐🌐 Background: Transport state changed to ${state.state} 🌐🌐🌐');
    
    if (state.state == TransportStateEnum.DISCONNECTED) {
      print('⚠️ Background: Transport disconnected, will attempt reconnection');
      PersistentBackgroundService._updateServiceNotification(
        'SIP Phone Reconnecting', 
        'Network connection lost - reconnecting...'
      );
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    print('📨 Background: New SIP message received');
  }

  @override
  void onNewNotify(Notify ntf) {
    print('📢 Background: New SIP notify received');
  }

  @override
  void onNewReinvite(ReInvite event) {
    print('🔄 Background: New SIP re-invite received');
    
    // For audio-only app, reject video upgrade requests
    if (event.reject != null) {
      event.reject!.call({'status_code': 488}); // Not acceptable here
      print('📞 Background: Video upgrade request rejected (audio-only)');
    }
  }
}