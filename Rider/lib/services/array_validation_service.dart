import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/services/order_service.dart';

const _doneStatuses = [
  'Order Completed',
  'Order Cancelled',
  'Order Rejected',
];

class ArrayValidationService {
  static final _fs = FirebaseFirestore.instance;

  /// Validates the rider's `inProgressOrderID` array against
  /// actual order statuses. Removes entries whose order is
  /// completed, cancelled, rejected, or no longer exists.
  /// Then recalculates rider availability via
  /// [OrderService.updateRiderStatus].
  static Future<void> validate(String riderId) async {
    try {
      final riderDoc =
          await _fs.collection('users').doc(riderId).get();
      if (!riderDoc.exists) return;

      final orders =
          riderDoc.data()?['inProgressOrderID'] as List? ??
              [];
      if (orders.isEmpty) return;

      developer.log(
        'Checking ${orders.length} orders',
        name: 'ArrayValidation',
      );

      final List<String> toRemove = [];

      for (final raw in orders) {
        final orderId = raw.toString();
        final orderDoc = await _fs
            .collection('restaurant_orders')
            .doc(orderId)
            .get();

        if (!orderDoc.exists) {
          toRemove.add(orderId);
          continue;
        }

        final status =
            (orderDoc.data()?['status'] ?? '').toString();
        if (_doneStatuses.contains(status)) {
          toRemove.add(orderId);
        }
      }

      if (toRemove.isEmpty) return;

      developer.log(
        'Removing ${toRemove.length} stuck orders: '
        '$toRemove',
        name: 'ArrayValidation',
      );

      await _fs.collection('users').doc(riderId).update({
        'inProgressOrderID':
            FieldValue.arrayRemove(toRemove),
      });

      final updatedDoc =
          await _fs.collection('users').doc(riderId).get();
      final remaining = updatedDoc
              .data()?['inProgressOrderID'] as List? ??
          [];

      if (remaining.isEmpty) {
        final data = updatedDoc.data();
        final online = data?['isOnline'] == true;
        final onBreak = (data?['riderAvailability'] ?? '') == 'on_break';
        final isAvailable = online && !onBreak;
        await _fs
            .collection('users')
            .doc(riderId)
            .update({
          'riderAvailability': isAvailable ? 'available' : 'offline',
          'riderDisplayStatus':
              isAvailable ? '\u{1F7E2} Available' : '\u{26AA} Offline',
          'isActive': isAvailable,
        });
      }

      await OrderService.updateRiderStatus();

      developer.log(
        'Cleanup done. Remaining: ${remaining.length}',
        name: 'ArrayValidation',
      );
    } catch (e) {
      developer.log(
        'Error: $e',
        name: 'ArrayValidation',
        error: e,
      );
    }
  }
}
