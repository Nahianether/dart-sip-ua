import 'dart:async';
import 'package:flutter/material.dart';
import 'websocket_connection_manager.dart';
import 'vpn_manager.dart';

/// Widget to show VPN connection status
class VPNStatusIndicator extends StatefulWidget {
  final WebSocketConnectionManager? connectionManager;
  
  const VPNStatusIndicator({
    super.key,
    this.connectionManager,
  });

  @override
  State<VPNStatusIndicator> createState() => _VPNStatusIndicatorState();
}

class _VPNStatusIndicatorState extends State<VPNStatusIndicator> {
  VpnConnectionStatus _status = VpnConnectionStatus.disconnected;
  late WebSocketConnectionManager _connectionManager;

  @override
  void initState() {
    super.initState();
    _connectionManager = widget.connectionManager ?? WebSocketConnectionManager();
    
    // Set up status listener first
    try {
      _connectionManager.vpnManager.onVpnStatusChanged = (status) {
        print('VPN Status listener triggered: $status');
        if (mounted) {
          setState(() {
            _status = status;
          });
        }
      };
    } catch (e) {
      print('Error setting up VPN status listener: $e');
    }
    
    // Get initial status
    _updateStatus();
    
    // Force an additional status check after a brief delay to catch any immediate changes
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        _updateStatus();
      }
    });
    
    // Update status periodically
    Timer.periodic(Duration(seconds: 2), (timer) {
      if (mounted) {
        _updateStatus();
      } else {
        timer.cancel();
      }
    });
  }

  void _updateStatus() {
    try {
      final vpnManager = _connectionManager.vpnManager;
      final currentStatus = vpnManager.currentStatus;
      
      // Debug logging to track status changes
      if (_status != currentStatus) {
        print('VPN Status changing from $_status to $currentStatus');
      }
      
      if (mounted) {
        setState(() {
          _status = currentStatus;
        });
      }
    } catch (e) {
      print('Error updating VPN status: $e');
      if (mounted) {
        setState(() {
          _status = VpnConnectionStatus.disconnected;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor().withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getStatusColor(),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getStatusIcon(),
            color: _getStatusColor(),
            size: 16,
          ),
          SizedBox(width: 6),
          Text(
            _getStatusText(),
            style: TextStyle(
              color: _getStatusColor(),
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (_status) {
      case VpnConnectionStatus.connected:
        return Colors.green;
      case VpnConnectionStatus.connecting:
        return Colors.orange;
      case VpnConnectionStatus.error:
      case VpnConnectionStatus.denied:
        return Colors.red;
      case VpnConnectionStatus.disconnected:
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    switch (_status) {
      case VpnConnectionStatus.connected:
        return Icons.vpn_lock;
      case VpnConnectionStatus.connecting:
        return Icons.sync;
      case VpnConnectionStatus.error:
      case VpnConnectionStatus.denied:
        return Icons.error;
      case VpnConnectionStatus.disconnected:
      default:
        return Icons.vpn_key_off;
    }
  }

  String _getStatusText() {
    switch (_status) {
      case VpnConnectionStatus.connected:
        return 'VPN Connected';
      case VpnConnectionStatus.connecting:
        return 'VPN Connecting';
      case VpnConnectionStatus.error:
        return 'VPN Error';
      case VpnConnectionStatus.denied:
        return 'VPN Denied';
      case VpnConnectionStatus.disconnected:
      default:
        return 'VPN Disconnected';
    }
  }
}