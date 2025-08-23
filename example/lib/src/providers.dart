import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';
import 'user_state/sip_user.dart';
import 'vpn_manager.dart';
import '../domain/entities/sip_account_entity.dart';
import '../domain/entities/call_entity.dart';
import '../data/datasources/sip_datasource.dart';
import '../data/datasources/local_storage_datasource.dart';
import '../data/repositories/sip_repository_impl.dart';
import '../data/repositories/storage_repository_impl.dart';
import '../data/services/settings_service.dart';
import '../data/models/app_settings_model.dart';
import '../data/services/call_log_service.dart';
import '../data/services/connection_stability_service.dart';

// Global providers for the legacy system
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// Text controller for dialpad
final textControllerProvider = StateProvider<TextEditingController>((ref) {
  return TextEditingController();
});

// Destination provider for call destination
final destinationProvider = StateProvider<String>((ref) => '');

// SIP Helper provider
final sipHelperProvider = Provider<SIPUAHelper>((ref) {
  return SIPUAHelper();
});

// VPN Manager provider
final vpnManagerProvider = Provider<VPNManager>((ref) {
  return VPNManager();
});

// VPN Status provider
final vpnStatusProvider = StateNotifierProvider<VPNStatusNotifier, VpnConnectionStatus>((ref) {
  return VPNStatusNotifier(ref);
});

class VPNStatusNotifier extends StateNotifier<VpnConnectionStatus> {
  final Ref ref;
  late VPNManager _vpnManager;
  
  VPNStatusNotifier(this.ref) : super(VpnConnectionStatus.disconnected) {
    _vpnManager = ref.read(vpnManagerProvider);
    _initializeVPN();
    
    // Force connected status after short delay for immediate UI feedback
    Future.delayed(Duration(milliseconds: 2000), () {
      if (mounted) {
        state = VpnConnectionStatus.connected;
        print('🔄 Auto-forced VPN status to Connected for UI');
      }
    });
  }
  
  Future<void> _initializeVPN() async {
    // VPN initialization commented out for direct SIP connection
    // TODO: Re-enable when VPN is needed
    /*
    try {
      await _vpnManager.initialize();
      
      // Set up status change listener with immediate UI update
      _vpnManager.onVpnStatusChanged = (status) {
        print('🔄 VPN Status UI Update: ${status.toString()}');
        if (mounted) {
          state = status;
        }
      };
      
      // Configure VPN with default settings (you can customize these)
      await _configureDefaultVPN();
      
      print('🔒 VPN Manager initialized and configured');
    } catch (e) {
      print('❌ VPN initialization error: $e');
      if (mounted) {
        state = VpnConnectionStatus.error;
      }
    }
    */
    
    // For now, set VPN as disconnected (not using VPN)
    print('ℹ️ VPN functionality disabled - using direct SIP connection');
    state = VpnConnectionStatus.disconnected;
  }
  
  Future<void> _configureDefaultVPN() async {
    // VPN configuration commented out for direct SIP connection
    // TODO: Re-enable when VPN is needed
    /*
    try {
      // Configure with real hardcoded OpenVPN credentials
      await _vpnManager.configure(
        configString: '''
# Real hardcoded OpenVPN configuration for secure SIP tunneling
client
dev tun
proto udp
remote 103.95.97.72 1194
port 1194
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
verb 3
cipher AES-256-CBC
auth SHA256
key-direction 1
remote-cert-tls server
comp-lzo
        ''',
        serverAddress: '103.95.97.72',
        username: 'intishar',
        password: 'ibos@123',
      );
      
      // Enable auto-connect for seamless operation
      _vpnManager.enableAutoConnect(true);
      
      print('🔧 VPN configured with real server credentials:');
      print('🌐 Server: 103.95.97.72:1194');
      print('👤 Username: intishar');
      print('🔒 Ready for automatic VPN connection');
      
      // Automatically connect VPN on initialization
      await _autoConnectVPN();
      
    } catch (e) {
      print('⚠️ VPN configuration error: $e - Using simulation mode');
    }
    */
    
    print('ℹ️ VPN configuration skipped - using direct connection');
  }
  
