import 'package:flutter/material.dart';
import '../vpn_manager.dart';

/// Simplified widget to show VPN connection status
class VPNStatusIndicator extends StatefulWidget {
  
  const VPNStatusIndicator({
    super.key,
  });

  @override
  State<VPNStatusIndicator> createState() => _VPNStatusIndicatorState();
}

class _VPNStatusIndicatorState extends State<VPNStatusIndicator> {
  VpnConnectionStatus _status = VpnConnectionStatus.disconnected;
  final VPNManager _vpnManager = VPNManager();

  @override
  void initState() {
    super.initState();
    
    // Set up status listener
    try {
      _vpnManager.onVpnStatusChanged = (status) {
        if (mounted) {
          setState(() {
            _status = status;
          });
        }
      };
      
      // Get initial status
      _updateStatus();
    } catch (e) {
      print('VPN Status Indicator error: $e');
    }
  }

  void _updateStatus() {
    setState(() {
      _status = _vpnManager.isConnected 
        ? VpnConnectionStatus.connected 
        : VpnConnectionStatus.disconnected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(_status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getStatusIcon(_status),
            size: 16,
            color: Colors.white,
          ),
          SizedBox(width: 4),
          Text(
            _getStatusText(_status),
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return Colors.green;
      case VpnConnectionStatus.connecting:
        return Colors.orange;
      case VpnConnectionStatus.disconnected:
        return Colors.red;
      case VpnConnectionStatus.error:
        return Colors.red[700]!;
      case VpnConnectionStatus.denied:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return Icons.vpn_lock;
      case VpnConnectionStatus.connecting:
        return Icons.vpn_key;
      case VpnConnectionStatus.disconnected:
        return Icons.vpn_key_off;
      case VpnConnectionStatus.error:
        return Icons.error;
      case VpnConnectionStatus.denied:
        return Icons.block;
    }
  }

  String _getStatusText(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return 'VPN Connected';
      case VpnConnectionStatus.connecting:
        return 'Connecting...';
      case VpnConnectionStatus.disconnected:
        return 'VPN Off';
      case VpnConnectionStatus.error:
        return 'VPN Error';
      case VpnConnectionStatus.denied:
        return 'VPN Denied';
    }
  }

  @override
  void dispose() {
    _vpnManager.onVpnStatusChanged = null;
    super.dispose();
  }
}