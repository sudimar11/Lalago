import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/order_notification_service.dart';

/// Service responsible for handling order rejection business logic
/// Separates Firebase operations from UI code
class OrderRejectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrderNotificationService _notificationService =
      OrderNotificationService();

  /// Reject an order with the selected rejection reason
  /// Returns true if successful, false otherwise
  Future<bool> rejectOrder({
    required String orderId,
    required String rejectionReason,
  }) async {
    try {
      // Validate rejection reason
      if (rejectionReason.isEmpty) {
        throw Exception('Rejection reason is required');
      }

      // Fetch order data before updating (to get customer info)
      final orderDoc =
          await _firestore.collection('restaurant_orders').doc(orderId).get();

      // Update order status to "Order Rejected" and save reason
      await _firestore.collection('restaurant_orders').doc(orderId).update({
        'status': 'Order Rejected',
        'rejectionReason': rejectionReason,
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      print('[Reject Order] Order $orderId rejected. Reason: $rejectionReason');

      // Send rejection SMS to customer if order exists
      if (orderDoc.exists && orderDoc.data() != null) {
        await _notificationService.sendOrderRejectedNotification(
          orderData: orderDoc.data()!,
        );
      }

      return true;
    } catch (e, stackTrace) {
      print('[Reject Order] Error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Validate if rejection reason was selected
  bool isValidRejectionReason(String? rejectionReason) {
    return rejectionReason != null && rejectionReason.isNotEmpty;
  }

  /// Get available rejection reason options
  List<String> getRejectionReasonOptions() {
    return [
      'Out of stock',
      'Restaurant closed',
      'Item not available',
      'Preparation time too long',
      'Distance too far',
      'Technical issues',
      'Other',
    ];
  }

  /// Show success message after rejecting order
  void showSuccessMessage(BuildContext context, String rejectionReason) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text('Order rejected successfully. Reason: $rejectionReason'),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show error message if rejecting order fails
  void showErrorMessage(BuildContext context, String error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to reject order: $error')),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show warning message when no rejection reason is selected
  void showWarningMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning, color: Colors.white),
            SizedBox(width: 8),
            Text('Please select a rejection reason!'),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Manually send rejection SMS notification to customer
  /// Returns true if successful, false otherwise
  Future<bool> sendRejectionSMS({
    required Map<String, dynamic> orderData,
  }) async {
    try {
      await _notificationService.sendOrderRejectedNotification(
        orderData: orderData,
      );
      return true;
    } catch (e, stackTrace) {
      print('[Send Rejection SMS] Error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Show success message after sending rejection SMS
  void showSMSSuccessMessage(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Rejection SMS sent successfully to customer'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Show error message if sending rejection SMS fails
  void showSMSErrorMessage(BuildContext context, String error) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text('Failed to send SMS: $error')),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
