import 'dart:async';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'user_state/sip_user.dart';
import '../data/models/stored_credentials_model.dart';

/// Persistent background service that maintains SIP connection
/// and handles incoming calls even when app is closed/locked
@pragma('vm:entry-point')
class PersistentBackgroundService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

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
  static DateTime? _lastAppStatusChange; // Track to prevent rapid switching

  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Initialize notifications first
    await _initializeNotifications();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Don't auto-start, we'll start manually
        isForegroundMode: true,
        notificationChannelId: 'persistent_sip_service',
        initialNotificationTitle: 'SIP Phone Active',
        initialNotificationContent: 'Ready to receive calls - Running in background for 24/7 operation',
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

    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true, // For critical incoming call alerts
    );

    const InitializationSettings initializationSettings = InitializationSettings(
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
    print('📱🔔📱 NOTIFICATION TAP RECEIVED 📱🔔📱');
    print('📱 Action ID: "${response.actionId}"');
    print('📱 Payload: "${response.payload}"');
    print('📱 Notification ID: ${response.notificationResponseType}');
    print('📱 Current incoming call exists: ${_currentIncomingCall != null}');

    // Handle notification actions
    if (response.actionId == 'answer_call') {
      print('✅✅✅ ANSWER CALL ACTION TAPPED ✅✅✅');
      _handleAcceptCallFromNotification(response.payload);
    } else if (response.actionId == 'decline_call') {
      print('❌❌❌ DECLINE CALL ACTION TAPPED ❌❌❌');
      _handleDeclineCallFromNotification(response.payload);
    } else if (response.payload?.contains('incoming_call') == true) {
      print('🔔 Incoming call notification tapped - opening app');
      _launchAppWithIncomingCall(response.payload);
    } else {
      print('⚠️ Unknown notification action: actionId="${response.actionId}", payload="${response.payload}"');
    }
  }

  @pragma('vm:entry-point')
  static void _handleAcceptCallFromNotification(String? payload) {
    print('📞📞📞 HANDLE ACCEPT CALL FROM NOTIFICATION 📞📞📞');
    print('📞 Payload: $payload');
    print('📞 Current incoming call: ${_currentIncomingCall?.id}');
    print('📞 Call remote identity: ${_currentIncomingCall?.remote_identity}');
    print('📞 Call state: ${_currentIncomingCall?.state}');

    if (_currentIncomingCall != null) {
      try {
        // Accept with audio-only constraints
        final mediaConstraints = <String, dynamic>{
          'audio': true,
          'video': false,
        };
        print('📞 Calling answer() with constraints: $mediaConstraints');
        _currentIncomingCall!.answer(mediaConstraints);
        print('✅ Call accepted from notification - answer() called successfully');

        // Move to active call
        _currentActiveCall = _currentIncomingCall;
        _currentIncomingCall = null;

        // Open the app to show call screen
        print('📞 Launching app with incoming call...');
        _launchAppWithIncomingCall(payload);
      } catch (e) {
        print('❌ Error accepting call from notification: $e');
        print('❌ Error type: ${e.runtimeType}');
        print('❌ Stack trace: ${StackTrace.current}');
      }
    } else {
      print('❌ No current incoming call to accept!');
    }
  }

  @pragma('vm:entry-point')
  static void _handleDeclineCallFromNotification(String? payload) {
    print('❌❌❌ HANDLE DECLINE CALL FROM NOTIFICATION ❌❌❌');
    print('📞 Payload: $payload');
    print('📞 Current incoming call: ${_currentIncomingCall?.id}');
    print('📞 Call remote identity: ${_currentIncomingCall?.remote_identity}');
    print('📞 Call state: ${_currentIncomingCall?.state}');

    if (_currentIncomingCall != null) {
      try {
        print('📞 Calling hangup() with status_code 486 (Busy Here)');
        _currentIncomingCall!.hangup({'status_code': 486}); // Busy here
        print('✅ Call declined from notification - hangup() called successfully');
        _currentIncomingCall = null;
        print('📞 Hiding incoming call notification...');
        hideIncomingCallNotification();
        print('✅ Notification hidden successfully');
      } catch (e) {
        print('❌ Error declining call from notification: $e');
        print('❌ Error type: ${e.runtimeType}');
        print('❌ Stack trace: ${StackTrace.current}');
      }
    } else {
      print('❌ No current incoming call to decline!');
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
  static void _launchAppWithIncomingCall(String? payload) {
    print('📱 Launching app for incoming call - payload: $payload');

    if (payload == null) {
      print('⚠️ No payload provided for incoming call');
      return;
    }

    try {
      // Parse payload: 'incoming_call:callId:caller'
      final parts = payload.split(':');
      if (parts.length >= 3) {
        final callId = parts[1];
        final caller = parts[2];

        print('📞 Launching app for call from $caller (ID: $callId)');

        // CRITICAL: Use the aggressive forceOpenAppForCall instead
        const platform = MethodChannel('sip_phone/incoming_call');
        platform.invokeMethod('forceOpenAppForCall', {
          'caller': caller,
          'callId': callId,
          'autoLaunch': true,
          'fromNotification': true,
          'forceToForeground': true,
          'showIncomingCallScreen': true,
        }).then((_) {
          print('✅ FORCE app launch request sent via platform channel');

          // Also ensure the call is properly stored for main app access
          if (_currentIncomingCall != null) {
            _forwardedCall = _currentIncomingCall;
            print('🔄 Stored current incoming call as forwarded call for main app');
          }
        }).catchError((error) {
          print('❌ Failed to FORCE launch app via platform channel: $error');

          // Fallback to old method
          platform.invokeMethod('launchIncomingCallScreen', {
            'caller': caller,
            'callId': callId,
            'fromNotification': true,
          });
        });
      } else {
        print('⚠️ Invalid payload format: $payload');
      }
    } catch (e) {
      print('❌ Error launching app for incoming call: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    print('🍎 iOS background service activated');
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    print('🚀 Background service onStart called');

    // CRITICAL: The foreground service notification is already handled by flutter_background_service
    // through the AndroidConfiguration in initializeService(). We just need to ensure
    // the service starts properly and doesn't get killed by Android timing constraints.
    print('✅ Service started - foreground notification handled by flutter_background_service');

    // Now do the initialization
    DartPluginRegistrant.ensureInitialized();

    if (_isServiceRunning) {
      print('⚠️ Service already running, ignoring duplicate start');
      return;
    }

    _serviceInstance = service;
    _isServiceRunning = true;
    print('✅ Persistent background service started');
    print('📱 Main app active status on service start: $_isMainAppActive');

    // Set up service control listeners first
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

    service.on('ping').listen((event) {
      print('🏓 Background service received ping - responding with status');
      service.invoke('pong', {
        'serviceRunning': _isServiceRunning,
        'helperExists': _backgroundSipHelper != null,
        'userExists': _currentSipUser != null,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
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

    print('✅ Background service started successfully in foreground mode');

    // Initialize SIP connection asynchronously to avoid blocking foreground service
    Future.delayed(Duration(milliseconds: 100), () async {
      try {
        await _initializePersistentSipConnection(service);
        print('✅ Background service initialization completed');
      } catch (e) {
        print('❌ Background service initialization failed: $e');
        _updateServiceNotification('SIP Phone Error', 'Failed to initialize - will retry when needed');
      }
    });
  }

  @pragma('vm:entry-point')
  static Future<void> _initializePersistentSipConnection(ServiceInstance service) async {
    try {
      print('🔄 Initializing persistent SIP connection in background...');

      // First try quick SharedPreferences load
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('websocket_sip_user');
      final shouldMaintain = prefs.getBool('should_maintain_websocket_connection') ?? false;

      if (savedUserJson != null && shouldMaintain) {
        _currentSipUser = SipUser.fromJsonString(savedUserJson);
        print('📋 Loaded SIP user from SharedPreferences: ${_currentSipUser!.authUser}');
      } else {
        print('⚠️ No saved SIP user in SharedPreferences, trying Hive...');

        // Try Hive with timeout to prevent hanging
        try {
          await _loadSipUserFromHiveForInitialization().timeout(
            Duration(seconds: 10),
            onTimeout: () {
              print('⏰ Hive loading timed out after 10 seconds');
              throw TimeoutException('Hive loading timeout');
            },
          );

          if (_currentSipUser == null) {
            print('❌ No SIP user configuration found');
            _updateServiceNotification('SIP Phone', 'Not configured - please login');
            return;
          }
        } catch (e) {
          print('❌ Error loading from Hive: $e');
          _updateServiceNotification('SIP Phone', 'Configuration error');
          return;
        }
      }

      // Initialize SIP helper
      _backgroundSipHelper = SIPUAHelper();
      final listener = PersistentSipListener(service);
      _backgroundSipHelper!.addSipUaHelperListener(listener);
      print('✅ Background SIP helper initialized');

      // Check if main app is active from Hive first, then fallback to SharedPreferences
      bool mainAppActive = false;
      try {
        final dir = await getApplicationDocumentsDirectory();
        await Hive.initFlutter(dir.path);
        final box = await Hive.openBox('app_data');

        mainAppActive = box.get('main_app_is_active') ?? false;

        // Check timestamp to ensure data is recent
        final timestamp = box.get('main_app_status_timestamp') ?? 0;
        if (timestamp > 0) {
          final lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final timeSinceUpdate = DateTime.now().difference(lastUpdate);

          if (timeSinceUpdate.inMinutes > 5) {
            print('⚠️ Main app status from Hive is outdated - assuming background');
            mainAppActive = false;
          }
        }

        // DON'T close the box - let the main app manage it
      } catch (e) {
        print('⚠️ Could not check main app status from Hive during init: $e');
        // Fallback to SharedPreferences
        mainAppActive = prefs.getBool('main_app_is_active') ?? false;
      }

      print('📊 Main app active status: $mainAppActive');

      if (mainAppActive) {
        print('📱 Main app is active - background service in standby mode');
        _isMainAppActive = true;
        _updateServiceNotification('SIP Phone (Standby)', 'Main app active - background service ready');
      } else {
        print('🔄 Main app is background - starting SIP connection');
        _isMainAppActive = false;
        await _connectSipInBackground(_currentSipUser!);
      }

      // Set up keep-alive and health monitoring
      _startKeepAliveTimer();
      _startHealthMonitoring();

      print('✅ Persistent SIP connection initialized successfully');
    } catch (e) {
      print('❌ Error initializing persistent SIP connection: $e');
      _updateServiceNotification('SIP Phone Error', 'Failed to connect: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _connectSipInBackground(SipUser user, {bool allowBackupConnection = false}) async {
    try {
      print('🔌 Connecting SIP in background...');

      if (_backgroundSipHelper == null) {
        print('⚠️ SIP helper not initialized - creating new one');
        _backgroundSipHelper = SIPUAHelper();

        // Add listener if service instance is available
        if (_serviceInstance != null) {
          final listener = PersistentSipListener(_serviceInstance!);
          _backgroundSipHelper!.addSipUaHelperListener(listener);
          print('✅ Background SIP listener added during connection');
        } else {
          print('⚠️ Service instance not available - SIP helper created without listener');
        }
      }

      // Disconnect if already connected
      if (_backgroundSipHelper!.registered) {
        print('📴 Background SIP helper already registered - unregistering first');
        await _backgroundSipHelper!.unregister();
        _backgroundSipHelper!.stop();
        await Future.delayed(Duration(seconds: 1));
        print('✅ Previous background registration cleaned up');
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
      print('📊 Main app active status: $_isMainAppActive');

      // Final check before connecting
      if (_isMainAppActive && !allowBackupConnection) {
        print('⚠️ Main app became active during connection - aborting');
        return;
      }

      if (_isMainAppActive && allowBackupConnection) {
        print('📞 Proceeding with backup connection while main app is active');
      }

      await _backgroundSipHelper!.start(settings);
      print('✅ Background SIP connection started');

      // Wait a moment for registration to complete
      await Future.delayed(Duration(seconds: 2));

      if (_backgroundSipHelper!.registered) {
        print('✅✅ Background SIP successfully registered! ✅✅');
        _updateServiceNotification(
            'SIP Phone Active (Background)', 'Connected and ready to receive calls in background');
      } else {
        print('❌ Background SIP registration failed - will retry');
        throw Exception('Background SIP registration failed');
      }
    } catch (e) {
      print('❌ Background SIP connection failed: $e');
      _updateServiceNotification('SIP Connection Failed', e.toString());
      _scheduleReconnection();
    }
  }

  @pragma('vm:entry-point')
  static void _startKeepAliveTimer() {
    _keepAliveTimer?.cancel();
    // Increased frequency for better background reliability
    _keepAliveTimer = Timer.periodic(Duration(seconds: 20), (timer) async {
      // Check if main app is active from Hive (real-time status)
      bool mainAppActive = _isMainAppActive;
      try {
        final dir = await getApplicationDocumentsDirectory();
        await Hive.initFlutter(dir.path);
        Box box;

        try {
          box = Hive.box('app_data');
          if (!box.isOpen) {
            box = await Hive.openBox('app_data');
          }
        } catch (e) {
          box = await Hive.openBox('app_data');
        }

        mainAppActive = box.get('main_app_is_active') ?? false;
        _isMainAppActive = mainAppActive; // Update static variable

        // Check timestamp to ensure data is recent (within last 5 minutes)
        final timestamp = box.get('main_app_status_timestamp') ?? 0;
        final lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final timeSinceUpdate = DateTime.now().difference(lastUpdate);

        if (timeSinceUpdate.inMinutes > 5) {
          print('⚠️ Main app status is outdated (${timeSinceUpdate.inMinutes} min old) - assuming background');
          mainAppActive = false;
          _isMainAppActive = false;
        }

        // DON'T close the box - let the main app manage it
      } catch (e) {
        print('⚠️ Could not check main app status from Hive: $e');

        // Fallback to SharedPreferences
        try {
          final prefs = await SharedPreferences.getInstance();
          mainAppActive = prefs.getBool('main_app_is_active') ?? false;
          _isMainAppActive = mainAppActive;
        } catch (fallbackError) {
          print('⚠️ SharedPreferences fallback also failed: $fallbackError');
        }
      }

      if (mainAppActive) {
        print('📱 Keep-alive: Main app active - background in standby');

        // Ensure background SIP is unregistered when main app is active
        if (_backgroundSipHelper != null && _backgroundSipHelper!.registered) {
          print('📴 Keep-alive: Unregistering background SIP - main app is handling calls');
          try {
            await _backgroundSipHelper!.unregister();
          } catch (e) {
            print('⚠️ Keep-alive: Error unregistering background SIP: $e');
          }
        }

        _updateServiceNotification('SIP Phone (Standby)', 'Main app active - background service ready');
        return;
      }

      if (_backgroundSipHelper?.registered == true) {
        print('💓 Background SIP keep-alive check: Connected');
        print('📊 Background SIP Helper Status:');
        print('  - Registered: ${_backgroundSipHelper?.registered}');
        print('  - WebSocket URL: ${_currentSipUser?.wsUrl}');
        print('  - Background helper ready: ${_backgroundSipHelper != null}');
        print('  - Service running: $_isServiceRunning');
        _updateServiceNotification(
            'SIP Phone 24/7 Active', 'Background service ready • ${DateTime.now().toString().substring(11, 16)}');

        // Additional health check - verify connection is stable
        // Note: We already know registered is true, so this is good
      } else {
        print('⚠️ Background SIP keep-alive check: Disconnected - initiating aggressive reconnection');
        _updateServiceNotification('SIP Phone Reconnecting', 'Attempting to reconnect...');
        if (_currentSipUser != null) {
          print('🔄 Keep-alive: Attempting reconnection with current SIP user');
          _connectSipInBackground(_currentSipUser!);
        } else {
          // Try to load SIP user from SharedPreferences if not in memory
          print('📎 Keep-alive: SIP user not in memory - attempting to load from SharedPreferences...');
          try {
            final prefs = await SharedPreferences.getInstance();
            final savedUserJson = prefs.getString('websocket_sip_user');

            if (savedUserJson != null) {
              _currentSipUser = SipUser.fromJsonString(savedUserJson);
              print('✅ Keep-alive: SIP user loaded from SharedPreferences: ${_currentSipUser!.authUser}');
              _connectSipInBackground(_currentSipUser!);
            } else {
              print('🔍 Keep-alive: No SIP user found in SharedPreferences - trying Hive...');
              await _loadSipUserFromHiveAndReregister();
            }
          } catch (e) {
            print('❌ Keep-alive: Error loading SIP user from SharedPreferences: $e');
            // Fallback to Hive
            await _loadSipUserFromHiveAndReregister();
          }
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
        if (_isMainAppActive) {
          print('📱 Health check: Main app active - background in standby');
          if (_backgroundSipHelper?.registered == true) {
            await _backgroundSipHelper!.unregister();
          }
          return;
        }

        if (_backgroundSipHelper?.registered != true && _currentSipUser != null) {
          print('🔄 Health check: Reconnecting background SIP');
          _connectSipInBackground(_currentSipUser!);
        } else {
          print('✅ Health check: Background SIP healthy');
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
    print('📊 Main app active status during update: $_isMainAppActive');

    _currentSipUser = newUser;

    // Only connect if main app is not active
    if (!_isMainAppActive) {
      print('📞 Main app not active - connecting with updated user');
      await _connectSipInBackground(newUser);
    } else {
      print('📱 Main app is active - storing user config but not connecting yet');
      print('📱 Background service will connect when main app goes to background');
    }
  }

  @pragma('vm:entry-point')
  static void _updateServiceNotification(String title, String content) {
    // Log the status update - the foreground notification is handled by flutter_background_service
    // The initial notification is set via AndroidConfiguration and will persist
    print('📱 Service status: $title - $content');

    // We could potentially use the notification plugin to create additional status notifications
    // but for foreground service, the main notification is handled by the service framework
  }

  @pragma('vm:entry-point')
  static Future<void> showIncomingCallNotification({
    required String caller,
    required String callId,
  }) async {
    print('🔔 Checking if notification should be shown for: $caller');

    // CRITICAL: Check if main app is active - if so, NO NOTIFICATION needed!
    try {
      bool mainAppActive = false;

      // Check Hive first
      try {
        final dir = await getApplicationDocumentsDirectory();
        await Hive.initFlutter(dir.path);
        final box = await Hive.openBox('app_data');

        mainAppActive = box.get('main_app_is_active') ?? false;

        // Check if status is recent (within last 2 minutes for calls)
        final timestamp = box.get('main_app_status_timestamp') ?? 0;
        if (timestamp > 0) {
          final lastUpdate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final timeSinceUpdate = DateTime.now().difference(lastUpdate);

          if (timeSinceUpdate.inMinutes > 2) {
            print('⚠️ Main app status outdated for call handling - assuming background');
            mainAppActive = false;
          }
        }

        // DON'T close the box - let the main app manage it
      } catch (hiveError) {
        print('⚠️ Could not check Hive for main app status: $hiveError');
        // Fallback to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        mainAppActive = prefs.getBool('main_app_is_active') ?? false;
      }

      if (mainAppActive) {
        print('📱 Main app appears active, but showing notification anyway for reliability');
        print('📱 Background calls should always have notification fallback');
      } else {
        print('📱 MAIN APP INACTIVE: Proceeding with notification and auto-launch');
      }
    } catch (e) {
      print('⚠️ Could not check main app status: $e - proceeding with notification');
    }

    print('🔔 Showing incoming call notification for: $caller');

    // 🔥🔥 ZERO-TOUCH AUTO-LAUNCH - APP COMES TO FOREGROUND AUTOMATICALLY 🔥🔥
    print('🚀🚀🚀 AUTOMATIC FOREGROUND LAUNCH for incoming call from: $caller (NO USER INTERACTION REQUIRED)');

    // IMMEDIATE LAUNCH: Attempt 1 - Direct auto-launch without notification dependency
    try {
      const platform = MethodChannel('sip_phone/incoming_call');
      await platform.invokeMethod('forceOpenAppForCall', {
        'caller': caller,
        'callId': callId,
        'autoLaunch': true,
        'automaticForeground': true,
        'noUserInteraction': true,
      });
      print('🎉 ZERO-TOUCH: App auto-launched to foreground successfully (attempt 1)');
    } catch (e) {
      print('⚠️ Auto-launch attempt 1 failed: $e');
    }

    // AGGRESSIVE RETRY: Attempt 2 - More aggressive after short delay
    Timer(Duration(milliseconds: 200), () async {
      try {
        const platform = MethodChannel('sip_phone/incoming_call');
        await platform.invokeMethod('forceOpenAppForCall', {
          'caller': caller,
          'callId': callId,
          'autoLaunch': true,
          'automaticForeground': true,
          'noUserInteraction': true,
          'aggressive': true,
          'retry': 2,
        });
        print('🎉 ZERO-TOUCH: App auto-launched to foreground successfully (attempt 2 - aggressive)');
      } catch (e) {
        print('⚠️ Auto-launch attempt 2 failed: $e');
      }
    });

    // SUPER AGGRESSIVE: Attempt 3 - Maximum force after longer delay
    Timer(Duration(milliseconds: 500), () async {
      try {
        const platform = MethodChannel('sip_phone/incoming_call');
        await platform.invokeMethod('forceOpenAppForCall', {
          'caller': caller,
          'callId': callId,
          'autoLaunch': true,
          'automaticForeground': true,
          'noUserInteraction': true,
          'superAggressive': true,
          'retry': 3,
        });
        print('🎉 ZERO-TOUCH: App auto-launched to foreground successfully (attempt 3 - SUPER AGGRESSIVE)');
      } catch (e) {
        print('⚠️ Auto-launch attempt 3 failed: $e');
      }
    });

    // NUCLEAR OPTION: Attempt 4 - Last resort with maximum delay
    Timer(Duration(seconds: 1), () async {
      try {
        const platform = MethodChannel('sip_phone/incoming_call');
        await platform.invokeMethod('forceOpenAppForCall', {
          'caller': caller,
          'callId': callId,
          'autoLaunch': true,
          'automaticForeground': true,
          'noUserInteraction': true,
          'nuclearOption': true,
          'retry': 4,
        });
        print('🎉 ZERO-TOUCH: App auto-launched to foreground successfully (attempt 4 - NUCLEAR)');
      } catch (e) {
        print('⚠️ Auto-launch attempt 4 failed: $e');
      }
    });

    // Start continuous ringing with vibration - async operation
    _startContinuousRinging();

    final androidDetails = AndroidNotificationDetails(
      'incoming_calls_channel',
      'Incoming Calls',
      channelDescription: 'Notifications for incoming SIP calls',
      importance: Importance.max,
      priority: Priority.max, // Changed to max for highest priority
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true, // Show as full screen on lock screen
      ongoing: true, // Cannot be dismissed
      autoCancel: false,
      showWhen: true,
      when: null,
      usesChronometer: false,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000]),
      ticker: 'Incoming call from $caller',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      visibility: NotificationVisibility.public,
      showProgress: false,
      indeterminate: false,
      // Enhanced for screen visibility
      enableLights: true,
      ledColor: const Color.fromARGB(255, 255, 0, 0),
      ledOnMs: 1000,
      ledOffMs: 500,
      timeoutAfter: null, // Never timeout
      groupKey: 'incoming_calls',
      setAsGroupSummary: true,
      onlyAlertOnce: false, // Always alert
      // Add action buttons for Answer/Decline
      actions: [
        AndroidNotificationAction(
          'answer_call',
          '📞 ANSWER',
          titleColor: Color.fromARGB(255, 0, 255, 0),
          icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          contextual: true,
        ),
        AndroidNotificationAction(
          'decline_call',
          '❌ DECLINE',
          titleColor: Color.fromARGB(255, 255, 0, 0),
          icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          contextual: true,
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
      '📞 INCOMING CALL - TAP TO ANSWER',
      '🔥 URGENT: Call from $caller - Tap anywhere to open app and answer',
      notificationDetails,
      payload: 'incoming_call:$callId:$caller',
    );

    print('✅ Incoming call notification displayed');

    // Also try the original method as backup
    try {
      // Use MethodChannel to attempt to launch the app
      const platform = MethodChannel('sip_phone/incoming_call');
      await platform.invokeMethod('launchIncomingCallScreen', {
        'caller': caller,
        'callId': callId,
        'fromBackground': true,
      });
      print('📱 Platform channel call made to launch app');
    } catch (e) {
      print('⚠️ Could not call platform channel: $e');
      // This is expected in background service - notifications will handle app launch
    }
  }

  static Timer? _ringingTimer;

  @pragma('vm:entry-point')
  static void _startContinuousRinging() {
    print('🔔 Starting continuous ringing...');

    // Stop any existing ringing
    _ringingTimer?.cancel();

    // Start ringing immediately and repeat every 2 seconds
    _playRingTone();
    _ringingTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      _playRingTone();
    });
  }

  @pragma('vm:entry-point')
  static void _playRingTone() {
    try {
      // Create strong vibration pattern for ringing
      HapticFeedback.heavyImpact();

      // Double vibration for ring effect
      Timer(Duration(milliseconds: 100), () {
        HapticFeedback.heavyImpact();
      });

      print('🔔 Ring vibration played');
    } catch (e) {
      print('❌ Error playing ringtone: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _stopRinging() {
    print('🔇 Stopping ringing...');
    _ringingTimer?.cancel();
    _ringingTimer = null;
  }

  @pragma('vm:entry-point')
  static Future<void> hideIncomingCallNotification() async {
    _stopRinging(); // Stop ringing when hiding notification
    await _notificationsPlugin.cancel(999);
    print('📱 Incoming call notification hidden');
  }

  @pragma('vm:entry-point')
  static void _stopPersistentService() {
    print('🛑🛑🛑 STOPPING PERSISTENT BACKGROUND SERVICE 🛑🛑🛑');
    print('📊 STOP: Called from: ${StackTrace.current}');
    print('📊 STOP: Service was running: $_isServiceRunning');
    print('📊 STOP: Helper exists: ${_backgroundSipHelper != null}');

    _isServiceRunning = false;
    _keepAliveTimer?.cancel();
    _reconnectionTimer?.cancel();

    try {
      if (_backgroundSipHelper?.registered == true) {
        _backgroundSipHelper?.unregister();
      }
      _backgroundSipHelper?.stop();
      _backgroundSipHelper = null;
      print('🛑 Background SIP helper destroyed');
    } catch (e) {
      print('❌ Error stopping SIP helper: $e');
    }

    print('✅ Persistent service stopped');
  }

  // Public API methods
  @pragma('vm:entry-point')
  static Future<void> startService() async {
    final service = FlutterBackgroundService();

    // Check if service is already running to prevent duplicate starts
    final isRunning = await service.isRunning();
    if (isRunning) {
      print('⚠️ Background service already running - not starting again');
      return;
    }

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
    // Store SIP user data in SharedPreferences for background service access
    // Note: We still need SharedPreferences for cross-isolate communication
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('websocket_sip_user', sipUser.toJsonString());
      await prefs.setBool('should_maintain_websocket_connection', true);
      print('💾 SIP user data stored in SharedPreferences for background service');
    } catch (e) {
      print('❌ Error storing SIP user data in SharedPreferences: $e');
    }

    // Check if service is running before trying to send data to it
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('updateSipUser', {
        'sipUser': sipUser.toJsonString(),
      });
      print('🔄 SIP user update sent to background service');
    } else {
      print('⚠️ Background service not running - cannot send SIP user update');
    }
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
  static void setIncomingCall(Call call) {
    print('📞 Setting incoming call: ${call.remote_identity} (ID: ${call.id})');
    _currentIncomingCall = call;
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
  static void setMainAppActive(bool isActive) {
    final now = DateTime.now();

    // Prevent rapid switching - ignore if the same state was set within last 2 seconds
    if (_lastAppStatusChange != null &&
        _isMainAppActive == isActive &&
        now.difference(_lastAppStatusChange!).inSeconds < 2) {
      print('🚫 Ignoring duplicate app status change to ${isActive ? "ACTIVE" : "BACKGROUND"} (within 2s)');
      return;
    }

    _lastAppStatusChange = now;
    print('📱 Main app status: ${isActive ? "ACTIVE" : "BACKGROUND"}');
    _isMainAppActive = isActive;

    // Save to SharedPreferences asynchronously
    _handleMainAppStatusChange(isActive);

    if (isActive) {
      print('📱 Main app active - unregistering background service');
      _temporarilyUnregisterForMainApp();
    } else {
      print('🔄 Main app backgrounded - re-registering background SIP');
      _reregisterAfterMainAppBackground();
    }
  }

  @pragma('vm:entry-point')
  static void _handleMainAppStatusChange(bool isActive) async {
    try {
      // Update Hive database with main app status
      final dir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(dir.path);
      Box? box;

      try {
        box = Hive.box('app_data');
        if (!box.isOpen) {
          box = await Hive.openBox('app_data');
        }
      } catch (e) {
        // Box might not exist, try to open it
        box = await Hive.openBox('app_data');
      }

      await box.put('main_app_is_active', isActive);
      await box.put('main_app_status_timestamp', DateTime.now().millisecondsSinceEpoch);

      _isMainAppActive = isActive;
      print('💾 Main app status updated in Hive: $isActive');

      // DON'T close the box - let the main app manage it
    } catch (e) {
      print('❌ Error saving main app status to Hive: $e');

      // Fallback to SharedPreferences for backward compatibility
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('main_app_is_active', isActive);
        print('💾 Main app status saved to SharedPreferences as fallback: $isActive');
      } catch (fallbackError) {
        print('❌ Error with SharedPreferences fallback: $fallbackError');
      }
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
            'SIP Phone (Main App Active)', 'Main app handling calls - background service standby');

        print('✅ Background SIP helper temporarily unregistered');
        print('📊 After unregister - Helper exists: ${_backgroundSipHelper != null}');
        print('📊 After unregister - Service running: $_isServiceRunning');
      } else {
        print('⚠️ Background SIP helper not available for unregistering');
        print('📊 Helper exists: ${_backgroundSipHelper != null}');
        print('📊 Helper registered: ${_backgroundSipHelper?.registered}');
      }
    } catch (e) {
      print('❌ Error temporarily unregistering background SIP helper: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _reregisterAfterMainAppBackground() {
    print('🔄 Re-registering background SIP after main app backgrounded');

    // Check if background service is already registered
    if (_backgroundSipHelper != null && _backgroundSipHelper!.registered) {
      print('✅ Background SIP already registered - skipping duplicate registration');
      _updateServiceNotification('SIP Phone Active (Background)', 'Already connected - ready to receive calls');
      return;
    }

    if (_currentSipUser != null && !_isMainAppActive) {
      print('🚀 Starting background SIP connection');
      _connectSipInBackground(_currentSipUser!);
    } else {
      print('⚠️ Cannot re-register: user=${_currentSipUser != null}, mainAppActive=$_isMainAppActive');

      // Try to load SIP user from SharedPreferences if not in memory
      if (_currentSipUser == null && !_isMainAppActive) {
        print('📎 SIP user not in memory - attempting to load from SharedPreferences...');
        _loadSipUserFromPreferencesAndReregister();
      }
    }
  }

  @pragma('vm:entry-point')
  static void _loadSipUserFromPreferencesAndReregister() async {
    try {
      print('📎 Loading SIP user from SharedPreferences for background re-registration...');
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('websocket_sip_user');

      if (savedUserJson != null) {
        _currentSipUser = SipUser.fromJsonString(savedUserJson);
        print('✅ SIP user loaded from SharedPreferences: ${_currentSipUser!.authUser}');

        // Now try to re-register with loaded user
        if (!_isMainAppActive) {
          print('🚀 Starting background SIP connection with loaded user');
          _connectSipInBackground(_currentSipUser!);
        }
      } else {
        print('🔍 No SIP user found in SharedPreferences - trying to load from Hive...');
        await _loadSipUserFromHiveAndReregister();
      }
    } catch (e) {
      print('❌ Error loading SIP user from preferences for re-registration: $e');
      // Fallback to Hive
      await _loadSipUserFromHiveAndReregister();
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _loadSipUserFromHiveForInitialization() async {
    await _loadSipUserFromHive();
  }

  @pragma('vm:entry-point')
  static Future<void> _loadSipUserFromHiveAndReregister() async {
    await _loadSipUserFromHive();

    // Now try to re-register with loaded user
    if (_currentSipUser != null && !_isMainAppActive) {
      print('🚀 Starting background SIP connection with Hive-loaded user');
      _connectSipInBackground(_currentSipUser!);
    }
  }

  @pragma('vm:entry-point')
  static Future<void> _loadSipUserFromHive() async {
    try {
      print('📎 Loading SIP user from Hive...');

      // Initialize Hive in background service isolate
      final dir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(dir.path);
      final box = await Hive.openBox('app_data');

      // Find default credentials
      StoredCredentialsModel? credentials;
      for (final key in box.keys) {
        if (key.toString().startsWith('credentials_')) {
          final data = box.get(key) as Map;
          if (data['isDefault'] == true) {
            credentials = StoredCredentialsModel()
              ..id = data['id']
              ..username = data['username'] ?? ''
              ..password = data['password'] ?? ''
              ..domain = data['domain'] ?? ''
              ..wsUrl = data['wsUrl'] ?? ''
              ..displayName = data['displayName']
              ..isDefault = data['isDefault'] ?? false;
            break;
          }
        }
      }

      // If no default, get most recent
      if (credentials == null) {
        DateTime? mostRecentTime;
        for (final key in box.keys) {
          if (key.toString().startsWith('credentials_')) {
            final data = box.get(key) as Map;
            final updatedAt = DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] ?? 0);
            if (mostRecentTime == null || updatedAt.isAfter(mostRecentTime)) {
              mostRecentTime = updatedAt;
              credentials = StoredCredentialsModel()
                ..id = data['id']
                ..username = data['username'] ?? ''
                ..password = data['password'] ?? ''
                ..domain = data['domain'] ?? ''
                ..wsUrl = data['wsUrl'] ?? ''
                ..displayName = data['displayName']
                ..isDefault = data['isDefault'] ?? false;
            }
          }
        }
      }

      if (credentials != null && credentials.username.isNotEmpty) {
        // Convert to SipUser format
        _currentSipUser = SipUser(
          sipUri: 'sip:${credentials.username}@${credentials.domain}',
          authUser: credentials.username,
          password: credentials.password,
          wsUrl: credentials.wsUrl,
          displayName: credentials.displayName ?? credentials.username,
          port: '5060',
          selectedTransport: TransportType.WS,
        );

        print('✅ SIP user loaded from Hive: ${_currentSipUser!.authUser}');

        // Store in SharedPreferences for future access
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('websocket_sip_user', _currentSipUser!.toJsonString());
        await prefs.setBool('should_maintain_websocket_connection', true);
      } else {
        print('❌ No valid SIP credentials found in Hive');
      }

      // DON'T close the box - let the main app manage it
    } catch (e) {
      print('❌ Error loading SIP user from Hive: $e');
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
  final ServiceInstance? service;

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
        print('📱 Background: Main app status during call: ${PersistentBackgroundService._isMainAppActive}');

        // Store the incoming call reference
        PersistentBackgroundService._currentIncomingCall = call;

        // ALWAYS show notification for background calls - let the notification handler decide
        print('🔔 Background: Showing notification for incoming call regardless of app state');
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
          // Show enhanced notification to open app for incoming calls
          PersistentBackgroundService.showIncomingCallNotification(
            caller: caller,
            callId: call.id ?? 'unknown',
          );
        }

        // Auto-answer after 15 seconds ONLY if main app is NOT active
        // If main app is active, let user manually accept/decline
        Timer(Duration(seconds: 15), () {
          // Check if main app is active first
          if (PersistentBackgroundService._isMainAppActive) {
            print('📱 Main app is active - NOT auto-answering (user should handle manually)');
            return;
          }

          if (call.state == CallStateEnum.CALL_INITIATION || call.state == CallStateEnum.PROGRESS) {
            print('⏰ Background: Checking if call needs auto-answer (app is closed)');
            print('📊 Background: Call state is still ${call.state}');

            try {
              // Check if call is still valid before answering
              if (call.state == CallStateEnum.CALL_INITIATION || call.state == CallStateEnum.PROGRESS) {
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
                  'Call Auto-Answered', 'Active call with $caller - tap app to access controls');

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

        // CRITICAL: Ensure SIP registration is maintained after call ends
        print('🔄 Checking SIP registration status after call ended...');
        Future.delayed(Duration(seconds: 2), () {
          if (PersistentBackgroundService._backgroundSipHelper != null) {
            final isRegistered = PersistentBackgroundService._backgroundSipHelper!.registered;
            print('📊 SIP Registration status after call: $isRegistered');

            if (!isRegistered && !PersistentBackgroundService._isMainAppActive) {
              print('⚠️ SIP not registered after call - attempting re-registration');
              if (PersistentBackgroundService._currentSipUser != null) {
                PersistentBackgroundService._connectSipInBackground(PersistentBackgroundService._currentSipUser!);
              } else {
                print('❌ No SIP user available for re-registration');
              }
            } else {
              print('✅ SIP registration maintained after call');
            }
          }
        });
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
            'SIP Phone Active', 'Connected and ready to receive calls');
        break;

      case RegistrationStateEnum.REGISTRATION_FAILED:
        print('❌ Background: SIP registration failed');
        PersistentBackgroundService._updateServiceNotification('SIP Phone Error', 'Registration failed - retrying...');
        break;

      case RegistrationStateEnum.UNREGISTERED:
        print('⚠️ Background: SIP unregistered');
        PersistentBackgroundService._updateServiceNotification(
            'SIP Phone Disconnected', 'Connection lost - reconnecting...');
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
          'SIP Phone Reconnecting', 'Network connection lost - reconnecting...');
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
