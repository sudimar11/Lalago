import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/utils/shared_preferences_helper.dart';

class OrderNotificationListener {
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  final NotificationService _notificationService;
  final String _userId;
  List<String> _lastOrderRequestData = [];
  static const String _prefKeyLastOrders = 'last_order_request_data';

  OrderNotificationListener(
    this._notificationService,
    this._userId,
  );

  Future<void> start() async {
    try {
      // Load last known order request data
      await _loadLastOrderData();

      // Listen to user document changes
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final orderRequestData =
                snapshot.data()!['orderRequestData'] as List<dynamic>?;
            _handleOrderRequestDataChange(orderRequestData ?? []);
          }
        },
        onError: (error) {
          log('❌ Error in order notification listener: $error');
        },
      );

      log('✅ Order notification listener started');
    } catch (e) {
      log('❌ Error starting order notification listener: $e');
    }
  }

  Future<void> _loadLastOrderData() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        final lastOrdersJson = prefs.getStringList(_prefKeyLastOrders);
        _lastOrderRequestData = lastOrdersJson ?? [];
      }
    } catch (e) {
      log('⚠️ Error loading last order data: $e');
    }
  }

  Future<void> _saveLastOrderData() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setStringList(_prefKeyLastOrders, _lastOrderRequestData);
      }
    } catch (e) {
      log('⚠️ Error saving last order data: $e');
    }
  }

  Future<void> _handleOrderRequestDataChange(
    List<dynamic> currentOrderRequestData,
  ) async {
    try {
      final currentOrderIds = currentOrderRequestData
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toList();

      // Find new orders (orders in current but not in last)
      final newOrderIds = currentOrderIds
          .where((id) => !_lastOrderRequestData.contains(id))
          .toList();

      if (newOrderIds.isNotEmpty) {
        log('📦 New orders detected: $newOrderIds');

        // Show notification for each new order
        for (final orderId in newOrderIds) {
          await _showOrderNotification(orderId);
        }
      }

      // Update last known order request data
      _lastOrderRequestData = List.from(currentOrderIds);
      await _saveLastOrderData();
    } catch (e) {
      log('❌ Error handling order request data change: $e');
    }
  }

  Future<void> _showOrderNotification(String orderId) async {
    try {
      // Fetch order details
      final orderStream = FireStoreUtils().getOrderByID(orderId);
      final order = await orderStream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      if (order == null) {
        log('⚠️ Could not fetch order details for $orderId');
        // Show basic notification without order details
        await _notificationService.showNotification(
          NotificationData(
            type: NotificationType.order,
            title: 'New Order Available',
            body: 'You have a new order request. Tap to view details.',
            priority: NotificationPriority.high,
            payload: {'orderId': orderId, 'type': 'order'},
            notificationId: NotificationService.idOrder + 1,
          ),
        );
        return;
      }

      // Build notification message
      final vendorName = order.vendor.title.isNotEmpty
          ? order.vendor.title
          : 'Restaurant';
      final orderTotal = order.deliveryCharge ?? '0';
      final address = order.address.getFullAddress();

      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.order,
          title: 'New Order from $vendorName',
          body: 'Order #${orderId.substring(0, 8)} - $address\nTotal: $orderTotal',
          priority: NotificationPriority.high,
          payload: {
            'orderId': orderId,
            'type': 'order',
            'vendorName': vendorName,
          },
          notificationId: NotificationService.idOrder + 1,
        ),
      );

      log('✅ Order notification shown for order: $orderId');
    } catch (e) {
      log('❌ Error showing order notification: $e');
    }
  }

  void stop() {
    _userSubscription?.cancel();
    _userSubscription = null;
    log('🛑 Order notification listener stopped');
  }

  void dispose() {
    stop();
  }
}

/// Handler class that processes order notifications (used by UnifiedNotificationListener)
class OrderNotificationHandler {
  final NotificationService _notificationService;
  final String _userId;
  List<String> _lastOrderRequestData = [];
  static const String _prefKeyLastOrders = 'last_order_request_data';

  OrderNotificationHandler(this._notificationService, this._userId);

  Future<void> initialize() async {
    await _loadLastOrderData();
  }

  Future<void> handleOrderRequestDataChange(
    List<dynamic> currentOrderRequestData,
  ) async {
    try {
      final currentOrderIds = currentOrderRequestData
          .map((e) => e.toString())
          .where((id) => id.isNotEmpty)
          .toList();

      // Find new orders (orders in current but not in last)
      final newOrderIds = currentOrderIds
          .where((id) => !_lastOrderRequestData.contains(id))
          .toList();

      if (newOrderIds.isNotEmpty) {
        log('📦 New orders detected: $newOrderIds');

        // Show notification for each new order
        for (final orderId in newOrderIds) {
          await _showOrderNotification(orderId);
        }
      }

      // Update last known order request data
      _lastOrderRequestData = List.from(currentOrderIds);
      await _saveLastOrderData();
    } catch (e) {
      log('❌ Error handling order request data change: $e');
    }
  }

  Future<void> _loadLastOrderData() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        final lastOrdersJson = prefs.getStringList(_prefKeyLastOrders);
        _lastOrderRequestData = lastOrdersJson ?? [];
      }
    } catch (e) {
      log('⚠️ Error loading last order data: $e');
    }
  }

  Future<void> _saveLastOrderData() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setStringList(_prefKeyLastOrders, _lastOrderRequestData);
      }
    } catch (e) {
      log('⚠️ Error saving last order data: $e');
    }
  }

  Future<void> _showOrderNotification(String orderId) async {
    try {
      // Fetch order details
      final orderStream = FireStoreUtils().getOrderByID(orderId);
      final order = await orderStream.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      if (order == null) {
        log('⚠️ Could not fetch order details for $orderId');
        // Show basic notification without order details
        await _notificationService.showNotification(
          NotificationData(
            type: NotificationType.order,
            title: 'New Order Available',
            body: 'You have a new order request. Tap to view details.',
            priority: NotificationPriority.high,
            payload: {'orderId': orderId, 'type': 'order'},
            notificationId: NotificationService.idOrder + 1,
          ),
        );
        return;
      }

      // Build notification message
      final vendorName = order.vendor.title.isNotEmpty
          ? order.vendor.title
          : 'Restaurant';
      final orderTotal = order.deliveryCharge ?? '0';
      final address = order.address.getFullAddress();

      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.order,
          title: 'New Order from $vendorName',
          body: 'Order #${orderId.substring(0, 8)} - $address\nTotal: $orderTotal',
          priority: NotificationPriority.high,
          payload: {
            'orderId': orderId,
            'type': 'order',
            'vendorName': vendorName,
          },
          notificationId: NotificationService.idOrder + 1,
        ),
      );

      log('✅ Order notification shown for order: $orderId');
    } catch (e) {
      log('❌ Error showing order notification: $e');
    }
  }

  void dispose() {
    // Cleanup if needed
  }
}
