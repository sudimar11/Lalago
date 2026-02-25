import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/model/bundle_model.dart';

class BundleService {
  static final _firestore = FirebaseFirestore.instance;

  /// Stream of active bundles, optionally filtered by restaurantId.
  static Stream<List<BundleModel>> getActiveBundlesStream({
    String? restaurantId,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q = _firestore
        .collection('bundles')
        .where('status', isEqualTo: 'active')
        .limit(limit);
    if (restaurantId != null && restaurantId.isNotEmpty) {
      q = q.where('restaurantId', isEqualTo: restaurantId);
    }
    return q.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => BundleModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.bundleId.compareTo(a.bundleId));
      return list;
    });
  }

  /// One-time fetch of active bundles.
  static Future<List<BundleModel>> getActiveBundles({
    String? restaurantId,
    int limit = 50,
  }) async {
    Query<Map<String, dynamic>> q = _firestore
        .collection('bundles')
        .where('status', isEqualTo: 'active')
        .limit(limit);
    if (restaurantId != null && restaurantId.isNotEmpty) {
      q = q.where('restaurantId', isEqualTo: restaurantId);
    }
    final snap = await q.get();
    final list = snap.docs.map((d) => BundleModel.fromFirestore(d)).toList();
    list.sort((a, b) => b.bundleId.compareTo(a.bundleId));
    return list;
  }

  /// Fetch a single bundle by id.
  static Future<BundleModel?> getBundle(String bundleId) async {
    final doc = await _firestore.collection('bundles').doc(bundleId).get();
    if (!doc.exists || doc.data() == null) return null;
    return BundleModel.fromFirestore(doc);
  }

  /// Enrich bundle items with photo from vendor_products (optional).
  static Future<List<Map<String, dynamic>>> itemsWithPhotos(
    String vendorId,
    List<BundleItemEntry> items,
  ) async {
    final result = <Map<String, dynamic>>[];
    final coll = _firestore.collection('vendor_products');
    for (final item in items) {
      String? photo;
      try {
        final doc = await coll.doc(item.productId).get();
        if (doc.exists && doc.data() != null) {
          final d = doc.data()!;
          photo = (d['photo'] ?? d['imageUrl'] ?? d['image'] ?? '').toString();
        }
      } catch (_) {}
      result.add({
        'productId': item.productId,
        'productName': item.productName,
        'quantity': item.quantity,
        'photo': photo ?? '',
        'category_id': items.isNotEmpty ? items.first.productId : '',
      });
    }
    return result;
  }
}
