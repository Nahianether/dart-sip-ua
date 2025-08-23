import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Enhanced Battery Optimization Helper
/// Handles battery optimization exemptions and background running permissions
/// Critical for VoIP apps that need to run 24/7 in background
class BatteryOptimizationHelper {
  static const MethodChannel _channel = MethodChannel('com.example.battery_optimization');

  /// Request to disable battery optimization for the app
  /// This is CRITICAL for background SIP service reliability
  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      print('🔋 Requesting battery optimization exemption...');
      final bool result = await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      print(result ? '✅ Battery optimization exemption granted' : '❌ Battery optimization exemption denied');
      return result;
    } on PlatformException catch (e) {
      print("❌ Failed to request battery optimization ignore: '${e.message}'.");
      return false;
    }
  }

  /// Check if battery optimization is ignored for the app
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;

    try {
      final bool result = await _channel.invokeMethod('isIgnoringBatteryOptimizations');
      print('🔋 Battery optimization status: ${result ? "IGNORED (Good)" : "OPTIMIZED (Bad for background)"}');
      return result;
    } on PlatformException catch (e) {
      print("❌ Failed to check battery optimization status: '${e.message}'.");
      return false;
    }
  }

  /// Show app settings to let user manually disable battery optimization
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;

    try {
      print('📱 Opening app settings for manual battery optimization disable...');
      await _channel.invokeMethod('openAppSettings');
    } on PlatformException catch (e) {
      print("❌ Failed to open app settings: '${e.message}'.");
    }
  }

  /// Request autostart permission for various Android OEMs
  /// Critical for apps to start automatically after boot
  static Future<bool> requestAutostartPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      print('🚀 Requesting autostart permission...');
      final bool result = await _channel.invokeMethod('requestAutostartPermission');
      print(result ? '✅ Autostart permission granted/available' : '❌ Autostart permission denied/unavailable');
      return result;
    } on PlatformException catch (e) {
      print("❌ Failed to request autostart permission: '${e.message}'.");
      return false;
    }
  }

  /// Check if app can draw over other apps (system alert window)
  /// Needed for incoming call notifications over lock screen
  static Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return true;

    try {
      final bool result = await _channel.invokeMethod('canDrawOverlays');
      print('🖼️ Draw over other apps permission: ${result ? "GRANTED" : "DENIED"}');
      return result;
    } on PlatformException catch (e) {
      print("❌ Failed to check overlay permission: '${e.message}'.");
      return false;
    }
  }

  /// Request permission to draw over other apps
  static Future<bool> requestDrawOverlays() async {
    if (!Platform.isAndroid) return true;

    try {
      print('🖼️ Requesting draw over other apps permission...');
      final bool result = await _channel.invokeMethod('requestDrawOverlays');
      print(result ? '✅ Draw over apps permission granted' : '❌ Draw over apps permission denied');
      return result;
    } on PlatformException catch (e) {
      print("❌ Failed to request overlay permission: '${e.message}'.");
      return false;
    }
  }

  /// Get device manufacturer to show specific instructions
  static Future<String> getDeviceManufacturer() async {
    if (!Platform.isAndroid) return 'Unknown';

    try {
      final String manufacturer = await _channel.invokeMethod('getDeviceManufacturer');
      print('📱 Device manufacturer: $manufacturer');
      return manufacturer;
    } on PlatformException catch (e) {
      print("❌ Failed to get device manufacturer: '${e.message}'.");
      return 'Unknown';
    }
  }

  /// Show comprehensive dialog for battery optimization setup
  static Future<void> showBatteryOptimizationDialog(BuildContext context) async {
    final isIgnoring = await isIgnoringBatteryOptimizations();
    final canOverlay = await canDrawOverlays();
    final manufacturer = await getDeviceManufacturer();

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('📱 Background App Setup Required'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For reliable call reception, this app needs to run in the background 24/7. Please enable the following:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                
                // Battery Optimization Status
                Card(
                  color: isIgnoring ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          isIgnoring ? Icons.battery_full : Icons.battery_alert,
                          color: isIgnoring ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Battery Optimization', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                isIgnoring 
                                  ? '✅ Disabled (Good)' 
                                  : '❌ Enabled (Will kill background calls)',
                                style: TextStyle(
                                  color: isIgnoring ? Colors.green : Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Overlay Permission Status
                Card(
                  color: canOverlay ? Colors.green.shade50 : Colors.red.shade50,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          canOverlay ? Icons.layers : Icons.layers_outlined,
                          color: canOverlay ? Colors.green : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Display Over Other Apps', style: TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                canOverlay 
                                  ? '✅ Enabled (Good)' 
                                  : '❌ Disabled (Incoming calls may not show)',
                                style: TextStyle(
                                  color: canOverlay ? Colors.green : Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Device-specific instructions
                if (manufacturer.toLowerCase() == 'xiaomi')
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📱 Xiaomi Device Detected', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('• Enable "Autostart" in Security app', style: TextStyle(fontSize: 12)),
                          Text('• Set "No restrictions" in Battery settings', style: TextStyle(fontSize: 12)),
                          Text('• Enable "Display popup windows" permission', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                
                if (manufacturer.toLowerCase() == 'huawei')
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📱 Huawei Device Detected', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('• Enable "Startup manager" for this app', style: TextStyle(fontSize: 12)),
                          Text('• Set to "Manual manage" in Battery settings', style: TextStyle(fontSize: 12)),
                          Text('• Enable all toggles (Auto-launch, Secondary launch, Run in background)', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                
                if (manufacturer.toLowerCase() == 'oppo' || manufacturer.toLowerCase() == 'oneplus')
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📱 $manufacturer Device Detected', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('• Enable "Autostart" in Settings', style: TextStyle(fontSize: 12)),
                          Text('• Add app to "Battery optimization" whitelist', style: TextStyle(fontSize: 12)),
                          Text('• Enable "Allow background activity"', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                
                if (manufacturer.toLowerCase() == 'samsung')
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📱 Samsung Device Detected', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('• Add to "Never sleeping apps" in Battery settings', style: TextStyle(fontSize: 12)),
                          Text('• Disable "Optimize battery usage" for this app', style: TextStyle(fontSize: 12)),
                          Text('• Enable "Allow background activity"', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (!isIgnoring)
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await requestIgnoreBatteryOptimizations();
                },
                child: Text('Fix Battery Settings'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            
            if (!canOverlay)
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await requestDrawOverlays();
                },
                child: Text('Enable Overlay'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
            
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: Text('Open Settings'),
            ),
            
            if (isIgnoring && canOverlay)
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('All Good!'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              )
            else
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Skip for Now'),
              ),
          ],
        );
      },
    );
  }

  /// Initialize all battery optimization and background permissions
  /// Call this on app startup
  static Future<bool> initializeBackgroundPermissions() async {
    if (!Platform.isAndroid) return true;

    print('🔋🔋🔋 INITIALIZING BACKGROUND PERMISSIONS 🔋🔋🔋');
    
    try {
      // Check current status
      final isIgnoring = await isIgnoringBatteryOptimizations();
      final canOverlay = await canDrawOverlays();
      final manufacturer = await getDeviceManufacturer();
      
      print('📊 Current Status:');
      print('  - Battery Optimization Ignored: $isIgnoring');
      print('  - Can Draw Overlays: $canOverlay');
      print('  - Device Manufacturer: $manufacturer');
      
      bool allPermissionsGranted = isIgnoring && canOverlay;
      
      if (!allPermissionsGranted) {
        print('⚠️ Some permissions missing - app may not work reliably in background');
      } else {
        print('✅ All background permissions are properly configured!');
      }
      
      return allPermissionsGranted;
      
    } catch (e) {
      print('❌ Error initializing background permissions: $e');
      return false;
    }
  }

  /// Request all necessary permissions automatically
  static Future<bool> requestAllPermissions() async {
    if (!Platform.isAndroid) return true;

    print('🚀 Requesting all background permissions...');
    
    bool batteryResult = await requestIgnoreBatteryOptimizations();
    bool overlayResult = await requestDrawOverlays();
    bool autostartResult = await requestAutostartPermission();
    
    bool allGranted = batteryResult && overlayResult;
    
    print('📊 Permission Results:');
    print('  - Battery Optimization: $batteryResult');
    print('  - Draw Overlays: $overlayResult');
    print('  - Autostart: $autostartResult');
    print('  - All Critical Permissions: $allGranted');
    
    return allGranted;
  }
}