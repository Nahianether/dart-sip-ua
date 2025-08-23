import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/auth_providers.dart';
import '../src/providers.dart';
import '../domain/entities/sip_account_entity.dart';

class ModernLoginScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<ModernLoginScreen> createState() => _ModernLoginScreenState();
}

class _ModernLoginScreenState extends ConsumerState<ModernLoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  late Animation<Offset> _slideAnimation;
  
  // Text controllers
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _domainController = TextEditingController();
  final _wsUrlController = TextEditingController();
  final _displayNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    
    // Initialize animations
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeInAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _animationController.forward();
    
    // Load saved credentials if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedCredentials();
    });
  }

  void _loadSavedCredentials() async {
    final autoLoginAsync = ref.read(autoLoginProvider);
    autoLoginAsync.whenData((account) {
      if (account != null) {
        ref.read(loginActionProvider).loadSavedCredentials(account);
        _updateControllers();
      }
    });
  }

  void _updateControllers() {
    _usernameController.text = ref.read(usernameProvider);
    _passwordController.text = ref.read(passwordProvider);
    _domainController.text = ref.read(domainProvider);
    _wsUrlController.text = ref.read(wsUrlProvider);
    _displayNameController.text = ref.read(displayNameProvider);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    _wsUrlController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLoading = ref.watch(loginLoadingProvider);
    final passwordVisible = ref.watch(passwordVisibilityProvider);

    // Listen to account state changes for navigation
    ref.listen<AsyncValue<SipAccountEntity?>>(accountProvider, (previous, next) {
      next.whenData((account) {
        if (account != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Connected successfully!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      });
      
      next.whenOrNull(
        error: (error, stackTrace) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Login failed: $error')),
                ],
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: Duration(seconds: 4),
            ),
          );
        },
      );
    });

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeInAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 40),
                    
                    // App Logo/Icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary,
                            colorScheme.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.phone_in_talk,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    
                    SizedBox(height: 32),
                    
                    // Title
                    Text(
                      'Welcome Back',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: 8),
                    
                    Text(
                      'Sign in to your VoIP account',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: 40),
                    
                    // Username Field
                    _buildAnimatedTextField(
                      controller: _usernameController,
                      label: 'Username',
                      icon: Icons.person_outline,
                      onChanged: (value) => ref.read(usernameProvider.notifier).state = value,
                      validator: (value) => ref.read(loginActionProvider).validateUsername(value),
                      delay: 200,
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Password Field
                    _buildAnimatedTextField(
                      controller: _passwordController,
                      label: 'Password',
                      icon: Icons.lock_outline,
                      obscureText: passwordVisible,
                      onChanged: (value) => ref.read(passwordProvider.notifier).state = value,
                      validator: (value) => ref.read(loginActionProvider).validatePassword(value),
                      suffixIcon: IconButton(
                        icon: Icon(
                          passwordVisible ? Icons.visibility_off : Icons.visibility,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          ref.read(passwordVisibilityProvider.notifier).state = !passwordVisible;
                        },
                      ),
                      delay: 300,
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Domain Field
                    _buildAnimatedTextField(
                      controller: _domainController,
                      label: 'Domain',
                      icon: Icons.dns_outlined,
                      onChanged: (value) => ref.read(domainProvider.notifier).state = value,
                      validator: (value) => ref.read(loginActionProvider).validateDomain(value),
                      delay: 400,
                    ),
                    
                    SizedBox(height: 16),
                    
                    // WebSocket URL Field
                    _buildAnimatedTextField(
                      controller: _wsUrlController,
                      label: 'WebSocket URL',
                      icon: Icons.link_outlined,
                      onChanged: (value) => ref.read(wsUrlProvider.notifier).state = value,
                      validator: (value) => ref.read(loginActionProvider).validateWsUrl(value),
                      delay: 500,
                    ),
                    
                    SizedBox(height: 16),
                    
                    // Display Name Field (Optional)
                    _buildAnimatedTextField(
                      controller: _displayNameController,
                      label: 'Display Name (Optional)',
                      icon: Icons.badge_outlined,
                      onChanged: (value) => ref.read(displayNameProvider.notifier).state = value,
                      validator: (value) => ref.read(loginActionProvider).validateDisplayName(value),
                      delay: 600,
                    ),
                    
                    SizedBox(height: 32),
                    
                    // Login Button
                    AnimatedContainer(
                      duration: Duration(milliseconds: 300),
                      height: 56,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          shadowColor: colorScheme.primary.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.login, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    
                    SizedBox(height: 24),
                    
                    // Connection Status
                    Consumer(
                      builder: (context, ref, child) {
                        final connectionStatus = ref.watch(connectionStatusProvider);
                        return connectionStatus.when(
                          data: (status) => _buildConnectionStatus(status, colorScheme),
                          loading: () => Container(),
                          error: (_, __) => Container(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    required ValueChanged<String> onChanged,
    required FormFieldValidator<String> validator,
    Widget? suffixIcon,
    int delay = 0,
  }) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 800 + delay),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 20),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: TextFormField(
        controller: controller,
        onChanged: onChanged,
        validator: validator,
        obscureText: obscureText,
        style: TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 22),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.error,
              width: 1,
            ),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainer,
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(ConnectionStatus status, ColorScheme colorScheme) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case ConnectionStatus.registered:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Connected';
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.registering:
        statusColor = Colors.orange;
        statusIcon = Icons.sync;
        statusText = 'Connecting...';
        break;
      case ConnectionStatus.failed:
        statusColor = Colors.red;
        statusIcon = Icons.error;
        statusText = 'Connection Failed';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.info;
        statusText = 'Disconnected';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(statusIcon, color: statusColor, size: 20),
          SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _handleLogin() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        // Ensure provider values are updated from controllers
        ref.read(usernameProvider.notifier).state = _usernameController.text;
        ref.read(passwordProvider.notifier).state = _passwordController.text;
        ref.read(domainProvider.notifier).state = _domainController.text;
        ref.read(wsUrlProvider.notifier).state = _wsUrlController.text;
        ref.read(displayNameProvider.notifier).state = _displayNameController.text;
        
        await ref.read(loginActionProvider).login();
      } catch (error) {
        // Error handling is done in the account provider listener
        print('🚨 Login error in UI: $error');
      }
    }
  }
}