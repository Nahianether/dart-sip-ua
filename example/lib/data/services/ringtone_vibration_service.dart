import 'dart:async';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'settings_service.dart';

class RingtoneVibrationService {
  static final RingtoneVibrationService _instance = RingtoneVibrationService._();
  factory RingtoneVibrationService() => _instance;
  RingtoneVibrationService._();

  AudioPlayer? _audioPlayer;
  Timer? _vibrationTimer;
  bool _isRinging = false;
  final SettingsService _settingsService = SettingsService();

  /// Initialize the service
  Future<void> initialize() async {
    try {
      _audioPlayer = AudioPlayer();
      await _requestPermissions();
      print('✅ Ringtone and Vibration service initialized');
    } catch (e) {
      print('❌ Failed to initialize ringtone service: $e');
    }
  }

  /// Request necessary permissions
  Future<void> _requestPermissions() async {
    try {
      // Request notification permission for sound
      await Permission.notification.request();
      
      // Check vibration availability
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) {
        print('⚠️ Device does not support vibration');
      }
      
      // Request phone permission if needed for better call handling
      await Permission.phone.request();
      
    } catch (e) {
      print('❌ Error requesting permissions: $e');
    }
  }

  /// Start ringing for incoming call
  Future<void> startRinging() async {
    if (_isRinging) {
      print('⚠️ Already ringing, ignoring duplicate start request');
      return;
    }

    try {
      _isRinging = true;
      final settings = await _settingsService.getSettings();
      
      print('📞 Starting ringtone and vibration...');
      
      // Start ringtone
      if (settings.ringtoneVolume != null && settings.ringtoneVolume! > 0) {
        await _playRingtone(settings.ringtoneVolume!);
      }
      
      // Start vibration
      if (settings.vibrationEnabled == true) {
        await _startVibrationPattern();
      }
      
    } catch (e) {
      print('❌ Error starting ringtone: $e');
      _isRinging = false;
    }
  }

  /// Stop ringing
  Future<void> stopRinging() async {
    if (!_isRinging) return;

    try {
      print('📞 Stopping ringtone and vibration...');
      _isRinging = false;
      
      // Stop audio
      await _audioPlayer?.stop();
      
      // Stop vibration
      _vibrationTimer?.cancel();
      await Vibration.cancel();
      
    } catch (e) {
      print('❌ Error stopping ringtone: $e');
    }
  }

  /// Play ringtone with specified volume
  Future<void> _playRingtone(double volume) async {
    try {
      if (_audioPlayer == null) return;

      // Set volume (0.0 to 1.0)
      await _audioPlayer!.setVolume(volume);
      
      // Play system ringtone or default
      await _playSystemRingtone();
      
    } catch (e) {
      print('❌ Error playing ringtone: $e');
      // Fallback to system sound
      await _playSystemSound();
    }
  }

  /// Play system ringtone
  Future<void> _playSystemRingtone() async {
    try {
      // Try to play default system ringtone
      const platform = MethodChannel('com.example.ringtone');
      await platform.invokeMethod('playDefaultRingtone');
      
    } catch (e) {
      print('❌ System ringtone unavailable, using fallback: $e');
      await _playFallbackRingtone();
    }
  }

  /// Play fallback ringtone (built-in audio file)
  Future<void> _playFallbackRingtone() async {
    try {
      // You can add a ringtone.mp3 file to assets/audio/
      await _audioPlayer?.play(AssetSource('audio/ringtone.mp3'));
      
      // If no custom ringtone, use system sound
    } catch (e) {
      print('❌ Fallback ringtone unavailable, using system sound: $e');
      await _playSystemSound();
    }
  }

  /// Play system notification sound as last resort
  Future<void> _playSystemSound() async {
    try {
      SystemSound.play(SystemSoundType.alert);
      
      // Repeat every 3 seconds while ringing
      Timer.periodic(Duration(seconds: 3), (timer) {
        if (!_isRinging) {
          timer.cancel();
          return;
        }
        SystemSound.play(SystemSoundType.alert);
      });
      
    } catch (e) {
      print('❌ Error playing system sound: $e');
    }
  }

  /// Start vibration pattern
  Future<void> _startVibrationPattern() async {
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) {
        print('⚠️ Device does not support vibration');
        return;
      }

      // Check if custom vibration patterns are supported
      final hasCustomVibrationsSupport = await Vibration.hasCustomVibrationsSupport() ?? false;
      
      if (hasCustomVibrationsSupport) {
        // Custom vibration pattern: [wait, vibrate, wait, vibrate, ...]
        // Pattern: Short pause, vibrate for 1000ms, pause 500ms, repeat
        const pattern = [0, 1000, 500, 1000, 500, 1000, 500];
        
        _startVibrationLoop(pattern);
      } else {
        // Use simple vibration
        _startSimpleVibrationLoop();
      }
      
    } catch (e) {
      print('❌ Error starting vibration: $e');
    }
  }

  /// Start vibration loop with custom pattern
  void _startVibrationLoop(List<int> pattern) {
    _vibrationTimer = Timer.periodic(Duration(seconds: 4), (timer) async {
      if (!_isRinging) {
        timer.cancel();
        return;
      }
      
      try {
        await Vibration.vibrate(pattern: pattern);
      } catch (e) {
        print('❌ Error in vibration loop: $e');
      }
    });
    
    // Start immediately
    Vibration.vibrate(pattern: pattern);
  }

  /// Start simple vibration loop
  void _startSimpleVibrationLoop() {
    _vibrationTimer = Timer.periodic(Duration(seconds: 2), (timer) async {
      if (!_isRinging) {
        timer.cancel();
        return;
      }
      
      try {
        await Vibration.vibrate(duration: 1000);
      } catch (e) {
        print('❌ Error in simple vibration: $e');
      }
    });
    
    // Start immediately
    Vibration.vibrate(duration: 1000);
  }

  /// Play notification sound for events
  Future<void> playNotificationSound() async {
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (e) {
      print('❌ Error playing notification sound: $e');
    }
  }

  /// Play DTMF tone for dialpad
  Future<void> playDTMFTone(String digit) async {
    try {
      // You can implement DTMF tones here
      // For now, just play a click sound
      SystemSound.play(SystemSoundType.click);
      
      // Optional: Generate actual DTMF frequencies
      // This would require additional audio processing
    } catch (e) {
      print('❌ Error playing DTMF tone: $e');
    }
  }

  /// Dispose service
  void dispose() {
    stopRinging();
    _audioPlayer?.dispose();
    _audioPlayer = null;
  }

  /// Check if currently ringing
  bool get isRinging => _isRinging;
}