package com.github.cloudwebrtc.dart_sip_ua_example

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BatteryOptimizationHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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
            else -> {
                result.notImplemented()
            }
        }
    }
    
    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                if (!powerManager.isIgnoringBatteryOptimizations(context.packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:${context.packageName}")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(intent)
                    result.success(true)
                } else {
                    result.success(true) // Already ignoring
                }
            } else {
                result.success(true) // Not applicable for Android versions below M
            }
        } catch (e: Exception) {
            result.error("BATTERY_OPTIMIZATION_ERROR", e.message, null)
        }
    }
    
    private fun isIgnoringBatteryOptimizations(result: MethodChannel.Result) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val isIgnoring = powerManager.isIgnoringBatteryOptimizations(context.packageName)
                result.success(isIgnoring)
            } else {
                result.success(true) // Not applicable for Android versions below M
            }
        } catch (e: Exception) {
            result.error("BATTERY_OPTIMIZATION_ERROR", e.message, null)
        }
    }
    
    private fun openAppSettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error("APP_SETTINGS_ERROR", e.message, null)
        }
    }
}