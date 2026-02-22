import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/main.dart';
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

      // Dynamic capacity check
      final effectiveCap = await _getEffectiveCapacity(
        driverData: driverData ?? {},
        multipleOrders: multipleOrders,
      );

      final activeOrderCheck = await _firestore
          .collection('restaurant_orders')
          .where('driverID', isEqualTo: currentUserId)
          .where('status', whereIn: [
            'Driver Pending',
            'Driver Accepted',
            'Order Shipped',
            'In Transit',
          ])
          .get();

      if (activeOrderCheck.docs.length >= effectiveCap) {
        await DialogUtils.showAlertDialog(
          context,
          title: "Active Order Exists",
          content: effectiveCap <= 1
              ? "You already have an ongoing order. Please complete or deliver it before accepting a new one."
              : "You already have ${activeOrderCheck.docs.length} active order(s) (limit: $effectiveCap). Complete one first.",
        );
        return false;
      }

      // Get order data for system message
      final orderDoc = await _firestore.collection('restaurant_orders').doc(orderId).get();
      final orderData = orderDoc.data();
      final author = orderData?['author'] as Map<String, dynamic>? ?? {};
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;

      // Assign the order
      await _firestore.collection('restaurant_orders').doc(orderId).update({
        'status': 'Driver Accepted',
        'driverId': currentUserId,
        'driverID': currentUserId,
        'driverName': '${driverData?['firstName']} ${driverData?['lastName']}',
        'driverLocation': {
          'latitude': driverLocation['latitude'],
          'longitude': driverLocation['longitude'],
        },
      });

      // Keep driver document consistent with current request/active lists.
      // This is safe even if the fields don't exist yet.
      await _firestore.collection('users').doc(currentUserId).set(
        {
          'orderRequestData': FieldValue.arrayRemove([orderId]),
          'inProgressOrderID': FieldValue.arrayUnion([orderId]),
        },
        SetOptions(merge: true),
      );

      await updateRiderStatus();

      // Send system message
      if (customerId != null) {
        await OrderChatService.sendSystemMessage(
          orderId: orderId,
          status: 'Driver Accepted',
          customerId: customerId.toString(),
          customerFcmToken: customerFcmToken,
          restaurantId: currentUserId,
        );
      }

      DialogUtils.showSnackBar(
        context,
        message: 'Order accepted successfully!',
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

  /// Accept all orders in a batch atomically.
  /// Guards run once; all orders are updated in a WriteBatch.
  static Future<bool> acceptBatch(
    List<Map<String, dynamic>> orders,
    List<String> orderIds,
    BuildContext context,
  ) async {
    try {
      final currentUserId = _auth.currentUser?.uid ?? '';
      if (currentUserId.isEmpty) {
        throw Exception('No user is logged in.');
      }

      final canProceed =
          await _guardAttendanceStatus(context, currentUserId);
      if (!canProceed) return false;

      final remittanceOk =
          await _guardRemittanceStatus(context, currentUserId);
      if (!remittanceOk) return false;

      final driverSnapshot = await _firestore
          .collection('users')
          .doc(currentUserId)
          .get();
      if (!driverSnapshot.exists) {
        throw Exception('Driver not found');
      }

      final driverData = driverSnapshot.data();
      final driverLocation = driverData?['location'] ?? {};
      if (driverLocation.isEmpty) {
        throw Exception('Driver location not available');
      }

      final wb = _firestore.batch();

      for (final orderId in orderIds) {
        final ref = _firestore
            .collection('restaurant_orders')
            .doc(orderId);
        wb.update(ref, {
          'status': 'Driver Accepted',
          'driverId': currentUserId,
          'driverID': currentUserId,
          'driverName':
              '${driverData?['firstName']} ${driverData?['lastName']}',
          'driverLocation': {
            'latitude': driverLocation['latitude'],
            'longitude': driverLocation['longitude'],
          },
        });
      }

      final driverRef =
          _firestore.collection('users').doc(currentUserId);
      wb.set(
        driverRef,
        {
          'orderRequestData':
              FieldValue.arrayRemove(orderIds),
          'inProgressOrderID':
              FieldValue.arrayUnion(orderIds),
        },
        SetOptions(merge: true),
      );

      await wb.commit();

      await updateRiderStatus();

      // Update batch doc status
      if (orders.isNotEmpty) {
        final batchId =
            orders.first['batch']?['batchId'] as String?;
        if (batchId != null) {
          await _firestore
              .collection('order_batches')
              .doc(batchId)
              .update({'status': 'accepted'});
        }
      }

      // Send system messages for each order
      for (int i = 0; i < orders.length; i++) {
        final author = orders[i]['author']
            as Map<String, dynamic>? ?? {};
        final customerId =
            author['id'] ?? author['customerID'];
        final token = author['fcmToken'] as String?;
        if (customerId != null) {
          await OrderChatService.sendSystemMessage(
            orderId: orderIds[i],
            status: 'Driver Accepted',
            customerId: customerId.toString(),
            customerFcmToken: token,
            restaurantId: currentUserId,
          );
        }
      }

      DialogUtils.showSnackBar(
        context,
        message:
            'Batch accepted (${orderIds.length} orders)!',
        backgroundColor: Colors.green,
      );
      return true;
    } catch (e) {
      DialogUtils.showSnackBar(
        context,
        message: 'Failed to accept batch: $e',
        backgroundColor: Colors.red,
      );
      return false;
    }
  }

  /// Reject all orders in a batch. Performance penalty is
  /// applied once, not per order.
  static Future<bool> rejectBatch(
    List<Map<String, dynamic>> orders,
    List<String> orderIds,
    BuildContext context,
  ) async {
    try {
      final currentUserId = _auth.currentUser?.uid ?? '';

      final canProceed =
          await _guardAttendanceStatus(context, currentUserId);
      if (!canProceed) return false;

      final wb = _firestore.batch();
      for (final orderId in orderIds) {
        final ref = _firestore
            .collection('restaurant_orders')
            .doc(orderId);
        wb.update(ref, {'status': 'Driver Rejected'});
      }
      await wb.commit();

      // Update batch doc
      if (orders.isNotEmpty) {
        final batchId =
            orders.first['batch']?['batchId'] as String?;
        if (batchId != null) {
          await _firestore
              .collection('order_batches')
              .doc(batchId)
              .update({'status': 'cancelled'});
        }
      }

      if (currentUserId.isNotEmpty) {
        await DriverPerformanceService
            .applyCancellationPenalty(currentUserId);
      }

      // Send system messages
      for (int i = 0; i < orders.length; i++) {
        final author = orders[i]['author']
            as Map<String, dynamic>? ?? {};
        final customerId =
            author['id'] ?? author['customerID'];
        final token = author['fcmToken'] as String?;
        if (customerId != null) {
          await OrderChatService.sendSystemMessage(
            orderId: orderIds[i],
            status: 'Driver Rejected',
            customerId: customerId.toString(),
            customerFcmToken: token,
          );
        }
      }

      DialogUtils.showSnackBar(
        context,
        message:
            'Batch rejected (${orderIds.length} orders).',
        backgroundColor: Colors.green,
      );
      return true;
    } catch (e) {
      DialogUtils.showSnackBar(
        context,
        message: 'Failed to reject batch: $e',
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

  /// Compute and persist `riderAvailability` + `riderDisplayStatus`.
  /// Call after every action that changes the rider's logical state
  /// (accept, complete, check-in, check-out, break).
  static Future<void> updateRiderStatus({
    String? overrideAvailability,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final user = MyAppState.currentUser;
    if (user == null) return;

    String availability;
    String displayStatus;

    if (user.suspended == true ||
        (user.attendanceStatus?.toLowerCase() == 'suspended')) {
      availability = 'suspended';
      displayStatus = '🔴 Suspended';
    } else if (user.checkedOutToday == true) {
      availability = 'checked_out';
      displayStatus = '⚫ Checked Out';
    } else if (overrideAvailability == 'on_break') {
      availability = 'on_break';
      displayStatus = '⏸ On Break';
    } else if (user.checkedInToday != true ||
        user.isOnline != true) {
      availability = 'offline';
      displayStatus = '⚪ Offline';
    } else {
      final orders =
          user.inProgressOrderID as List? ?? [];
      final cap = await _getEffectiveCapacity(
        driverData: {
          'driver_performance': user.driverPerformance,
          'multipleOrders': user.multipleOrders,
        },
        multipleOrders: user.multipleOrders,
      );
      if (orders.isNotEmpty && orders.length >= cap) {
        availability = 'on_delivery';
        displayStatus = '🟡 On Delivery';
      } else if (orders.isNotEmpty) {
        availability = 'available';
        displayStatus = '🟡 On Delivery';
      } else {
        availability = 'available';
        displayStatus = '🟢 Available';
      }
    }

    user.riderAvailability = availability;
    user.riderDisplayStatus = displayStatus;

    await _firestore.collection('users').doc(uid).update({
      'riderAvailability': availability,
      'riderDisplayStatus': displayStatus,
    });
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

    final isSuspended = latestUser.suspended == true ||
        (latestUser.attendanceStatus?.toLowerCase() == 'suspended');
    if (isSuspended) {
      _showSuspendedDialog(context);
      return false;
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
                'Your account is currently suspended. Please contact the '
                'administrator to restore access.',
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

  /// Compute effective order capacity for the current rider using
  /// the dynamic capacity config from Firestore.
  static Future<int> _getEffectiveCapacity({
    required Map<String, dynamic> driverData,
    required bool multipleOrders,
  }) async {
    if (!multipleOrders) return 1;
    try {
      final configDoc = await _firestore
          .collection('config')
          .doc('dispatch_weights')
          .get();
      final m = configDoc.data() ?? {};
      final enabled = m['dynamicCapacityEnabled'] as bool? ?? true;
      if (!enabled) {
        return (m['maxActiveOrdersPerRider'] as num?)?.toInt() ?? 2;
      }

      final baseCapacity =
          (m['baseCapacity'] as num?)?.toInt() ?? 2;
      final peakReduction =
          (m['peakCapacityReduction'] as num?)?.toInt() ?? 1;
      final boostThreshold =
          (m['performanceBoostThreshold'] as num?)?.toDouble() ?? 90;
      final penaltyThreshold =
          (m['performancePenaltyThreshold'] as num?)?.toDouble() ?? 65;
      final weather =
          m['weatherCondition'] as String? ?? 'normal';

      final peakStart = (m['peakHourStart'] as num?)?.toInt() ?? 11;
      final peakEnd = (m['peakHourEnd'] as num?)?.toInt() ?? 14;
      final peakStart2 =
          (m['peakHourStart2'] as num?)?.toInt() ?? 17;
      final peakEnd2 = (m['peakHourEnd2'] as num?)?.toInt() ?? 21;
      final hour = DateTime.now().hour;
      final isPeak = (hour >= peakStart && hour < peakEnd) ||
          (hour >= peakStart2 && hour < peakEnd2);

      int cap = baseCapacity;
      if (isPeak) cap -= peakReduction;

      final perf =
          (driverData['driver_performance'] as num?)?.toDouble() ?? 0;
      if (perf >= boostThreshold) {
        cap += 1;
      } else if (perf < penaltyThreshold) {
        cap -= 1;
      }

      if (weather == 'rain') {
        cap -= 1;
      } else if (weather == 'storm') {
        cap -= 2;
      }

      return cap.clamp(1, 4);
    } catch (_) {
      return 2;
    }
  }
}
