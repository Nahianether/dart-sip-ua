import 'dart:async';
import 'package:flutter/services.dart';

class RingtoneService {
  static Timer? _ringtoneTimer;
  static bool _isRinging = false;

  /// Start ringing with system default sound
  static void startRinging() {
    if (_isRinging) return;
    
    print('📱 Starting ringtone...');
    _isRinging = true;
    
    // Play ringtone immediately
    _playRingtone();
    
    // Continue ringing every 2 seconds
    _ringtoneTimer = Timer.periodic(Duration(seconds: 2), (timer) {
      _playRingtone();
    });
  }
  
  /// Stop ringing
  static void stopRinging() {
    if (!_isRinging) return;
    
    print('📱 Stopping ringtone...');
    _isRinging = false;
    _ringtoneTimer?.cancel();
    _ringtoneTimer = null;
  }
  
  /// Play single ringtone sound
  static void _playRingtone() {
    try {
      // Use haptic feedback for ringing sensation
      HapticFeedback.heavyImpact();
      
      // Add vibration pattern
      HapticFeedback.vibrate();
    } catch (e) {
      print('❌ Error playing ringtone: $e');
    }
  }
  
  /// Check if currently ringing
  static bool get isRinging => _isRinging;
}