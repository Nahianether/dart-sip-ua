import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class RecentCallsScreen extends StatefulWidget {
  @override
  State<RecentCallsScreen> createState() => _RecentCallsScreenState();
}

class _RecentCallsScreenState extends State<RecentCallsScreen> {
  List<CallHistoryItem> _callHistory = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCallHistory();
  }

  Future<void> _loadCallHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList('call_history') ?? [];
      
      setState(() {
        _callHistory = historyJson
            .map((json) => CallHistoryItem.fromJson(jsonDecode(json)))
            .toList();
        _callHistory.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        _loading = false;
      });
    } catch (e) {
      print('Error loading call history: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear Call History'),
        content: Text('Are you sure you want to clear all call history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('call_history');
      setState(() {
        _callHistory.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Call history cleared')),
      );
    }
  }

  void _callNumber(String number) {
    Navigator.pop(context, number);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Recent Calls'),
        actions: [
          if (_callHistory.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_all),
              onPressed: _clearHistory,
              tooltip: 'Clear History',
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _callHistory.isEmpty
              ? _buildEmptyState()
              : _buildCallList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'No Recent Calls',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SizedBox(height: 8),
          Text(
            'Your call history will appear here',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildCallList() {
    return ListView.builder(
      itemCount: _callHistory.length,
      itemBuilder: (context, index) {
        final call = _callHistory[index];
        return _buildCallItem(call);
      },
    );
  }

  Widget _buildCallItem(CallHistoryItem call) {
    final theme = Theme.of(context);
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getCallTypeColor(call.type),
        child: Icon(
          _getCallTypeIcon(call.type),
          color: Colors.white,
        ),
      ),
      title: Text(
        call.number,
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatCallType(call.type)),
          Text(
            _formatDateTime(call.timestamp),
            style: theme.textTheme.bodySmall,
          ),
          if (call.duration > 0)
            Text(
              'Duration: ${_formatDuration(call.duration)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.green,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () => _showCallDetails(call),
          ),
          IconButton(
            icon: Icon(Icons.call),
            onPressed: () => _callNumber(call.number),
          ),
        ],
      ),
      onTap: () => _callNumber(call.number),
    );
  }

  Color _getCallTypeColor(CallType type) {
    switch (type) {
      case CallType.outgoing:
        return Colors.green;
      case CallType.incoming:
        return Colors.blue;
      case CallType.missed:
        return Colors.red;
      case CallType.failed:
        return Colors.orange;
    }
  }

  IconData _getCallTypeIcon(CallType type) {
    switch (type) {
      case CallType.outgoing:
        return Icons.call_made;
      case CallType.incoming:
        return Icons.call_received;
      case CallType.missed:
        return Icons.call_received;
      case CallType.failed:
        return Icons.call_end;
    }
  }

  String _formatCallType(CallType type) {
    switch (type) {
      case CallType.outgoing:
        return 'Outgoing call';
      case CallType.incoming:
        return 'Incoming call';
      case CallType.missed:
        return 'Missed call';
      case CallType.failed:
        return 'Failed call';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      // Today
      return 'Today ${_formatTime(dateTime)}';
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday ${_formatTime(dateTime)}';
    } else if (difference.inDays < 7) {
      // This week
      final weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dateTime.weekday - 1];
      return '$weekday ${_formatTime(dateTime)}';
    } else {
      // Older
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${_formatTime(dateTime)}';
    }
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour == 0 ? 12 : (dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour);
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final amPm = dateTime.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $amPm';
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    
    if (minutes == 0) {
      return '${secs}s';
    } else {
      return '${minutes}m ${secs}s';
    }
  }

  void _showCallDetails(CallHistoryItem call) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Call Details'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _detailRow('Number:', call.number),
            _detailRow('Type:', _formatCallType(call.type)),
            _detailRow('Date:', _formatDateTime(call.timestamp)),
            if (call.duration > 0)
              _detailRow('Duration:', _formatDuration(call.duration)),
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
              _callNumber(call.number);
            },
            child: Text('Call'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class CallHistoryItem {
  final String number;
  final CallType type;
  final DateTime timestamp;
  final int duration; // seconds

  CallHistoryItem({
    required this.number,
    required this.type,
    required this.timestamp,
    this.duration = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'type': type.index,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'duration': duration,
    };
  }

  factory CallHistoryItem.fromJson(Map<String, dynamic> json) {
    return CallHistoryItem(
      number: json['number'] as String,
      type: CallType.values[json['type'] as int],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      duration: json['duration'] as int? ?? 0,
    );
  }
}

enum CallType {
  outgoing,
  incoming,
  missed,
  failed,
}

class CallHistoryManager {
  static Future<void> addCall({
    required String number,
    required CallType type,
    int duration = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList('call_history') ?? [];
      
      final newCall = CallHistoryItem(
        number: number,
        type: type,
        timestamp: DateTime.now(),
        duration: duration,
      );
      
      historyJson.insert(0, jsonEncode(newCall.toJson()));
      
      // Keep only last 100 calls
      if (historyJson.length > 100) {
        historyJson.removeRange(100, historyJson.length);
      }
      
      await prefs.setStringList('call_history', historyJson);
      print('✅ Call added to history: $number (${type.name})');
    } catch (e) {
      print('❌ Error adding call to history: $e');
    }
  }
}