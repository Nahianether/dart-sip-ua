import '../models/stored_credentials_model.dart';
import '../../domain/entities/sip_account_entity.dart';
import 'hive_service.dart';
import 'settings_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final HiveService _hiveService = HiveService.instance;
  final SettingsService _settingsService = SettingsService();

  /// Save login credentials securely in Isar
  Future<void> saveLoginCredentials(SipAccountEntity account) async {
    try {
      // Save to Isar database (without password for security)
      final storedCredentials = StoredCredentialsModel.fromEntity(account);
      storedCredentials.isDefault = true; // Mark as default

      await _hiveService.saveCredentials(storedCredentials);

      // Also update settings for backward compatibility
      final settings = await _settingsService.getSettings();
      settings.lastUsedUsername = account.username;
      settings.lastUsedDomain = account.domain;
      settings.lastUsedWsUrl = account.wsUrl;
      settings.lastUsedDisplayName = account.displayName;

      await _settingsService.saveSettings(settings);
      print('✅ Login credentials saved successfully');
    } catch (e) {
      print('❌ Error saving login credentials: $e');
      throw Exception('Failed to save login credentials');
    }
  }

  /// Get saved login credentials
  Future<SipAccountEntity?> getSavedCredentials() async {
    try {
      // First try to get from Isar database
      final storedCredentials = await _hiveService.getDefaultCredentials();
      if (storedCredentials != null) {
        return storedCredentials.toEntity();
      }

      // Fallback to settings for backward compatibility
      final settings = await _settingsService.getSettings();

      if (settings.lastUsedUsername != null && settings.lastUsedDomain != null && settings.lastUsedWsUrl != null) {
        return SipAccountEntity(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          username: settings.lastUsedUsername!,
          password: '', // Don't store password for security
          domain: settings.lastUsedDomain!,
          wsUrl: settings.lastUsedWsUrl!,
          displayName: settings.lastUsedDisplayName ?? settings.lastUsedUsername!,
        );
      }

      return null;
    } catch (e) {
      print('❌ Error retrieving saved credentials: $e');
      return null;
    }
  }

  /// Check if user has saved login credentials
  Future<bool> hasValidSession() async {
    final credentials = await getSavedCredentials();
    return credentials != null;
  }

  /// Clear saved login credentials (logout)
  Future<void> clearCredentials() async {
    try {
      // Clear from Isar database
      await _hiveService.clearAllCredentials();

      // Clear from settings for backward compatibility
      final settings = await _settingsService.getSettings();
      settings.lastUsedUsername = null;
      settings.lastUsedDomain = null;
      settings.lastUsedWsUrl = null;
      settings.lastUsedDisplayName = null;

      await _settingsService.saveSettings(settings);
      print('✅ Login credentials cleared');
    } catch (e) {
      print('❌ Error clearing credentials: $e');
      throw Exception('Failed to clear credentials');
    }
  }

  /// Validate login form
  String? validateUsername(String? value) {
    if (value == null || value.isEmpty) {
      return 'Username is required';
    }
    if (value.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
      return 'Username can only contain letters, numbers, dots, hyphens, and underscores';
    }
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? validateDomain(String? value) {
    if (value == null || value.isEmpty) {
      return 'Domain is required';
    }
    return null;
  }

  String? validateWsUrl(String? value) {
    if (value == null || value.isEmpty) {
      return 'WebSocket URL is required';
    }
    if (!value.startsWith('wss://') && !value.startsWith('ws://')) {
      return 'WebSocket URL must start with ws:// or wss://';
    }
    try {
      final uri = Uri.parse(value);
      // Check if it has a valid host
      if (uri.host.isEmpty) {
        return 'Please enter a valid WebSocket URL with a host';
      }
    } catch (e) {
      return 'Please enter a valid WebSocket URL';
    }
    return null;
  }

  String? validateDisplayName(String? value) {
    if (value != null && value.isNotEmpty && value.length < 2) {
      return 'Display name must be at least 2 characters';
    }
    return null;
  }
}
