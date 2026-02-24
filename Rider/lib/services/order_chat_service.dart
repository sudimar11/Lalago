import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:foodie_driver/model/conversation_model.dart';
import 'package:foodie_driver/model/inbox_model.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:uuid/uuid.dart';

class OrderChatService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const _uuid = Uuid();
  static final Map<String, StreamSubscription> _statusListeners = {};
  static final Map<String, Timer> _delayTimers = {};

  /// Get system message text for order status
  static String _getSystemMessage(String status) {
    switch (status) {
      case 'Driver Assigned':
        return 'Driver has been assigned to your order';
      case 'Driver Accepted':
        return 'Driver is waiting for restaurant to prepare your order';
      case 'Order Shipped':
        return 'Your order is ready for pickup';
      case 'In Transit':
        return 'Driver is on the way with your order';
      case 'Order Completed':
        return 'Your order has been delivered. Thank you!';
      case 'Driver Rejected':
        return 'Driver declined this order. A new driver will be assigned.';
      case 'Order Cancelled':
        return 'This order has been cancelled';
      default:
        return 'Order status updated: $status';
    }
  }

  /// Send a system message to the order chat
  static Future<void> sendSystemMessage({
    required String orderId,
    required String status,
    required String customerId,
    String? customerFcmToken,
    String? customerName,
    String? restaurantId,
  }) async {
    try {
      final messageId = _uuid.v4();
      final messageText = _getSystemMessage(status);

      final systemMessage = ConversationModel(
        id: messageId,
        senderId: 'system',
        receiverId: customerId,
        orderId: orderId,
        message: messageText,
        messageType: 'system',
        senderType: 'system',
        orderStatus: status,
        createdAt: Timestamp.now(),
        isRead: false,
      );

      // Save to Firestore
      await FireStoreUtils.addDriverChat(systemMessage);

      // Send push notification if token available
      if (customerFcmToken != null && customerFcmToken.isNotEmpty) {
        await FireStoreUtils.sendChatFcmMessage(
          'Order Update',
          messageText,
          customerFcmToken,
          orderId: orderId,
          orderStatus: status,
          customerId: customerId,
          restaurantId: restaurantId,
          tokenSource: 'order.author',
        );
      }
    } catch (e) {
      print('Error sending system message: $e');
    }
  }

  /// Send a driver message (appears as if from driver, not system)
  static Future<void> sendDriverMessage({
    required String orderId,
    required String message,
    required String driverId,
    required String driverName,
    String? driverProfileImage,
    required String customerId,
    required String customerName,
    String? customerProfileImage,
    String? customerFcmToken,
  }) async {
    try {
      final messageId = _uuid.v4();

      // Create conversation message
      final driverMessage = ConversationModel(
        id: messageId,
        senderId: driverId,
        receiverId: customerId,
        orderId: orderId,
        message: message,
        messageType: 'text',
        senderType: 'driver',
        createdAt: Timestamp.now(),
        isRead: false,
      );

      // Save message to Firestore
      await FireStoreUtils.addDriverChat(driverMessage);

      // Update inbox
      final inboxModel = InboxModel(
        lastSenderId: driverId,
        customerId: customerId,
        customerName: customerName,
        restaurantId: driverId,
        restaurantName: driverName,
        createdAt: Timestamp.now(),
        orderId: orderId,
        customerProfileImage: customerProfileImage,
        restaurantProfileImage: driverProfileImage,
        lastMessage: message,
        chatType: 'Driver',
      );

      await FireStoreUtils.addDriverInbox(inboxModel);

      // Resolve FCM token with fallback: order.author -> users/{customerId}
      // Always fetch fresh token from order document first (most reliable source)
      String? fcmToken;
      String? fallbackToken;
      String? resolvedCustomerId = customerId;
      String tokenSource = 'unknown';

      try {
        final orderDoc =
            await _firestore.collection('restaurant_orders').doc(orderId).get();

        if (orderDoc.exists) {
          final orderData = orderDoc.data();
          final author = orderData?['author'] as Map<String, dynamic>? ?? {};
          fcmToken = author['fcmToken'] as String?;
          resolvedCustomerId =
              author['id'] as String? ?? author['customerID'] as String? ?? customerId;
          tokenSource = 'order.author';

          // Always fetch fallback token from users collection in case order.author token is invalid
          if (resolvedCustomerId.isNotEmpty) {
            try {
              final userDoc =
                  await _firestore.collection('users').doc(resolvedCustomerId).get();
              if (userDoc.exists) {
                final userData = userDoc.data();
                fallbackToken = userData?['fcmToken'] as String?;
                if (fallbackToken != null && fallbackToken.isNotEmpty && fallbackToken != fcmToken) {
                  debugPrint(
                      '[OrderChatService.sendDriverMessage] Order $orderId: Retrieved fallback FCM token from users collection for customer $resolvedCustomerId');
                }
              }
            } catch (userError) {
              debugPrint(
                  '[OrderChatService.sendDriverMessage] Order $orderId: Error reading user doc: $userError');
            }
          }

          // If order.author token is missing, use fallback token
          if ((fcmToken == null || fcmToken.isEmpty) && fallbackToken != null) {
            fcmToken = fallbackToken;
            tokenSource = 'users.collection';
            fallbackToken = null; // Clear fallback since we're using it
          }
        } else {
          debugPrint(
              '[OrderChatService.sendDriverMessage] Order $orderId: Order document not found');
        }
      } catch (orderError) {
        debugPrint(
            '[OrderChatService.sendDriverMessage] Order $orderId: Error reading order doc: $orderError');
      }

      // Send push notification if token available
      if (fcmToken != null && fcmToken.isNotEmpty) {
        // Build payload keys for debug logging
        final payloadKeys = <String>['type', 'orderId', 'senderRole', 'messageType'];

        // Log resolved customer ID, token source, and payload keys
        debugPrint(
            '[OrderChatService.sendDriverMessage] Order $orderId: Resolved customerId=${resolvedCustomerId ?? "null"}, tokenSource=$tokenSource, payloadKeys=[${payloadKeys.join(", ")}]');

        // Send notification with proper payload (await to ensure completion)
        bool sendSuccess = await FireStoreUtils.sendChatFcmMessage(
          driverName,
          message,
          fcmToken,
          orderId: orderId,
          senderRole: 'rider',
          messageType: 'chat',
          customerId: resolvedCustomerId,
          restaurantId: driverId,
          tokenSource: tokenSource,
        );

        // If first attempt failed and we have a fallback token, try again with fallback
        if (!sendSuccess && fallbackToken != null && fallbackToken.isNotEmpty && fcmToken != fallbackToken) {
          debugPrint(
              '[OrderChatService.sendDriverMessage] Order $orderId: First token failed, retrying with fallback token from users collection');
          sendSuccess = await FireStoreUtils.sendChatFcmMessage(
            driverName,
            message,
            fallbackToken,
            orderId: orderId,
            senderRole: 'rider',
            messageType: 'chat',
            customerId: resolvedCustomerId,
            restaurantId: driverId,
            tokenSource: 'users.collection',
          );
          if (sendSuccess) {
            debugPrint(
                '[OrderChatService.sendDriverMessage] Order $orderId: FCM notification sent successfully using fallback token');
          }
        }

        if (sendSuccess) {
          debugPrint(
              '[OrderChatService.sendDriverMessage] Order $orderId: FCM notification sent successfully');
        } else {
          debugPrint(
              '[OrderChatService.sendDriverMessage] Order $orderId: FCM notification failed to send - token may be invalid. Customer ID: ${resolvedCustomerId ?? "unknown"}');
        }
      } else {
        debugPrint(
            '[OrderChatService.sendDriverMessage] Order $orderId: No FCM token available for customer ${resolvedCustomerId ?? "unknown"}');
      }
    } catch (e) {
      print('Error sending driver message: $e');
    }
  }

  /// Send a delay alert message
  static Future<void> sendDelayAlert({
    required String orderId,
    required String customerId,
    required String delayReason,
    String? customerFcmToken,
  }) async {
    try {
      final messageId = _uuid.v4();
      final messageText = '⚠️ Delay Alert: $delayReason';

      final delayMessage = ConversationModel(
        id: messageId,
        senderId: 'system',
        receiverId: customerId,
        orderId: orderId,
        message: messageText,
        messageType: 'system',
        senderType: 'system',
        orderStatus: null,
        createdAt: Timestamp.now(),
        isRead: false,
        readBy: {},
      );

      await FireStoreUtils.addDriverChat(delayMessage);

      if (customerFcmToken != null && customerFcmToken.isNotEmpty) {
        await FireStoreUtils.sendChatFcmMessage(
          'Order Delay',
          messageText,
          customerFcmToken,
          orderId: orderId,
          customerId: customerId,
          tokenSource: 'order.author',
        );
      }
    } catch (e) {
      print('Error sending delay alert: $e');
    }
  }

  /// Monitor order for delays and send alerts
  static void monitorOrderForDelays({
    required String orderId,
    required Map<String, dynamic> orderData,
    required String customerId,
    String? customerFcmToken,
  }) {
    // Cancel existing timer if any
    _delayTimers[orderId]?.cancel();
    _delayTimers.remove(orderId);

    final status = orderData['status'] as String? ?? '';
    final createdAt = orderData['createdAt'] as Timestamp?;
    final estimatedTime = orderData['estimatedTimeToPrepare'] as String?;

    if (createdAt == null) return;

    final now = DateTime.now();
    final orderTime = createdAt.toDate();
    final duration = now.difference(orderTime);

    // Check for different delay scenarios
    if (status == 'Driver Assigned') {
      // Check if not accepted within 5 minutes
      final timer = Timer(const Duration(minutes: 5), () {
        _firestore.collection('restaurant_orders').doc(orderId).get().then((doc) {
          if (!doc.exists) return;
          final currentData = doc.data();
          final currentStatus = currentData?['status'] as String? ?? '';
          if (currentStatus == 'Driver Assigned') {
            sendDelayAlert(
              orderId: orderId,
              customerId: customerId,
              delayReason: 'Driver has not accepted the order yet. We are looking for another driver.',
              customerFcmToken: customerFcmToken,
            );
          }
        });
      });
      _delayTimers[orderId] = timer;
    } else if (status == 'Driver Accepted') {
      // Check if order is pending longer than estimated time + 10 minutes
      int estimatedMinutes = 0;
      if (estimatedTime != null && estimatedTime.isNotEmpty) {
        estimatedMinutes = int.tryParse(estimatedTime) ?? 0;
      }
      final delayThreshold = Duration(minutes: estimatedMinutes + 10);

      if (duration > delayThreshold) {
        sendDelayAlert(
          orderId: orderId,
          customerId: customerId,
          delayReason: 'Order preparation is taking longer than expected. We apologize for the delay.',
          customerFcmToken: customerFcmToken,
        );
      } else {
        final remainingTime = delayThreshold - duration;
        final timer = Timer(remainingTime, () {
          _firestore.collection('restaurant_orders').doc(orderId).get().then((doc) {
            if (!doc.exists) return;
            final currentData = doc.data();
            final currentStatus = currentData?['status'] as String? ?? '';
            if (currentStatus == 'Driver Accepted') {
              sendDelayAlert(
                orderId: orderId,
                customerId: customerId,
                delayReason: 'Order preparation is taking longer than expected. We apologize for the delay.',
                customerFcmToken: customerFcmToken,
              );
            }
          });
        });
        _delayTimers[orderId] = timer;
      }
    } else if (status == 'In Transit') {
      // Check if in transit for more than 30 minutes
      final timer = Timer(const Duration(minutes: 30), () {
        _firestore.collection('restaurant_orders').doc(orderId).get().then((doc) {
          if (!doc.exists) return;
          final currentData = doc.data();
          final currentStatus = currentData?['status'] as String? ?? '';
          if (currentStatus == 'In Transit') {
            sendDelayAlert(
              orderId: orderId,
              customerId: customerId,
              delayReason: 'Delivery is taking longer than expected. Driver may be experiencing delays.',
              customerFcmToken: customerFcmToken,
            );
          }
        });
      });
      _delayTimers[orderId] = timer;
    }
  }

  /// Start monitoring an order for status changes and delays
  static void startMonitoringOrder(String orderId) {
    // Cancel existing listener if any
    _statusListeners[orderId]?.cancel();
    _statusListeners.remove(orderId);

    // Get initial order data and start delay monitoring
    _firestore.collection('restaurant_orders').doc(orderId).get().then((doc) {
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final author = data['author'] as Map<String, dynamic>? ?? {};
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;

      // Start delay monitoring for current status
      if (customerId != null) {
        monitorOrderForDelays(
          orderId: orderId,
          orderData: data,
          customerId: customerId.toString(),
          customerFcmToken: customerFcmToken,
        );
      }
    });

    // Listen to status changes
    final subscription = _firestore
        .collection('restaurant_orders')
        .doc(orderId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final data = snapshot.data();
      if (data == null) return;

      final status = data['status'] as String? ?? '';
      final author = data['author'] as Map<String, dynamic>? ?? {};
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;
      final previousStatus = data['_previousStatus'] as String?;

      // Only send message if status actually changed
      if (previousStatus != null && previousStatus != status) {
        final driverId =
            data['driverID'] as String? ?? data['driverId'] as String?;
        sendSystemMessage(
          orderId: orderId,
          status: status,
          customerId: customerId.toString(),
          customerFcmToken: customerFcmToken,
          restaurantId: driverId,
        );

        // Monitor for delays on new status
        if (customerId != null) {
          monitorOrderForDelays(
            orderId: orderId,
            orderData: data,
            customerId: customerId.toString(),
            customerFcmToken: customerFcmToken,
          );
        }
      }

      // Store current status for next comparison
      _firestore.collection('restaurant_orders').doc(orderId).update({
        '_previousStatus': status,
      });
    });

    _statusListeners[orderId] = subscription;
  }

  /// Listen to order status changes and send system messages
  /// @deprecated Use startMonitoringOrder instead
  static void listenToOrderStatusChanges(String orderId) {
    startMonitoringOrder(orderId);
  }

  /// Stop listening to order status changes
  static void stopListeningToOrderStatus(String orderId) {
    _statusListeners[orderId]?.cancel();
    _statusListeners.remove(orderId);
    _delayTimers[orderId]?.cancel();
    _delayTimers.remove(orderId);
  }

  /// Clean up all listeners and timers
  static void dispose() {
    for (var listener in _statusListeners.values) {
      listener.cancel();
    }
    _statusListeners.clear();

    for (var timer in _delayTimers.values) {
      timer.cancel();
    }
    _delayTimers.clear();
  }
}


