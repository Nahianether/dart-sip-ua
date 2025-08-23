class PhoneNumberFormatter {
  static const String bangladeshCountryCode = '+880';
  static const String bangladeshCode = '88';

  /// Format phone number for SIP calling
  /// Removes +88 and +880 prefixes for Bangladesh numbers
  static String formatForSipCall(String phoneNumber) {
    if (phoneNumber.isEmpty) return phoneNumber;
    
    String formatted = phoneNumber.trim();
    
    // Remove +880 (full Bangladesh code)
    if (formatted.startsWith('+880')) {
      formatted = formatted.substring(4);
    }
    // Remove +88 (short form)
    else if (formatted.startsWith('+88')) {
      formatted = formatted.substring(3);
    }
    // Remove 880 (without plus)
    else if (formatted.startsWith('880')) {
      formatted = formatted.substring(3);
    }
    // Remove 88 (without plus)
    else if (formatted.startsWith('88') && formatted.length > 10) {
      // Only remove if it looks like a country code (length > 10)
      formatted = formatted.substring(2);
    }
    
    // Remove any remaining non-digit characters except +
    formatted = formatted.replaceAll(RegExp(r'[^\d+]'), '');
    
    print('📞 Phone number formatted: $phoneNumber -> $formatted');
    return formatted;
  }

  /// Format phone number for display (with country code)
  static String formatForDisplay(String phoneNumber) {
    if (phoneNumber.isEmpty) return phoneNumber;
    
    String formatted = phoneNumber.trim();
    
    // If it looks like a local Bangladesh number, add +880
    if (formatted.length == 11 && formatted.startsWith('01')) {
      formatted = '+880${formatted.substring(1)}';
    }
    // If it's 10 digits starting with 1, might be local
    else if (formatted.length == 10 && formatted.startsWith('1')) {
      formatted = '+880$formatted';
    }
    
    return formatted;
  }

  /// Check if number looks like a Bangladesh mobile number
  static bool isBangladeshMobile(String phoneNumber) {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    
    // Bangladesh mobile patterns:
    // 01XXXXXXXXX (11 digits)
    // 1XXXXXXXXX (10 digits, without leading 0)
    return (cleaned.length == 11 && cleaned.startsWith('01')) ||
           (cleaned.length == 10 && cleaned.startsWith('1'));
  }

  /// Validate phone number format
  static bool isValidPhoneNumber(String phoneNumber) {
    if (phoneNumber.isEmpty) return false;
    
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    
    // Should be at least 7 digits, max 15 (international standard)
    return cleaned.length >= 7 && cleaned.length <= 15;
  }

  /// Clean phone number (remove spaces, dashes, parentheses)
  static String cleanPhoneNumber(String phoneNumber) {
    return phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
  }
}