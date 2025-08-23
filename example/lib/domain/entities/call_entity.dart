import 'package:equatable/equatable.dart';

enum CallDirection { incoming, outgoing }

enum CallStatus { 
  connecting,
  ringing,
  connected,
  disconnected,
  failed,
  ended
}

class CallEntity extends Equatable {
  final String id;
  final String remoteIdentity;
  final String? displayName;
  final CallDirection direction;
  final CallStatus status;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration? duration;

  const CallEntity({
    required this.id,
    required this.remoteIdentity,
    this.displayName,
    required this.direction,
    required this.status,
    required this.startTime,
    this.endTime,
    this.duration,
  });

  CallEntity copyWith({
    String? id,
    String? remoteIdentity,
    String? displayName,
    CallDirection? direction,
    CallStatus? status,
    DateTime? startTime,
    DateTime? endTime,
    Duration? duration,
  }) {
    return CallEntity(
      id: id ?? this.id,
      remoteIdentity: remoteIdentity ?? this.remoteIdentity,
      displayName: displayName ?? this.displayName,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
    );
  }

  @override
  List<Object?> get props => [
        id,
        remoteIdentity,
        displayName,
        direction,
        status,
        startTime,
        endTime,
        duration,
      ];
}