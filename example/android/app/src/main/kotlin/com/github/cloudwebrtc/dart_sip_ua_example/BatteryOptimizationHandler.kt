package com.github.cloudwebrtc.dart_sip_ua_example

import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BatteryOptimizationHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    
    private val TAG = "BatteryOptHandler"
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "Method call: ${call.method}")
        when (call.method) {
            "requestIgnoreBatteryOptimizations" -> {
                requestIgnoreBatteryOptimizations(result)
            }
            "isIgnoringBatteryOptimizations" -> {
                isIgnoringBatteryOptimizations(result)
            }
            "openAppSettings" -> {
                openAppSettings(result)
            }
            "requestAutostartPermission" -> {
                requestAutostartPermission(result)
            }
            "canDrawOverlays" -> {
                canDrawOverlays(result)
            }
            "requestDrawOverlays" -> {
                requestDrawOverlays(result)
            }
            "getDeviceManufacturer" -> {
                getDeviceManufacturer(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    /**
     * CRITICAL: Request to disable battery optimization
     * This is the most important permission for background VoIP apps
     */
    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!powerManager.isIgnoringBatteryOptimizations(context.packageName)) {
                    Log.d(TAG, "🔋 Requesting battery optimization exemption...")
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:${context.packageName}")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                    result.success(true)
                    Log.d(TAG, "🔋 Battery optimization exemption dialog opened")
                } else {
                    Log.d(TAG, "🔋 Battery optimization already disabled (good!)")
                    result.success(true) // Already ignoring
                }
            } else {
                Log.d(TAG, "🔋 Battery optimization not applicable for Android < M")
                result.success(true) // Not applicable for Android versions below M
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error requesting battery optimization exemption: ${e.message}")
            result.error("BATTERY_OPTIMIZATION_ERROR", e.message, null)
        }
    }
    
    /**
     * Check if battery optimization is disabled (ignored) for this app
     */
    private fun isIgnoringBatteryOptimizations(result: MethodChannel.Result) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val isIgnoring = powerManager.isIgnoringBatteryOptimizations(context.packageName)
                Log.d(TAG, "🔋 Battery optimization status: ${if (isIgnoring) "IGNORED (Good)" else "OPTIMIZED (Bad)"}")
                result.success(isIgnoring)
            } else {
                Log.d(TAG, "🔋 Battery optimization check not applicable for Android < M")
                result.success(true) // Not applicable for Android versions below M
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking battery optimization status: ${e.message}")
            result.error("BATTERY_OPTIMIZATION_ERROR", e.message, null)
        }
    }
    
    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Opening app settings...")
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Error opening app settings: ${e.message}")
            result.error("APP_SETTINGS_ERROR", e.message, null)
        }
    }
    
    /**
     * CRITICAL: Request autostart permission for various Android OEMs
     * This is essential for VoIP apps to start automatically after boot
     */
    private fun requestAutostartPermission(result: MethodChannel.Result) {
        try {
            Log.d(TAG, "Requesting autostart permission for manufacturer: ${Build.MANUFACTURER}")
            
            val manufacturer = Build.MANUFACTURER.lowercase()
            var intent: Intent? = null
            
            when (manufacturer) {
                "xiaomi" -> {
                    // Xiaomi MIUI autostart permission
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    Log.d(TAG, "Opening Xiaomi autostart settings")
                }
                "huawei", "honor" -> {
                    // Huawei/Honor startup manager
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    Log.d(TAG, "Opening Huawei startup manager")
                }
                "oppo" -> {
                    // OPPO autostart permission
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.coloros.safecenter",
                            "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                        )
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    Log.d(TAG, "Opening OPPO autostart settings")
                }
                "oneplus" -> {
                    // OnePlus autostart permission
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.oneplus.security",
                            "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
                        )
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    Log.d(TAG, "Opening OnePlus autostart settings")
                }
                "vivo" -> {
                    // Vivo autostart permission
                    intent = Intent().apply {
                        component = ComponentName(
                            "com.vivo.permissionmanager",
                            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                        )
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    Log.d(TAG, "Opening Vivo autostart settings")
                }
                "samsung" -> {
                    // Samsung - open battery optimization instead
                    intent = Intent().apply {
                        action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        data = Uri.parse("package:${context.packageName}")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    Log.d(TAG, "Opening Samsung battery optimization (no separate autostart)")
                }
                else -> {
                    Log.d(TAG, "Unknown manufacturer, opening general battery settings")
                    // Fallback to battery optimization settings
                    intent = Intent().apply {
                        action = Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                }
            }
            
            if (intent != null) {
                try {
                    context.startActivity(intent)
                    result.success(true)
                    Log.d(TAG, "Autostart permission intent launched successfully")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to open autostart settings, trying fallback: ${e.message}")
                    // Fallback to general settings
                    val fallbackIntent = Intent(Settings.ACTION_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(fallbackIntent)
                    result.success(false)
                }
            } else {
                result.success(false)
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting autostart permission: ${e.message}")
            result.error("AUTOSTART_ERROR", e.message, null)
        }
    }
    
    /**
     * Check if app can draw over other apps (system alert window)
     * Critical for incoming call notifications over lock screen
     */
    private fun canDrawOverlays(result: MethodChannel.Result) {
        try {
            val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true // Not applicable for Android versions below M
            }
            Log.d(TAG, "Can draw overlays: $canDraw")
            result.success(canDraw)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking overlay permission: ${e.message}")
            result.error("OVERLAY_CHECK_ERROR", e.message, null)
        }
    }
    
    /**
     * Request permission to draw over other apps
     */
    private fun requestDrawOverlays(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(context)) {
                    Log.d(TAG, "Requesting draw overlays permission...")
                    val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                        data = Uri.parse("package:${context.packageName}")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                    result.success(true)
                } else {
                    Log.d(TAG, "Draw overlays permission already granted")
                    result.success(true)
                }
            } else {
                Log.d(TAG, "Draw overlays permission not needed for this Android version")
                result.success(true)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting overlay permission: ${e.message}")
            result.error("OVERLAY_REQUEST_ERROR", e.message, null)
        }
    }
    
    /**
     * Get device manufacturer for showing specific instructions
     */
    private fun getDeviceManufacturer(result: MethodChannel.Result) {
        try {
            val manufacturer = Build.MANUFACTURER
            Log.d(TAG, "Device manufacturer: $manufacturer")
            result.success(manufacturer)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting device manufacturer: ${e.message}")
            result.error("MANUFACTURER_ERROR", e.message, null)
        }
    }
}