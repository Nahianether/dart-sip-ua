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
    
    // Continue ringing every 1 second for more responsive feedback
    _ringtoneTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_isRinging) {
        _playRingtone();
      } else {
        timer.cancel();
      }
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
      print('🔔 Playing ringtone - enhanced pattern');
      
      // Enhanced vibration pattern for incoming calls
      HapticFeedback.heavyImpact();
      
      // Play system alert sound immediately
      SystemSound.play(SystemSoundType.alert);
      
      // Additional vibration burst pattern
      Timer(Duration(milliseconds: 150), () {
        if (_isRinging) {
          HapticFeedback.heavyImpact();
        }
      });
      
      Timer(Duration(milliseconds: 300), () {
        if (_isRinging) {
          HapticFeedback.vibrate();
        }
      });
      
      Timer(Duration(milliseconds: 450), () {
        if (_isRinging) {
          HapticFeedback.heavyImpact();
        }
      });
      
      // Final vibration
      Timer(Duration(milliseconds: 600), () {
        if (_isRinging) {
          HapticFeedback.vibrate();
        }
      });
      
    } catch (e) {
      print('❌ Error playing ringtone: $e');
      // Fallback to basic vibration
      try {
        HapticFeedback.vibrate();
      } catch (fallbackError) {
        print('❌ Fallback vibration also failed: $fallbackError');
      }
    }
  }
  
  /// Check if currently ringing
  static bool get isRinging => _isRinging;
}