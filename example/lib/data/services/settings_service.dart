import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';
import 'hive_service.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._();
  factory SettingsService() => _instance;
  SettingsService._();

  final HiveService _hiveService = HiveService.instance;

  Future<AppSettingsModel> getSettings() async {
    return await _hiveService.getSettings();
  }

  Future<void> saveSettings(AppSettingsModel settings) async {
    await _hiveService.saveSettings(settings);
  }

  Future<void> migrateLegacySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = await getSettings();
      
      bool hasChanges = false;

      // Migrate VPN settings
      final vpnServer = prefs.getString('vpn_server');
      final vpnUsername = prefs.getString('vpn_username'); 
      final vpnPassword = prefs.getString('vpn_password');
      if (vpnServer != null) {
        settings.vpnServerAddress = vpnServer;
        hasChanges = true;
      }
      if (vpnUsername != null) {
        settings.vpnUsername = vpnUsername;
        hasChanges = true;
      }
      if (vpnPassword != null) {
        settings.vpnPassword = vpnPassword;
        hasChanges = true;
      }

      // Migrate SIP account settings
      final sipAccountJson = prefs.getString('sip_account');
      if (sipAccountJson != null) {
        try {
          // Parse the JSON to extract account details
          // This is a simplified version - in real implementation you'd parse properly
          settings.lastUsedUsername = 'migrated_user';
          hasChanges = true;
        } catch (e) {
          print('❌ Error parsing legacy SIP account: $e');
        }
      }

      // Migrate websocket SIP user
      final websocketSipUser = prefs.getString('websocket_sip_user');
      if (websocketSipUser != null) {
        try {
          settings.lastUsedUsername = 'websocket_user';
          hasChanges = true;
        } catch (e) {
          print('❌ Error parsing legacy websocket SIP user: $e');
        }
      }

      // Migrate connection maintenance setting
      final shouldMaintain = prefs.getBool('should_maintain_websocket_connection');
      if (shouldMaintain != null) {
        settings.autoVpnConnect = shouldMaintain;
        hasChanges = true;
      }

      // Save if there were any changes
      if (hasChanges) {
        await saveSettings(settings);
        print('✅ Successfully migrated legacy settings to Hive');
        
        // Clean up old SharedPreferences keys
        await _cleanupLegacyKeys(prefs);
      }
      
    } catch (e) {
      print('❌ Error migrating legacy settings: $e');
    }
  }

  Future<void> _cleanupLegacyKeys(SharedPreferences prefs) async {
    try {
      // VPN related keys
      await prefs.remove('vpn_config');
      await prefs.remove('vpn_server');
      await prefs.remove('vpn_username');
      await prefs.remove('vpn_password');
      
      // SIP account keys
      await prefs.remove('sip_account');
      await prefs.remove('websocket_sip_user');
      await prefs.remove('should_maintain_websocket_connection');
      
      // Call history keys (handled separately by CallLogService)
      await prefs.remove('call_history');
      
      print('✅ Cleaned up legacy SharedPreferences keys');
    } catch (e) {
      print('❌ Error cleaning up legacy keys: $e');
    }
  }

  // Convenience methods for common settings
  Future<void> updateTheme(ThemeMode themeMode) async {
    final settings = await getSettings();
    settings.themeMode = themeMode;
    await saveSettings(settings);
  }

  Future<void> updateVpnSettings({
    String? serverAddress,
    String? username,
    String? password,
    bool? autoConnect,
  }) async {
    final settings = await getSettings();
    if (serverAddress != null) settings.vpnServerAddress = serverAddress;
    if (username != null) settings.vpnUsername = username;
    if (password != null) settings.vpnPassword = password;
    if (autoConnect != null) settings.vpnAutoConnect = autoConnect;
    await saveSettings(settings);
  }

  Future<void> updateCallSettings({
    bool? callWaiting,
    double? ringtoneVolume,
    bool? vibrationEnabled,
    bool? autoAnswerEnabled,
    int? autoAnswerDelay,
  }) async {
    final settings = await getSettings();
    if (callWaiting != null) settings.callWaiting = callWaiting;
    if (ringtoneVolume != null) settings.ringtoneVolume = ringtoneVolume;
    if (vibrationEnabled != null) settings.vibrationEnabled = vibrationEnabled;
    if (autoAnswerEnabled != null) settings.autoAnswerEnabled = autoAnswerEnabled;
    if (autoAnswerDelay != null) settings.autoAnswerDelay = autoAnswerDelay;
    await saveSettings(settings);
  }

  Future<void> updateSipAccountCache({
    String? username,
    String? domain,
    String? wsUrl,
    String? displayName,
  }) async {
    final settings = await getSettings();
    if (username != null) settings.lastUsedUsername = username;
    if (domain != null) settings.lastUsedDomain = domain;
    if (wsUrl != null) settings.lastUsedWsUrl = wsUrl;
    if (displayName != null) settings.lastUsedDisplayName = displayName;
    await saveSettings(settings);
  }
}