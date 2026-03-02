import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/services/restaurant_status_service.dart';

/// Syncs local cart state to Firestore for server-side cart recovery.
class CartSyncService {
  static const int abandonmentHours = 2;

  static StreamSubscription<List<CartProduct>>? _cartSubscription;

  /// Start watching cart and sync to Firestore when changes occur.
  static void startCartSync(CartDatabase cartDb) {
    _cartSubscription?.cancel();

    _cartSubscription = cartDb.watchProducts.listen((cartItems) async {
      await _syncCartToFirestore(cartItems);
    });
  }

  static void stopCartSync() {
    _cartSubscription?.cancel();
    _cartSubscription = null;
  }

  static Future<void> _syncCartToFirestore(List<CartProduct> cartItems) async {
    final userId = auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    if (cartItems.isEmpty) {
      await FirebaseFirestore.instance
          .collection('user_carts')
          .doc(userId)
          .delete();
      return;
    }

    final Map<String, List<Map<String, dynamic>>> vendorGroups = {};

    for (var item in cartItems) {
      if (!vendorGroups.containsKey(item.vendorID)) {
        vendorGroups[item.vendorID] = [];
      }

      vendorGroups[item.vendorID]!.add({
        'productId': item.id,
        'name': item.name,
        'quantity': item.quantity,
        'price': item.price,
        'vendorId': item.vendorID,
        'addedAt': (item.addedAt).toIso8601String(),
        'lastModifiedAt': (item.lastModifiedAt ?? item.addedAt)
            .toIso8601String(),
        'extras': item.extras,
        'variant_info': item.variant_info,
      });
    }

    DateTime lastModified = cartItems
        .map((item) => item.lastModifiedAt ?? item.addedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final itemsData = cartItems.map((item) {
      return {
        'productId': item.id,
        'name': item.name,
        'quantity': item.quantity,
        'price': item.price,
        'vendorId': item.vendorID,
        'addedAt': Timestamp.fromDate(item.addedAt),
        'lastModifiedAt': Timestamp.fromDate(
          item.lastModifiedAt ?? item.addedAt,
        ),
      };
    }).toList();

    final totalValue = cartItems.fold<double>(
      0.0,
      (sum, item) =>
          sum + ((double.tryParse(item.price) ?? 0) * item.quantity),
    );

    final uniqueVendorIds = cartItems
        .map((item) => item.vendorID)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final Map<String, dynamic> vendorStatuses = {};
    if (uniqueVendorIds.isNotEmpty) {
      try {
        final statusMap = await RestaurantStatusService
            .checkMultipleVendorsStatus(uniqueVendorIds);
        for (final vid in uniqueVendorIds) {
          final s = statusMap[vid];
          try {
            if (s != null) {
              vendorStatuses[vid] = {
                'isOpen': s['isOpen'] as bool? ?? false,
                'vendorName': (s['vendorName'] ?? 'Restaurant').toString(),
                'lastChecked': FieldValue.serverTimestamp(),
              };
            } else {
              vendorStatuses[vid] = {
                'isOpen': false,
                'error': 'No status',
                'lastChecked': FieldValue.serverTimestamp(),
              };
            }
          } catch (e) {
            vendorStatuses[vid] = {
              'isOpen': false,
              'error': e.toString(),
              'lastChecked': FieldValue.serverTimestamp(),
            };
          }
        }
        log('[CART_SYNC] Syncing with vendor statuses: $vendorStatuses');
      } catch (e) {
        log('[CART_SYNC] Status check failed (sync continues): $e');
      }
    }

    await FirebaseFirestore.instance
        .collection('user_carts')
        .doc(userId)
        .set({
      'userId': userId,
      'items': itemsData,
      'vendorGroups': _serializeVendorGroups(vendorGroups),
      'vendorStatuses': vendorStatuses,
      'itemCount': cartItems.length,
      'totalValue': totalValue,
      'lastModified': Timestamp.fromDate(lastModified),
      'lastSyncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Map<String, dynamic> _serializeVendorGroups(
    Map<String, List<Map<String, dynamic>>> vendorGroups,
  ) {
    final result = <String, dynamic>{};
    for (var e in vendorGroups.entries) {
      result[e.key] = e.value;
    }
    return result;
  }

  /// Check if a cart is abandoned (no activity for X hours).
  static Future<bool> isCartAbandoned(String userId) async {
    final cartDoc = await FirebaseFirestore.instance
        .collection('user_carts')
        .doc(userId)
        .get();

    if (!cartDoc.exists || cartDoc.data() == null) return false;

    final data = cartDoc.data()!;
    final lastModified = (data['lastModified'] as Timestamp?)?.toDate();

    if (lastModified == null) return false;

    final hoursSinceModification =
        DateTime.now().difference(lastModified).inHours;
    return hoursSinceModification >= abandonmentHours;
  }

  /// Call when user logs out.
  static Future<void> onLogout() async {
    stopCartSync();
    final userId = auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('user_carts')
            .doc(userId)
            .delete();
      } catch (_) {}
    }
  }
}
