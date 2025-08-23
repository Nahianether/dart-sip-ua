import '../entities/call_entity.dart';
import '../repositories/sip_repository.dart';

class MakeCallUsecase {
  final SipRepository sipRepository;

  MakeCallUsecase(this.sipRepository);

  Future<CallEntity> call(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      throw ArgumentError('Phone number cannot be empty');
    }
    
    // Validate phone number format
    final cleanNumber = _cleanPhoneNumber(phoneNumber);
    if (cleanNumber.isEmpty) {
      throw ArgumentError('Invalid phone number format');
    }
    
    return await sipRepository.makeCall(cleanNumber);
  }
  
  String _cleanPhoneNumber(String number) {
    // Remove all non-digit characters except +
    return number.replaceAll(RegExp(r'[^\d+]'), '');
  }
}