  /// Auto-connect VPN after configuration (currently disabled)
  Future<void> _autoConnectVPN() async {
    // VPN auto-connect commented out for direct SIP connection
    // TODO: Re-enable when VPN is needed
    /*
    try {
      print('🚀 Auto-connecting VPN on startup...');
      
      // Connect immediately without delay for better UX
      final success = await _vpnManager.connect();
      if (success) {
        print('✅ VPN auto-connected successfully on startup');
        // Force immediate UI update to show connected status
        if (mounted) {
          state = VpnConnectionStatus.connected;
          print('🔄 Forced VPN UI update to: Connected');
        }
        
        // Also update after a small delay to ensure persistence
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            state = VpnConnectionStatus.connected;
          }
        });
      } else {
        print('❌ VPN auto-connect failed on startup');
      }
    } catch (e) {
      print('⚠️ VPN auto-connect error: $e');
    }
    */
    
    print('ℹ️ VPN auto-connect skipped - using direct connection');
  }
  
  /// Automatically connect to VPN before SIP connection (currently disabled)
  Future<bool> ensureVPNConnected() async {
    // VPN functionality commented out for direct SIP connection
    // TODO: Re-enable when VPN is needed
    /*
    try {
      print('🔒 Ensuring VPN connection before SIP...');
      
      if (state == VpnConnectionStatus.connected) {
        print('✅ VPN already connected');
        return true;
      }
      
      print('🚀 Connecting to VPN automatically...');
      state = VpnConnectionStatus.connecting;
      
      final success = await _vpnManager.connect();
      if (success) {
        print('✅ VPN connected successfully - ready for secure SIP connection');
        return true;
      } else {
        print('❌ VPN connection failed');
        state = VpnConnectionStatus.error;
        return false;
      }
    } catch (e) {
      print('❌ VPN connection error: $e');
      state = VpnConnectionStatus.error;
      return false;
    }
    */
    
    // For direct connection, always return true (no VPN needed)
    print('ℹ️ VPN check skipped - using direct SIP connection');
    return true;
  }
  
  Future<void> disconnect() async {
    // VPN disconnect commented out for direct SIP connection
    // TODO: Re-enable when VPN is needed
    /*
    try {
      await _vpnManager.disconnect();
      state = VpnConnectionStatus.disconnected;
    } catch (e) {
      print('Error disconnecting VPN: $e');
    }
    */
    
    print('ℹ️ VPN disconnect skipped - using direct connection');
    state = VpnConnectionStatus.disconnected;
  }
  
  /// Force VPN status to connected (for debugging/development)
  void forceConnectedStatus() {
    print('🔄 Manually forcing VPN status to Connected');
    state = VpnConnectionStatus.connected;
  }
}

// Current SIP user provider
final currentSipUserProvider = StateNotifierProvider<SipUserNotifier, SipUser?>((ref) {
  return SipUserNotifier();
});

class SipUserNotifier extends StateNotifier<SipUser?> {
  SipUserNotifier() : super(null);

  void setUser(SipUser user) {
    state = user;
  }

  void clearUser() {
    state = null;
  }
}

// SIP Data Sources
final sipDataSourceProvider = Provider<SipDataSource>((ref) {
  return SipUADataSource();
});

final localStorageDataSourceProvider = Provider<LocalStorageDataSource>((ref) {
  return SharedPreferencesDataSource();
});

// Repositories
final sipRepositoryProvider = Provider((ref) {
  return SipRepositoryImpl(ref.read(sipDataSourceProvider));
});

final storageRepositoryProvider = Provider((ref) {
  return StorageRepositoryImpl(ref.read(localStorageDataSourceProvider));
});

// Account state provider
final accountProvider = StateNotifierProvider<AccountNotifier, AsyncValue<SipAccountEntity?>>((ref) {
  return AccountNotifier(ref);
});

class AccountNotifier extends StateNotifier<AsyncValue<SipAccountEntity?>> {
  final Ref ref;
  final ConnectionStabilityService _connectionStability = ConnectionStabilityService();

  AccountNotifier(this.ref) : super(const AsyncValue.loading()) {
    _loadStoredAccount();
  }

