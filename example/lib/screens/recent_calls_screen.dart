import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/call_log_service.dart';
import '../data/models/call_log_model.dart' as Models;

final recentCallsProvider = FutureProvider<List<Models.CallLogModel>>((ref) async {
  return await CallLogService().getRecentCalls();
});

class RecentCallsScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<RecentCallsScreen> createState() => _RecentCallsScreenState();
}

class _RecentCallsScreenState extends ConsumerState<RecentCallsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Calls',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.clear_all),
                  onPressed: () {
                    _showClearAllDialog();
                  },
                ),
              ],
            ),
          ),
          
          // Call List
          Expanded(
            child: _buildCallList(),
          ),
        ],
      ),
    );
  }

  Widget _buildCallList() {
    return Consumer(
      builder: (context, ref, child) {
        final callLogsAsync = ref.watch(recentCallsProvider);
        
        return callLogsAsync.when(
          data: (callLogs) {
            if (callLogs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No recent calls',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your call history will appear here',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: callLogs.length,
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemBuilder: (context, index) {
                final callLog = callLogs[index];
                return _buildCallItem(callLog);
              },
            );
          },
          loading: () => Center(child: CircularProgressIndicator()),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 80,
                  color: Colors.grey[400],
                ),
                SizedBox(height: 16),
                Text(
                  'Error loading call history',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCallItem(Models.CallLogModel callLog) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[300],
            ),
            child: callLog.contactName != null && callLog.contactName!.isNotEmpty
              ? Text(
                  callLog.initials,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                )
              : Icon(
                  Icons.person,
                  color: Colors.grey[600],
                ),
          ),
          
          SizedBox(width: 16),
          
          // Call details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  callLog.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      _getCallTypeIcon(callLog.direction, callLog.missed),
                      size: 14,
                      color: _getCallTypeColor(callLog.direction, callLog.missed),
                    ),
                    SizedBox(width: 4),
                    Text(
                      callLog.phoneNumber,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Time and actions
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                callLog.formattedTime,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
              SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.info_outline),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: () {
                      _showCallDetailsDialog(callLog);
                    },
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.phone),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    color: Colors.green,
                    onPressed: () {
                      _callBack(callLog.phoneNumber);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getCallTypeIcon(Models.CallDirection direction, bool missed) {
    if (missed) {
      return Icons.call_received;
    }
    
    switch (direction) {
      case Models.CallDirection.outgoing:
        return Icons.call_made;
      case Models.CallDirection.incoming:
        return Icons.call_received;
    }
  }

  Color _getCallTypeColor(Models.CallDirection direction, bool missed) {
    if (missed) {
      return Colors.red;
    }
    
    switch (direction) {
      case Models.CallDirection.outgoing:
        return Colors.green;
      case Models.CallDirection.incoming:
        return Colors.blue;
    }
  }

  void _callBack(String number) {
    // TODO: Implement callback functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calling $number...'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showCallDetailsDialog(Models.CallLogModel callLog) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Call Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Name', callLog.displayName),
            _buildDetailRow('Number', callLog.phoneNumber),
            _buildDetailRow('Time', callLog.formattedTime),
            _buildDetailRow('Duration', callLog.formattedDuration ?? 'N/A'),
            _buildDetailRow('Type', _formatCallType(callLog.direction)),
            _buildDetailRow('Status', callLog.missed ? 'Missed' : 'Answered'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _callBack(callLog.phoneNumber);
            },
            child: Text('Call Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  String _formatCallType(Models.CallDirection direction) {
    switch (direction) {
      case Models.CallDirection.outgoing:
        return 'Outgoing';
      case Models.CallDirection.incoming:
        return 'Incoming';
    }
  }

  void _showClearAllDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Clear All Calls'),
        content: Text('Are you sure you want to clear all recent calls? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await CallLogService().clearCallHistory();
                ref.refresh(recentCallsProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('All calls cleared'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error clearing calls: $e'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Clear All'),
          ),
        ],
      ),
    );
  }
}