import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers.dart';

class DebugScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  String _debugInfo = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
  }

  Future<void> _loadDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final sipUserCubit = ref.read(sipUserCubitProvider);
    final sipHelper = ref.read(sipHelperProvider);
    
    final info = StringBuffer();
    info.writeln('=== SIP CONNECTION DEBUG INFO ===\n');
    
    // Storage info
    info.writeln('📁 STORAGE:');
    info.writeln('• registered_sip_user: ${prefs.getString('registered_sip_user') != null ? 'EXISTS' : 'NULL'}');
    info.writeln('• is_registered: ${prefs.getBool('is_registered') ?? false}');
    
    // SIP helper info
    info.writeln('\n🔌 SIP HELPER:');
    info.writeln('• registered: ${sipHelper.registered}');
    info.writeln('• registration state: ${sipHelper.registerState.state?.name ?? 'UNKNOWN'}');
    
    // SIP user cubit info
    info.writeln('\n👤 SIP USER CUBIT:');
    info.writeln('• state: ${sipUserCubit.state?.authUser ?? 'NULL'}');
    info.writeln('• isRegistered: ${sipUserCubit.isRegistered}');
    
    setState(() {
      _debugInfo = info.toString();
    });
  }

  Future<void> _testReconnect() async {
    try {
      final sipUserCubit = ref.read(sipUserCubitProvider);
      await sipUserCubit.forceReconnect();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Force reconnect initiated')),
      );
      await Future.delayed(Duration(seconds: 2));
      _loadDebugInfo();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('All data cleared')),
    );
    _loadDebugInfo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Connection Debug'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadDebugInfo,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _debugInfo,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _testReconnect,
                    child: Text('Force Reconnect'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _loadDebugInfo,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    child: Text('Refresh'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _clearAllData,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text('Clear All Data'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}