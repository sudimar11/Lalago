import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Tracks driver responses to order assignments.
/// Monitors acceptance, rejection, and timeout. Logs outcomes to
/// both assignments_log and dispatch_events.
class DriverResponseTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, Timer> _timeoutTimers = {};

  /// Set up listener to track driver response (accept/reject).
  /// Also starts a 65-second client-side timeout fallback.
  StreamSubscription<DocumentSnapshot> setupDriverResponseListener({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
    required Set<String> trackedOrders,
    required void Function(String orderId) onListenerComplete,
    required String Function(dynamic statusRaw) statusToText,
  }) {
    if (trackedOrders.contains(orderId)) {
      print('[Driver Response] Already tracking order $orderId');
      return Stream<DocumentSnapshot>.empty().listen((_) {});
    }

    trackedOrders.add(orderId);
    final assignedAt = DateTime.now();
    print(
        '[Driver Response] Setting up listener for order '
        '$orderId (driver: $driverId)');

    // Phase 1B: Start 65-second client-side timeout fallback
    _timeoutTimers[orderId]?.cancel();
    _timeoutTimers[orderId] = Timer(
      const Duration(seconds: 65),
      () => _checkTimeout(
        orderId: orderId,
        driverId: driverId,
        assignmentLogId: assignmentLogId,
        onComplete: onListenerComplete,
        statusToText: statusToText,
      ),
    );

    final listener = _firestore
        .collection('restaurant_orders')
        .doc(orderId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      final statusRaw = data['status'];
      final status = statusToText(statusRaw);
      final currentDriverId = (data['driverID'] ??
              data['driverId'] ??
              data['driver_id'] ??
              '') as String? ??
          '';

      if (currentDriverId != driverId) return;

      if (_isDriverAccepted(status)) {
        _timeoutTimers[orderId]?.cancel();
        await _handleDriverAcceptance(
          orderId: orderId,
          driverId: driverId,
          assignmentLogId: assignmentLogId,
          assignedAt: assignedAt,
          onComplete: onListenerComplete,
        );
      } else if (_isDriverRejected(status)) {
        _timeoutTimers[orderId]?.cancel();
        final rejectionReason =
            data['driverRejectionReason'] as String?;
        await _handleDriverRejection(
          orderId: orderId,
          driverId: driverId,
          assignmentLogId: assignmentLogId,
          assignedAt: assignedAt,
          rejectionReason: rejectionReason,
          onComplete: onListenerComplete,
        );
      }
    });

    return listener;
  }

  bool _isDriverAccepted(String status) {
    return status == 'Driver Accepted' ||
        status == 'driver accepted' ||
        status == 'Order Shipped' ||
        status == 'order shipped';
  }

  bool _isDriverRejected(String status) {
    return status == 'Driver Rejected' ||
        status == 'driver rejected' ||
        status == 'Order Rejected' ||
        status == 'order rejected';
  }

  /// Phase 1B: Client-side fallback timeout check.
  Future<void> _checkTimeout({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
    required void Function(String orderId) onComplete,
    required String Function(dynamic statusRaw) statusToText,
  }) async {
    try {
      final snap = await _firestore
          .collection('restaurant_orders')
          .doc(orderId)
          .get();
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final status = statusToText(data['status']);
      if (status != 'Driver Assigned') return;

      print('[TIMER] Client timeout for order $orderId - '
          'invoking releaseOrderDueToTimeout');

      await _firestore
          .collection('assignments_log')
          .doc(assignmentLogId)
          .update({
        'status': 'timeout',
        'timedOutAt': FieldValue.serverTimestamp(),
      });

      await _logOutcome(
        orderId: orderId,
        driverId: driverId,
        wasAccepted: false,
        responseTimeSeconds: 65,
        reason: 'client_timeout',
      );

      try {
        final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('releaseOrderDueToTimeout')
            .call({'orderId': orderId});
        if ((result.data as Map<dynamic, dynamic>?)?['success'] == true) {
          print('[Driver Response] Order $orderId released for redispatch');
        }
      } catch (e) {
        print('[Driver Response] releaseOrderDueToTimeout failed: $e');
      }

      onComplete(orderId);
    } catch (e) {
      print('[Driver Response] Timeout check error: $e');
    }
  }

  Future<void> _handleDriverAcceptance({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
    required DateTime assignedAt,
    required void Function(String orderId) onComplete,
  }) async {
    print('[Driver Response] Driver $driverId ACCEPTED '
        'order $orderId');
    try {
      final responseSeconds =
          DateTime.now().difference(assignedAt).inSeconds;

      await _firestore
          .collection('assignments_log')
          .doc(assignmentLogId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'responseTimeSeconds': responseSeconds,
      });

      await _logOutcome(
        orderId: orderId,
        driverId: driverId,
        wasAccepted: true,
        responseTimeSeconds: responseSeconds,
      );

      onComplete(orderId);
    } catch (e) {
      print('[Driver Response] Error: $e');
    }
  }

  Future<void> _handleDriverRejection({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
    required DateTime assignedAt,
    String? rejectionReason,
    required void Function(String orderId) onComplete,
  }) async {
    print('[Driver Response] Driver $driverId REJECTED '
        'order $orderId');
    try {
      final responseSeconds =
          DateTime.now().difference(assignedAt).inSeconds;

      final updateData = <String, dynamic>{
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'responseTimeSeconds': responseSeconds,
      };
      if (rejectionReason != null && rejectionReason.isNotEmpty) {
        updateData['rejectionReason'] = rejectionReason;
      }

      await _firestore
          .collection('assignments_log')
          .doc(assignmentLogId)
          .update(updateData);

      await _logOutcome(
        orderId: orderId,
        driverId: driverId,
        wasAccepted: false,
        responseTimeSeconds: responseSeconds,
      );

      onComplete(orderId);
    } catch (e) {
      print('[Driver Response] Error: $e');
    }
  }

  /// Phase 1D: Log outcome to dispatch_events so the
  /// original dispatch record gets an outcome update.
  Future<void> _logOutcome({
    required String orderId,
    required String driverId,
    required bool wasAccepted,
    required int responseTimeSeconds,
    String? reason,
  }) async {
    try {
      final eventsQuery = await _firestore
          .collection('dispatch_events')
          .where('orderId', isEqualTo: orderId)
          .where('riderId', isEqualTo: driverId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (eventsQuery.docs.isNotEmpty) {
        await eventsQuery.docs.first.reference.update({
          'outcome': {
            'wasAccepted': wasAccepted,
            'responseTimeSeconds': responseTimeSeconds,
            'respondedAt': FieldValue.serverTimestamp(),
            if (reason != null) 'reason': reason,
          },
        });
      }
    } catch (e) {
      print('[Driver Response] Failed to log outcome: $e');
    }
  }
}
