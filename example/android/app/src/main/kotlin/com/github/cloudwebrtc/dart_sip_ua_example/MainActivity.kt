package com.github.cloudwebrtc.dart_sip_ua_example

import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    
    private val INCOMING_CALL_CHANNEL = "sip_phone/incoming_call"
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
                    "launchIncomingCallScreen" -> {
                        // Simplified approach - just return success
                        // Let the notification handle app opening
                        Log.d(TAG, "Platform channel: Incoming call launch requested")
                        result.success("Using notification tap to launch")
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }
    
    private fun handleIncomingCallIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("incoming_call", false) == true) {
            Log.d(TAG, "Handling incoming call intent")
            
            val caller = intent.getStringExtra("caller") ?: "Unknown"
            val callId = intent.getStringExtra("callId") ?: ""
            
            Log.d(TAG, "Incoming call from: $caller, callId: $callId")
            
            // Send this information to Flutter when the engine is ready
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, INCOMING_CALL_CHANNEL)
                    .invokeMethod("handleIncomingCall", mapOf(
                        "caller" to caller,
                        "callId" to callId
                    ))
            }
        }
    }
}
