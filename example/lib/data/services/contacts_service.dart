import 'package:flutter_contacts/flutter_contacts.dart';
import '../models/contact_model.dart';
import 'hive_service.dart';

class ContactsService {
  static final ContactsService _instance = ContactsService._();
  factory ContactsService() => _instance;
  ContactsService._();

  final HiveService _hiveService = HiveService.instance;

  Future<bool> requestContactsPermission() async {
    if (!await FlutterContacts.requestPermission()) {
      print('❌ Contacts permission denied');
      return false;
    }
    return true;
  }

  Future<List<ContactModel>> loadDeviceContacts() async {
    try {
      final hasPermission = await requestContactsPermission();
      if (!hasPermission) {
        print('❌ Contacts permission denied');
        return [];
      }

      print('📱 Loading device contacts...');
      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      
      final contactModels = <ContactModel>[];
      
      for (final contact in contacts) {
        if (contact.phones.isNotEmpty) {
          for (final phone in contact.phones) {
            final phoneNumber = _cleanPhoneNumber(phone.number);
            if (phoneNumber.isNotEmpty) {
              final contactModel = ContactModel()
                ..displayName = contact.displayName.isNotEmpty 
                    ? contact.displayName 
                    : '${contact.name.first} ${contact.name.last}'.trim()
                ..firstName = contact.name.first
                ..lastName = contact.name.last
                ..phoneNumber = phoneNumber
                ..email = contact.emails.isNotEmpty 
                    ? contact.emails.first.address 
                    : null
                ..company = contact.organizations.isNotEmpty 
                    ? contact.organizations.first.company 
                    : null;
              
              contactModels.add(contactModel);
            }
          }
        }
      }

      // Save to Hive
      await _hiveService.saveContacts(contactModels);
      
      print('✅ Loaded ${contactModels.length} contacts from device');
      return contactModels;
      
    } catch (e) {
      print('❌ Error loading contacts: $e');
      return [];
    }
  }

  Future<List<ContactModel>> getStoredContacts() async {
    return await _hiveService.getAllContacts();
  }

  Future<List<ContactModel>> searchContacts(String query) async {
    if (query.isEmpty) return await getStoredContacts();
    return await _hiveService.searchContacts(query);
  }

  Future<ContactModel?> getContactByPhone(String phoneNumber) async {
    final cleanNumber = _cleanPhoneNumber(phoneNumber);
    return await _hiveService.getContactByPhone(cleanNumber);
  }

  Future<void> refreshContacts() async {
    await _hiveService.clearAllContacts();
    await loadDeviceContacts();
  }

  String _cleanPhoneNumber(String phoneNumber) {
    // Remove all non-digit characters except +
    return phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
  }
}