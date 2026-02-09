import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Service responsible for handling driver change operations
/// Manages fetching drivers and updating order assignments
class DriverChangeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Fetch all drivers from the system
  Future<List<Map<String, dynamic>>> fetchAllDrivers() async {
    try {
      final driversQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();

      return driversQuery.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'firstName': data['firstName'] ?? '',
          'lastName': data['lastName'] ?? '',
          'phoneNumber': data['phoneNumber'] ?? '',
          'isActive': data['isActive'] == true,
        };
      }).toList();
    } catch (e) {
      print('[Driver Change Service] Error fetching drivers: $e');
      rethrow;
    }
  }

  /// Change the driver assigned to an order
  Future<void> changeDriver({
    required String orderId,
    required String newDriverId,
  }) async {
    try {
      // Update the order with the new driver
      await _firestore.collection('restaurant_orders').doc(orderId).update({
        'driverID': newDriverId,
        'driverId': newDriverId,
        'driver_id': newDriverId,
        'manualDriverChange': true,
        'driverChangedAt': FieldValue.serverTimestamp(),
      });

      print(
          '[Driver Change Service] Successfully changed driver for order $orderId to $newDriverId');
    } catch (e) {
      print('[Driver Change Service] Error changing driver: $e');
      rethrow;
    }
  }

  /// Complete driver change operation with UI feedback
  /// Returns true if successful, false otherwise
  Future<bool> changeDriverForOrder({
    required BuildContext context,
    required String orderId,
    required String newDriverId,
    required String newDriverName,
  }) async {
    try {
      // Change the driver using the service
      await changeDriver(
        orderId: orderId,
        newDriverId: newDriverId,
      );

      // Show success message
      showSuccessMessage(context, newDriverName);
      return true;
    } catch (e) {
      print('[Change Driver] Error: $e');
      showErrorMessage(context, e.toString());
      return false;
    }
  }

  /// Format driver name from first and last name
  String formatDriverName(String firstName, String lastName) {
    final driverName = '$firstName $lastName'.trim();
    return driverName.isEmpty ? 'Unknown Driver' : driverName;
  }

  /// Check if driver list is empty
  bool hasDrivers(List<Map<String, dynamic>> drivers) {
    return drivers.isNotEmpty;
  }

  /// Show success message after changing driver
  void showSuccessMessage(BuildContext context, String driverName) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Driver changed to $driverName successfully!'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show error message if changing driver fails
  void showErrorMessage(BuildContext context, String error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to change driver: $error')),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show warning message when no drivers are found
  void showNoDriversWarning(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Text('No drivers found in the system'),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Show error message when loading drivers fails
  void showLoadDriversError(BuildContext context, String error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to load drivers: $error')),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
