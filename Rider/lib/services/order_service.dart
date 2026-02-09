import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/utils/dialog_utils.dart';
import 'package:foodie_driver/services/driver_performance_service.dart';
import 'package:foodie_driver/services/order_chat_service.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/attendance_service.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';

/// Service class for order-related operations
class OrderService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Accepts an order for the current driver
  ///
  /// [order] - The order data
  /// [orderId] - The order document ID
  /// [context] - BuildContext for UI interactions
  ///
  /// Returns true if order was accepted successfully, false otherwise
  static Future<bool> acceptOrder(
    Map<String, dynamic> order,
    String orderId,
    BuildContext context,
  ) async {
    try {
      final currentUserId = _auth.currentUser?.uid ?? '';
      if (currentUserId.isEmpty) {
        throw Exception("No user is logged in.");
      }

      final canProceed =
          await _guardAttendanceStatus(context, currentUserId);
      if (!canProceed) return false;

      final remittanceOk =
          await _guardRemittanceStatus(context, currentUserId);
      if (!remittanceOk) return false;

      final driverSnapshot =
          await _firestore.collection('users').doc(currentUserId).get();

      if (!driverSnapshot.exists) {
        throw Exception("Driver not found");
      }

      final driverData = driverSnapshot.data();
      final bool checkedInToday =
          driverData?['checkedInToday'] == true;
      final todayCheckOut = driverData?['todayCheckOutTime'];
      final bool hasCheckedOutToday =
          todayCheckOut != null && todayCheckOut.toString().isNotEmpty;
      final todayCheckIn = driverData?['todayCheckInTime'];
      final bool hasCheckedInToday = checkedInToday &&
          todayCheckIn != null &&
          todayCheckIn.toString().isNotEmpty;

      if (!hasCheckedInToday || hasCheckedOutToday) {
        await DialogUtils.showAlertDialog(
          context,
          title: 'Check In Required',
          content: 'You must check in today to accept orders.',
        );
        return false;
      }

      final driverLocation = driverData?['location'] ?? {};
      final bool multipleOrders = driverData?['multipleOrders'] == true;

      if (driverLocation.isEmpty) {
        throw Exception("Driver location not available");
      }

      // Check if driver already has an active order (only if multipleOrders is false)
      if (!multipleOrders) {
        final activeOrderCheck = await _firestore
            .collection('restaurant_orders')
            .where('driverID', isEqualTo: currentUserId)
            .where('status', whereIn: [
              'Driver Pending',
              'Driver Accepted',
              'Order Shipped',
              'In Transit',
            ])
            .limit(1)
            .get();

        if (activeOrderCheck.docs.isNotEmpty) {
          await DialogUtils.showAlertDialog(
            context,
            title: "Active Order Exists",
            content:
                "You already have an ongoing order. Please complete or deliver it before accepting a new one.",
          );
          return false;
        }
      }

      // Get order data for system message
      final orderDoc = await _firestore.collection('restaurant_orders').doc(orderId).get();
      final orderData = orderDoc.data();
      final author = orderData?['author'] as Map<String, dynamic>? ?? {};
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;

      // Assign the order
      await _firestore.collection('restaurant_orders').doc(orderId).update({
        'status': 'Driver Pending',
        'driverId': currentUserId,
        'driverID': currentUserId,
        'driverName': '${driverData?['firstName']} ${driverData?['lastName']}',
        'driverLocation': {
          'latitude': driverLocation['latitude'],
          'longitude': driverLocation['longitude'],
        },
      });

      // Send system message
      if (customerId != null) {
        await OrderChatService.sendSystemMessage(
          orderId: orderId,
          status: 'Driver Pending',
          customerId: customerId.toString(),
          customerFcmToken: customerFcmToken,
          restaurantId: currentUserId,
        );
      }

      DialogUtils.showSnackBar(
        context,
        message: 'Order accepted successfully! Driver assigned.',
        backgroundColor: Colors.green,
      );

      return true;
    } catch (e) {
      DialogUtils.showSnackBar(
        context,
        message: 'Failed to accept order: $e',
        backgroundColor: Colors.red,
      );
      return false;
    }
  }

  /// Rejects an order
  ///
  /// [order] - The order data
  /// [orderId] - The order document ID
  /// [context] - BuildContext for UI interactions
  ///
  /// Returns true if order was rejected successfully, false otherwise
  static Future<bool> rejectOrder(
    Map<String, dynamic> order,
    String orderId,
    BuildContext context,
  ) async {
    try {
      final currentUserId = _auth.currentUser?.uid ?? '';

      final canProceed =
          await _guardAttendanceStatus(context, currentUserId);
      if (!canProceed) return false;
      
      final orderRef = _firestore.collection('restaurant_orders').doc(orderId);

      // Get order data for system message
      final orderDoc = await orderRef.get();
      final orderData = orderDoc.data();
      final author = orderData?['author'] as Map<String, dynamic>? ?? {};
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;

      // Update the order status
      await orderRef.update({'status': 'Driver Rejected'});

      // Apply performance penalty for driver-fault cancellation
      if (currentUserId.isNotEmpty) {
        await DriverPerformanceService.applyCancellationPenalty(currentUserId);
      }

      // Send system message
      if (customerId != null) {
        await OrderChatService.sendSystemMessage(
          orderId: orderId,
          status: 'Driver Rejected',
          customerId: customerId.toString(),
          customerFcmToken: customerFcmToken,
        );
      }

      DialogUtils.showSnackBar(
        context,
        message: 'Order rejected successfully!',
        backgroundColor: Colors.green,
      );

      return true;
    } catch (e) {
      DialogUtils.showSnackBar(
        context,
        message: 'Failed to reject order: $e',
        backgroundColor: Colors.red,
      );
      return false;
    }
  }

  /// Get system message text for order status
  static String _getStatusMessage(String status) {
    switch (status) {
      case 'Driver Assigned':
        return 'Driver has been assigned to your order';
      case 'Driver Pending':
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

  /// Send FCM notification to customer when order status is updated
  /// 
  /// [orderId] - The order document ID
  /// [newStatus] - The new order status
  /// [customerFcmToken] - Optional customer FCM token. If not provided, will fetch from order document
  /// 
  /// Returns true if notification was sent successfully, false otherwise
  /// Errors are logged but don't throw exceptions to prevent blocking status updates
  static Future<bool> sendStatusUpdateNotification(
    String orderId,
    String newStatus, {
    String? customerFcmToken,
  }) async {
    try {
      // Fetch order document for driver ID and optionally token/customerId
      final orderDoc =
          await _firestore.collection('restaurant_orders').doc(orderId).get();
      if (!orderDoc.exists) {
        debugPrint('Order not found for FCM notification: $orderId');
        return false;
      }

      final orderData = orderDoc.data();
      final author = orderData?['author'] as Map<String, dynamic>? ?? {};
      final driverId = orderData?['driverID'] as String? ??
          orderData?['driverId'] as String?;

      String? fcmToken = customerFcmToken;
      String? customerId = author['id'] as String? ?? author['customerID'];
      String tokenSource = 'provided';

      if (fcmToken == null || fcmToken.isEmpty) {
        fcmToken = author['fcmToken'] as String?;
        tokenSource = 'order.author';

        if ((fcmToken == null || fcmToken.isEmpty) && customerId != null) {
          try {
            final userDoc =
                await _firestore.collection('users').doc(customerId).get();
            if (userDoc.exists) {
              final userData = userDoc.data();
              fcmToken = userData?['fcmToken'] as String?;
              tokenSource = 'users.collection';
              debugPrint(
                  '[sendStatusUpdateNotification] Order $orderId: Retrieved '
                  'FCM token from users collection for customer $customerId');
            }
          } catch (userError) {
            debugPrint(
                '[sendStatusUpdateNotification] Order $orderId: Error reading '
                'user doc: $userError');
          }
        }
      }

      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint(
            '[sendStatusUpdateNotification] Order $orderId: No FCM token '
            'available for customer ${customerId ?? "unknown"}');
        return false;
      }

      debugPrint(
          '[sendStatusUpdateNotification] Order $orderId: Resolved '
          'customerId=${customerId ?? "unknown"}, tokenSource=$tokenSource');

      final messageBody = _getStatusMessage(newStatus);

      await FireStoreUtils.sendChatFcmMessage(
        'Order Update',
        messageBody,
        fcmToken,
        orderId: orderId,
        orderStatus: newStatus,
        senderRole: 'rider',
        messageType: 'status_update',
        customerId: customerId,
        restaurantId: driverId,
        tokenSource: tokenSource,
      );

      return true;
    } catch (e) {
      // Log error but don't throw - FCM failures shouldn't block status updates
      debugPrint('Error sending status update FCM notification: $e');
      return false;
    }
  }

  static Future<bool> _guardRemittanceStatus(
    BuildContext context,
    String userId,
  ) async {
    try {
      final blocked = await RemittanceEnforcementService.evaluateIsBlocked(
        _firestore,
        userId,
      );
      if (blocked) {
        _showRemittanceRequiredDialog(context);
        return false;
      }
      return true;
    } catch (_) {
      _showRemittanceRequiredDialog(context);
      return false;
    }
  }

  static void _showRemittanceRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily Remittance Required'),
        content: const SelectableText.rich(
          TextSpan(
            text:
                'Daily remittance required. Please remit your credit wallet '
                'before accepting orders.',
            style: TextStyle(color: Colors.black87),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _guardAttendanceStatus(
    BuildContext context,
    String userId,
  ) async {
    final latestUser = await AttendanceService.fetchLatestUser(userId);
    if (latestUser == null) return true;

    if (latestUser.suspended == true) {
      _showSuspendedDialog(context);
      return false;
    }

    final status =
        await AttendanceService.evaluateAndUpdateAttendance(latestUser);
    if (status.isSuspended) {
      _showSuspendedDialog(context);
      return false;
    }
    if (status.showWarning) {
      _showWarningDialog(context);
    }

    await AttendanceService.touchLastActiveDate(latestUser);
    return true;
  }

  static void _showSuspendedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account Suspended'),
        content: SelectableText.rich(
          TextSpan(
            text:
                'Your account is suspended due to two consecutive days of '
                'absence. Please contact the administrator to restore '
                'access.',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void _showWarningDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attendance Warning'),
        content: SelectableText.rich(
          TextSpan(
            text:
                'You have been absent for one full day. Another day of '
                'absence will result in automatic suspension.',
            style: const TextStyle(color: Colors.orange),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
