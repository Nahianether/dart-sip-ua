import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  /// Shows a dialog to guide users to app settings for permanently denied permissions
  static Future<void> showPermissionDialog(
    BuildContext context, {
    required List<Permission> deniedPermissions,
    required String title,
    required String message,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.security, color: Theme.of(context).colorScheme.error),
              SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message),
                SizedBox(height: 16),
                Text(
                  'Required permissions:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                ...deniedPermissions.map((permission) {
                  final permissionInfo = _getPermissionInfo(permission);
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(permissionInfo.icon, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                permissionInfo.name,
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              Text(
                                permissionInfo.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How to enable permissions:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(height: 8),
                      _buildStep('1', 'Open device Settings'),
                      _buildStep('2', 'Find "Apps" or "Application Manager"'),
                      _buildStep('3', 'Select "SIP Phone"'),
                      _buildStep('4', 'Tap "Permissions"'),
                      _buildStep('5', 'Enable the required permissions'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Later'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.settings),
              label: Text('Open Settings'),
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  /// Checks if essential permissions are granted
  static Future<bool> hasEssentialPermissions() async {
    final microphone = await Permission.microphone.isGranted;
    final notification = await Permission.notification.isGranted;
    return microphone && notification;
  }

  /// Checks all permissions and shows dialog if needed
  static Future<void> checkAndRequestPermissions(BuildContext context) async {
    final essentialPermissions = [
      Permission.microphone,
      Permission.notification,
    ];

    final denied = <Permission>[];
    
    for (final permission in essentialPermissions) {
      final status = await permission.status;
      if (status != PermissionStatus.granted) {
        // Try requesting once more
        final newStatus = await permission.request();
        if (newStatus != PermissionStatus.granted) {
          denied.add(permission);
        }
      }
    }

    if (denied.isNotEmpty && context.mounted) {
      await showPermissionDialog(
        context,
        deniedPermissions: denied,
        title: 'Permissions Required',
        message: 'SIP Phone needs these permissions to work properly. '
            'Without them, you may not be able to make calls or receive notifications.',
      );
    }
  }

  static Widget _buildStep(String number, String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  static _PermissionInfo _getPermissionInfo(Permission permission) {
    if (permission == Permission.microphone) {
      return _PermissionInfo(
        name: 'Microphone',
        description: 'Required to make and receive voice calls',
        icon: Icons.mic,
      );
    } else if (permission == Permission.notification) {
      return _PermissionInfo(
        name: 'Notifications',
        description: 'Required to show incoming call alerts',
        icon: Icons.notifications,
      );
    } else if (permission == Permission.camera) {
      return _PermissionInfo(
        name: 'Camera',
        description: 'Required for video calls',
        icon: Icons.videocam,
      );
    } else if (permission == Permission.contacts) {
      return _PermissionInfo(
        name: 'Contacts',
        description: 'Optional: Access your contacts for easier dialing',
        icon: Icons.contacts,
      );
    } else if (permission == Permission.phone) {
      return _PermissionInfo(
        name: 'Phone',
        description: 'Required for call management features',
        icon: Icons.phone,
      );
    } else {
      return _PermissionInfo(
        name: permission.toString().split('.').last,
        description: 'Required for app functionality',
        icon: Icons.security,
      );
    }
  }
}

class _PermissionInfo {
  final String name;
  final String description;
  final IconData icon;

  _PermissionInfo({
    required this.name,
    required this.description,
    required this.icon,
  });
}