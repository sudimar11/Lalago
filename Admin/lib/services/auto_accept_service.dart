import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/order_notification_service.dart';

/// Service for handling automatic order acceptance
/// Auto-accepts orders after 4 minutes if restaurant hasn't responded
class AutoAcceptService {
  // Auto-accept timer management
  final Map<String, Timer> _autoAcceptTimers = {};
  final Map<String, DateTime> _orderPlacedTimes = {};

  // Notification service for sending SMS
  final OrderNotificationService _notificationService =
      OrderNotificationService();

  /// Start auto-accept timer for an order
  /// Will auto-accept the order after 4 minutes from orderCreatedAt
  void startAutoAcceptTimer(
    String orderId,
    DateTime orderCreatedAt, {
    VoidCallback? onAutoAccept,
  }) {
    // Cancel existing timer if any
    _autoAcceptTimers[orderId]?.cancel();

    // Store the order placed time
    _orderPlacedTimes[orderId] = orderCreatedAt;

    // Calculate time until auto-accept (4 minutes)
    final timeUntilAutoAccept = DateTime.now().difference(orderCreatedAt);
    final remainingTime = const Duration(minutes: 4) - timeUntilAutoAccept;

    if (remainingTime.isNegative) {
      // Order is already past 4 minutes, auto-accept immediately
      autoAcceptOrder(orderId, onAutoAccept: onAutoAccept);
    } else {
      // Set timer for remaining time
      _autoAcceptTimers[orderId] = Timer(remainingTime, () {
        autoAcceptOrder(orderId, onAutoAccept: onAutoAccept);
      });
    }
  }

  /// Cancel auto-accept timer for an order
  void cancelAutoAcceptTimer(String orderId) {
    _autoAcceptTimers[orderId]?.cancel();
    _autoAcceptTimers.remove(orderId);
    _orderPlacedTimes.remove(orderId);
  }

  /// Auto-accept an order with default preparation time
  Future<void> autoAcceptOrder(
    String orderId, {
    VoidCallback? onAutoAccept,
    BuildContext? context,
  }) async {
    try {
      print('[Auto Accept] Auto-accepting order $orderId after 4 minutes');

      // Fetch order data before updating
      final orderDoc = await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .get();

      if (!orderDoc.exists) {
        print('[Auto Accept] Order $orderId not found');
        return;
      }

      final orderData = orderDoc.data()!;

      // Update order status to "Order Accepted" with default preparation time
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .update({
        'status': 'Order Accepted',
        'estimatedTimeToPrepare': '30 min',
        'acceptedAt': FieldValue.serverTimestamp(),
        'autoAccepted': true, // Mark as auto-accepted
      });

      print(
          '[Auto Accept] ✅ Order $orderId auto-accepted with prep time: 30 min');

      // Send ALL notifications in sequence via queue
      await _notificationService.sendOrderAcceptanceNotifications(
        orderId: orderId,
        orderData: orderData,
        isAutoAccepted: true,
      );

      // Cancel the timer
      cancelAutoAcceptTimer(orderId);

      // Call callback if provided
      onAutoAccept?.call();

      // Show success message if context is provided
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔄 Order $orderId auto-accepted after 4 minutes'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('[Auto Accept] Error: $e\n$stackTrace');
    }
  }

  /// Cancel all active auto-accept timers
  /// Should be called when disposing the service
  void dispose() {
    for (final timer in _autoAcceptTimers.values) {
      timer.cancel();
    }
    _autoAcceptTimers.clear();
    _orderPlacedTimes.clear();
  }

  /// Get the time when an order was placed
  DateTime? getOrderPlacedTime(String orderId) {
    return _orderPlacedTimes[orderId];
  }

  /// Check if an order has an active auto-accept timer
  bool hasActiveTimer(String orderId) {
    return _autoAcceptTimers.containsKey(orderId);
  }

  /// Get the number of active timers
  int get activeTimersCount => _autoAcceptTimers.length;
}
