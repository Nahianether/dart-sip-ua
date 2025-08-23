class CallLogModel {
  String? id;

  late String callId;
  late String phoneNumber;
  String? contactName;
  late CallDirection direction;
  late CallType type;
  late CallStatus status;
  late DateTime startTime;
  DateTime? endTime;
  int? duration; // Duration in seconds
  bool missed = false;
  bool isRead = false;

  // Computed properties
  String get initials {
    if (contactName == null || contactName!.isEmpty) return '?';
    final nameParts = contactName!.split(' ');
    if (nameParts.length >= 2) {
      return (nameParts[0][0] + nameParts[1][0]).toUpperCase();
    }
    return contactName![0].toUpperCase();
  }
  
  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(startTime);
    
    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    } else {
      return '${startTime.day}/${startTime.month}/${startTime.year}';
    }
  }
  
  String? get formattedDuration {
    if (duration == null || duration == 0) return null;
    
    final minutes = (duration! ~/ 60).toString().padLeft(2, '0');
    final seconds = (duration! % 60).toString().padLeft(2, '0');
    
    if (duration! >= 3600) {
      final hours = (duration! ~/ 3600).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    
    return '$minutes:$seconds';
  }

  String get displayName => contactName ?? phoneNumber;

  CallLogModel();
}

enum CallDirection { incoming, outgoing }

enum CallType { voice, video }

enum CallStatus { 
  connecting,
  ringing, 
  connected, 
  ended, 
  failed, 
  missed, 
  rejected 
}