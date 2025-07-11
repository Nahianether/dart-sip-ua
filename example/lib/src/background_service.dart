import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'user_state/sip_user.dart';

class BackgroundService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

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
    
    // Initialize SIP in background
    await _initializeSipInBackground(service);

    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  static Future<void> _initializeSipInBackground(ServiceInstance service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserJson = prefs.getString('registered_sip_user');
      final isRegistered = prefs.getBool('is_registered') ?? false;

      if (savedUserJson != null && isRegistered) {
        final sipUser = SipUser.fromJsonString(savedUserJson);
        
        // Create SIP helper for background
        final sipHelper = SIPUAHelper();
        
        // Configure SIP settings
        UaSettings settings = UaSettings();
        
        // Parse SIP URI
        String sipUri = sipUser.sipUri ?? '';
        String username = sipUser.authUser;
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
        settings.webSocketUrl = sipUser.wsUrl ?? '';
        settings.webSocketSettings.extraHeaders = sipUser.wsExtraHeaders ?? {};
        settings.webSocketSettings.allowBadCertificate = true;
        settings.tcpSocketSettings.allowBadCertificate = true;
        settings.transportType = sipUser.selectedTransport;
        settings.uri = properSipUri;
        settings.host = domain;
        settings.registrarServer = domain;
        settings.realm = null;
        settings.authorizationUser = username;
        settings.password = sipUser.password;
        settings.displayName = sipUser.displayName;
        settings.userAgent = 'JsSIP 3.10.0';
        settings.dtmfMode = DtmfMode.RFC2833;
        settings.register = true;
        settings.register_expires = 600;
        settings.contact_uri = null;
        
        // Add listener for incoming calls
        sipHelper.addSipUaHelperListener(BackgroundSipListener(service));
        
        // Start SIP helper
        await sipHelper.start(settings);
        
        print('SIP service initialized in background');
      }
    } catch (e) {
      print('Error initializing SIP in background: $e');
    }
  }

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

  static Future<void> startService() async {
    final service = FlutterBackgroundService();
    await service.startService();
  }

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