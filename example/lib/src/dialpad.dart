import 'package:dart_sip_ua_example/src/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'widgets/action_button.dart';
import 'permission_helper.dart';
import 'recent_calls.dart';
import 'connection_manager.dart';

class DialPadWidget extends ConsumerStatefulWidget {
  final SIPUAHelper? _helper;

  DialPadWidget(this._helper, {Key? key}) : super(key: key);

  @override
  ConsumerState<DialPadWidget> createState() => _MyDialPadWidget();
}

class _MyDialPadWidget extends ConsumerState<DialPadWidget>
    implements SipUaHelperListener {
  SIPUAHelper? get helper => widget._helper;
  late SharedPreferences _preferences;

  final Logger _logger = Logger();

  @override
  initState() {
    super.initState();
    _bindEventListeners();
    _loadSettings();
  }

  void _loadSettings() async {
    _preferences = await SharedPreferences.getInstance();
    final dest = _preferences.getString('dest') ?? '';
    final textController = ref.read(textControllerProvider);
    textController.text = dest;
    ref.read(destinationProvider.notifier).state = dest;
  }

  void _bindEventListeners() {
    helper!.addSipUaHelperListener(this);
  }

  Future<Widget?> _handleCall(BuildContext context,
      [bool voiceOnly = false]) async {
    // Hide keyboard when starting a call
    FocusScope.of(context).unfocus();
    
    // Skip permission_handler plugin and go straight to WebRTC native API
    // This will trigger iOS permission if needed, and work if already granted
    print('🚀 Starting call - bypassing permission_handler plugin');
    print('📞 Attempting direct media access for iOS compatibility');

    final textController = ref.read(textControllerProvider);
    final dest = textController.text;
    if (dest.isEmpty) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Target is empty.'),
            content: Text('Please enter a SIP URI or username!'),
            actions: <Widget>[
              TextButton(
                child: Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      return null;
    }

    var mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': {
        'mandatory': <String, dynamic>{
          'minWidth': '640',
          'minHeight': '480',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
      }
    };

    MediaStream mediaStream;

    try {
      if (kIsWeb && !voiceOnly) {
        mediaStream =
            await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
        mediaConstraints['video'] = false;
        MediaStream userStream =
            await navigator.mediaDevices.getUserMedia(mediaConstraints);
        final audioTracks = userStream.getAudioTracks();
        if (audioTracks.isNotEmpty) {
          mediaStream.addTrack(audioTracks.first, addToNative: true);
        }
      } else {
        if (voiceOnly) {
          mediaConstraints['video'] = !voiceOnly;
        }
        print('🔄 Requesting media access with constraints: $mediaConstraints');
        mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        print('✅ Media stream obtained successfully');
      }
    } catch (e) {
      print('❌ Media access error: $e');
      
      // Show user-friendly error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to access microphone. Please check permissions in Settings.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Open Settings',
            onPressed: () => openAppSettings(),
          ),
        ),
      );
      return null;
    }

    helper!.call(dest, voiceOnly: voiceOnly, mediaStream: mediaStream);
    _preferences.setString('dest', dest);
    ref.read(destinationProvider.notifier).state = dest;
    
    // Add to call history
    await CallHistoryManager.addCall(
      number: dest,
      type: CallType.outgoing,
    );
    
    return null;
  }

  void _handleBackSpace([bool deleteAll = false]) {
    // Hide keyboard when using backspace
    FocusScope.of(context).unfocus();
    
    final textController = ref.read(textControllerProvider);
    var text = textController.text;
    if (text.isNotEmpty) {
      text = deleteAll ? '' : text.substring(0, text.length - 1);
      textController.text = text;
      ref.read(destinationProvider.notifier).state = text;
    }
  }

  void _handleNum(String number) {
    // Hide keyboard when using custom number pad
    FocusScope.of(context).unfocus();
    
    final textController = ref.read(textControllerProvider);
    textController.text += number;
    ref.read(destinationProvider.notifier).state = textController.text;
  }

  List<Widget> _buildNumPad() {
    final labels = [
      [
        {'1': ''},
        {'2': 'abc'},
        {'3': 'def'}
      ],
      [
        {'4': 'ghi'},
        {'5': 'jkl'},
        {'6': 'mno'}
      ],
      [
        {'7': 'pqrs'},
        {'8': 'tuv'},
        {'9': 'wxyz'}
      ],
      [
        {'*': ''},
        {'0': '+'},
        {'#': ''}
      ],
    ];

    return labels
        .map((row) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .map((label) => ActionButton(
                          title: label.keys.first,
                          subTitle: label.values.first,
                          onPressed: () => _handleNum(label.keys.first),
                          number: true,
                        ))
                    .toList())))
        .toList();
  }

  /// Sanitize phone number for SIP calling
  String _sanitizePhoneNumber(String phoneNumber) {
    // Remove all non-digit characters except +
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    
    print('📞 Original number: $phoneNumber');
    print('📞 Cleaned number: $cleaned');
    
    // Store original for fallback
    final originalCleaned = cleaned;
    
    // Remove country codes that might interfere with SIP calling
    // But ensure we preserve the local mobile number format
    if (cleaned.startsWith('+880')) {
      // Bangladesh country code +880 - extract local number
      final localPart = cleaned.substring(4);
      // Ensure local number starts with proper mobile prefix
      if (localPart.length >= 10 && localPart.startsWith('1')) {
        // Mobile number like +8801712345678 -> 01712345678
        cleaned = '0' + localPart;
        print('📞 Bangladesh mobile (+880): $cleaned');
      } else {
        cleaned = localPart;
        print('📞 Bangladesh other (+880): $cleaned');
      }
    } else if (cleaned.startsWith('+88')) {
      // Malformed +88 prefix - extract what follows
      final localPart = cleaned.substring(3);
      if (localPart.length >= 10 && localPart.startsWith('01')) {
        // Already has 01 prefix
        cleaned = localPart;
        print('📞 Corrected +88 with 01 prefix: $cleaned');
      } else if (localPart.length >= 9 && localPart.startsWith('1')) {
        // Missing leading 0
        cleaned = '0' + localPart;
        print('📞 Corrected +88 added leading 0: $cleaned');
      } else {
        cleaned = localPart;
        print('📞 Corrected +88 other: $cleaned');
      }
    } else if (cleaned.startsWith('880')) {
      // Bangladesh without + sign - extract local part
      final localPart = cleaned.substring(3);
      if (localPart.length >= 10 && localPart.startsWith('1')) {
        cleaned = '0' + localPart;
        print('📞 Bangladesh (880) added leading 0: $cleaned');
      } else {
        cleaned = localPart;
        print('📞 Bangladesh (880): $cleaned');
      }
    } else if (cleaned.startsWith('88') && cleaned.length > 11) {
      // Potential malformed 88 prefix (only if number is very long)
      final localPart = cleaned.substring(2);
      if (localPart.length >= 10 && localPart.startsWith('01')) {
        cleaned = localPart;
        print('📞 Removed 88, preserved 01: $cleaned');
      } else if (localPart.length >= 9 && localPart.startsWith('1')) {
        cleaned = '0' + localPart;
        print('📞 Removed 88, added leading 0: $cleaned');
      } else {
        // Keep original if unsure
        cleaned = originalCleaned;
        print('📞 Kept original (88 ambiguous): $cleaned');
      }
    } else if (cleaned.startsWith('+1')) {
      // US/Canada country code
      cleaned = cleaned.substring(2);
      print('📞 Removed +1 prefix: $cleaned');
    } else if (cleaned.startsWith('+')) {
      // Remove any other country code (+ followed by 1-3 digits)
      final match = RegExp(r'^\+\d{1,3}').firstMatch(cleaned);
      if (match != null) {
        cleaned = cleaned.substring(match.end);
        print('📞 Removed country code: $cleaned');
      }
    }
    
    // Final validation - ensure we have a reasonable number
    if (cleaned.length < 6) {
      print('⚠️ Number too short after cleaning: $cleaned, reverting to original');
      return originalCleaned.replaceAll('+', ''); // Remove only the + sign
    }
    
    // Ensure mobile numbers have proper format
    if (cleaned.length >= 10 && cleaned.startsWith('1') && !cleaned.startsWith('01')) {
      // Looks like a mobile number missing leading 0
      cleaned = '0' + cleaned;
      print('📞 Added missing leading 0: $cleaned');
    }
    
    print('📞 Final sanitized number: $cleaned');
    return cleaned;
  }

  Future<void> _pickContact() async {
    // Hide keyboard when picking contact
    FocusScope.of(context).unfocus();
    
    print('📱 Attempting to pick contact...');
    
    try {
      // Bypass permission_handler and go directly to FlutterContacts
      // This will trigger native iOS contact permission if needed
      final contact = await FlutterContacts.openExternalPick();
      
      if (contact != null) {
        print('✅ Contact selected: ${contact.displayName}');
        
        if (contact.phones.isNotEmpty) {
          final rawPhoneNumber = contact.phones.first.number;
          final sanitizedNumber = _sanitizePhoneNumber(rawPhoneNumber);
          
          final textController = ref.read(textControllerProvider);
          textController.text = sanitizedNumber;
          ref.read(destinationProvider.notifier).state = sanitizedNumber;
          
          print('📞 Phone number added: $sanitizedNumber (was: $rawPhoneNumber)');
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Contact added: ${contact.displayName} ($sanitizedNumber)'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Selected contact has no phone number'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        print('ℹ️ Contact picker was canceled');
      }
    } catch (e) {
      print('❌ Error picking contact: $e');
      
      // If this is a permission error, show helpful message
      if (e.toString().contains('denied') || e.toString().contains('permission')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Contacts permission required. Please enable in Settings.'),
            duration: Duration(seconds: 4),
            backgroundColor: Theme.of(context).colorScheme.error,
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accessing contacts: ${e.toString()}'),
            duration: Duration(seconds: 3),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Contacts Permission Required'),
        content: Text(
          'To pick contacts, please grant contacts permission in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _debugPermissions() async {
    print('🔍 DEBUGGING PERMISSIONS...');
    
    try {
      // Check all permission statuses
      final contactsStatus = await Permission.contacts.status;
      final microphoneStatus = await Permission.microphone.status;
      final cameraStatus = await Permission.camera.status;
      
      print('📱 Current Permission Status:');
      print('  - Contacts: ${contactsStatus.name} (${contactsStatus.toString()})');
      print('  - Microphone: ${microphoneStatus.name}');
      print('  - Camera: ${cameraStatus.name}');
      
      // Force request contacts permission
      print('🔄 Requesting contacts permission...');
      final newContactsStatus = await Permission.contacts.request();
      print('📞 New contacts status: ${newContactsStatus.name}');
      
      // Show debug info to user
      String debugInfo = 'Permission Debug Info:\n\n';
      debugInfo += 'Contacts: ${newContactsStatus.name}\n';
      debugInfo += 'Microphone: ${microphoneStatus.name}\n';
      debugInfo += 'Camera: ${cameraStatus.name}\n\n';
      
      if (newContactsStatus.isGranted) {
        debugInfo += '✅ Contacts permission is granted!\n';
        debugInfo += 'The contact picker should work now.';
      } else if (newContactsStatus.isDenied) {
        debugInfo += '❌ Contacts permission was denied.\n';
        debugInfo += 'Please check your device settings.';
      } else if (newContactsStatus.isPermanentlyDenied) {
        debugInfo += '🚫 Contacts permission is permanently denied.\n';
        debugInfo += 'Please enable it in device settings.';
      } else {
        debugInfo += '❓ Contacts permission status: ${newContactsStatus.name}';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Debug Information'),
          content: SingleChildScrollView(
            child: Text(debugInfo),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
            if (!newContactsStatus.isGranted)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: Text('Open Settings'),
              ),
          ],
        ),
      );
      
    } catch (e) {
      print('❌ Debug error: $e');
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Debug Error'),
          content: Text('Error checking permissions: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _forceRequestPermissions() async {
    print('🔓 FORCING iOS PERMISSION REQUESTS...');
    
    try {
      // Show explanatory dialog first
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.info),
              SizedBox(width: 8),
              Text('Permission Setup'),
            ],
          ),
          content: Text(
            'This will request essential permissions for SIP calls:\n\n'
            '🎤 Microphone - Required for voice calls\n'
            '📷 Camera - Required for video calls\n'
            '📱 Contacts - Optional for contact integration\n\n'
            'iOS will show permission dialogs. Please tap "Allow" to enable full functionality.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Continue'),
            ),
          ],
        ),
      ) ?? false;
      
      if (!shouldContinue) return;
      
      // Force request permissions sequentially with delays
      print('🎤 Requesting microphone permission...');
      
      // Try to trigger native media access to force iOS permission prompt
      MediaStream? audioStream;
      try {
        print('🔄 Attempting to access microphone via getUserMedia...');
        audioStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        print('✅ Native microphone access successful - keeping stream active for 3 seconds');
        
        // Keep the stream active for a few seconds to ensure iOS registers it
        await Future.delayed(Duration(seconds: 3));
        
      } catch (e) {
        print('⚠️ Native microphone access failed: $e');
      } finally {
        // Clean up the stream
        audioStream?.getTracks().forEach((track) => track.stop());
      }
      
      final micStatus = await Permission.microphone.request();
      print('🎤 Microphone result: ${micStatus.name}');
      
      // Small delay between requests
      await Future.delayed(Duration(milliseconds: 500));
      
      print('📷 Requesting camera permission...');
      
      // Try camera access
      MediaStream? videoStream;
      try {
        print('🔄 Attempting to access camera via getUserMedia...');
        videoStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': true,
        });
        print('✅ Native camera access successful - keeping stream active for 3 seconds');
        
        // Keep the stream active for a few seconds to ensure iOS registers it
        await Future.delayed(Duration(seconds: 3));
        
      } catch (e) {
        print('⚠️ Native camera access failed: $e');
      } finally {
        // Clean up the stream
        videoStream?.getTracks().forEach((track) => track.stop());
      }
      
      final camStatus = await Permission.camera.request();
      print('📷 Camera result: ${camStatus.name}');
      
      await Future.delayed(Duration(milliseconds: 500));
      
      print('📱 Requesting contacts permission...');
      final contactsStatus = await Permission.contacts.request();
      print('📱 Contacts result: ${contactsStatus.name}');
      
      // Wait a bit for iOS to update system settings
      await Future.delayed(Duration(milliseconds: 1000));
      
      // Show results
      String resultInfo = 'Permission Results:\n\n';
      resultInfo += '🎤 Microphone: ${_getStatusEmoji(micStatus)} ${micStatus.name}\n';
      resultInfo += '📷 Camera: ${_getStatusEmoji(camStatus)} ${camStatus.name}\n';
      resultInfo += '📱 Contacts: ${_getStatusEmoji(contactsStatus)} ${contactsStatus.name}\n\n';
      
      if (micStatus.isGranted) {
        resultInfo += '✅ Essential permissions granted!\n\n';
        resultInfo += 'Now check:\n';
        resultInfo += '• Settings → Privacy & Security → Microphone\n';
        resultInfo += '• Settings → Privacy & Security → Camera\n\n';
        resultInfo += 'Your app should now appear in these lists.';
      } else {
        resultInfo += '❌ Microphone permission is required for calls.\n\n';
        resultInfo += 'To enable manually:\n';
        resultInfo += '1. Go to Settings → Privacy & Security → Microphone\n';
        resultInfo += '2. Find "Dart Sip Ua Example"\n';
        resultInfo += '3. Toggle it ON';
      }
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Permission Status'),
          content: SingleChildScrollView(
            child: Text(resultInfo),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
            if (!micStatus.isGranted || !camStatus.isGranted)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: Text('Open Settings'),
              ),
          ],
        ),
      );
      
    } catch (e) {
      print('❌ Permission request error: $e');
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Permission Error'),
          content: Text('Error requesting permissions: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }
  
  void _showConnectionStatus() {
    final connectionManager = ConnectionManager();
    
    // Perform immediate status check
    connectionManager.performConnectionStatusCheck();
    
    // Get status for display
    final status = connectionManager.getConnectionStatus();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              status['isConnected'] ? Icons.wifi : Icons.wifi_off,
              color: status['isConnected'] ? Colors.green : Colors.red,
            ),
            SizedBox(width: 8),
            Text('Connection Status'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusRow('Connected', status['isConnected'] ? '✅ YES' : '❌ NO'),
                _statusRow('Should Maintain', status['shouldMaintainConnection'] ? '✅ YES' : '❌ NO'),
                _statusRow('Connecting', status['isConnecting'] ? '🔄 YES' : '✅ NO'),
                _statusRow('Network', status['hasNetworkConnectivity'] ? '✅ Available' : '❌ Unavailable'),
                _statusRow('Attempts', '${status['reconnectionAttempts']}/${status['maxReconnectionAttempts']}'),
                if (status['currentUserName'] != null)
                  _statusRow('User', status['currentUserName']),
                if (status['secondsSinceLastConnection'] != null)
                  _statusRow('Last Connected', '${status['secondsSinceLastConnection']}s ago'),
                if (status['secondsSinceLastAttempt'] != null)
                  _statusRow('Last Attempt', '${status['secondsSinceLastAttempt']}s ago'),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: status['isConnected'] ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status['isConnected'] 
                        ? '✅ SIP connection is active and ready for calls'
                        : '❌ SIP connection is down - auto-reconnection in progress',
                    style: TextStyle(
                      color: status['isConnected'] ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          if (!status['isConnected'])
            ElevatedButton(
              onPressed: () {
                connectionManager.forceReconnect();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Force reconnection initiated...'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              child: Text('Force Reconnect'),
            ),
        ],
      ),
    );
  }
  
  Widget _statusRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label + ':',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
  
  String _getStatusEmoji(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
        return '✅';
      case PermissionStatus.denied:
        return '❌';
      case PermissionStatus.permanentlyDenied:
        return '🚫';
      default:
        return '❓';
    }
  }

  List<Widget> _buildDialPad() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textController = ref.watch(textControllerProvider);
    
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Destination',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _pickContact,
                      icon: Icon(Icons.contact_phone, size: 18),
                      label: Text('Contacts'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _debugPermissions,
                      icon: Icon(Icons.bug_report, size: 16),
                      label: Text('Debug'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        textStyle: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.done,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Enter SIP URI or number',
                suffixIcon: GestureDetector(
                  onTap: () {
                    // Hide keyboard when dialpad icon is tapped
                    FocusScope.of(context).unfocus();
                  },
                  child: const Icon(Icons.dialpad),
                ),
              ),
              controller: textController,
              onSubmitted: (value) {
                // Hide keyboard when done is pressed
                FocusScope.of(context).unfocus();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: _buildNumPad(),
        ),
      ),
      const SizedBox(height: 24),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            ActionButton(
              icon: Icons.videocam_outlined,
              title: 'Video',
              onPressed: () => _handleCall(context),
            ),
            ActionButton(
              icon: Icons.call,
              title: 'Call',
              fillColor: theme.colorScheme.primary,
              checked: true,
              onPressed: () => _handleCall(context, true),
            ),
            ActionButton(
              icon: Icons.backspace_outlined,
              title: 'Clear',
              onPressed: () => _handleBackSpace(),
              onLongPress: () => _handleBackSpace(true),
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isDarkTheme = theme.brightness == Brightness.dark;
    final receivedMsg = ref.watch(receivedMessageProvider);
    final themeNotifier = ref.watch(themeNotifierProvider);

    return GestureDetector(
      onTap: () {
        // Hide keyboard when tapping anywhere on screen
        FocusScope.of(context).unfocus();
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          "SIP Phone",
          style: theme.textTheme.headlineMedium,
        ),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.more_vert),
            onPressed: () {
              // Hide keyboard when opening menu
              FocusScope.of(context).unfocus();
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) => Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(Icons.account_circle_outlined),
                        title: Text('Account Settings'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/register');
                        },
                      ),
                      ListTile(
                        leading: Icon(isDarkTheme ? Icons.light_mode : Icons.dark_mode),
                        title: Text(isDarkTheme ? 'Light Mode' : 'Dark Mode'),
                        onTap: () {
                          isDarkTheme = !isDarkTheme;
                          if (isDarkTheme) {
                            themeNotifier.setDarkmode();
                          } else {
                            themeNotifier.setLightMode();
                          }
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('About'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/about');
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.bug_report),
                        title: Text('Connection Debug'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/debug');
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.security),
                        title: Text('Request Permissions'),
                        subtitle: Text('Force iOS permission requests'),
                        onTap: () {
                          Navigator.pop(context);
                          _forceRequestPermissions();
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.network_check),
                        title: Text('Connection Status'),
                        subtitle: Text('Test persistent connection'),
                        onTap: () {
                          Navigator.pop(context);
                          _showConnectionStatus();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Listener(
        onPointerDown: (_) {
          // Hide keyboard on any touch event
          FocusScope.of(context).unfocus();
        },
        child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 4,
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: helper!.registerState.state == RegistrationStateEnum.REGISTERED
                                ? Colors.green.withValues(alpha: 0.1)
                                : helper!.registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                    ? Colors.red.withValues(alpha: 0.1)
                                    : Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            helper!.registerState.state == RegistrationStateEnum.REGISTERED
                                ? Icons.check_circle
                                : helper!.registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                    ? Icons.error
                                    : Icons.pending,
                            color: helper!.registerState.state == RegistrationStateEnum.REGISTERED
                                ? Colors.green
                                : helper!.registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                    ? Colors.red
                                    : Colors.orange,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getStatusTitle(helper!.registerState.state),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: helper!.registerState.state == RegistrationStateEnum.REGISTERED
                                      ? Colors.green
                                      : helper!.registerState.state == RegistrationStateEnum.REGISTRATION_FAILED
                                          ? Colors.red
                                          : Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _getStatusSubtitle(helper!.registerState.state),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (receivedMsg?.isNotEmpty == true) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.message_outlined,
                              color: colorScheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                receivedMsg!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: _buildDialPad(),
              ),
            ),
          ),
        ],
        ), // Close Listener
      ),
      ), // Close GestureDetector
    );
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    setState(() {
      _logger.i("Registration state: ${state.state?.name}");
    });
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void callStateChanged(Call call, CallState callState) {
    switch (callState.state) {
      case CallStateEnum.CALL_INITIATION:
        Navigator.pushNamed(context, '/callscreen', arguments: call);
        break;
      case CallStateEnum.FAILED:
        reRegisterWithCurrentUser();
        break;
      case CallStateEnum.ENDED:
        reRegisterWithCurrentUser();
        break;
      default:
    }
  }

  void reRegisterWithCurrentUser() async {
    final currentUserCubit = ref.read(sipUserCubitProvider);
    if (currentUserCubit.state == null) return;
    if (helper!.registered) await helper!.unregister();
    _logger.i("Re-registering");
    currentUserCubit.register(currentUserCubit.state!);
  }

  void _forceReconnect() async {
    final currentUserCubit = ref.read(sipUserCubitProvider);
    await currentUserCubit.forceReconnect();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Attempting to reconnect...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _getStatusTitle(RegistrationStateEnum? state) {
    switch (state) {
      case RegistrationStateEnum.REGISTERED:
        return 'Connected';
      case RegistrationStateEnum.REGISTRATION_FAILED:
        return 'Connection Failed';
      case RegistrationStateEnum.UNREGISTERED:
        return 'Disconnected';
      default:
        return 'Connecting...';
    }
  }

  String _getStatusSubtitle(RegistrationStateEnum? state) {
    switch (state) {
      case RegistrationStateEnum.REGISTERED:
        return 'Ready to make calls';
      case RegistrationStateEnum.REGISTRATION_FAILED:
        return 'Check your account settings';
      case RegistrationStateEnum.UNREGISTERED:
        return 'Configure your account';
      default:
        return 'Please wait...';
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    //Save the incoming message to DB
    String? msgBody = msg.request.body as String?;
    ref.read(receivedMessageProvider.notifier).state = msgBody;
  }

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {
    // Handle re-invite events here if needed
  }
}
