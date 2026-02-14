import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';

class DispatchPrecheckResult {
  final bool canCheckout;
  final String? blockedMessage;
  final String? blockedEventType;
  final int activeOrders;
  final int activeRiders;

  const DispatchPrecheckResult({
    required this.canCheckout,
    required this.blockedMessage,
    required this.blockedEventType,
    required this.activeOrders,
    required this.activeRiders,
  });
}

class DispatchPrecheckService {
  static const int _maxOrdersPerRider = 2;

  static const String _eventCheckoutBlockedOverload =
      'checkout_blocked_overload';
  static const String _eventCheckoutBlockedNoCapacity =
      'checkout_blocked_no_capacity';

  static const List<String> _activeOrderStatuses = <String>[
    // Rider-first hidden stage (server writes this).
    'Awaiting Rider',
    // Usual active stages.
    ORDER_STATUS_PLACED,
    'Driver Assigned',
    ORDER_STATUS_DRIVER_PENDING,
    'Driver Accepted',
    ORDER_STATUS_ACCEPTED,
    ORDER_STATUS_SHIPPED,
    ORDER_STATUS_IN_TRANSIT,
  ];

  final FirebaseFirestore _firestore;

  DispatchPrecheckService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<DispatchPrecheckResult> runPrecheck({
    required String customerId,
    required String vendorId,
  }) async {
    final activeOrders = await _countActiveOrders();
    final ridersSnapshot = await _firestore
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER)
        .where('isOnline', isEqualTo: true)
        .where('checkedInToday', isEqualTo: true)
        .get();

    final riders = ridersSnapshot.docs.map((d) => d.data()).toList();

    final filteredRiders = riders.where((r) {
      final isSuspended = r['suspended'] == true ||
          (r['attendanceStatus']?.toString().toLowerCase() == 'suspended');
      if (isSuspended) return false;

      final isCheckedOutToday = r['checkedOutToday'] == true ||
          (r['todayCheckOutTime'] != null &&
              r['todayCheckOutTime'].toString().isNotEmpty);
      if (isCheckedOutToday) return false;

      return true;
    }).toList();

    final activeRiders = filteredRiders.length;
    final isOverloaded = activeOrders > (activeRiders * _maxOrdersPerRider);

    if (isOverloaded) {
      await _tryLogEvent(
        eventType: _eventCheckoutBlockedOverload,
        customerId: customerId,
        vendorId: vendorId,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
      return DispatchPrecheckResult(
        canCheckout: false,
        blockedMessage: 'All riders are currently busy.',
        blockedEventType: _eventCheckoutBlockedOverload,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
    }

    final hasAnyCapacity = filteredRiders.any((r) {
      final activeOrders = _getActiveOrdersCount(r);
      if (activeOrders == 0) return true;
      if (activeOrders == 1) {
        return r['multipleOrders'] == true;
      }
      return false;
    });

    if (!hasAnyCapacity) {
      await _tryLogEvent(
        eventType: _eventCheckoutBlockedNoCapacity,
        customerId: customerId,
        vendorId: vendorId,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
      return DispatchPrecheckResult(
        canCheckout: false,
        blockedMessage: 'High demand in your area.',
        blockedEventType: _eventCheckoutBlockedNoCapacity,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
    }

    return DispatchPrecheckResult(
      canCheckout: true,
      blockedMessage: null,
      blockedEventType: null,
      activeOrders: activeOrders,
      activeRiders: activeRiders,
    );
  }

  Future<int> _countActiveOrders() async {
    try {
      final snap = await _firestore
          .collection(ORDERS)
          .where('status', whereIn: _activeOrderStatuses)
          .get();
      return snap.size;
    } catch (e) {
      log('[DispatchPrecheck] Failed to count active orders: $e');
      return 0;
    }
  }

  int _getActiveOrdersCount(Map<String, dynamic> rider) {
    final v = rider['inProgressOrderID'];
    if (v is List) return v.length;
    return 0;
  }

  Future<void> _tryLogEvent({
    required String eventType,
    required String customerId,
    required String vendorId,
    required int activeOrders,
    required int activeRiders,
  }) async {
    try {
      await _firestore.collection('dispatch_events').add({
        'type': eventType,
        'customerId': customerId,
        'vendorId': vendorId,
        'activeOrders': activeOrders,
        'activeRiders': activeRiders,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'customer_checkout',
      });
    } catch (e) {
      // Best effort: do not block checkout UI on metric logging failures.
      log('[DispatchPrecheck] Failed to log event $eventType: $e');
    }
  }
}

