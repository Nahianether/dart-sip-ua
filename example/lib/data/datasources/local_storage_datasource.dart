import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sip_account_model.dart';
import '../models/call_model.dart';

abstract class LocalStorageDataSource {
  Future<void> saveAccount(SipAccountModel account);
  Future<SipAccountModel?> getAccount();
  Future<void> deleteAccount();
  
  Future<void> saveCallRecord(CallModel call);
  Future<List<CallModel>> getCallHistory();
  Future<void> clearCallHistory();
  
  Future<void> saveSetting(String key, dynamic value);
  Future<T?> getSetting<T>(String key);
  Future<void> deleteSetting(String key);
}

class SharedPreferencesDataSource implements LocalStorageDataSource {
  static const String _accountKey = 'sip_account';
  static const String _callHistoryKey = 'call_history';
  
  @override
  Future<void> saveAccount(SipAccountModel account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountKey, account.toJsonString());
  }

  @override
  Future<SipAccountModel?> getAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_accountKey);
    
    if (jsonString != null) {
      try {
        return SipAccountModel.fromJsonString(jsonString);
      } catch (e) {
        // If parsing fails, remove corrupted data
        await prefs.remove(_accountKey);
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountKey);
  }

  @override
  Future<void> saveCallRecord(CallModel call) async {
    final prefs = await SharedPreferences.getInstance();
    final callHistory = await getCallHistory();
    
    // Add new call to the beginning
    callHistory.insert(0, call);
    
    // Keep only last 100 calls
    if (callHistory.length > 100) {
      callHistory.removeRange(100, callHistory.length);
    }
    
    final jsonList = callHistory.map((call) => call.toJson()).toList();
    await prefs.setString(_callHistoryKey, jsonEncode(jsonList));
  }

  @override
  Future<List<CallModel>> getCallHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_callHistoryKey);
    
    if (jsonString != null) {
      try {
        final jsonList = jsonDecode(jsonString) as List;
        return jsonList
            .map((json) => CallModel.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // If parsing fails, return empty list and clear corrupted data
        await prefs.remove(_callHistoryKey);
        return [];
      }
    }
    return [];
  }

  @override
  Future<void> clearCallHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_callHistoryKey);
  }

  @override
  Future<void> saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(key, value);
    } else {
      // For complex objects, store as JSON string
      await prefs.setString(key, jsonEncode(value));
    }
  }

  @override
  Future<T?> getSetting<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (T == String) {
      return prefs.getString(key) as T?;
    } else if (T == int) {
      return prefs.getInt(key) as T?;
    } else if (T == double) {
      return prefs.getDouble(key) as T?;
    } else if (T == bool) {
      return prefs.getBool(key) as T?;
    } else if (T == List<String>) {
      return prefs.getStringList(key) as T?;
    } else {
      // For complex objects, try to decode from JSON string
      final jsonString = prefs.getString(key);
      if (jsonString != null) {
        try {
          return jsonDecode(jsonString) as T?;
        } catch (e) {
          return null;
        }
      }
      return null;
    }
  }

  @override
  Future<void> deleteSetting(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}