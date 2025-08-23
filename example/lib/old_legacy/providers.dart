import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sip_ua/sip_ua.dart';
// import 'user_state/sip_user_cubit.dart'; // Unused import removed

// Legacy provider stubs for old files to compile without errors
// These are not actively used in the main app

final textControllerProvider = Provider<TextEditingController>((ref) => TextEditingController());
final destinationProvider = StateProvider<String>((ref) => '');
final receivedMessageProvider = StateProvider<String?>((ref) => null);

// Port controller providers
final portControllerProvider = Provider<TextEditingController>((ref) => TextEditingController());
final wsUriControllerProvider = Provider<TextEditingController>((ref) => TextEditingController());
final sipUriControllerProvider = Provider<TextEditingController>((ref) => TextEditingController());
final displayNameControllerProvider = Provider<TextEditingController>((ref) => TextEditingController());
final passwordControllerProvider = Provider<TextEditingController>((ref) => TextEditingController());
final authorizationUserControllerProvider = Provider<TextEditingController>((ref) => TextEditingController());

// State providers
final passwordVisibilityProvider = StateProvider<bool>((ref) => false);
final transportTypeProvider = StateProvider<TransportType>((ref) => TransportType.WS);
final registrationStateProvider = StateProvider<RegistrationStateEnum>((ref) => RegistrationStateEnum.UNREGISTERED);

// SIP Helper provider (stub)
final sipHelperProvider = Provider<SIPUAHelper>((ref) => SIPUAHelper());

// SIP User Cubit provider (stub) - returns a mock that has state property
final sipUserCubitProvider = Provider<MockSipUserCubit>((ref) => MockSipUserCubit());

// Theme provider (stub)  
final themeNotifierProvider = Provider<ThemeNotifier>((ref) => throw UnimplementedError('Legacy provider stub'));

// Stub theme notifier class
class ThemeNotifier {
  void setDarkmode() {}
  void setLightMode() {}
}

// Mock SipUserCubit class with state property
class MockSipUserCubit {
  MockSipUser? get state => null;
  bool get isRegistered => false;
  void register(dynamic user) {}
  Future<void> disconnect() async {}
  Future<void> forceReconnect() async {}
}

// Mock SipUser class for the MockSipUserCubit
class MockSipUser {
  String? get authUser => null;
}