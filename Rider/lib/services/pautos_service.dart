import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/PautosOrderModel.dart';
import 'package:foodie_driver/model/SubstitutionRequestModel.dart';

const _substitutionRequests = 'substitution_requests';

class PautosService {
  static Stream<List<PautosOrderModel>> getMyPautosOrders(String driverId) {
    return FirebaseFirestore.instance
        .collection(PAUTOS_ORDERS)
        .where('driverID', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return PautosOrderModel.fromJson(data);
      }).toList();
    });
  }

  static Stream<PautosOrderModel?> getPautosOrderStream(String orderId) {
    return FirebaseFirestore.instance
        .collection(PAUTOS_ORDERS)
        .doc(orderId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      return PautosOrderModel.fromJson(data);
    });
  }

  static Future<bool> acceptPautosAssignment(String orderId) async {
    final user = MyAppState.currentUser;
    if (user == null) return false;
    final driverId = FirebaseAuth.instance.currentUser?.uid ?? user.userID;

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final orderRef =
          FirebaseFirestore.instance.collection(PAUTOS_ORDERS).doc(orderId);
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) return false;
      final orderData = orderSnap.data() ?? {};
      if ((orderData['driverID'] ?? '').toString() != driverId) return false;
      if ((orderData['status'] ?? '').toString() != 'Driver Assigned') {
        return false;
      }

      tx.update(orderRef, {
        'status': 'Driver Accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      final riderRef =
          FirebaseFirestore.instance.collection('users').doc(driverId);
      tx.update(riderRef, {
        'pautosOrderRequestData': FieldValue.arrayRemove([orderId]),
      });
      return true;
    });
  }

  static Future<bool> rejectPautosAssignment(String orderId, [String? reason]) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('pautosRejectAndReassign');
      await callable.call({'orderId': orderId, 'reason': reason ?? ''});
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start shopping: Driver Accepted -> Shopping.
  static Future<bool> startShopping(String orderId) async {
    final user = MyAppState.currentUser;
    if (user == null) return false;
    final driverId = FirebaseAuth.instance.currentUser?.uid ?? user.userID;

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final orderRef =
          FirebaseFirestore.instance.collection(PAUTOS_ORDERS).doc(orderId);
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) return false;
      final orderData = orderSnap.data() ?? {};
      if ((orderData['driverID'] ?? '').toString() != driverId) return false;
      if ((orderData['status'] ?? '').toString() != 'Driver Accepted') {
        return false;
      }

      tx.update(orderRef, {'status': 'Shopping'});
      return true;
    });
  }

  /// Complete shopping: Shopping -> Delivering with cost and receipt.
  /// Blocked when status is Substitution Pending (has unresolved substitutions).
  static Future<bool> completeShopping(
    String orderId,
    double actualItemCost,
    String? receiptPhotoUrl, [
    List<int>? itemsFound,
  ]) async {
    final user = MyAppState.currentUser;
    if (user == null) return false;
    final driverId = FirebaseAuth.instance.currentUser?.uid ?? user.userID;

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final orderRef =
          FirebaseFirestore.instance.collection(PAUTOS_ORDERS).doc(orderId);
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) return false;
      final orderData = orderSnap.data() ?? {};
      if ((orderData['driverID'] ?? '').toString() != driverId) return false;
      final status = (orderData['status'] ?? '').toString();
      if (status != 'Shopping') return false;

      // tx.get() only accepts DocumentReference; query subcollection outside tx
      final subSnap = await orderRef
          .collection(_substitutionRequests)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (subSnap.docs.isNotEmpty) return false;

      final update = <String, dynamic>{
        'status': 'Delivering',
        'actualItemCost': actualItemCost,
      };
      if (receiptPhotoUrl != null && receiptPhotoUrl.isNotEmpty) {
        update['receiptPhotoUrl'] = receiptPhotoUrl;
      }
      if (itemsFound != null && itemsFound.isNotEmpty) {
        update['itemsFound'] = itemsFound;
      }
      tx.update(orderRef, update);
      return true;
    });
  }

  static CollectionReference<Map<String, dynamic>> _subRef(String orderId) {
    return FirebaseFirestore.instance
        .collection(PAUTOS_ORDERS)
        .doc(orderId)
        .collection(_substitutionRequests);
  }

  /// Create a substitution request; sets order status to Substitution Pending.
  static Future<String?> createSubstitutionRequest(
    String orderId,
    String originalItem,
    int originalItemIndex,
    String proposedItem,
    double proposedPrice,
  ) async {
    final user = MyAppState.currentUser;
    if (user == null) return null;
    final driverId = FirebaseAuth.instance.currentUser?.uid ?? user.userID;

    try {
      final orderRef =
          FirebaseFirestore.instance.collection(PAUTOS_ORDERS).doc(orderId);
      final orderSnap = await orderRef.get();
      if (!orderSnap.exists) return null;
      final orderData = orderSnap.data() ?? {};
      if ((orderData['driverID'] ?? '').toString() != driverId) return null;

      final ref = _subRef(orderId).doc();
      final now = FieldValue.serverTimestamp();
      await ref.set({
        'originalItem': originalItem,
        'originalItemIndex': originalItemIndex,
        'proposedItem': proposedItem,
        'proposedPrice': proposedPrice,
        'status': 'pending',
        'createdAt': now,
        'createdBy': driverId,
      });

      if ((orderData['status'] ?? '').toString() != 'Substitution Pending') {
        await orderRef.update({'status': 'Substitution Pending'});
      }
      return ref.id;
    } catch (_) {
      return null;
    }
  }

  static Stream<List<SubstitutionRequestModel>> getSubstitutionRequestsStream(
    String orderId,
  ) {
    return _subRef(orderId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) =>
                SubstitutionRequestModel.fromJson(d.id, d.data()))
            .toList());
  }

  /// Complete PAUTOS order (Mark Delivered): calls Cloud Function to process
  /// payment and set status to Completed.
  static Future<String?> completePautosOrder(String orderId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('pautosCompleteOrder');
      await callable.call({'orderId': orderId});
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  /// Update PAUTOS order status (Delivering only; use completePautosOrder for Delivered).
  /// Valid transitions: Driver Accepted -> Delivering.
  static Future<bool> updatePautosStatus(String orderId, String newStatus) async {
    final user = MyAppState.currentUser;
    if (user == null) return false;
    final driverId = FirebaseAuth.instance.currentUser?.uid ?? user.userID;

    if (newStatus != 'Delivering') return false;

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final orderRef =
          FirebaseFirestore.instance.collection(PAUTOS_ORDERS).doc(orderId);
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) return false;
      final orderData = orderSnap.data() ?? {};
      if ((orderData['driverID'] ?? '').toString() != driverId) return false;
      if ((orderData['status'] ?? '').toString() != 'Driver Accepted') {
        return false;
      }
      tx.update(orderRef, {'status': 'Delivering'});
      return true;
    });
  }
}