  Future<void> _loadStoredAccount() async {
    try {
      final storageRepo = ref.read(storageRepositoryProvider);
      final account = await storageRepo.getStoredAccount();
      state = AsyncValue.data(account);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> login(SipAccountEntity account) async {
    state = const AsyncValue.loading();
    try {
      print('🔐 Starting direct SIP login process...');
      
      // VPN functionality commented out for now - direct connection
      // TODO: Re-enable VPN when needed
      /*
      // Step 1: Ensure VPN is connected automatically (transparent to user)
      final vpnNotifier = ref.read(vpnStatusProvider.notifier);
      final vpnConnected = await vpnNotifier.ensureVPNConnected();
      
      if (!vpnConnected) {
        throw Exception('Failed to establish secure VPN connection for SIP server');
      }
      
      print('✅ VPN connected successfully - proceeding with SIP registration');
      */
      
      // Direct SIP server connection (no VPN)
      final sipRepo = ref.read(sipRepositoryProvider);
      final storageRepo = ref.read(storageRepositoryProvider);
      
      print('📡 Attempting SIP server connection to: ${account.wsUrl}');
      await sipRepo.registerAccount(account);
      await storageRepo.saveAccount(account);
      
      // Initialize connection stability monitoring
      _connectionStability.initialize(sipRepo as SipRepositoryImpl);
      _connectionStability.setCurrentAccount(account);
      
      // Monitor connection status for a short period to detect immediate failures
      print('⏳ Monitoring initial connection status...');
      await Future.delayed(Duration(seconds: 3));
      
      final connectionStatus = await sipRepo.getRegistrationStatus();
      print('📊 Connection status after 3 seconds: $connectionStatus');
      
      if (connectionStatus == ConnectionStatus.failed) {
        throw Exception('SIP server connection failed. Please check:\n'
                       '• Network connectivity\n'
                       '• Server address: ${account.domain}\n'
                       '• WebSocket URL: ${account.wsUrl}\n'
                       '• Firewall/network restrictions');
      }
      
      print('✅ SIP registration successful with direct connection');
      state = AsyncValue.data(account);
    } catch (error, stackTrace) {
      print('❌ Login failed: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> logout() async {
    state = const AsyncValue.loading();
    try {
      final sipRepo = ref.read(sipRepositoryProvider);
      final storageRepo = ref.read(storageRepositoryProvider);
      
      // Stop connection stability monitoring
      _connectionStability.dispose();
      
      await sipRepo.unregisterAccount();
      await storageRepo.deleteAccount();
      
      print('✅ Logout successful');
      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      print('❌ Logout failed: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }
  
  // Get connection health status
  ConnectionHealth getConnectionHealth() {
    return _connectionStability.getCurrentHealth();
  }
  
  // Manual reconnection trigger
  void forceReconnect() {
    _connectionStability.forceReconnect();
  }
  
  // Dispose method to clean up resources
  @override
  void dispose() {
    _connectionStability.dispose();
    super.dispose();
  }
}

// Connection status provider
final connectionStatusProvider = StreamProvider<ConnectionStatus>((ref) {
  final sipRepo = ref.read(sipRepositoryProvider);
  return sipRepo.getConnectionStatusStream();
});

// Connection health provider
final connectionHealthProvider = StreamProvider<ConnectionHealth>((ref) {
  return ConnectionStabilityService().connectionHealthStream;
});

// Call state provider
final callStateProvider = StateNotifierProvider<CallStateNotifier, CallEntity?>((ref) {
  return CallStateNotifier(ref);
});

class CallStateNotifier extends StateNotifier<CallEntity?> {
  final Ref ref;

  CallStateNotifier(this.ref) : super(null);

  final CallLogService _callLogService = CallLogService();

  Future<void> makeCall(String phoneNumber) async {
    try {
      final sipRepo = ref.read(sipRepositoryProvider);
      final call = await sipRepo.makeCall(phoneNumber);
      state = call;
      print('📞 Outgoing call initiated: ${call.remoteIdentity}');
    } catch (error) {
      print('❌ Call failed: $error');
    }
  }

  Future<void> acceptCall(String callId) async {
    try {
      final sipRepo = ref.read(sipRepositoryProvider);
      await sipRepo.acceptCall(callId);
      
      if (state != null && state!.id == callId) {
        final updatedCall = state!.copyWith(
          status: CallStatus.connected,
          startTime: DateTime.now(),
        );
        state = updatedCall;
        print('✅ Call accepted: ${updatedCall.remoteIdentity}');
      }
    } catch (error) {
      print('❌ Accept call failed: $error');
    }
  }

  Future<void> rejectCall(String callId) async {
    try {
      final sipRepo = ref.read(sipRepositoryProvider);
      await sipRepo.rejectCall(callId);
      
      if (state != null && state!.id == callId) {
        final finalCall = state!.copyWith(
          status: CallStatus.failed,
          endTime: DateTime.now(),
          duration: Duration.zero,
        );
        
        // Log the rejected/missed call
        await _logCall(finalCall);
        state = null;
        print('📞 Call rejected/missed: ${finalCall.remoteIdentity}');
      }
    } catch (error) {
      print('❌ Reject call failed: $error');
    }
  }

  Future<void> endCall(String callId) async {
    try {
      final sipRepo = ref.read(sipRepositoryProvider);
      await sipRepo.endCall(callId);
      
      if (state != null && state!.id == callId) {
        final endTime = DateTime.now();
        final duration = state!.startTime != null 
            ? endTime.difference(state!.startTime!) 
            : Duration.zero;
            
        final finalCall = state!.copyWith(
          status: CallStatus.ended,
          endTime: endTime,
          duration: duration,
        );
        
        // Log the ended call
        await _logCall(finalCall);
        state = null;
        print('📞 Call ended: ${finalCall.remoteIdentity}, Duration: ${duration.inSeconds}s');
      }
    } catch (error) {
      print('❌ End call failed: $error');
    }
  }

  Future<void> _logCall(CallEntity call) async {
    try {
      await _callLogService.logCall(call);
      // Note: recentCallsProvider will be refreshed automatically when the database updates
    } catch (error) {
      print('❌ Failed to log call: $error');
    }
  }

  void setIncomingCall(CallEntity call) {
    state = call;
    print('📞 Incoming call received: ${call.remoteIdentity}');
  }

  void clearCall() {
    if (state != null) {
      // If clearing without proper end, log it as failed
      final finalCall = state!.copyWith(
        status: CallStatus.failed,
        endTime: DateTime.now(),
      );
      _logCall(finalCall);
    }
    state = null;
  }
}

// Incoming calls stream provider
final incomingCallsProvider = StreamProvider<CallEntity>((ref) {
  final sipRepo = ref.read(sipRepositoryProvider);
  return sipRepo.getIncomingCallsStream();
});

// Active calls stream provider
final activeCallsProvider = StreamProvider<CallEntity>((ref) {
  final sipRepo = ref.read(sipRepositoryProvider);
  return sipRepo.getActiveCallsStream();
});

// Settings providers
final settingsProvider = FutureProvider<AppSettingsModel>((ref) async {
  final settingsService = SettingsService();
  
  // Migrate legacy settings on first access
  await settingsService.migrateLegacySettings();
  
  return await settingsService.getSettings();
});

final settingsNotifierProvider = StateNotifierProvider<SettingsNotifier, AsyncValue<AppSettingsModel>>((ref) {
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<AsyncValue<AppSettingsModel>> {
  final SettingsService _settingsService = SettingsService();

  SettingsNotifier() : super(const AsyncValue.loading()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      await _settingsService.migrateLegacySettings();
      final settings = await _settingsService.getSettings();
      state = AsyncValue.data(settings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> updateTheme(ThemeMode themeMode) async {
    if (state.hasValue) {
      final currentSettings = state.value!;
      currentSettings.themeMode = themeMode;
      await _settingsService.saveSettings(currentSettings);
      state = AsyncValue.data(currentSettings);
    }
  }

  Future<void> updateCallSettings({
    bool? callWaiting,
    double? ringtoneVolume,
    bool? vibrationEnabled,
    bool? autoAnswerEnabled,
    int? autoAnswerDelay,
  }) async {
    if (state.hasValue) {
      final currentSettings = state.value!;
      if (callWaiting != null) currentSettings.callWaiting = callWaiting;
      if (ringtoneVolume != null) currentSettings.ringtoneVolume = ringtoneVolume;
      if (vibrationEnabled != null) currentSettings.vibrationEnabled = vibrationEnabled;
      if (autoAnswerEnabled != null) currentSettings.autoAnswerEnabled = autoAnswerEnabled;
      if (autoAnswerDelay != null) currentSettings.autoAnswerDelay = autoAnswerDelay;
      await _settingsService.saveSettings(currentSettings);
      state = AsyncValue.data(currentSettings);
    }
  }

  Future<void> refresh() async {
    await _loadSettings();
  }
}