package com.github.cloudwebrtc.dart_sip_ua_example

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    
    private val INCOMING_CALL_CHANNEL = "sip_phone/incoming_call"
    private val BATTERY_OPTIMIZATION_CHANNEL = "com.example.battery_optimization"
    private val TAG = "MainActivity"
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        Log.d(TAG, "MainActivity onCreate")
        
        // Check if this was launched by an incoming call
        handleIncomingCallIntent(intent)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "MainActivity onNewIntent")
        handleIncomingCallIntent(intent)
    }
    
    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Set up platform channel for incoming calls
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INCOMING_CALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "forceOpenAppForCall" -> {
                        val caller = call.argument<String>("caller") ?: "Unknown"
                        val callId = call.argument<String>("callId") ?: ""
                        val autoLaunch = call.argument<Boolean>("autoLaunch") ?: false
                        
                        Log.d(TAG, "FORCE OPEN APP for incoming call - Caller: $caller, CallId: $callId, AutoLaunch: $autoLaunch")
                        
                        // Force bring app to foreground immediately
                        bringAppToForeground()
                        
                        // Launch app with incoming call intent
                        val intent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            putExtra("incoming_call", true)
                            putExtra("caller", caller)
                            putExtra("callId", callId)
                            putExtra("autoLaunch", true)
                        }
                        startActivity(intent)
                        
                        // Send incoming call data to Flutter immediately
                        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                            MethodChannel(messenger, INCOMING_CALL_CHANNEL)
                                .invokeMethod("handleIncomingCall", mapOf(
                                    "caller" to caller,
                                    "callId" to callId,
                                    "autoLaunch" to true,
                                    "fromBackground" to true
                                ))
                        }
                        
                        result.success("App force-launched for incoming call")
                    }
                    "launchIncomingCallScreen" -> {
                        val caller = call.argument<String>("caller") ?: "Unknown"
                        val callId = call.argument<String>("callId") ?: ""
                        val fromNotification = call.argument<Boolean>("fromNotification") ?: false
                        val fromBackground = call.argument<Boolean>("fromBackground") ?: false
                        
                        Log.d(TAG, "Incoming call launch requested - Caller: $caller, CallId: $callId, FromNotification: $fromNotification, FromBackground: $fromBackground")
                        
                        if (fromNotification || fromBackground) {
                            // Bring app to foreground and show over lock screen
                            bringAppToForeground()
                        }
                        
                        // Send incoming call data to Flutter
                        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                            MethodChannel(messenger, INCOMING_CALL_CHANNEL)
                                .invokeMethod("handleIncomingCall", mapOf(
                                    "caller" to caller,
                                    "callId" to callId,
                                    "fromNotification" to fromNotification,
                                    "fromBackground" to fromBackground
                                ))
                        }
                        
                        result.success("App launched for incoming call")
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
        
        // Set up battery optimization channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_OPTIMIZATION_CHANNEL)
            .setMethodCallHandler(BatteryOptimizationHandler(this))
    }
    
    private fun bringAppToForeground() {
        try {
            // Add flags to show over lock screen and bring to front
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
            
            Log.d(TAG, "App brought to foreground for incoming call")
        } catch (e: Exception) {
            Log.e(TAG, "Error bringing app to foreground: ${e.message}")
        }
    }
    
    private fun handleIncomingCallIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("incoming_call", false) == true) {
            Log.d(TAG, "Handling incoming call intent")
            
            val caller = intent.getStringExtra("caller") ?: "Unknown"
            val callId = intent.getStringExtra("callId") ?: ""
            
            Log.d(TAG, "Incoming call from: $caller, callId: $callId")
            
            // Bring app to foreground
            bringAppToForeground()
            
            // Send this information to Flutter when the engine is ready
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, INCOMING_CALL_CHANNEL)
                    .invokeMethod("handleIncomingCall", mapOf(
                        "caller" to caller,
                        "callId" to callId,
                        "fromIntent" to true
                    ))
            }
        }
    }
}
