import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:http/http.dart' as http;

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
    // #region agent log
    log('[DispatchPrecheck] entry customerId=$customerId vendorId=$vendorId',
        name: 'precheck');
    try {
      await http.post(
        Uri.parse(
            'http://127.0.0.1:7245/ingest/5f1a6d32-5b64-4784-b085-ee17060b4d34'),
        headers: {'Content-Type': 'application/json'},
        body: '{"location":"dispatch_precheck_service.dart:runPrecheck:entry","message":"precheck started","data":{"customerId":"$customerId","vendorId":"$vendorId"},"timestamp":${DateTime.now().millisecondsSinceEpoch},"hypothesisId":"A"}',
      ).catchError((_) => null);
    } catch (_) {}
    // #endregion

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
    final isOverloaded = activeOrders >= (activeRiders * _maxOrdersPerRider);

    // #region agent log
    log(
        '[DispatchPrecheck] after query activeOrders=$activeOrders '
        'rawRiderCount=${riders.length} activeRiders=$activeRiders '
        'isOverloaded=$isOverloaded',
        name: 'precheck');
    try {
      await http.post(
        Uri.parse(
            'http://127.0.0.1:7245/ingest/5f1a6d32-5b64-4784-b085-ee17060b4d34'),
        headers: {'Content-Type': 'application/json'},
        body:
            '{"location":"dispatch_precheck_service.dart:after query","message":"counts and overload","data":{"activeOrders":$activeOrders,"rawRiderCount":${riders.length},"activeRiders":$activeRiders,"isOverloaded":$isOverloaded},"timestamp":${DateTime.now().millisecondsSinceEpoch},"hypothesisId":"A,B"}',
      ).catchError((_) => null);
    } catch (_) {}
    // #endregion

    if (isOverloaded) {
      // #region agent log
      log('[DispatchPrecheck] BLOCKED overload', name: 'precheck');
      try {
        await http.post(
          Uri.parse(
              'http://127.0.0.1:7245/ingest/5f1a6d32-5b64-4784-b085-ee17060b4d34'),
          headers: {'Content-Type': 'application/json'},
          body:
              '{"location":"dispatch_precheck_service.dart:blocked","message":"blocked overload","data":{"blockedEventType":"$_eventCheckoutBlockedOverload"},"timestamp":${DateTime.now().millisecondsSinceEpoch},"hypothesisId":"B"}',
        ).catchError((_) => null);
      } catch (_) {}
      // #endregion
      await _tryLogEvent(
        eventType: _eventCheckoutBlockedOverload,
        customerId: customerId,
        vendorId: vendorId,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
      return DispatchPrecheckResult(
        canCheckout: false,
        blockedMessage:
            'Our delivery team is at full capacity at the moment. '
            'Please try again in a few minutes.',
        blockedEventType: _eventCheckoutBlockedOverload,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
    }

    // No orders today: allow checkout; no competition for riders.
    if (activeOrders == 0) {
      // #region agent log
      log('[DispatchPrecheck] ALLOW checkout (0 orders today)', name: 'precheck');
      try {
        await http.post(
          Uri.parse(
              'http://127.0.0.1:7245/ingest/5f1a6d32-5b64-4784-b085-ee17060b4d34'),
          headers: {'Content-Type': 'application/json'},
          body:
              '{"location":"dispatch_precheck_service.dart:allow 0 orders","message":"allowing checkout (0 orders today)","data":{"activeOrders":0},"timestamp":${DateTime.now().millisecondsSinceEpoch},"hypothesisId":"E"}',
        ).catchError((_) => null);
      } catch (_) {}
      // #endregion
      return DispatchPrecheckResult(
        canCheckout: true,
        blockedMessage: null,
        blockedEventType: null,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
    }

    // Not overloaded: allow checkout. Only block when activeOrders > activeRiders * _maxOrdersPerRider.
    // Per-rider assignment is handled by dispatch; we do not block for "no capacity" here.
    // #region agent log
    log(
        '[DispatchPrecheck] ALLOW checkout (not overloaded) '
        'activeOrders=$activeOrders activeRiders=$activeRiders',
        name: 'precheck');
    try {
      await http.post(
        Uri.parse(
            'http://127.0.0.1:7245/ingest/5f1a6d32-5b64-4784-b085-ee17060b4d34'),
        headers: {'Content-Type': 'application/json'},
        body:
            '{"location":"dispatch_precheck_service.dart:allow","message":"not overloaded","data":{"activeOrders":$activeOrders,"activeRiders":$activeRiders},"timestamp":${DateTime.now().millisecondsSinceEpoch}}',
      ).catchError((_) => null);
    } catch (_) {}
    // #endregion
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
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final endOfToday = startOfToday.add(const Duration(days: 1));
      final startTs = Timestamp.fromDate(startOfToday);
      final endTs = Timestamp.fromDate(endOfToday);

      final snap = await _firestore
          .collection(ORDERS)
          .where('status', whereIn: _activeOrderStatuses)
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .where('createdAt', isLessThan: endTs)
          .orderBy('createdAt')
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

