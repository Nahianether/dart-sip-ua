import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/call_log_model.dart';
import '../models/contact_model.dart';
import '../models/app_settings_model.dart';
import '../models/stored_credentials_model.dart';

class HiveService {
  static HiveService? _instance;
  static Box? _dataBox;

  HiveService._();

  static HiveService get instance {
    _instance ??= HiveService._();
    return _instance!;
  }

  static Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);
    
    _dataBox = await Hive.openBox('app_data');
  }

  // Call Log operations - using simple Map storage
  Future<void> saveCallLog(CallLogModel callLog) async {
    final box = _dataBox!;
    final key = 'call_log_${callLog.callId}';
    
    final data = {
      'callId': callLog.callId,
      'phoneNumber': callLog.phoneNumber,
      'contactName': callLog.contactName,
      'direction': callLog.direction.index,
      'type': callLog.type.index,
      'status': callLog.status.index,
      'startTime': callLog.startTime.millisecondsSinceEpoch,
      'endTime': callLog.endTime?.millisecondsSinceEpoch,
      'duration': callLog.duration,
      'missed': callLog.missed,
      'isRead': callLog.isRead,
    };
    
    await box.put(key, data);
  }

  Future<List<CallLogModel>> getCallLogs({int limit = 50}) async {
    final box = _dataBox!;
    final logs = <CallLogModel>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('call_log_')) {
        final data = box.get(key) as Map;
        final log = _mapToCallLog(data);
        logs.add(log);
      }
    }
    
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    return logs.take(limit).toList();
  }

  Future<List<CallLogModel>> getCallLogsByNumber(String phoneNumber) async {
    final box = _dataBox!;
    final logs = <CallLogModel>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('call_log_')) {
        final data = box.get(key) as Map;
        if (data['phoneNumber'] == phoneNumber) {
          final log = _mapToCallLog(data);
          logs.add(log);
        }
      }
    }
    
    logs.sort((a, b) => b.startTime.compareTo(a.startTime));
    return logs;
  }

  Future<void> deleteOldCallLogs(int maxDays) async {
    final box = _dataBox!;
    final cutoffDate = DateTime.now().subtract(Duration(days: maxDays));
    final keysToDelete = <String>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('call_log_')) {
        final data = box.get(key) as Map;
        final startTime = DateTime.fromMillisecondsSinceEpoch(data['startTime']);
        if (startTime.isBefore(cutoffDate)) {
          keysToDelete.add(key.toString());
        }
      }
    }
    
    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  Future<void> clearAllCallLogs() async {
    final box = _dataBox!;
    final keysToDelete = <String>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('call_log_')) {
        keysToDelete.add(key.toString());
      }
    }
    
    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  // Contact operations - simplified
  Future<void> saveContact(ContactModel contact) async {
    final box = _dataBox!;
    final key = 'contact_${contact.phoneNumber}';
    
    final data = {
      'displayName': contact.displayName,
      'firstName': contact.firstName,
      'lastName': contact.lastName,
      'phoneNumber': contact.phoneNumber,
      'email': contact.email,
      'company': contact.company,
    };
    
    await box.put(key, data);
  }

  Future<void> saveContacts(List<ContactModel> contacts) async {
    for (final contact in contacts) {
      await saveContact(contact);
    }
  }

  Future<List<ContactModel>> getAllContacts() async {
    final box = _dataBox!;
    final contacts = <ContactModel>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('contact_')) {
        final data = box.get(key) as Map;
        final contact = _mapToContact(data);
        contacts.add(contact);
      }
    }
    
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    return contacts;
  }

  Future<List<ContactModel>> searchContacts(String query) async {
    final box = _dataBox!;
    final contacts = <ContactModel>[];
    final lowerQuery = query.toLowerCase();
    
    for (final key in box.keys) {
      if (key.toString().startsWith('contact_')) {
        final data = box.get(key) as Map;
        final displayName = data['displayName']?.toString().toLowerCase() ?? '';
        final phoneNumber = data['phoneNumber']?.toString() ?? '';
        
        if (displayName.contains(lowerQuery) || phoneNumber.contains(query)) {
          final contact = _mapToContact(data);
          contacts.add(contact);
        }
      }
    }
    
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    return contacts;
  }

  Future<ContactModel?> getContactByPhone(String phoneNumber) async {
    final box = _dataBox!;
    final data = box.get('contact_$phoneNumber');
    if (data != null) {
      return _mapToContact(data as Map);
    }
    return null;
  }

  Future<void> clearAllContacts() async {
    final box = _dataBox!;
    final keysToDelete = <String>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('contact_')) {
        keysToDelete.add(key.toString());
      }
    }
    
    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  // Settings operations - simple storage
  Future<AppSettingsModel> getSettings() async {
    final box = _dataBox!;
    final data = box.get('app_settings');
    
    if (data == null) {
      final settings = AppSettingsModel();
      await saveSettings(settings);
      return settings;
    }
    
    return _mapToSettings(data as Map);
  }

  Future<void> saveSettings(AppSettingsModel settings) async {
    final box = _dataBox!;
    final data = {
      'themeMode': settings.themeMode?.index,
      'ringtoneVolume': settings.ringtoneVolume,
      'vibrationEnabled': settings.vibrationEnabled,
      'autoAnswerEnabled': settings.autoAnswerEnabled,
      'autoAnswerDelay': settings.autoAnswerDelay,
      'callWaiting': settings.callWaiting,
      'vpnServerAddress': settings.vpnServerAddress,
      'vpnUsername': settings.vpnUsername,
      'vpnPassword': settings.vpnPassword,
      'vpnAutoConnect': settings.vpnAutoConnect,
      'autoVpnConnect': settings.autoVpnConnect,
      'lastUsedUsername': settings.lastUsedUsername,
      'lastUsedDomain': settings.lastUsedDomain,
      'lastUsedWsUrl': settings.lastUsedWsUrl,
      'lastUsedDisplayName': settings.lastUsedDisplayName,
    };
    
    await box.put('app_settings', data);
  }

  // Utility methods
  Future<void> closeDatabase() async {
    await _dataBox?.close();
  }

  Future<int> getCallLogCount() async {
    final box = _dataBox!;
    int count = 0;
    for (final key in box.keys) {
      if (key.toString().startsWith('call_log_')) {
        count++;
      }
    }
    return count;
  }

  Future<int> getContactCount() async {
    final box = _dataBox!;
    int count = 0;
    for (final key in box.keys) {
      if (key.toString().startsWith('contact_')) {
        count++;
      }
    }
    return count;
  }

  // Credentials operations - simplified
  Future<void> saveCredentials(StoredCredentialsModel credentials) async {
    final box = _dataBox!;
    
    // Clear previous default if this is set as default
    if (credentials.isDefault) {
      for (final key in box.keys) {
        if (key.toString().startsWith('credentials_')) {
          final data = box.get(key) as Map;
          if (data['id'] != credentials.id) {
            data['isDefault'] = false;
            await box.put(key, data);
          }
        }
      }
    }
    
    final key = 'credentials_${credentials.id ?? DateTime.now().millisecondsSinceEpoch}';
    final data = {
      'id': credentials.id,
      'username': credentials.username,
      'password': credentials.password, // Now saving password for auto-login
      'domain': credentials.domain,
      'wsUrl': credentials.wsUrl,
      'displayName': credentials.displayName,
      'isDefault': credentials.isDefault,
      'createdAt': credentials.createdAt.millisecondsSinceEpoch,
      'updatedAt': credentials.updatedAt.millisecondsSinceEpoch,
    };
    
    await box.put(key, data);
    print('✅ Credentials saved to Hive: ${credentials.username}@${credentials.domain}');
  }

  Future<StoredCredentialsModel?> getDefaultCredentials() async {
    final box = _dataBox!;
    
    // First try to get default credentials
    for (final key in box.keys) {
      if (key.toString().startsWith('credentials_')) {
        final data = box.get(key) as Map;
        if (data['isDefault'] == true) {
          return _mapToCredentials(data);
        }
      }
    }
    
    // If no default, get the most recently used
    StoredCredentialsModel? mostRecent;
    DateTime? mostRecentTime;
    
    for (final key in box.keys) {
      if (key.toString().startsWith('credentials_')) {
        final data = box.get(key) as Map;
        final updatedAt = DateTime.fromMillisecondsSinceEpoch(data['updatedAt']);
        if (mostRecentTime == null || updatedAt.isAfter(mostRecentTime)) {
          mostRecentTime = updatedAt;
          mostRecent = _mapToCredentials(data);
        }
      }
    }
    
    return mostRecent;
  }

  Future<List<StoredCredentialsModel>> getAllCredentials() async {
    final box = _dataBox!;
    final credentials = <StoredCredentialsModel>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('credentials_')) {
        final data = box.get(key) as Map;
        final cred = _mapToCredentials(data);
        credentials.add(cred);
      }
    }
    
    credentials.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return credentials;
  }

  Future<void> updateCredentials(StoredCredentialsModel credentials) async {
    credentials.updatedAt = DateTime.now();
    await saveCredentials(credentials);
    print('✅ Credentials updated in Hive: ${credentials.username}@${credentials.domain}');
  }

  Future<void> deleteCredentials(String id) async {
    final box = _dataBox!;
    
    for (final key in box.keys) {
      if (key.toString().startsWith('credentials_')) {
        final data = box.get(key) as Map;
        if (data['id'] == id) {
          await box.delete(key);
          print('✅ Credentials deleted from Hive');
          return;
        }
      }
    }
  }

  Future<void> clearAllCredentials() async {
    final box = _dataBox!;
    final keysToDelete = <String>[];
    
    for (final key in box.keys) {
      if (key.toString().startsWith('credentials_')) {
        keysToDelete.add(key.toString());
      }
    }
    
    for (final key in keysToDelete) {
      await box.delete(key);
    }
    
    print('✅ All credentials cleared from Hive');
  }

  Future<bool> credentialsExist(String username, String domain) async {
    final box = _dataBox!;
    
    for (final key in box.keys) {
      if (key.toString().startsWith('credentials_')) {
        final data = box.get(key) as Map;
        if (data['username'] == username && data['domain'] == domain) {
          return true;
        }
      }
    }
    
    return false;
  }

  // Helper methods to convert Maps to Models
  CallLogModel _mapToCallLog(Map data) {
    final log = CallLogModel()
      ..callId = data['callId']
      ..phoneNumber = data['phoneNumber']
      ..contactName = data['contactName']
      ..direction = CallDirection.values[data['direction']]
      ..type = CallType.values[data['type']]
      ..status = CallStatus.values[data['status']]
      ..startTime = DateTime.fromMillisecondsSinceEpoch(data['startTime'])
      ..duration = data['duration']
      ..missed = data['missed'] ?? false
      ..isRead = data['isRead'] ?? false;
    
    if (data['endTime'] != null) {
      log.endTime = DateTime.fromMillisecondsSinceEpoch(data['endTime']);
    }
    
    return log;
  }

  ContactModel _mapToContact(Map data) {
    return ContactModel()
      ..displayName = data['displayName'] ?? ''
      ..firstName = data['firstName']
      ..lastName = data['lastName']
      ..phoneNumber = data['phoneNumber'] ?? ''
      ..email = data['email']
      ..company = data['company'];
  }

  AppSettingsModel _mapToSettings(Map data) {
    final settings = AppSettingsModel();
    
    if (data['themeMode'] != null) {
      settings.themeMode = ThemeMode.values[data['themeMode']];
    }
    settings.ringtoneVolume = data['ringtoneVolume']?.toDouble();
    settings.vibrationEnabled = data['vibrationEnabled'];
    settings.autoAnswerEnabled = data['autoAnswerEnabled'];
    settings.autoAnswerDelay = data['autoAnswerDelay'];
    settings.callWaiting = data['callWaiting'];
    settings.vpnServerAddress = data['vpnServerAddress'];
    settings.vpnUsername = data['vpnUsername'];
    settings.vpnPassword = data['vpnPassword'];
    settings.vpnAutoConnect = data['vpnAutoConnect'];
    settings.autoVpnConnect = data['autoVpnConnect'];
    settings.lastUsedUsername = data['lastUsedUsername'];
    settings.lastUsedDomain = data['lastUsedDomain'];
    settings.lastUsedWsUrl = data['lastUsedWsUrl'];
    settings.lastUsedDisplayName = data['lastUsedDisplayName'];
    
    return settings;
  }

  StoredCredentialsModel _mapToCredentials(Map data) {
    return StoredCredentialsModel()
      ..id = data['id']
      ..username = data['username'] ?? ''
      ..password = data['password'] ?? '' // Now reading password from storage
      ..domain = data['domain'] ?? ''
      ..wsUrl = data['wsUrl'] ?? ''
      ..displayName = data['displayName']
      ..isDefault = data['isDefault'] ?? false
      ..createdAt = DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch)
      ..updatedAt = DateTime.fromMillisecondsSinceEpoch(data['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch);
  }
}