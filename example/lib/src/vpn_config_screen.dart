import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connection_manager.dart';

class VPNConfigScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<VPNConfigScreen> createState() => _VPNConfigScreenState();
}

class _VPNConfigScreenState extends ConsumerState<VPNConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _customConfigController = TextEditingController();
  
  bool _autoConnect = true;
  bool _isLoading = false;
  bool _showPassword = false;

  late ConnectionManager _connectionManager;

  @override
  void initState() {
    super.initState();
    _connectionManager = ConnectionManager();
    _loadExistingConfig();
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _customConfigController.dispose();
    super.dispose();
  }

  void _loadExistingConfig() async {
    try {
      final vpnManager = _connectionManager.vpnManager;
      await vpnManager.initialize(); // Ensure VPN manager is initialized
      final info = vpnManager.getConnectionInfo();
      
      setState(() {
        _serverController.text = info['serverAddress'] ?? '';
        _usernameController.text = info['username'] ?? '';
        _autoConnect = info['shouldAutoConnect'] ?? true;
      });
    } catch (e) {
      print('Error loading VPN config: $e');
      // Set defaults if loading fails
      setState(() {
        _autoConnect = true;
      });
    }
  }

  Future<void> _saveVPNConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _connectionManager.configureVPN(
        serverAddress: _serverController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        customConfig: _customConfigController.text.trim().isEmpty 
            ? null 
            : _customConfigController.text.trim(),
        enableAutoConnect: _autoConnect,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('VPN configuration saved successfully'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('VPN configuration failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testVPNConnection() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Save config first
      await _connectionManager.configureVPN(
        serverAddress: _serverController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        customConfig: _customConfigController.text.trim().isEmpty 
            ? null 
            : _customConfigController.text.trim(),
        enableAutoConnect: false, // Don't auto-connect during test
      );

      final success = await _connectionManager.testVPNConnection();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
              ? 'VPN connection test successful!' 
              : 'VPN connection test failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('VPN test error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('VPN Configuration'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveVPNConfig,
            child: Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'VPN Server Configuration',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Configure VPN settings for secure SIP connection. The VPN will connect automatically before establishing SIP connection.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            
            // Server Address
            TextFormField(
              controller: _serverController,
              decoration: InputDecoration(
                labelText: 'VPN Server Address',
                hintText: 'vpn.example.com',
                prefixIcon: Icon(Icons.dns),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Server address is required';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            
            // Username
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'VPN Username',
                hintText: 'Enter your VPN username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Username is required';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            
            // Password
            TextFormField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'VPN Password',
                hintText: 'Enter your VPN password',
                prefixIcon: Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _showPassword = !_showPassword;
                    });
                  },
                ),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Password is required';
                }
                return null;
              },
            ),
            SizedBox(height: 16),
            
            // Auto-connect toggle
            Card(
              child: SwitchListTile(
                title: Text('Auto-connect VPN'),
                subtitle: Text('Automatically connect VPN before SIP connection'),
                value: _autoConnect,
                onChanged: (value) {
                  setState(() {
                    _autoConnect = value;
                  });
                },
                secondary: Icon(Icons.vpn_key),
              ),
            ),
            SizedBox(height: 16),
            
            // Custom config (optional)
            ExpansionTile(
              title: Text('Custom OpenVPN Configuration (Optional)'),
              subtitle: Text('Advanced users can provide custom .ovpn config'),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: TextFormField(
                    controller: _customConfigController,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: 'Paste your custom OpenVPN configuration here...\n\nExample:\nclient\ndev tun\nproto udp\nremote your-server.com 1194\n...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 24),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testVPNConnection,
                    icon: _isLoading 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.wifi_protected_setup),
                    label: Text(_isLoading ? 'Testing...' : 'Test Connection'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.all(16),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveVPNConfig,
                    icon: Icon(Icons.save),
                    label: Text('Save & Configure'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            
            // Help text
            Card(
              color: Colors.blue.withOpacity(0.1),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'How it works',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Configure your VPN server details above\n'
                      '2. Enable "Auto-connect VPN" if you want automatic VPN connection\n'
                      '3. When you connect to SIP, VPN will connect first for security\n'
                      '4. All SIP traffic will be routed through the VPN tunnel',
                      style: TextStyle(color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}