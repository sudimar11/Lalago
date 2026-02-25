import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/model/addon_promo_model.dart';

class AddonPromoService {
  static final _firestore = FirebaseFirestore.instance;

  /// Stream of active add-on promos, optionally filtered by restaurantId.
  static Stream<List<AddonPromoModel>> getActiveAddonPromosStream({
    String? restaurantId,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> q = _firestore
        .collection('addon_promos')
        .where('status', isEqualTo: 'active')
        .limit(limit);
    if (restaurantId != null && restaurantId.isNotEmpty) {
      q = q.where('restaurantId', isEqualTo: restaurantId);
    }
    return q.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => AddonPromoModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.addonPromoId.compareTo(a.addonPromoId));
      return list;
    });
  }

  /// One-time fetch of active add-on promos.
  static Future<List<AddonPromoModel>> getActiveAddonPromos({
    String? restaurantId,
    int limit = 50,
  }) async {
    Query<Map<String, dynamic>> q = _firestore
        .collection('addon_promos')
        .where('status', isEqualTo: 'active')
        .limit(limit);
    if (restaurantId != null && restaurantId.isNotEmpty) {
      q = q.where('restaurantId', isEqualTo: restaurantId);
    }
    final snap = await q.get();
    final list =
        snap.docs.map((d) => AddonPromoModel.fromFirestore(d)).toList();
    list.sort((a, b) => b.addonPromoId.compareTo(a.addonPromoId));
    return list;
  }

  /// Fetch add-on promos whose trigger product is [productId] and restaurant
  /// is [restaurantId]. For use on ProductDetailsScreen.
  static Future<List<AddonPromoModel>> getPromosByTriggerProduct({
    required String productId,
    required String restaurantId,
  }) async {
    final all = await getActiveAddonPromos(
      restaurantId: restaurantId,
      limit: 50,
    );
    return all
        .where((p) =>
            p.triggerType == 'product' && p.triggerProductId == productId)
        .toList();
  }

  /// Stream of add-on promos for a restaurant; filter by trigger in caller.
  static Stream<List<AddonPromoModel>> getPromosStreamForRestaurant(
    String restaurantId, {
    int limit = 50,
  }) {
    return getActiveAddonPromosStream(
      restaurantId: restaurantId,
      limit: limit,
    );
  }
}
