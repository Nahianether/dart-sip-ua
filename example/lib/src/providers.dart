import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sip_ua/sip_ua.dart';
import 'theme_provider.dart';
import 'user_state/sip_user_cubit.dart';

// SIP Helper Provider
final sipHelperProvider = Provider<SIPUAHelper>((ref) {
  return SIPUAHelper();
});

// Theme Provider
final themeNotifierProvider = ChangeNotifierProvider<ThemeProvider>((ref) {
  return ThemeProvider();
});

// SIP User Cubit Provider
final sipUserCubitProvider = Provider<SipUserCubit>((ref) {
  final sipHelper = ref.watch(sipHelperProvider);
  return SipUserCubit(sipHelper: sipHelper);
});

// Registration state provider
final registrationStateProvider = StateProvider<RegistrationState?>((ref) {
  return null;
});

// Password visibility provider
final passwordVisibilityProvider = StateProvider<bool>((ref) {
  return false;
});

// Text editing controllers providers
final passwordControllerProvider = Provider<TextEditingController>((ref) {
  return TextEditingController();
});

final portControllerProvider = Provider<TextEditingController>((ref) {
  return TextEditingController();
});

final wsUriControllerProvider = Provider<TextEditingController>((ref) {
  return TextEditingController();
});

final sipUriControllerProvider = Provider<TextEditingController>((ref) {
  return TextEditingController();
});

final displayNameControllerProvider = Provider<TextEditingController>((ref) {
  return TextEditingController();
});

final authorizationUserControllerProvider = Provider<TextEditingController>((ref) {
  return TextEditingController();
});

final textControllerProvider = Provider<TextEditingController>((ref) {
  return TextEditingController();
});

// Transport type provider
final transportTypeProvider = StateProvider<TransportType>((ref) {
  return TransportType.TCP;
});

// Destination provider
final destinationProvider = StateProvider<String>((ref) {
  return '';
});

// Received message provider
final receivedMessageProvider = StateProvider<String?>((ref) {
  return null;
});