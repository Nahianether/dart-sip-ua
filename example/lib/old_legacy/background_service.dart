import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_state/sip_user.dart';

@pragma('vm:entry-point')
class BackgroundService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Initialize notifications
    await _initializeNotifications();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'sip_background_service',
        initialNotificationTitle: 'SIP Service',
        initialNotificationContent: 'SIP service is running in background',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    
    print('Background service started');
    
    // DO NOT initialize SIP here - let ConnectionManager handle it
    // The main app's ConnectionManager will maintain the persistent connection
    print('Background service: SIP connection managed by main app');

    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  @pragma('vm:entry-point')
  static Future<void> _initializeSipInBackground(ServiceInstance service) async {
    try {
      print('Initializing SIP connection in background...');
      
      // Load saved SIP user configuration
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('registered_sip_user');
      final isRegistered = prefs.getBool('is_registered') ?? false;
      
      if (savedUserJson == null || !isRegistered) {
        print('Background service: No saved SIP user found');
        return;
      }
      
      final sipUser = SipUser.fromJsonString(savedUserJson);
      print('Background service: Loading SIP user ${sipUser.authUser}');
      
      // Create SIP helper for background
      final sipHelper = SIPUAHelper();
      final backgroundListener = BackgroundSipListener(service);
      sipHelper.addSipUaHelperListener(backgroundListener);
      
      // Configure SIP settings
      await _registerSipInBackground(sipHelper, sipUser);
      
      print('Background SIP service initialized successfully');
      
      // Monitor service status and maintain connection
      Timer.periodic(Duration(minutes: 2), (timer) async {
        try {
          if (!sipHelper.registered) {
            print('Background service: Connection lost, attempting reconnection...');
            await _registerSipInBackground(sipHelper, sipUser);
          } else {
            print('Background service health check: Connected and registered');
          }
        } catch (e) {
          print('Background service health check error: $e');
        }
      });
      
    } catch (e) {
      print('Error initializing SIP in background: $e');
    }
  }
  
  @pragma('vm:entry-point')
  static Future<void> _registerSipInBackground(SIPUAHelper sipHelper, SipUser user) async {
    try {
      UaSettings settings = UaSettings();
      
      // Parse SIP URI
      String sipUri = user.sipUri ?? '';
      String username = user.authUser;
      String domain = '';
      
      if (sipUri.contains('@')) {
        final parts = sipUri.split('@');
        if (parts.length > 1) {
          username = parts[0].replaceAll('sip:', '');
          domain = parts[1];
        }
      }
      
      String properSipUri = 'sip:$username@$domain';
      
      // Configure settings
      settings.webSocketUrl = user.wsUrl ?? '';
      settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
      settings.webSocketSettings.allowBadCertificate = true;
      settings.tcpSocketSettings.allowBadCertificate = true;
      settings.transportType = user.selectedTransport;
      settings.uri = properSipUri;
      settings.host = domain;
      settings.registrarServer = domain;
      settings.realm = null;
      settings.authorizationUser = username;
      settings.password = user.password;
      settings.displayName = user.displayName;
      settings.userAgent = 'Flutter SIP Client Background v1.0.0';
      settings.dtmfMode = DtmfMode.RFC2833;
      settings.register = true;
      settings.register_expires = 300;
      settings.contact_uri = null;
      
      if (user.selectedTransport != TransportType.WS && user.port.isNotEmpty) {
        settings.port = user.port;
      }
      
      print('Background service: Starting SIP with ${settings.uri} via ${settings.webSocketUrl}');
      await sipHelper.start(settings);
      
    } catch (e) {
      print('Background SIP registration error: $e');
    }
  }

  @pragma('vm:entry-point')
  static Future<void> showIncomingCallNotification(String caller) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'incoming_calls',
      'Incoming Calls',
      channelDescription: 'Notifications for incoming calls',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
    );

    const DarwinNotificationDetails iosPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iosPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      999,
      'Incoming Call',
      'Call from $caller',
      platformChannelSpecifics,
    );
  }

  @pragma('vm:entry-point')
  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    await service.startService();
  }

  @pragma('vm:entry-point')
  static Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }
}

class BackgroundSipListener implements SipUaHelperListener {
  final ServiceInstance service;

  BackgroundSipListener(this.service);

  @override
  void callStateChanged(Call call, CallState state) {
    print('Background: Call state changed to ${state.state}');
    
    if (state.state == CallStateEnum.CALL_INITIATION) {
      // Show incoming call notification
      final caller = call.remote_identity ?? 'Unknown';
      BackgroundService.showIncomingCallNotification(caller);
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    print('Background: Registration state changed to ${state.state}');
    
    // Service notification will be handled by the service itself
    print('Background: Registration state updated');
  }

  @override
  void transportStateChanged(TransportState state) {
    print('Background: Transport state changed to ${state.state}');
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    print('Background: New SIP message received');
  }

  @override
  void onNewNotify(Notify ntf) {
    print('Background: New SIP notify received');
  }

  @override
  void onNewReinvite(ReInvite event) {
    print('Background: New SIP re-invite received');
  }
}