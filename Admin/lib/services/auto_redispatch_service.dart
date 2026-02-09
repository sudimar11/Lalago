import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Service responsible for handling auto-dispatch after driver rejection
/// Manages automatic reassignment with retry logic and driver exclusion
class AutoRedispatchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Auto-dispatch an order after driver rejection
  /// Excludes the rejected driver and tries to find another
  Future<Map<String, dynamic>> dispatchAfterRejection({
    required String orderId,
    required Map<String, dynamic> orderData,
    required Future<Map<String, dynamic>> Function({
      required String orderId,
      required double vendorLat,
      required double vendorLng,
      String? excludeDriverId,
    }) findAndAssignDriver,
  }) async {
    try {
      // Check current order status from Firestore before redispatching
      final orderDoc =
          await _firestore.collection('restaurant_orders').doc(orderId).get();

      if (orderDoc.exists) {
        final currentData = orderDoc.data();
        if (currentData != null) {
          final statusRaw = currentData['status'];
          final status = statusRaw?.toString().toLowerCase() ?? '';

          // Skip redispatch if order is already completed or in transit
          if (status == 'order completed' ||
              status == 'completed' ||
              statusRaw == 3 ||
              status == 'in transit' ||
              status == 'order shipped') {
            print(
                '[Auto Re-Dispatch] Order $orderId is already $statusRaw. Skipping redispatch.');
            return {
              'success': false,
              'skipped': true,
              'reason': 'Order already $statusRaw',
            };
          }
        }
      }

      print(
          '[Auto Re-Dispatch] Driver rejected order $orderId, searching for another rider...');

      // Extract vendor location from order data
      final location = extractVendorLocation(orderData);
      final vendorLat = location['latitude']!;
      final vendorLng = location['longitude']!;

      // Validate vendor location
      if (vendorLat == 0.0 || vendorLng == 0.0) {
        throw Exception('Invalid vendor location');
      }

      // Get the previously rejected driver ID to exclude them
      final rejectedDriverId = extractRejectedDriverId(orderData);

      // Try to find available drivers (excluding rejected one)
      final result = await findAndAssignDriver(
        orderId: orderId,
        vendorLat: vendorLat,
        vendorLng: vendorLng,
        excludeDriverId: rejectedDriverId,
      );

      if (result['success']) {
        // Successfully assigned to a new driver
        return result;
      } else {
        // No active drivers available - needs retry
        print(
            '[Auto Re-Dispatch] No active riders available. Waiting 20 seconds to retry...');

        return {
          'success': false,
          'needsRetry': true,
          'vendorLat': vendorLat,
          'vendorLng': vendorLng,
          'rejectedDriverId': rejectedDriverId,
        };
      }
    } catch (e, stackTrace) {
      print('[Auto Re-Dispatch] Error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Retry dispatch after waiting
  Future<Map<String, dynamic>> retryDispatchAfterRejection({
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    required String? rejectedDriverId,
    required Future<Map<String, dynamic>> Function({
      required String orderId,
      required double vendorLat,
      required double vendorLng,
      String? excludeDriverId,
    }) findAndAssignDriver,
    int waitSeconds = 20,
  }) async {
    try {
      // Wait before retrying
      await Future.delayed(Duration(seconds: waitSeconds));

      // Check current order status from Firestore before retrying
      final orderDoc =
          await _firestore.collection('restaurant_orders').doc(orderId).get();

      if (orderDoc.exists) {
        final currentData = orderDoc.data();
        if (currentData != null) {
          final statusRaw = currentData['status'];
          final status = statusRaw?.toString().toLowerCase() ?? '';

          // Skip redispatch if order is already completed or in transit
          if (status == 'order completed' ||
              status == 'completed' ||
              statusRaw == 3 ||
              status == 'in transit' ||
              status == 'order shipped') {
            print(
                '[Auto Re-Dispatch] Order $orderId is already $statusRaw. Skipping retry.');
            return {
              'success': false,
              'skipped': true,
              'reason': 'Order already $statusRaw',
            };
          }
        }
      }

      print('[Auto Re-Dispatch] Retrying after $waitSeconds seconds...');

      // Retry finding a driver (excluding rejected one)
      final retryResult = await findAndAssignDriver(
        orderId: orderId,
        vendorLat: vendorLat,
        vendorLng: vendorLng,
        excludeDriverId: rejectedDriverId,
      );

      if (retryResult['success']) {
        // Successfully assigned to a driver after retry
        return retryResult;
      } else {
        // Still no drivers available - needs listener setup
        print(
            '[Auto Re-Dispatch] Still no riders available after retry. Setting up listener...');

        return {
          'success': false,
          'needsListener': true,
          'vendorLat': vendorLat,
          'vendorLng': vendorLng,
          'rejectedDriverId': rejectedDriverId,
        };
      }
    } catch (e, stackTrace) {
      print('[Auto Re-Dispatch] Retry error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Extract vendor location from order data
  Map<String, double> extractVendorLocation(Map<String, dynamic> orderData) {
    final vendor = (orderData['vendor'] ?? {}) as Map<String, dynamic>;

    // Helper function to safely convert to double
    double asDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final vendorLat = asDouble(vendor['latitude'] ?? vendor['lat']);
    final vendorLng = asDouble(vendor['longitude'] ?? vendor['lng']);

    return {
      'latitude': vendorLat,
      'longitude': vendorLng,
    };
  }

  /// Extract rejected driver ID from order data
  String? extractRejectedDriverId(Map<String, dynamic> orderData) {
    final rejectedDriverId = (orderData['driverID'] ??
            orderData['driverId'] ??
            orderData['driver_id'] ??
            '') as String? ??
        '';

    return rejectedDriverId.isEmpty ? null : rejectedDriverId;
  }

  /// Show success message after auto-dispatch
  void showSuccessMessage(
    BuildContext context,
    String driverName,
    double distance,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '✅ Auto-dispatched to $driverName (${distance.toStringAsFixed(2)} km)'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show retry message when no drivers available
  void showRetryMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text('⏳ All riders offline. Retrying in 20 seconds...'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  /// Show success message after retry
  void showRetrySuccessMessage(
    BuildContext context,
    String driverName,
    double distance,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '✅ Rider found! Auto-dispatched to $driverName (${distance.toStringAsFixed(2)} km)'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show message when still waiting for drivers
  void showWaitingForDriversMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                  '⏳ Still offline. Waiting for a rider to come online...'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 5),
      ),
    );
  }

  /// Show error message if auto-dispatch fails
  void showErrorMessage(BuildContext context, String error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Auto Re-Dispatch failed: $error')),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Set up listener to wait for drivers to come online
  StreamSubscription<QuerySnapshot> setupDriverOnlineListener({
    required BuildContext context,
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    String? excludeDriverId,
    required Future<Map<String, dynamic>> Function({
      required String orderId,
      required double vendorLat,
      required double vendorLng,
      String? excludeDriverId,
    }) findAndAssignDriver,
    required void Function(String orderId) onListenerCancel,
  }) {
    print(
        '[Auto Re-Dispatch] Setting up driver online listener for order $orderId');

    // Set up a listener for drivers going online
    final listener = _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snapshot) async {
      // Check if any active drivers are available
      if (snapshot.docs.isEmpty) {
        return;
      }

      print(
          '[Auto Re-Dispatch] Active driver detected for order $orderId. Attempting assignment...');

      // Check current order status before attempting assignment
      final orderDoc =
          await _firestore.collection('restaurant_orders').doc(orderId).get();

      if (orderDoc.exists) {
        final currentData = orderDoc.data();
        if (currentData != null) {
          final statusRaw = currentData['status'];
          final status = statusRaw?.toString().toLowerCase() ?? '';

          // Skip assignment if order is already completed or in transit
          if (status == 'order completed' ||
              status == 'completed' ||
              statusRaw == 3 ||
              status == 'in transit' ||
              status == 'order shipped') {
            print(
                '[Auto Re-Dispatch] Order $orderId is already $statusRaw. Canceling listener.');
            onListenerCancel(orderId);
            return;
          }
        }
      }

      // Try to assign to a driver
      try {
        final result = await findAndAssignDriver(
          orderId: orderId,
          vendorLat: vendorLat,
          vendorLng: vendorLng,
          excludeDriverId: excludeDriverId,
        );

        if (result['success']) {
          // Successfully assigned - notify to cancel listener
          onListenerCancel(orderId);

          // Show success message
          showDriverCameOnlineMessage(
            context,
            result['driverName'] as String,
            result['distance'] as double,
          );
        }
      } catch (e) {
        print('[Auto Re-Dispatch] Error in listener: $e');
      }
    });

    print('[Auto Re-Dispatch] Listener setup complete for order $orderId');
    return listener;
  }

  /// Show success message when driver comes online
  void showDriverCameOnlineMessage(
    BuildContext context,
    String driverName,
    double distance,
  ) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '✅ Rider came online! Auto-dispatched to $driverName (${distance.toStringAsFixed(2)} km)'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
