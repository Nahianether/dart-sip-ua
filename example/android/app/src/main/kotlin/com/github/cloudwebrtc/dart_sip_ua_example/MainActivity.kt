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
                        val retry = call.argument<Int>("retry") ?: 1
                        val aggressive = call.argument<Boolean>("aggressive") ?: false
                        val superAggressive = call.argument<Boolean>("superAggressive") ?: false
                        val nuclearOption = call.argument<Boolean>("nuclearOption") ?: false
                        val fromNotification = call.argument<Boolean>("fromNotification") ?: false
                        val showIncomingCallScreen = call.argument<Boolean>("showIncomingCallScreen") ?: false
                        
                        Log.d(TAG, "🚀🚀 FORCE OPEN APP (attempt $retry) for incoming call - Caller: $caller, CallId: $callId, FromNotification: $fromNotification, ShowCallScreen: $showIncomingCallScreen")
                        
                        // Create intent with maximum aggressive flags based on retry attempt
                        val intent = Intent(this, MainActivity::class.java).apply {
                            if (nuclearOption) {
                                // NUCLEAR: Maximum possible flags
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                       Intent.FLAG_ACTIVITY_CLEAR_TOP or 
                                       Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                       Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                       Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT or
                                       Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                                       Intent.FLAG_ACTIVITY_CLEAR_WHEN_TASK_RESET
                            } else if (superAggressive) {
                                // SUPER AGGRESSIVE: More flags
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                       Intent.FLAG_ACTIVITY_CLEAR_TOP or 
                                       Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                       Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                                       Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT
                            } else if (aggressive) {
                                // AGGRESSIVE: Additional flags
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                       Intent.FLAG_ACTIVITY_CLEAR_TOP or 
                                       Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                       Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                            } else {
                                // STANDARD: Original flags
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                                       Intent.FLAG_ACTIVITY_CLEAR_TOP or 
                                       Intent.FLAG_ACTIVITY_SINGLE_TOP
                            }
                            
                            putExtra("incoming_call", true)
                            putExtra("caller", caller)
                            putExtra("callId", callId)
                            putExtra("autoLaunch", true)
                            putExtra("forceToForeground", true)
                            putExtra("retryAttempt", retry)
                            putExtra("fromNotification", fromNotification)
                            putExtra("showIncomingCallScreen", showIncomingCallScreen)
                        }
                        
                        Log.d(TAG, "🚀 Launching activity (attempt $retry) to bring app to foreground...")
                        startActivity(intent)
                        
                        // Apply window flags to current activity with increasing aggression
                        try {
                            bringAppToForeground()
                            Log.d(TAG, "✅ Window flags applied to current activity (attempt $retry)")
                        } catch (e: Exception) {
                            Log.w(TAG, "Could not apply window flags to current activity (attempt $retry): ${e.message}")
                        }
                        
                        // For aggressive attempts, also try to force task to front
                        if (aggressive || superAggressive || nuclearOption) {
                            try {
                                // Force move to front multiple times
                                moveTaskToBack(false)
                                moveTaskToBack(false)
                                
                                if (superAggressive || nuclearOption) {
                                    // Additional aggressive measures
                                    window.decorView.requestFocus()
                                    setShowWhenLocked(true)
                                    setTurnScreenOn(true)
                                }
                                
                                Log.d(TAG, "✅ Extra aggressive foreground measures applied (attempt $retry)")
                            } catch (e: Exception) {
                                Log.w(TAG, "Could not apply extra aggressive measures (attempt $retry): ${e.message}")
                            }
                        }
                        
                        // Send incoming call data to Flutter immediately
                        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                            MethodChannel(messenger, INCOMING_CALL_CHANNEL)
                                .invokeMethod("handleIncomingCall", mapOf(
                                    "caller" to caller,
                                    "callId" to callId,
                                    "autoLaunch" to true,
                                    "fromBackground" to true,
                                    "forceToForeground" to true,
                                    "retryAttempt" to retry,
                                    "fromNotification" to fromNotification,
                                    "showIncomingCallScreen" to showIncomingCallScreen,
                                    "aggressive" to aggressive,
                                    "superAggressive" to superAggressive,
                                    "nuclearOption" to nuclearOption
                                ))
                        }
                        
                        Log.d(TAG, "✅ Force app launch completed successfully (attempt $retry)")
                        result.success("App force-launched for incoming call with foreground priority (attempt $retry)")
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
            Log.d(TAG, "🔥 AGGRESSIVELY bringing app to foreground...")
            
            // Step 1: Add window flags to show over lock screen and wake up device
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
            )
            
            // Step 2: Move task to front
            try {
                moveTaskToBack(false)  // First move to back
                moveTaskToBack(false)  // Then bring to front (this forces refresh)
                Log.d(TAG, "✅ Task moved to front")
            } catch (e: Exception) {
                Log.w(TAG, "Could not move task: ${e.message}")
            }
            
            // Step 3: Request focus and bring to front
            try {
                window.decorView.requestFocus()
                requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                Log.d(TAG, "✅ Window focus requested")
            } catch (e: Exception) {
                Log.w(TAG, "Could not request focus: ${e.message}")
            }
            
            Log.d(TAG, "🎉 App aggressively brought to foreground for incoming call")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error bringing app to foreground: ${e.message}")
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
