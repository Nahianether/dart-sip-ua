import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/providers.dart';

// Removed duplicate theme provider - using settingsNotifierProvider instead

class SettingsScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final currentTheme = settingsAsync.maybeWhen(
      data: (settings) => settings.themeMode ?? ThemeMode.system,
      orElse: () => ThemeMode.system,
    );
    final account = ref.watch(accountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
          // Account Section
          _buildSection(
            title: 'Account',
            children: [
              account.when(
                data: (acc) => acc != null
                    ? _buildAccountTile(acc)
                    : _buildSignInTile(),
                loading: () => _buildLoadingTile(),
                error: (error, stack) => _buildErrorTile(),
              ),
            ],
          ),

          SizedBox(height: 24),

          // Appearance Section
          _buildSection(
            title: 'Appearance',
            children: [
              _buildThemeTile(currentTheme),
            ],
          ),

          SizedBox(height: 24),

          // Call Settings Section
          _buildSection(
            title: 'Call Settings',
            children: [
              _buildSettingsTile(
                icon: Icons.mic,
                title: 'Audio Settings',
                subtitle: 'Microphone, speaker, and audio quality',
                onTap: () {
                  // TODO: Navigate to audio settings
                },
              ),
              _buildSettingsTile(
                icon: Icons.vibration,
                title: 'Notifications',
                subtitle: 'Ringtone, vibration, and call alerts',
                onTap: () {
                  // TODO: Navigate to notification settings
                },
              ),
              _buildSwitchTile(
                icon: Icons.call_split,
                title: 'Call Waiting',
                subtitle: 'Enable call waiting during active calls',
                value: true, // TODO: Get from preferences
                onChanged: (value) {
                  // TODO: Update call waiting setting
                },
              ),
            ],
          ),

          SizedBox(height: 24),

          // Security Section
          _buildSection(
            title: 'Security',
            children: [
              _buildSettingsTile(
                icon: Icons.vpn_key,
                title: 'VPN Settings',
                subtitle: 'Configure secure VPN connection',
                onTap: () {
                  // TODO: Navigate to VPN settings
                },
              ),
              _buildSwitchTile(
                icon: Icons.security,
                title: 'Auto VPN Connect',
                subtitle: 'Automatically connect VPN for calls',
                value: true, // TODO: Get from preferences
                onChanged: (value) {
                  // TODO: Update auto VPN setting
                },
              ),
            ],
          ),

          SizedBox(height: 24),

          // About Section
          _buildSection(
            title: 'About',
            children: [
              _buildSettingsTile(
                icon: Icons.info_outline,
                title: 'App Version',
                subtitle: '1.0.0',
                onTap: () {
                  _showAboutDialog();
                },
              ),
              _buildSettingsTile(
                icon: Icons.help_outline,
                title: 'Help & Support',
                subtitle: 'Get help with using the app',
                onTap: () {
                  // TODO: Navigate to help screen
                },
              ),
              _buildSettingsTile(
                icon: Icons.bug_report,
                title: 'Debug Information',
                subtitle: 'Connection and diagnostic info',
                onTap: () {
                  // TODO: Navigate to debug screen
                },
              ),
            ],
          ),

          SizedBox(height: 24),

          // Sign Out Section (if signed in)
          account.when(
            data: (acc) => acc != null
                ? _buildSection(
                    title: 'Account Actions',
                    children: [
                      _buildSettingsTile(
                        icon: Icons.logout,
                        title: 'Sign Out',
                        subtitle: 'Sign out from your SIP account',
                        iconColor: Colors.red,
                        onTap: () {
                          _showSignOutDialog();
                        },
                      ),
                    ],
                  )
                : SizedBox.shrink(),
            loading: () => SizedBox.shrink(),
            error: (error, stack) => SizedBox.shrink(),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Colors.blue).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Colors.blue,
          size: 20,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: Colors.blue,
          size: 20,
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildThemeTile(ThemeMode currentTheme) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.palette_outlined,
          color: Colors.purple,
          size: 20,
        ),
      ),
      title: Text('Theme'),
      subtitle: Text(_getThemeText(currentTheme)),
      trailing: Icon(Icons.chevron_right),
      onTap: () {
        _showThemeDialog();
      },
    );
  }

  Widget _buildAccountTile(account) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.account_circle,
          color: Colors.green,
          size: 20,
        ),
      ),
      title: Text('Connected Account'),
      subtitle: Text(account.username ?? 'SIP Account'),
      trailing: Icon(Icons.chevron_right),
      onTap: () {
        // TODO: Navigate to account details
      },
    );
  }

  Widget _buildSignInTile() {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.login,
          color: Colors.orange,
          size: 20,
        ),
      ),
      title: Text('Sign In'),
      subtitle: Text('Connect to your SIP account'),
      trailing: Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).pop(); // Go back to login screen
      },
    );
  }

  Widget _buildLoadingTile() {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      title: Text('Loading...'),
      subtitle: Text('Checking account status'),
    );
  }

  Widget _buildErrorTile() {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.error,
          color: Colors.red,
          size: 20,
        ),
      ),
      title: Text('Account Error'),
      subtitle: Text('Unable to load account information'),
      trailing: Icon(Icons.refresh),
      onTap: () {
        // TODO: Retry loading account
      },
    );
  }

  String _getThemeText(ThemeMode theme) {
    switch (theme) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  void _showThemeDialog() {
    final settingsAsync = ref.read(settingsNotifierProvider);
    final currentTheme = settingsAsync.maybeWhen(
      data: (settings) => settings.themeMode ?? ThemeMode.system,
      orElse: () => ThemeMode.system,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption(
              'Light',
              ThemeMode.light,
              Icons.light_mode,
              currentTheme,
            ),
            _buildThemeOption(
              'Dark',
              ThemeMode.dark,
              Icons.dark_mode,
              currentTheme,
            ),
            _buildThemeOption(
              'System default',
              ThemeMode.system,
              Icons.settings_brightness,
              currentTheme,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    String title,
    ThemeMode mode,
    IconData icon,
    ThemeMode currentTheme,
  ) {
    final isSelected = currentTheme == mode;
    
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).primaryColor : null,
      ),
      title: Text(title),
      trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
      onTap: () async {
        // Update theme using the settings notifier that saves to Hive
        await ref.read(settingsNotifierProvider.notifier).updateTheme(mode);
        Navigator.pop(context);
      },
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out from your SIP account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(accountProvider.notifier).logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'SIP Phone',
      applicationVersion: '1.0.0',
      applicationIcon: Icon(Icons.phone, size: 48),
      children: [
        Text('A modern SIP client with VPN support for secure voice calls.'),
        SizedBox(height: 16),
        Text('Features:'),
        Text('• Secure VPN tunneling'),
        Text('• Modern material design'),
        Text('• Call history and contacts'),
        Text('• Dark and light themes'),
      ],
    );
  }
}