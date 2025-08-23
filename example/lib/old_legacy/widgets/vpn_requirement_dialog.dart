import 'package:flutter/material.dart';

/// Dialog to inform user that VPN connection is required
class VPNRequirementDialog extends StatelessWidget {
  final VoidCallback? onConfigureVPN;
  final VoidCallback? onCancel;
  final String message;

  const VPNRequirementDialog({
    Key? key,
    this.onConfigureVPN,
    this.onCancel,
    this.message = 'VPN connection is required to establish secure SIP connection.',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Icon(
            Icons.vpn_lock,
            color: Colors.orange.shade700,
            size: 28,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'VPN Required',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              height: 1.4,
            ),
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.security,
                  color: Colors.orange.shade600,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'VPN ensures secure and encrypted communication.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            onCancel?.call();
          },
          child: Text(
            'Cancel',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onConfigureVPN?.call();
          },
          icon: Icon(Icons.settings),
          label: Text('Configure VPN'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade600,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

/// Show VPN requirement dialog
Future<bool?> showVPNRequirementDialog(
  BuildContext context, {
  String? customMessage,
  VoidCallback? onConfigureVPN,
  VoidCallback? onCancel,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false, // Force user to make a choice
    builder: (BuildContext context) {
      return VPNRequirementDialog(
        message: customMessage ?? 'VPN connection is required to establish secure SIP connection.',
        onConfigureVPN: onConfigureVPN,
        onCancel: onCancel,
      );
    },
  );
}