import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/services/sms_service.dart';
import 'package:brgy/widgets/orders/order_helpers.dart';

/// Service for handling SMS operations related to orders
/// Sends SMS to customers, drivers, and restaurant owners
class OrderSMSService {
  final SMSService _smsService = SMSService();

  /// Send SMS to customer
  /// Returns a result map with 'success' boolean and optional 'message'
  Future<Map<String, dynamic>> sendSMSToCustomer({
    required Map<String, dynamic> orderData,
    required String message,
  }) async {
    try {
      // Get customer phone number
      final author = orderData['author'] as Map<String, dynamic>?;
      final customerId = author?['id'] as String? ?? '';

      if (customerId.isEmpty) {
        return {
          'success': false,
          'message': 'Customer information not available'
        };
      }

      final phoneNumber = await _fetchCustomerPhone(customerId);
      if (phoneNumber.isEmpty) {
        return {
          'success': false,
          'message': 'Customer phone number not available'
        };
      }

      // Send SMS
      final result = await _smsService.sendSingleSMS(
        phoneNumber: phoneNumber,
        message: message,
        useFallback: true,
      );

      return result;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Send SMS to driver
  /// Returns a result map with 'success' boolean and optional 'message'
  Future<Map<String, dynamic>> sendSMSToDriver({
    required Map<String, dynamic> orderData,
    required String message,
  }) async {
    try {
      // Get driver ID from the order data
      final driverId = (orderData['driverID'] ??
              orderData['driverId'] ??
              orderData['driver_id'] ??
              '') as String? ??
          '';

      if (driverId.isEmpty) {
        return {
          'success': false,
          'message': 'Driver not assigned to this order'
        };
      }

      // Fetch driver information using the existing helper function
      final driverInfo = await fetchDriverInfo(driverId);
      final driverPhone = driverInfo['phone'] ?? '';

      if (driverPhone.isEmpty) {
        return {
          'success': false,
          'message': 'Driver phone number not available'
        };
      }

      // Send SMS
      final result = await _smsService.sendSingleSMS(
        phoneNumber: driverPhone,
        message: message,
        useFallback: true,
      );

      return result;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Send SMS to restaurant owner
  /// Returns a result map with 'success' boolean and optional 'message'
  Future<Map<String, dynamic>> sendSMSToOwner({
    required Map<String, dynamic> orderData,
    required String message,
  }) async {
    try {
      // Get restaurant owner information
      final ownerInfo = await fetchRestaurantOwnerInfo(orderData);
      final ownerPhone = ownerInfo['phone'] ?? '';

      if (ownerPhone.isEmpty) {
        return {
          'success': false,
          'message': 'Restaurant owner phone number not available'
        };
      }

      // Send SMS
      final result = await _smsService.sendSingleSMS(
        phoneNumber: ownerPhone,
        message: message,
        useFallback: true,
      );

      return result;
    } catch (e) {
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Helper method to fetch customer phone number
  Future<String> _fetchCustomerPhone(String customerId) async {
    try {
      final customerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(customerId)
          .get();

      if (customerDoc.exists) {
        final customerData = customerDoc.data();
        return (customerData?['phoneNumber'] ?? '').toString();
      }
      return '';
    } catch (e) {
      print('Error fetching customer phone: $e');
      return '';
    }
  }
}
