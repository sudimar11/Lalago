import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/order_notification_service.dart';

/// Service responsible for handling order acceptance business logic
/// Separates Firebase operations from UI code
class OrderAcceptanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrderNotificationService _notificationService =
      OrderNotificationService();

  /// Accept an order with the selected preparation time
  /// Returns true if successful, false otherwise
  Future<bool> acceptOrder({
    required String orderId,
    required String preparationTime,
  }) async {
    try {
      // Validate preparation time
      if (preparationTime.isEmpty) {
        throw Exception('Preparation time is required');
      }

      // Fetch order data before updating
      final orderDoc =
          await _firestore.collection('restaurant_orders').doc(orderId).get();

      if (!orderDoc.exists) {
        throw Exception('Order not found');
      }

      final orderData = orderDoc.data()!;

      // Update order status to "Order Accepted" and add preparation time
      await _firestore.collection('restaurant_orders').doc(orderId).update({
        'status': 'Order Accepted',
        'estimatedTimeToPrepare': preparationTime,
        'acceptedAt': FieldValue.serverTimestamp(),
        'autoAccepted': false, // Mark as manually accepted
      });

      print(
          '[Accept Order] Order $orderId accepted with prep time: $preparationTime');

      // Send notification via queue (only to customer for manual acceptance)
      await _notificationService.sendOrderAcceptanceNotifications(
        orderId: orderId,
        orderData: orderData,
        isAutoAccepted: false,
      );

      return true;
    } catch (e, stackTrace) {
      print('[Accept Order] Error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Validate if preparation time was selected
  bool isValidPreparationTime(String? preparationTime) {
    return preparationTime != null && preparationTime.isNotEmpty;
  }

  /// Get available preparation time options
  List<String> getPreparationTimeOptions() {
    return [
      '10 min',
      '15 min',
      '20 min',
      '30 min',
      '45 min',
      '60 min',
    ];
  }

  /// Show success message after accepting order
  void showSuccessMessage(BuildContext context, String preparationTime) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '✅ Order accepted! Prep time: $preparationTime. Tap "Manual Dispatch (AI)" next.'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show error message if accepting order fails
  void showErrorMessage(BuildContext context, String error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to accept order: $error')),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show warning message when no preparation time is selected
  void showWarningMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Text('Preparation time is required to accept the order!'),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
