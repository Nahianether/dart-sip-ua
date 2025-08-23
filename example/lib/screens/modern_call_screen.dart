import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../src/providers.dart';
import '../domain/entities/call_entity.dart';

// Call control providers
final isMutedProvider = StateProvider.autoDispose<bool>((ref) => false);
final isSpeakerOnProvider = StateProvider.autoDispose<bool>((ref) => false);
final isHoldingProvider = StateProvider.autoDispose<bool>((ref) => false);

class ModernCallScreen extends ConsumerStatefulWidget {
  final CallEntity call;

  const ModernCallScreen({super.key, required this.call});

  @override
  ConsumerState<ModernCallScreen> createState() => _ModernCallScreenState();
}

class _ModernCallScreenState extends ConsumerState<ModernCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // Pulse animation for call state
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    // Slide animation for incoming calls
    _slideController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _slideController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _onHangup() {
    HapticFeedback.heavyImpact();
    ref.read(callStateProvider.notifier).endCall(widget.call.id);
    
    // Navigate back to dial screen and clear call state
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onAccept() {
    HapticFeedback.heavyImpact();
    ref.read(callStateProvider.notifier).acceptCall(widget.call.id);
    
    // Stay on call screen for accepted calls
  }

  void _onReject() {
    HapticFeedback.heavyImpact();
    ref.read(callStateProvider.notifier).rejectCall(widget.call.id);
    
    // Navigate back to dial screen after rejecting call
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onMute() {
    HapticFeedback.lightImpact();
    final currentMuted = ref.read(isMutedProvider);
    ref.read(isMutedProvider.notifier).state = !currentMuted;
    // TODO: Implement mute functionality
  }

  void _onSpeaker() {
    HapticFeedback.lightImpact();
    final currentSpeaker = ref.read(isSpeakerOnProvider);
    ref.read(isSpeakerOnProvider.notifier).state = !currentSpeaker;
    // TODO: Implement speaker functionality
  }

  void _onHold() {
    HapticFeedback.lightImpact();
    final currentHold = ref.read(isHoldingProvider);
    ref.read(isHoldingProvider.notifier).state = !currentHold;
    // TODO: Implement hold functionality
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isIncomingCall = widget.call.direction == CallDirection.incoming;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[900],
      body: SafeArea(
        child: SlideTransition(
          position: _slideAnimation,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.grey[900]!,
                  Colors.black,
                ],
              ),
            ),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 
                            MediaQuery.of(context).padding.top - 
                            MediaQuery.of(context).padding.bottom,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // Top section with call info
                      Expanded(
                        flex: 2,
                        child: _buildCallInfo(isIncomingCall),
                      ),
                      
                      // Controls section
                      Expanded(
                        flex: 1,
                        child: _buildCallControls(isIncomingCall),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallInfo(bool isIncomingCall) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Call status
        Text(
          isIncomingCall ? 'Incoming call' : _getCallStatusText(),
          style: TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w300,
          ),
        ),
        
        SizedBox(height: 32),
        
        // Avatar with pulse effect
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // Pulse rings
                if (isIncomingCall || widget.call.status == CallStatus.ringing)
                  ...List.generate(3, (index) {
                    return Transform.scale(
                      scale: 1 + (_pulseAnimation.value * 0.8) + (index * 0.2),
                      child: Container(
                        width: 160 + (index * 40),
                        height: 160 + (index * 40),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: (0.3 - (index * 0.1)) * (1 - _pulseAnimation.value),
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  }),
                
                // Main avatar
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[700],
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Icon(
                      Icons.person,
                      size: 80,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        
        SizedBox(height: 32),
        
        // Caller name
        Text(
          widget.call.displayName ?? widget.call.remoteIdentity,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w300,
          ),
          textAlign: TextAlign.center,
        ),
        
        SizedBox(height: 8),
        
        // Phone number
        Text(
          widget.call.remoteIdentity,
          style: TextStyle(
            color: Colors.white60,
            fontSize: 18,
            fontWeight: FontWeight.w300,
          ),
        ),
        
        SizedBox(height: 16),
        
        // Call duration (for connected calls)
        if (widget.call.status == CallStatus.connected)
          _buildCallDuration(),
      ],
    );
  }

  Widget _buildCallDuration() {
    return StreamBuilder<int>(
      stream: Stream.periodic(Duration(seconds: 1), (i) => i),
      builder: (context, snapshot) {
        final duration = _formatDuration(widget.call.duration);
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            duration,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCallControls(bool isIncomingCall) {
    if (isIncomingCall) {
      return _buildIncomingCallControls();
    } else {
      return _buildActiveCallControls();
    }
  }

  Widget _buildIncomingCallControls() {
    return Padding(
      padding: EdgeInsets.all(32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline button
          _buildCallActionButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            onPressed: _onReject,
            size: 70,
          ),
          
          // Quick actions
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCallActionButton(
                icon: Icons.message,
                backgroundColor: Colors.grey[700],
                onPressed: () {
                  // TODO: Quick message
                },
                size: 50,
              ),
              SizedBox(height: 12),
              _buildCallActionButton(
                icon: Icons.person_add,
                backgroundColor: Colors.grey[700],
                onPressed: () {
                  // TODO: Add to contacts
                },
                size: 50,
              ),
            ],
          ),
          
          // Accept button
          _buildCallActionButton(
            icon: Icons.call,
            backgroundColor: Colors.green,
            onPressed: _onAccept,
            size: 70,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCallControls() {
    return Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        children: [
          // Top row controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCallActionButton(
                icon: ref.watch(isMutedProvider) ? Icons.mic_off : Icons.mic,
                backgroundColor: ref.watch(isMutedProvider) ? Colors.red : Colors.grey[700],
                onPressed: _onMute,
              ),
              
              _buildCallActionButton(
                icon: Icons.dialpad,
                backgroundColor: Colors.grey[700],
                onPressed: () {
                  // TODO: Show dialpad
                },
              ),
              
              _buildCallActionButton(
                icon: ref.watch(isSpeakerOnProvider) ? Icons.volume_up : Icons.volume_down,
                backgroundColor: ref.watch(isSpeakerOnProvider) ? Colors.blue : Colors.grey[700],
                onPressed: _onSpeaker,
              ),
            ],
          ),
          
          SizedBox(height: 24),
          
          // Bottom row controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCallActionButton(
                icon: Icons.add_call,
                backgroundColor: Colors.grey[700],
                onPressed: () {
                  // TODO: Add call
                },
              ),
              
              _buildCallActionButton(
                icon: ref.watch(isHoldingProvider) ? Icons.play_arrow : Icons.pause,
                backgroundColor: ref.watch(isHoldingProvider) ? Colors.orange : Colors.grey[700],
                onPressed: _onHold,
              ),
              
              _buildCallActionButton(
                icon: Icons.contacts,
                backgroundColor: Colors.grey[700],
                onPressed: () {
                  // TODO: Show contacts
                },
              ),
            ],
          ),
          
          SizedBox(height: 32),
          
          // Hangup button
          _buildCallActionButton(
            icon: Icons.call_end,
            backgroundColor: Colors.red,
            onPressed: _onHangup,
            size: 70,
          ),
        ],
      ),
    );
  }

  Widget _buildCallActionButton({
    required IconData icon,
    required Color? backgroundColor,
    required VoidCallback onPressed,
    double size = 60,
  }) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(size / 2),
      color: backgroundColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: Colors.white,
            size: size * 0.4,
          ),
        ),
      ),
    );
  }

  String _getCallStatusText() {
    switch (widget.call.status) {
      case CallStatus.connecting:
        return 'Connecting...';
      case CallStatus.ringing:
        return 'Ringing...';
      case CallStatus.connected:
        return 'Active call';
      default:
        return 'Call';
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '00:00';
    
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    
    return '$minutes:$seconds';
  }
}

// Using enums from domain entities