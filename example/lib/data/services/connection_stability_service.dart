import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/entities/sip_account_entity.dart';
import '../repositories/sip_repository_impl.dart';

enum ConnectionHealth {
  healthy,
  unstable,
  poor,
  disconnected,
}

class ConnectionStabilityService {
  static final ConnectionStabilityService _instance = ConnectionStabilityService._();
  factory ConnectionStabilityService() => _instance;
  ConnectionStabilityService._();

  Timer? _healthCheckTimer;
  Timer? _reconnectTimer;
  StreamController<ConnectionHealth>? _healthController;
  
  // Connection parameters
  int _reconnectAttempts = 0;
  int _maxReconnectAttempts = 10;
  int _baseReconnectDelay = 2; // seconds
  bool _isReconnecting = false;
  
  // Health monitoring
  DateTime? _lastSuccessfulConnection;
  int _failedHealthChecks = 0;
  
  SipRepositoryImpl? _sipRepository;
  SipAccountEntity? _currentAccount;

  Stream<ConnectionHealth> get connectionHealthStream {
    _healthController ??= StreamController<ConnectionHealth>.broadcast();
    return _healthController!.stream;
  }

  void initialize(SipRepositoryImpl sipRepository) {
    _sipRepository = sipRepository;
    _startHealthMonitoring();
  }

  void dispose() {
    _healthCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _healthController?.close();
    _healthController = null;
  }

  void setCurrentAccount(SipAccountEntity account) {
    _currentAccount = account;
    _lastSuccessfulConnection = DateTime.now();
    _reconnectAttempts = 0;
    _failedHealthChecks = 0;
  }

  void _startHealthMonitoring() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _performHealthCheck();
    });
  }

  void _performHealthCheck() async {
    if (_sipRepository == null || _currentAccount == null) {
      _updateHealthStatus(ConnectionHealth.disconnected);
      return;
    }

    try {
      // Check SIP registration status
      final status = await _sipRepository!.getRegistrationStatus();
      
      if (status == ConnectionStatus.registered) {
        _lastSuccessfulConnection = DateTime.now();
        _failedHealthChecks = 0;
        _reconnectAttempts = 0;
        _updateHealthStatus(ConnectionHealth.healthy);
      } else if (status == ConnectionStatus.connecting || status == ConnectionStatus.registering) {
        _updateHealthStatus(ConnectionHealth.unstable);
      } else {
        _failedHealthChecks++;
        _handleConnectionFailure();
      }
    } catch (e) {
      print('❌ Health check failed: $e');
      _failedHealthChecks++;
      _handleConnectionFailure();
    }
  }

  void _handleConnectionFailure() {
    print('🔄 Connection failure detected. Failed checks: $_failedHealthChecks');
    
    if (_failedHealthChecks >= 3) {
      _updateHealthStatus(ConnectionHealth.disconnected);
      _triggerReconnection();
    } else if (_failedHealthChecks >= 2) {
      _updateHealthStatus(ConnectionHealth.poor);
    } else {
      _updateHealthStatus(ConnectionHealth.unstable);
    }
  }

  void _triggerReconnection() {
    if (_isReconnecting || _currentAccount == null || _sipRepository == null) {
      return;
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('❌ Max reconnection attempts reached. Giving up.');
      _updateHealthStatus(ConnectionHealth.disconnected);
      return;
    }

    _isReconnecting = true;
    _reconnectAttempts++;

    // Calculate exponential backoff delay
    final delay = _calculateReconnectDelay();
    print('🔄 Attempting reconnection $_reconnectAttempts/$_maxReconnectAttempts in ${delay}s...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _attemptReconnection();
    });
  }

  int _calculateReconnectDelay() {
    // Exponential backoff with jitter
    final exponentialDelay = _baseReconnectDelay * pow(2, _reconnectAttempts - 1);
    final maxDelay = 300; // 5 minutes max
    final delayWithCap = min(exponentialDelay, maxDelay);
    
    // Add jitter to prevent thundering herd
    final jitter = Random().nextDouble() * 0.3; // ±30% jitter
    return ((delayWithCap * (1 + jitter)).toInt());
  }

  void _attemptReconnection() async {
    if (_currentAccount == null || _sipRepository == null) {
      _isReconnecting = false;
      return;
    }

    try {
      print('🔄 Attempting to reconnect...');
      
      // First disconnect if still connected
      await _sipRepository!.disconnect();
      await Future.delayed(Duration(seconds: 2));
      
      // Attempt to reconnect
      await _sipRepository!.connect(_currentAccount!);
      
      print('✅ Reconnection successful!');
      _isReconnecting = false;
      _failedHealthChecks = 0;
      _lastSuccessfulConnection = DateTime.now();
      _updateHealthStatus(ConnectionHealth.healthy);
      
    } catch (e) {
      print('❌ Reconnection attempt $_reconnectAttempts failed: $e');
      _isReconnecting = false;
      
      // Schedule next reconnection attempt
      _triggerReconnection();
    }
  }

  void _updateHealthStatus(ConnectionHealth health) {
    _healthController?.add(health);
    
    final now = DateTime.now();
    final statusEmoji = {
      ConnectionHealth.healthy: '✅',
      ConnectionHealth.unstable: '⚠️',
      ConnectionHealth.poor: '🔴',
      ConnectionHealth.disconnected: '❌',
    }[health];
    
    if (kDebugMode) {
      print('$statusEmoji Connection Health: ${health.name.toUpperCase()}');
    }
  }

  // Manual reconnection trigger
  void forceReconnect() {
    if (_currentAccount != null) {
      print('🔄 Manual reconnection triggered');
      _reconnectAttempts = 0; // Reset attempts for manual trigger
      _triggerReconnection();
    }
  }

  // Get current health status
  ConnectionHealth getCurrentHealth() {
    if (_sipRepository == null || _currentAccount == null) {
      return ConnectionHealth.disconnected;
    }

    if (_lastSuccessfulConnection == null) {
      return ConnectionHealth.disconnected;
    }

    final timeSinceLastSuccess = DateTime.now().difference(_lastSuccessfulConnection!);
    
    if (timeSinceLastSuccess.inMinutes > 10) {
      return ConnectionHealth.disconnected;
    } else if (timeSinceLastSuccess.inMinutes > 5 || _failedHealthChecks >= 2) {
      return ConnectionHealth.poor;
    } else if (timeSinceLastSuccess.inMinutes > 2 || _failedHealthChecks >= 1) {
      return ConnectionHealth.unstable;
    } else {
      return ConnectionHealth.healthy;
    }
  }

  // Network change detection
  void onNetworkChanged() {
    print('🌐 Network change detected, forcing reconnection...');
    _failedHealthChecks = 0; // Reset failed checks on network change
    forceReconnect();
  }

  // Call quality monitoring
  void reportCallQuality(bool isGoodQuality) {
    if (!isGoodQuality) {
      _failedHealthChecks++;
      if (_failedHealthChecks >= 2) {
        _updateHealthStatus(ConnectionHealth.poor);
      } else {
        _updateHealthStatus(ConnectionHealth.unstable);
      }
    }
  }
}