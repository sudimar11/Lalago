import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only service for viewing and managing order batches
/// from the Admin UI. Batch creation is handled server-side
/// by the orderBatchingCron Cloud Function.
class OrderBatchingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream active batches (pending or assigned).
  Stream<List<Map<String, dynamic>>> streamActiveBatches() {
    return _firestore
        .collection('order_batches')
        .where('status', whereIn: ['pending', 'assigned'])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  /// Get a single batch by ID.
  Future<Map<String, dynamic>?> getBatch(String batchId) async {
    final doc = await _firestore
        .collection('order_batches')
        .doc(batchId)
        .get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data()!};
  }

  /// Cancel a batch: set status to cancelled and remove batch
  /// fields from all member orders so they can be dispatched
  /// individually again.
  Future<void> cancelBatch(String batchId) async {
    final batchRef =
        _firestore.collection('order_batches').doc(batchId);
    final batchSnap = await batchRef.get();
    if (!batchSnap.exists) return;

    final data = batchSnap.data() ?? {};
    final orderIds =
        List<String>.from(data['orderIds'] ?? []);

    final batch = _firestore.batch();
    batch.update(batchRef, {'status': 'cancelled'});

    for (final orderId in orderIds) {
      final orderRef = _firestore
          .collection('restaurant_orders')
          .doc(orderId);
      batch.update(orderRef, {
        'batch': FieldValue.delete(),
      });
    }

    await batch.commit();
  }
}
