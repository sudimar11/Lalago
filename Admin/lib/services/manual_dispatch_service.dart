import 'package:flutter/material.dart';

/// Service responsible for handling manual dispatch operations
/// Manages AI-powered driver assignment with retry logic
class ManualDispatchService {
  /// Dispatch an order to a driver using AI logic
  /// Returns result map with success status and driver info
  Future<Map<String, dynamic>> dispatchOrder({
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    double? deliveryLat,
    double? deliveryLng,
    String? deliveryLocality,
    required Future<Map<String, dynamic>> Function({
      required String orderId,
      required double vendorLat,
      required double vendorLng,
      String? excludeDriverId,
      double? deliveryLat,
      double? deliveryLng,
      String? deliveryLocality,
    }) findAndAssignDriver,
  }) async {
    try {
      // Validate vendor location
      if (vendorLat == 0.0 || vendorLng == 0.0) {
        throw Exception('Invalid vendor location');
      }

      print('[Manual Dispatch AI] Searching for active drivers...');

      final result = await findAndAssignDriver(
        orderId: orderId,
        vendorLat: vendorLat,
        vendorLng: vendorLng,
        deliveryLat: deliveryLat,
        deliveryLng: deliveryLng,
        deliveryLocality: deliveryLocality,
      );

      if (result['success']) {
        // Successfully assigned
        return result;
      } else {
        // No active drivers - retry after 20 seconds
        print(
            '[Manual Dispatch AI] No active riders. Waiting 20 seconds to retry...');

        // Return pending status to show retry message
        return {
          'success': false,
          'needsRetry': true,
          'message': 'No active riders, will retry',
        };
      }
    } catch (e, stackTrace) {
      print('[Manual Dispatch AI] Error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Retry dispatch after waiting
  Future<Map<String, dynamic>> retryDispatch({
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    double? deliveryLat,
    double? deliveryLng,
    String? deliveryLocality,
    required Future<Map<String, dynamic>> Function({
      required String orderId,
      required double vendorLat,
      required double vendorLng,
      String? excludeDriverId,
      double? deliveryLat,
      double? deliveryLng,
      String? deliveryLocality,
    }) findAndAssignDriver,
    int waitSeconds = 20,
  }) async {
    try {
      await Future.delayed(Duration(seconds: waitSeconds));
      print('[Manual Dispatch AI] Retrying after $waitSeconds seconds...');

      final retryResult = await findAndAssignDriver(
        orderId: orderId,
        vendorLat: vendorLat,
        vendorLng: vendorLng,
        deliveryLat: deliveryLat,
        deliveryLng: deliveryLng,
        deliveryLocality: deliveryLocality,
      );

      if (retryResult['success']) {
        // Successfully assigned after retry
        return retryResult;
      } else {
        // Still no riders - throw exception
        throw Exception('No active riders available after retry');
      }
    } catch (e, stackTrace) {
      print('[Manual Dispatch AI] Retry error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Extract delivery address location and locality from order data
  Map<String, dynamic> extractDeliveryAddress(Map<String, dynamic> orderData) {
    final addr = (orderData['address'] ?? {}) as Map<String, dynamic>?;
    if (addr == null) return {'lat': null, 'lng': null, 'locality': null};
    final loc = (addr['location'] ?? {}) as Map<String, dynamic>?;
    double? lat;
    double? lng;
    if (loc != null) {
      final v = loc['latitude'] ?? loc['lat'];
      if (v != null) lat = (v is num) ? v.toDouble() : double.tryParse('$v');
      final w = loc['longitude'] ?? loc['lng'];
      if (w != null) lng = (w is num) ? w.toDouble() : double.tryParse('$w');
    }
    final locality = (addr['locality'] ?? '').toString().trim();
    return {'lat': lat, 'lng': lng, 'locality': locality.isEmpty ? null : locality};
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

  /// Show success message after successful driver assignment
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
                  '✅ AI assigned $driverName to order! (${distance.toStringAsFixed(2)} km away)'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show retry message when no drivers are available
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
                  '✅ Rider found! AI assigned $driverName to order! (${distance.toStringAsFixed(2)} km away)'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show error message if dispatch fails
  void showErrorMessage(BuildContext context, String error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('AI Dispatch failed: $error')),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

