import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/hive_service.dart';
import '../domain/entities/sip_account_entity.dart';
import 'providers.dart';

// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

// Password visibility state provider
final passwordVisibilityProvider = StateProvider.autoDispose<bool>((ref) => true);

// Login form state providers
final usernameProvider = StateProvider.autoDispose<String>((ref) => '');
final passwordProvider = StateProvider.autoDispose<String>((ref) => '');
final domainProvider = StateProvider.autoDispose<String>((ref) => '');
final wsUrlProvider = StateProvider.autoDispose<String>((ref) => '');
final displayNameProvider = StateProvider.autoDispose<String>((ref) => '');

// Login loading state
final loginLoadingProvider = StateProvider<bool>((ref) => false);

// Auto-login check provider
final autoLoginProvider = FutureProvider<SipAccountEntity?>((ref) async {
  try {
    final authService = ref.read(authServiceProvider);
    final savedCredentials = await authService.getSavedCredentials();
    
    if (savedCredentials != null) {
      print('✅ Auto-login credentials found: ${savedCredentials.username}@${savedCredentials.domain}');
      return savedCredentials;
    } else {
      print('ℹ️ No auto-login credentials found');
      return null;
    }
  } catch (e) {
    print('❌ Auto-login check failed: $e');
    return null;
  }
});

// Provider for all saved credentials
final savedCredentialsProvider = FutureProvider<List<SipAccountEntity>>((ref) async {
  try {
    final hiveService = HiveService.instance;
    final storedCredentials = await hiveService.getAllCredentials();
    
    return storedCredentials.map((stored) => stored.toEntity()).toList();
  } catch (e) {
    print('❌ Failed to load saved credentials: $e');
    return [];
  }
});

// Login action provider
final loginActionProvider = Provider<LoginActions>((ref) => LoginActions(ref));

class LoginActions {
  final Ref ref;
  
  LoginActions(this.ref);

  Future<void> login() async {
    final authService = ref.read(authServiceProvider);
    final accountNotifier = ref.read(accountProvider.notifier);
    
    ref.read(loginLoadingProvider.notifier).state = true;
    
    try {
      final username = ref.read(usernameProvider);
      final password = ref.read(passwordProvider);
      final domain = ref.read(domainProvider);
      final wsUrl = ref.read(wsUrlProvider);
      final displayName = ref.read(displayNameProvider);

      // Debug: Print values to see what we're getting
      print('🔍 Login Debug - Username: "$username", Domain: "$domain", WsUrl: "$wsUrl"');

      // Validate that we have the required fields
      if (username.isEmpty || password.isEmpty || domain.isEmpty || wsUrl.isEmpty) {
        throw Exception('Please fill in all required fields');
      }

      // Create SIP account
      final account = SipAccountEntity(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        username: username,
        password: password,
        domain: domain,
        wsUrl: wsUrl,
        displayName: displayName.isEmpty ? username : displayName,
      );

      print('🔍 Created account - SIP URI: ${account.sipUri}');

      // Attempt login through account provider - this will throw on failure
      await accountNotifier.login(account);
      
      // Only save credentials if login was successful (no exception thrown)
      print('✅ Login successful, saving credentials...');
      await authService.saveLoginCredentials(account);
      
    } catch (error) {
      print('❌ Login failed, not saving credentials: $error');
      rethrow;
    } finally {
      ref.read(loginLoadingProvider.notifier).state = false;
    }
  }

  Future<void> logout() async {
    final authService = ref.read(authServiceProvider);
    final accountNotifier = ref.read(accountProvider.notifier);
    
    try {
      // Clear credentials
      await authService.clearCredentials();
      
      // Logout from account provider
      await accountNotifier.logout();
      
    } catch (error) {
      print('❌ Error during logout: $error');
      rethrow;
    }
  }

  void loadSavedCredentials(SipAccountEntity account) {
    ref.read(usernameProvider.notifier).state = account.username;
    ref.read(domainProvider.notifier).state = account.domain;
    ref.read(wsUrlProvider.notifier).state = account.wsUrl;
    ref.read(displayNameProvider.notifier).state = account.displayName ?? '';
  }

  void clearForm() {
    ref.read(usernameProvider.notifier).state = '';
    ref.read(passwordProvider.notifier).state = '';
    ref.read(domainProvider.notifier).state = '';
    ref.read(wsUrlProvider.notifier).state = '';
    ref.read(displayNameProvider.notifier).state = '';
  }

  // Form validation helpers
  String? validateUsername([String? value]) {
    final authService = ref.read(authServiceProvider);
    final valueToValidate = value ?? ref.read(usernameProvider);
    return authService.validateUsername(valueToValidate);
  }

  String? validatePassword([String? value]) {
    final authService = ref.read(authServiceProvider);
    final valueToValidate = value ?? ref.read(passwordProvider);
    return authService.validatePassword(valueToValidate);
  }

  String? validateDomain([String? value]) {
    final authService = ref.read(authServiceProvider);
    final valueToValidate = value ?? ref.read(domainProvider);
    return authService.validateDomain(valueToValidate);
  }

  String? validateWsUrl([String? value]) {
    final authService = ref.read(authServiceProvider);
    final valueToValidate = value ?? ref.read(wsUrlProvider);
    return authService.validateWsUrl(valueToValidate);
  }

  String? validateDisplayName([String? value]) {
    final authService = ref.read(authServiceProvider);
    final valueToValidate = value ?? ref.read(displayNameProvider);
    return authService.validateDisplayName(valueToValidate);
  }

  bool isFormValid() {
    return validateUsername() == null &&
           validatePassword() == null &&
           validateDomain() == null &&
           validateWsUrl() == null &&
           validateDisplayName() == null;
  }
}