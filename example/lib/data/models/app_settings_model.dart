import 'package:flutter/material.dart';

class AppSettingsModel {
  static const int settingsId = 1;
  
  String? id = settingsId.toString();

  // Appearance
  ThemeMode? themeMode = ThemeMode.system;
  
  // Audio & Call Settings
  double? ringtoneVolume = 1.0;
  bool? vibrationEnabled = true;
  bool? autoAnswerEnabled = false;
  int? autoAnswerDelay = 3; // seconds
  bool? callWaiting = true;
  
  // VPN Settings
  String? vpnServerAddress;
  String? vpnUsername;
  String? vpnPassword;
  bool? vpnAutoConnect = false;
  bool? autoVpnConnect = false; // Legacy support
  
  // SIP Account Cache (for auto-fill)
  String? lastUsedUsername;
  String? lastUsedDomain;
  String? lastUsedWsUrl;
  String? lastUsedDisplayName;

  AppSettingsModel();
}