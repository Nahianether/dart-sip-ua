import 'dart:convert';
import '../../domain/entities/call_entity.dart';

class CallModel extends CallEntity {
  const CallModel({
    required super.id,
    required super.remoteIdentity,
    super.displayName,
    required super.direction,
    required super.status,
    required super.startTime,
    super.endTime,
    super.duration,
  });

  // Convert from entity
  factory CallModel.fromEntity(CallEntity entity) {
    return CallModel(
      id: entity.id,
      remoteIdentity: entity.remoteIdentity,
      displayName: entity.displayName,
      direction: entity.direction,
      status: entity.status,
      startTime: entity.startTime,
      endTime: entity.endTime,
      duration: entity.duration,
    );
  }

  // Convert from JSON
  factory CallModel.fromJson(Map<String, dynamic> json) {
    return CallModel(
      id: json['id'] ?? '',
      remoteIdentity: json['remoteIdentity'] ?? '',
      displayName: json['displayName'],
      direction: _callDirectionFromString(json['direction']),
      status: _callStatusFromString(json['status']),
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime']),
      endTime: json['endTime'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['endTime'])
          : null,
      duration: json['duration'] != null 
          ? Duration(milliseconds: json['duration'])
          : null,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'remoteIdentity': remoteIdentity,
      'displayName': displayName,
      'direction': direction.name,
      'status': status.name,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime?.millisecondsSinceEpoch,
      'duration': duration?.inMilliseconds,
    };
  }

  // Convert to JSON string
  String toJsonString() {
    return jsonEncode(toJson());
  }

  static CallDirection _callDirectionFromString(String? direction) {
    switch (direction) {
      case 'outgoing':
        return CallDirection.outgoing;
      default:
        return CallDirection.incoming;
    }
  }

  static CallStatus _callStatusFromString(String? status) {
    switch (status) {
      case 'connecting':
        return CallStatus.connecting;
      case 'ringing':
        return CallStatus.ringing;
      case 'connected':
        return CallStatus.connected;
      case 'disconnected':
        return CallStatus.disconnected;
      case 'failed':
        return CallStatus.failed;
      case 'ended':
        return CallStatus.ended;
      default:
        return CallStatus.disconnected;
    }
  }
}