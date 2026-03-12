import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/utils/dialog_utils.dart';
import 'package:foodie_driver/services/audio_service.dart';
import 'package:foodie_driver/services/driver_performance_service.dart';
import 'package:foodie_driver/services/order_chat_service.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/attendance_service.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';
import 'package:foodie_driver/widgets/rejection_reason_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

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
      final bool riderOnline = driverData?['isOnline'] == true;
      final String availability =
          (driverData?['riderAvailability'] ?? 'offline')
              .toString();
      if (!riderOnline ||
          availability == 'offline' ||
          availability == 'on_break') {
        await DialogUtils.showAlertDialog(
          context,
          title: 'Go Online Required',
          content: 'Please go online to accept orders.',
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
      await FireStoreUtils.touchLastActivity(currentUserId);

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

      AudioService.instance.markOrderAsNotified(orderId);
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
  /// [orderId] - The order document ID
  /// [context] - BuildContext for guards and snackbars
  /// [reason] - Optional rejection reason code (e.g. too_far, restaurant_closed)
  /// [orderData] - Optional order data; if null, fetched from Firestore
  /// [evidence] - Optional evidence URL (e.g. photo for restaurant_closed)
  ///
  /// Returns true if order was rejected successfully, false otherwise
  static Future<bool> rejectOrder(
    String orderId,
    BuildContext context, {
    String? reason,
    Map<String, dynamic>? orderData,
    String? evidence,
  }) async {
    try {
      final currentUserId = _auth.currentUser?.uid ?? '';

      final canProceed =
          await _guardAttendanceStatus(context, currentUserId);
      if (!canProceed) return false;

      final orderRef = _firestore.collection('restaurant_orders').doc(orderId);
      final orderDoc = await orderRef.get();
      final fetchedData = orderDoc.data();
      final data = orderData ?? fetchedData;
      final author = data?['author'] as Map<String, dynamic>? ?? {};
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;

      final rejectedBy = List<String>.from(
        (fetchedData?['rejectedByDrivers'] as List<dynamic>?) ?? [],
      );
      if (currentUserId.isNotEmpty && !rejectedBy.contains(currentUserId)) {
        rejectedBy.add(currentUserId);
      }

      final updateData = <String, dynamic>{
        'status': 'Driver Rejected',
        'rejectedByDrivers': rejectedBy,
        'rejectedAt': FieldValue.serverTimestamp(),
        'dispatch.rejectionCount': FieldValue.increment(1),
      };
      if (reason != null) {
        updateData['driverRejectionReason'] = reason;
      }
      if (evidence != null) {
        updateData['driverRejectionEvidence'] = evidence;
      }
      await orderRef.update(updateData);

      if (currentUserId.isNotEmpty) {
        await _firestore.collection('users').doc(currentUserId).set(
          {'orderRequestData': FieldValue.arrayRemove([orderId])},
          SetOptions(merge: true),
        );
        await DriverPerformanceService.applyCancellationPenalty(currentUserId);
      }

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

  /// Upload photo for restaurant_closed evidence.
  /// Returns download URL or null on failure.
  static Future<String?> uploadRestaurantClosedEvidence(
    File image,
    String orderId,
  ) async {
    try {
      final compressed = await FireStoreUtils.compressImage(image);
      final fileName = '${const Uuid().v4()}.jpg';
      final ref = FireStoreUtils.storage
          .child('restaurant_closed_evidence/$orderId/$fileName');
      final task = ref.putFile(compressed);
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  /// Shows rejection dialog, handles restaurant_closed with photo, then rejects.
  /// Returns true if rejection completed, false if cancelled.
  static Future<bool> rejectOrderWithReason(
    BuildContext context,
    String orderId, {
    Map<String, dynamic>? orderData,
    String? preselectedReason,
  }) async {
    final reason =
        preselectedReason ?? await showRejectionReasonDialog(context);
    if (reason == null || reason.isEmpty) return false;

    if (reason == 'restaurant_closed') {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: ImageSource.camera);
      if (xFile == null || !context.mounted) return false;

      final imageUrl = await uploadRestaurantClosedEvidence(
        File(xFile.path),
        orderId,
      );
      if (imageUrl == null) {
        if (context.mounted) {
          DialogUtils.showSnackBar(
            context,
            message: 'Failed to upload photo',
            backgroundColor: Colors.red,
          );
        }
        return false;
      }
      return rejectOrder(
        orderId,
        context,
        reason: reason,
        orderData: orderData,
        evidence: imageUrl,
      );
    }

    return rejectOrder(
      orderId,
      context,
      reason: reason,
      orderData: orderData,
    );
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
      await FireStoreUtils.touchLastActivity(currentUserId);

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
      for (final orderId in orderIds) {
        AudioService.instance.markOrderAsNotified(orderId);
      }
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
    BuildContext context, {
    String? reason,
  }) async {
    try {
      final currentUserId = _auth.currentUser?.uid ?? '';

      final canProceed =
          await _guardAttendanceStatus(context, currentUserId);
      if (!canProceed) return false;

      final wb = _firestore.batch();
      final reasonCode = reason ?? 'batch';

      for (final orderId in orderIds) {
        final ref = _firestore.collection('restaurant_orders').doc(orderId);
        final doc = await ref.get();
        final data = doc.data();
        final rejectedBy = List<String>.from(
          (data?['rejectedByDrivers'] as List<dynamic>?) ?? [],
        );
        if (currentUserId.isNotEmpty && !rejectedBy.contains(currentUserId)) {
          rejectedBy.add(currentUserId);
        }
        final updateData = <String, dynamic>{
          'status': 'Driver Rejected',
          'rejectedByDrivers': rejectedBy,
          'driverRejectionReason': reasonCode,
          'rejectedAt': FieldValue.serverTimestamp(),
          'dispatch.rejectionCount': FieldValue.increment(1),
        };
        wb.update(ref, updateData);
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
        await _firestore.collection('users').doc(currentUserId).set(
          {
            'orderRequestData': FieldValue.arrayRemove(orderIds),
          },
          SetOptions(merge: true),
        );
        await DriverPerformanceService
            .applyCancellationPenalty(currentUserId);
      }

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

  /// Compute and persist canonical rider status.
  /// Invariant: isOnline=false always forces riderAvailability=offline.
  static Future<void> updateRiderStatus({
    String? overrideAvailability,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final user = MyAppState.currentUser;
    if (user == null) return;

    String availability;
    String displayStatus;

    if (overrideAvailability == 'on_break' &&
        user.isOnline == true) {
      availability = 'on_break';
      displayStatus = '⏸ On Break';
    } else if (user.isOnline != true) {
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

    final Map<String, dynamic> updateMap = {
      'riderAvailability': availability,
      'riderDisplayStatus': displayStatus,
    };

    final bool activeForDispatch = availability == 'available';
    user.isActive = activeForDispatch;
    updateMap['isActive'] = activeForDispatch;

    await _firestore.collection('users').doc(uid).update(updateMap);
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

  /// Removes [orderId] from the rider's inProgressOrderID array
  /// and updates availability. Logs the before/after state for
  /// debugging capacity calculations in the customer precheck.
  static Future<void> completeOrder(String orderId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      print('[ORDER_COMPLETE] No authenticated user');
      return;
    }

    print('[ORDER_COMPLETE] '
        '===== STARTING ORDER COMPLETION =====');
    print('[ORDER_COMPLETE] Rider: $uid');
    print('[ORDER_COMPLETE] Order: $orderId');
    print('[ORDER_COMPLETE] Time: ${DateTime.now()}');

    final beforeDoc = await _firestore
        .collection('users')
        .doc(uid)
        .get();
    final beforeData = beforeDoc.data();
    final beforeOrders =
        beforeData?['inProgressOrderID'] as List? ?? [];

    print('[ORDER_COMPLETE] BEFORE: $beforeOrders '
        '(${beforeOrders.length})');
    print('[ORDER_COMPLETE]   avail='
        '${beforeData?['riderAvailability']}, '
        'active=${beforeData?['isActive']}, '
        'checkedOut='
        '${beforeData?['checkedOutToday']}');

    // ── Retry loop with verification ──
    const maxRetries = 3;
    bool removed = !beforeOrders.contains(orderId);
    if (removed) {
      print('[ORDER_COMPLETE] Order already absent '
          'from array');
    }

    List afterOrders = List.from(beforeOrders);

    for (int attempt = 1;
        !removed && attempt <= maxRetries;
        attempt++) {
      print('[ORDER_COMPLETE] arrayRemove attempt '
          '#$attempt');
      await _firestore
          .collection('users')
          .doc(uid)
          .update({
        'inProgressOrderID':
            FieldValue.arrayRemove([orderId]),
      });

      await Future<void>.delayed(
        const Duration(milliseconds: 300),
      );

      final verifyDoc = await _firestore
          .collection('users')
          .doc(uid)
          .get();
      afterOrders = verifyDoc.data()?[
              'inProgressOrderID'] as List? ??
          [];

      if (!afterOrders.contains(orderId)) {
        removed = true;
        print('[ORDER_COMPLETE] Removed on attempt '
            '#$attempt');
      } else {
        print('[ORDER_COMPLETE] Still present after '
            'attempt #$attempt');
      }
    }

    // ── Fallback: overwrite the whole array ──
    if (!removed) {
      print('[ORDER_COMPLETE] FALLBACK: overwriting '
          'array without $orderId');
      final cleaned = beforeOrders
          .where((id) => id != orderId)
          .toList();
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'inProgressOrderID': cleaned});
      afterOrders = cleaned;
      print('[ORDER_COMPLETE] Array set to: $cleaned');
    }

    print('[ORDER_COMPLETE] AFTER: $afterOrders '
        '(${afterOrders.length})');

    // ── Sync in-memory model ──
    final user = MyAppState.currentUser;
    if (user != null) {
      user.inProgressOrderID =
          List<dynamic>.from(afterOrders);
      print('[ORDER_COMPLETE] In-memory synced');
    }

    // ── Cross-check restaurant_orders ──
    print('[ORDER_COMPLETE] Cross-checking orders...');
    final activeCheck = await _firestore
        .collection('restaurant_orders')
        .where('driverID', isEqualTo: uid)
        .where('status', whereIn: [
          'Driver Accepted',
          'Order Shipped',
          'In Transit',
        ])
        .get();
    print('[ORDER_COMPLETE] Active in system: '
        '${activeCheck.docs.length}');
    for (final doc in activeCheck.docs) {
      print('[ORDER_COMPLETE]   ${doc.id}: '
          '${doc.data()['status']}');
    }

    if (afterOrders.isEmpty &&
        activeCheck.docs.isNotEmpty) {
      final orphanIds =
          activeCheck.docs.map((d) => d.id).toList();
      print('[ORDER_COMPLETE] Re-adding orphans: '
          '$orphanIds');
      await _firestore
          .collection('users')
          .doc(uid)
          .update({
        'inProgressOrderID':
            FieldValue.arrayUnion(orphanIds),
      });
      if (user != null) {
        user.inProgressOrderID = orphanIds;
      }
    }

    await updateRiderStatus();
    await FireStoreUtils.touchLastActivity(uid);

    // ── Final state ──
    final statusDoc = await _firestore
        .collection('users')
        .doc(uid)
        .get();
    final f = statusDoc.data();
    print('[ORDER_COMPLETE] FINAL: '
        '${f?['inProgressOrderID']} '
        'avail=${f?['riderAvailability']} '
        'display=${f?['riderDisplayStatus']} '
        'active=${f?['isActive']}');
    print('[ORDER_COMPLETE] '
        '===== ORDER COMPLETION FINISHED =====');
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
