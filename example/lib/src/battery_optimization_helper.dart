import 'dart:io' show Platform;
import 'package:flutter/services.dart';

class BatteryOptimizationHelper {
  static const MethodChannel _channel =
      MethodChannel('com.example.battery_optimization');

  /// Request to disable battery optimization for the app
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final bool result = await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      return result;
    } on PlatformException catch (e) {
      print("Failed to request battery optimization ignore: '${e.message}'.");
      return false;
    }
  }

  /// Check if battery optimization is ignored for the app
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final bool result = await _channel.invokeMethod('isIgnoringBatteryOptimizations');
      return result;
    } on PlatformException catch (e) {
      print("Failed to check battery optimization status: '${e.message}'.");
      return false;
    }
  }

  /// Show app settings to let user manually disable battery optimization
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('openAppSettings');
    } on PlatformException catch (e) {
      print("Failed to open app settings: '${e.message}'.");
    }
  }
}