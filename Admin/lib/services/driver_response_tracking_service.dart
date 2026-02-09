import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service responsible for tracking driver responses to order assignments
/// Monitors driver acceptance or rejection and updates assignment logs
class DriverResponseTrackingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Set up listener to track driver response (accept/reject)
  /// Returns the StreamSubscription for the listener
  StreamSubscription<DocumentSnapshot> setupDriverResponseListener({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
    required Set<String> trackedOrders,
    required void Function(String orderId) onListenerComplete,
    required String Function(dynamic statusRaw) statusToText,
  }) {
    // Check if we're already tracking this order
    if (trackedOrders.contains(orderId)) {
      print('[Driver Response] Already tracking order $orderId');
      // Return a dummy subscription that does nothing
      return Stream<DocumentSnapshot>.empty().listen((_) {});
    }

    trackedOrders.add(orderId);
    print(
        '[Driver Response] Setting up listener for order $orderId (driver: $driverId)');

    // Set up listener to monitor order status changes
    final listener = _firestore
        .collection('restaurant_orders')
        .doc(orderId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        print('[Driver Response] Order $orderId no longer exists');
        return;
      }

      final data = snapshot.data();
      if (data == null) return;

      final statusRaw = data['status'];
      final status = statusToText(statusRaw);
      final currentDriverId = (data['driverID'] ??
              data['driverId'] ??
              data['driver_id'] ??
              '') as String? ??
          '';

      // Only track responses from the assigned driver
      if (currentDriverId != driverId) {
        return;
      }

      print('[Driver Response] Order $orderId status: $status');

      // Check for driver acceptance
      if (_isDriverAccepted(status)) {
        await _handleDriverAcceptance(
          orderId: orderId,
          driverId: driverId,
          assignmentLogId: assignmentLogId,
          onComplete: onListenerComplete,
        );
      }
      // Check for driver rejection
      else if (_isDriverRejected(status)) {
        await _handleDriverRejection(
          orderId: orderId,
          driverId: driverId,
          assignmentLogId: assignmentLogId,
          onComplete: onListenerComplete,
        );
      }
    });

    print('[Driver Response] Listener active for order $orderId');
    return listener;
  }

  /// Check if status indicates driver acceptance
  bool _isDriverAccepted(String status) {
    return status == 'Driver Accepted' ||
        status == 'driver accepted' ||
        status == 'Order Shipped' ||
        status == 'order shipped';
  }

  /// Check if status indicates driver rejection
  bool _isDriverRejected(String status) {
    return status == 'Driver Rejected' ||
        status == 'driver rejected' ||
        status == 'Order Rejected' ||
        status == 'order rejected';
  }

  /// Handle driver acceptance
  Future<void> _handleDriverAcceptance({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
    required void Function(String orderId) onComplete,
  }) async {
    print('[Driver Response] ✅ Driver $driverId ACCEPTED order $orderId');

    // Update assignment log with acceptance
    try {
      await _firestore
          .collection('assignments_log')
          .doc(assignmentLogId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'responseTime':
            FieldValue.serverTimestamp(), // Time when driver responded
      });

      print('[Driver Response] Updated assignment log with ACCEPTANCE');

      // Notify to cancel and complete tracking
      onComplete(orderId);
    } catch (e) {
      print('[Driver Response] Error updating assignment log: $e');
    }
  }

  /// Handle driver rejection
  Future<void> _handleDriverRejection({
    required String orderId,
    required String driverId,
    required String assignmentLogId,
    required void Function(String orderId) onComplete,
  }) async {
    print('[Driver Response] ❌ Driver $driverId REJECTED order $orderId');

    // Update assignment log with rejection
    try {
      await _firestore
          .collection('assignments_log')
          .doc(assignmentLogId)
          .update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'responseTime':
            FieldValue.serverTimestamp(), // Time when driver responded
      });

      print('[Driver Response] Updated assignment log with REJECTION');

      // Notify to cancel and complete tracking
      onComplete(orderId);
    } catch (e) {
      print('[Driver Response] Error updating assignment log: $e');
    }
  }
}
