class ContactModel {
  String? id;
  
  late String displayName;
  String? firstName;
  String? lastName;
  late String phoneNumber;
  String? email;
  String? company;

  // Helper method for search
  List<String> get searchTerms {
    final terms = <String>[];
    if (displayName.isNotEmpty) {
      terms.addAll(displayName.toLowerCase().split(' '));
    }
    if (firstName != null && firstName!.isNotEmpty) {
      terms.add(firstName!.toLowerCase());
    }
    if (lastName != null && lastName!.isNotEmpty) {
      terms.add(lastName!.toLowerCase());
    }
    if (phoneNumber.isNotEmpty) {
      terms.add(phoneNumber);
    }
    return terms.toSet().toList(); // Remove duplicates
  }

  String get initials {
    if (displayName.isEmpty) return '?';
    final nameParts = displayName.split(' ');
    if (nameParts.length >= 2) {
      return (nameParts[0][0] + nameParts[1][0]).toUpperCase();
    }
    return displayName[0].toUpperCase();
  }

  ContactModel();
}