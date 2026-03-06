import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/SubstitutionRequestModel.dart';

const _substitutionRequests = 'substitution_requests';

class PautosSubstitutionService {
  static CollectionReference<Map<String, dynamic>> _subRef(String orderId) {
    return FirebaseFirestore.instance
        .collection(PAUTOS_ORDERS)
        .doc(orderId)
        .collection(_substitutionRequests);
  }

  static Stream<List<SubstitutionRequestModel>> getSubstitutionRequestsStream(
    String orderId,
  ) {
    return _subRef(orderId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SubstitutionRequestModel.fromJson(d.id, d.data()))
            .toList());
  }

  static Future<bool> approveSubstitutionRequest(
    String orderId,
    String requestId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    return _resolveRequest(orderId, requestId, 'approved', uid);
  }

  static Future<bool> rejectSubstitutionRequest(
    String orderId,
    String requestId,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    return _resolveRequest(orderId, requestId, 'rejected', uid);
  }

  static Future<bool> _resolveRequest(
    String orderId,
    String requestId,
    String newStatus,
    String resolvedBy,
  ) async {
    try {
      final orderRef = FirebaseFirestore.instance
          .collection(PAUTOS_ORDERS)
          .doc(orderId);
      final requestRef = _subRef(orderId).doc(requestId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final orderSnap = await tx.get(orderRef);
        if (!orderSnap.exists) throw StateError('Order not found');
        final orderData = orderSnap.data() ?? {};
        if ((orderData['authorID'] ?? '').toString() != resolvedBy) {
          throw StateError('Only customer can approve/reject');
        }

        tx.update(requestRef, {
          'status': newStatus,
          'resolvedAt': FieldValue.serverTimestamp(),
          'resolvedBy': resolvedBy,
        });
      });

      final subSnap = await _subRef(orderId).get();
      final hasPending = subSnap.docs.any((d) =>
          (d.data()['status'] ?? 'pending').toString() == 'pending');
      if (!hasPending) {
        await orderRef.update({'status': 'Shopping'});
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
