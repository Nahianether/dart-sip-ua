import 'dart:async';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'user_state/sip_user.dart';

/// Simplified iOS CallKit service for better call handling
class IOSCallKitService {
  static IOSCallKitService? _instance;
  static IOSCallKitService get instance => _instance ??= IOSCallKitService._();
  
  IOSCallKitService._();
  
  SIPUAHelper? _tempSipHelper;
  bool _isInitialized = false;
  
  /// Initialize CallKit service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('🍎📞 iOS CallKit: Initializing CallKit service...');
    
    try {
      // Initialize CallKit
      await _initializeCallKit();
      
      _isInitialized = true;
      print('✅ iOS CallKit: Service initialized successfully');
      
    } catch (e) {
      print('❌ iOS CallKit: Initialization failed: $e');
    }
  }
  
  /// Initialize CallKit for native iOS call interface
  Future<void> _initializeCallKit() async {
    print('📞 iOS CallKit: Initializing CallKit...');
    
    // Listen for CallKit events
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event != null) {
        print('📞 iOS CallKit: CallKit event: ${event.event}');
        _handleCallKitEvent(event);
      }
    });
    
    print('✅ iOS CallKit: CallKit initialized');
  }
  
  /// Show CallKit incoming call interface for SIP calls
  Future<void> showIncomingCall({
    required String callId,
    required String caller,
    required String callerNumber,
  }) async {
    print('📞 iOS CallKit: Showing incoming call from $caller...');
    
    final callKitParams = CallKitParams(
      id: callId,
      nameCaller: caller,
      appName: 'SIP Phone',
      handle: callerNumber,
      type: 0, // Audio call
      extra: <String, dynamic>{
        'caller': caller,
        'caller_number': callerNumber,
        'sip_call': true,
      },
    );
    
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
      print('✅ iOS CallKit: Incoming call displayed');
    } catch (e) {
      print('❌ iOS CallKit: Failed to show call: $e');
    }
  }
  
  /// Handle CallKit events (accept, decline, etc.)
  void _handleCallKitEvent(CallEvent event) {
    print('📞 iOS CallKit: Handling event: ${event.event}');
    
    switch (event.event) {
      case Event.actionCallAccept:
        print('✅ iOS CallKit: User accepted call');
        _handleCallAccepted(event);
        break;
        
      case Event.actionCallDecline:
        print('❌ iOS CallKit: User declined call');
        _handleCallDeclined(event);
        break;
        
      case Event.actionCallEnded:
        print('🔚 iOS CallKit: Call ended');
        _handleCallEnded(event);
        break;
        
      default:
        print('📞 iOS CallKit: Unhandled event: ${event.event}');
    }
  }
  
  /// Handle call accepted by user
  void _handleCallAccepted(CallEvent event) {
    print('✅ iOS CallKit: Processing call acceptance...');
    
    // The SIP call should already be handled by the main app
    // Just log for now - integration with main app will handle navigation
    print('🚀 iOS CallKit: Call accepted - main app should handle navigation');
  }
  
  /// Handle call declined by user
  void _handleCallDeclined(CallEvent event) {
    print('❌ iOS CallKit: Processing call decline...');
    
    // The SIP call should be rejected by the main app
    print('📞 iOS CallKit: Call declined - main app should reject SIP call');
  }
  
  /// Handle call ended
  void _handleCallEnded(CallEvent event) {
    print('🔚 iOS CallKit: Processing call end...');
    
    // Clean up any temporary resources
    print('🧹 iOS CallKit: Call ended cleanup');
  }
  
  /// End active CallKit call
  Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
      print('✅ iOS CallKit: Call $callId ended');
    } catch (e) {
      print('❌ iOS CallKit: Failed to end call $callId: $e');
    }
  }
  
  /// Check if CallKit is available and initialized
  bool get isInitialized => _isInitialized;
}