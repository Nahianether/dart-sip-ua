import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/providers.dart';
import '../src/vpn_manager.dart';
import '../domain/entities/sip_account_entity.dart';
import '../data/services/contacts_service.dart';
import '../data/models/contact_model.dart';
import '../utils/phone_number_formatter.dart';
import 'modern_call_screen.dart';
import 'recent_calls_screen.dart';
import 'settings_screen.dart';

final contactsProvider = FutureProvider<List<ContactModel>>((ref) async {
  final contactsService = ContactsService();
  return await contactsService.getStoredContacts();
});

final contactSearchProvider = StateProvider<String>((ref) => '');

// Provider for the current dialed number
final currentNumberProvider = StateProvider<String>((ref) => '');

class ModernDialerScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<ModernDialerScreen> createState() => _ModernDialerScreenState();
}

class _ModernDialerScreenState extends ConsumerState<ModernDialerScreen> 
    with TickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  late TabController _tabController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pulseController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Listen for call state changes and navigate to call screen
    ref.listenManual(callStateProvider, (previous, next) {
      if (next != null && previous == null) {
        // Call was initiated
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ModernCallScreen(call: next),
          ),
        );
      } else if (next == null && previous != null) {
        // Call ended, pop call screen if it exists
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _tabController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onNumberPressed(String number) {
    final currentNumber = ref.read(currentNumberProvider);
    final newNumber = currentNumber + number;
    ref.read(currentNumberProvider.notifier).state = newNumber;
    _phoneController.text = newNumber;
  }

  void _onBackspacePressed() {
    final currentNumber = ref.read(currentNumberProvider);
    if (currentNumber.isNotEmpty) {
      final newNumber = currentNumber.substring(0, currentNumber.length - 1);
      ref.read(currentNumberProvider.notifier).state = newNumber;
      _phoneController.text = newNumber;
    }
  }

  void _onClearPressed() {
    ref.read(currentNumberProvider.notifier).state = '';
    _phoneController.text = '';
  }

  void _onCallPressed() async {
    final currentNumber = ref.read(currentNumberProvider);
    if (currentNumber.isNotEmpty) {
      // Add haptic feedback
      HapticFeedback.heavyImpact();
      
      // Check if registered first
      final accountState = ref.read(accountProvider);
      final account = accountState.valueOrNull;
      if (account == null) {
        _showErrorSnackBar('Please register your account first');
        return;
      }
      
      // Format the phone number for SIP calling (remove +88/+880)
      final formattedNumber = PhoneNumberFormatter.formatForSipCall(currentNumber);
      
      // Validate the number
      if (!PhoneNumberFormatter.isValidPhoneNumber(formattedNumber)) {
        _showErrorSnackBar('Please enter a valid phone number');
        return;
      }
      
      print('📞 Calling: $currentNumber -> $formattedNumber');
      
      // Make the call with formatted number
      ref.read(callStateProvider.notifier).makeCall(formattedNumber);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final connectionStatus = ref.watch(connectionStatusProvider);
    final vpnStatus = ref.watch(vpnStatusProvider);
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          'SIP Phone',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => SettingsScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: Icon(Icons.dialpad), text: 'Dial'),
            Tab(icon: Icon(Icons.history), text: 'Recent'),
            Tab(icon: Icon(Icons.contacts), text: 'Contacts'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Connection Status Bar
          _buildConnectionStatus(connectionStatus, vpnStatus, isDark),
          
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Dialer Tab
                _buildDialerTab(theme, isDark),
                
                // Recent Calls Tab
                RecentCallsScreen(),
                
                // Contacts Tab
                _buildContactsTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(AsyncValue connectionStatus, VpnConnectionStatus vpnStatus, bool isDark) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Connection Status
          Expanded(
            child: connectionStatus.when(
              data: (status) => Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColor(status).withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getStatusText(status),
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              loading: () => Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Connecting...'),
                ],
              ),
              error: (error, stack) => Row(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Connection Error')),
                ],
              ),
            ),
          ),
          
          // VPN Status
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getVPNStatusColor(vpnStatus).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getVPNStatusIcon(vpnStatus),
                  size: 14,
                  color: _getVPNStatusColor(vpnStatus),
                ),
                SizedBox(width: 4),
                Text(
                  vpnStatus == VpnConnectionStatus.connected ? 'Secure' : 'VPN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _getVPNStatusColor(vpnStatus),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialerTab(ThemeData theme, bool isDark) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            // Phone Number Display
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  width: 0.5,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    ref.watch(currentNumberProvider).isEmpty ? 'Enter number' : ref.watch(currentNumberProvider),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: ref.watch(currentNumberProvider).isEmpty 
                          ? (isDark ? Colors.grey[500] : Colors.grey[600])
                          : (isDark ? Colors.white : Colors.black87),
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (ref.watch(currentNumberProvider).isNotEmpty) ...[
                    SizedBox(height: 4),
                    Consumer(
                      builder: (context, ref, child) {
                        final currentNumber = ref.watch(currentNumberProvider);
                        final formattedNumber = PhoneNumberFormatter.formatForSipCall(currentNumber);
                        final isFormatted = currentNumber != formattedNumber;
                        
                        return Column(
                          children: [
                            if (isFormatted) ...[
                              Text(
                                'Will call: $formattedNumber',
                                style: TextStyle(
                                  color: Colors.blue[600],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 2),
                            ],
                            Text(
                              isFormatted ? 'Number formatted for calling' : 'Ready to call',
                              style: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[600],
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            
            // Dialpad - Fill available space properly
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableHeight = constraints.maxHeight - 80; // Reserve space for buttons
                  final dialpadSize = (constraints.maxWidth - 40).clamp(240.0, 320.0);
                  
                  return Center(
                    child: Container(
                      width: dialpadSize,
                      height: availableHeight.clamp(280.0, 400.0),
                      child: _buildModernDialpad(),
                    ),
                  );
                },
              ),
            ),
            
            // Action Buttons - Fixed at bottom
            Container(
              height: 80,
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Backspace
                  _buildActionButton(
                    icon: Icons.backspace_outlined,
                    onPressed: ref.watch(currentNumberProvider).isNotEmpty ? _onBackspacePressed : null,
                    onLongPress: ref.watch(currentNumberProvider).isNotEmpty ? _onClearPressed : null,
                    backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                    iconColor: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 52,
                  ),
                  
                  // Call Button
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: ref.watch(currentNumberProvider).isNotEmpty ? _pulseAnimation.value : 1.0,
                        child: _buildActionButton(
                          icon: Icons.phone,
                          onPressed: ref.watch(currentNumberProvider).isNotEmpty ? _onCallPressed : null,
                          backgroundColor: ref.watch(currentNumberProvider).isNotEmpty ? Colors.green : Colors.grey[300],
                          iconColor: Colors.white,
                          size: 64,
                          iconSize: 26,
                        ),
                      );
                    },
                  ),
                  
                  // Add Contact
                  _buildActionButton(
                    icon: Icons.person_add_outlined,
                    onPressed: ref.watch(currentNumberProvider).isNotEmpty ? () {
                      // TODO: Add contact functionality
                    } : null,
                    backgroundColor: isDark ? Colors.blue[900] : Colors.blue[50],
                    iconColor: isDark ? Colors.blue[300] : Colors.blue[600],
                    size: 52,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernDialpad() {
    final dialpadNumbers = [
      ['1', ''], ['2', 'ABC'], ['3', 'DEF'],
      ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'],
      ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'],
      ['*', ''], ['0', '+'], ['#', ''],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonSize = (constraints.maxWidth / 3 - 16).clamp(55.0, 75.0);
        final spacing = (constraints.maxWidth - (buttonSize * 3)) / 4;
        
        return GridView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: spacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.0,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing.clamp(8.0, 16.0),
          ),
          itemCount: dialpadNumbers.length,
          itemBuilder: (context, index) {
            final number = dialpadNumbers[index][0];
            final letters = dialpadNumbers[index][1];
            
            return _buildDialpadButton(number, letters, buttonSize);
          },
        );
      },
    );
  }

  Widget _buildDialpadButton(String number, String letters, double size) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fontSize = (size * 0.32).clamp(16.0, 24.0);
    final letterSize = (size * 0.12).clamp(7.0, 10.0);
    
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(size / 2),
      color: isDark ? Colors.grey[850] : Colors.grey[50],
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: () {
          HapticFeedback.lightImpact();
          _onNumberPressed(number);
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size / 2),
            border: Border.all(
              color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                number,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (letters.isNotEmpty) ...[
                SizedBox(height: 1),
                Text(
                  letters,
                  style: TextStyle(
                    fontSize: letterSize,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    Color? backgroundColor,
    Color? iconColor,
    double size = 60,
    double iconSize = 24,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      elevation: onPressed != null ? 2 : 0.5,
      borderRadius: BorderRadius.circular(size / 2),
      color: onPressed != null 
          ? backgroundColor 
          : (isDark ? Colors.grey[800] : Colors.grey[300]),
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: onPressed,
        onLongPress: onLongPress,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size / 2),
            border: Border.all(
              color: onPressed != null 
                  ? Colors.transparent 
                  : (isDark ? Colors.grey[700]! : Colors.grey[400]!),
              width: 0.5,
            ),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: onPressed != null 
                ? iconColor 
                : (isDark ? Colors.grey[500] : Colors.grey[600]),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsTab(bool isDark) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Search bar
          Container(
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                width: 0.5,
              ),
            ),
            child: Consumer(
              builder: (context, ref, child) {
                return TextField(
                  onChanged: (value) {
                    ref.read(contactSearchProvider.notifier).state = value;
                  },
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                );
              },
            ),
          ),
          
          // Conditionally show Load Device Contacts button
          Consumer(
            builder: (context, ref, child) {
              final contactsAsync = ref.watch(contactsProvider);
              
              return contactsAsync.when(
                data: (contacts) {
                  // Only show the button if no contacts are loaded
                  if (contacts.isEmpty) {
                    return Container(
                      margin: EdgeInsets.only(bottom: 16),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await ContactsService().loadDeviceContacts();
                            ref.refresh(contactsProvider);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Contacts loaded successfully'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error loading contacts: $e'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: Icon(Icons.contacts),
                        label: Text('Load Device Contacts'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    );
                  } else {
                    // Contacts are loaded, show refresh button instead
                    return Container(
                      margin: EdgeInsets.only(bottom: 16),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await ContactsService().refreshContacts();
                            ref.refresh(contactsProvider);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Contacts refreshed successfully'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error refreshing contacts: $e'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: Icon(Icons.refresh),
                        label: Text('Refresh Contacts'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                        ),
                      ),
                    );
                  }
                },
                loading: () => Container(
                  margin: EdgeInsets.only(bottom: 16),
                  child: ElevatedButton.icon(
                    onPressed: null, // Disabled while loading
                    icon: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    label: Text('Loading...'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[400],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                error: (error, stack) => Container(
                  margin: EdgeInsets.only(bottom: 16),
                  child: ElevatedButton.icon(
                    onPressed: () => ref.refresh(contactsProvider),
                    icon: Icon(Icons.error_outline),
                    label: Text('Retry Loading'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              );
            },
          ),
          
          // Contacts list
          Expanded(
            child: Consumer(
              builder: (context, ref, child) {
                final contactsAsync = ref.watch(contactsProvider);
                final searchQuery = ref.watch(contactSearchProvider);
                
                return contactsAsync.when(
                  data: (contacts) {
                    final filteredContacts = searchQuery.isEmpty 
                      ? contacts 
                      : contacts.where((contact) => 
                          contact.displayName.toLowerCase().contains(searchQuery.toLowerCase()) == true ||
                          contact.phoneNumber.contains(searchQuery)
                        ).toList();
                    
                    if (filteredContacts.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.contacts,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              searchQuery.isEmpty ? 'No contacts' : 'No matching contacts',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              searchQuery.isEmpty 
                                ? 'Load device contacts to see them here'
                                : 'Try a different search term',
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
                      itemCount: filteredContacts.length,
                      itemBuilder: (context, index) {
                        final contact = filteredContacts[index];
                        return _buildContactItem(contact, isDark);
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
                          'Error loading contacts',
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(ContactModel contact, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 0.5,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue[600],
          child: Text(
            contact.initials,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          contact.displayName ?? 'Unknown',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          contact.phoneNumber,
          style: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.phone,
                color: Colors.green[600],
                size: 22,
              ),
              onPressed: () {
                // Format the contact number for display
                final formattedNumber = PhoneNumberFormatter.formatForSipCall(contact.phoneNumber);
                ref.read(currentNumberProvider.notifier).state = formattedNumber;
                _phoneController.text = formattedNumber;
                _tabController.animateTo(0); // Switch to dialer tab
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Number added: $formattedNumber (formatted from ${contact.phoneNumber})'),
                    duration: Duration(seconds: 3),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(
                Icons.message,
                color: Colors.blue[600],
                size: 22,
              ),
              onPressed: () {
                // TODO: Implement SMS functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('SMS feature coming soon'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Status helper methods
  Color _getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.registered:
        return Colors.green;
      case ConnectionStatus.connecting:
      case ConnectionStatus.registering:
        return Colors.orange;
      case ConnectionStatus.failed:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.registered:
        return 'Connected';
      case ConnectionStatus.connecting:
        return 'Connecting...';
      case ConnectionStatus.registering:
        return 'Registering...';
      case ConnectionStatus.connected:
        return 'Online';
      case ConnectionStatus.failed:
        return 'Connection failed';
      default:
        return 'Offline';
    }
  }

  Color _getVPNStatusColor(VpnConnectionStatus status) {
    switch (status) {
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

  IconData _getVPNStatusIcon(VpnConnectionStatus status) {
    switch (status) {
      case VpnConnectionStatus.connected:
        return Icons.shield_outlined;
      case VpnConnectionStatus.connecting:
        return Icons.sync;
      case VpnConnectionStatus.error:
      case VpnConnectionStatus.denied:
        return Icons.error_outline;
      case VpnConnectionStatus.disconnected:
      default:
        return Icons.shield_outlined;
    }
  }
}

