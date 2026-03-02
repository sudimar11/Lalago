import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:foodie_customer/constants.dart';

/// Service for per-restaurant popularity (order count aggregation).
class PopularityService {
  static const int defaultLimit = 10;
  static const int maxDays = 30;

  /// Get popular items for a specific restaurant.
  static Future<List<Map<String, dynamic>>> getPopularItemsAtRestaurant({
    required String vendorId,
    String timeRange = 'week',
    int limit = defaultLimit,
  }) async {
    try {
      debugPrint(
        '📊 [POPULARITY] vendor=$vendorId range=$timeRange limit=$limit',
      );

      final now = DateTime.now();
      DateTime startDate;
      switch (timeRange.toLowerCase()) {
        case 'today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case 'all':
        default:
          startDate = now.subtract(Duration(days: maxDays));
          break;
      }

      final orderSnapshot = await FirebaseFirestore.instance
          .collection(ORDERS)
          .where('vendorID', isEqualTo: vendorId)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();

      debugPrint(
        '📊 [POPULARITY] Found ${orderSnapshot.docs.length} orders',
      );

      final productCounts = <String, Map<String, dynamic>>{};
      for (final doc in orderSnapshot.docs) {
        final data = doc.data();
        final products = data['products'] as List<dynamic>? ?? [];
        for (final product in products) {
          if (product is! Map) continue;
          final fullId = (product['id'] ?? '').toString();
          final baseId = fullId.split('~').first;
          if (baseId.isEmpty) continue;

          if (!productCounts.containsKey(baseId)) {
            productCounts[baseId] = {
              'id': baseId,
              'name': (product['name'] ?? 'Unknown').toString(),
              'price': (product['price'] ?? '0').toString(),
              'count': 0,
            };
          }
          final qty = product['quantity'];
          final quantity = qty is int
              ? qty
              : (int.tryParse(qty?.toString() ?? '1') ?? 1);
          productCounts[baseId]!['count'] =
              (productCounts[baseId]!['count'] as int) + quantity;
        }
      }

      if (productCounts.isEmpty) return [];

      var popularItems = productCounts.values.toList();
      popularItems.sort(
        (a, b) => (b['count'] as int).compareTo(a['count'] as int),
      );
      if (popularItems.length > limit) {
        popularItems = popularItems.sublist(0, limit);
      }

      String vendorName = '';
      try {
        final vendorDoc = await FirebaseFirestore.instance
            .collection(VENDORS)
            .doc(vendorId)
            .get();
        if (vendorDoc.exists && vendorDoc.data() != null) {
          vendorName =
              (vendorDoc.data()!['title'] ?? '').toString();
        }
      } catch (_) {}

      final productDetails = <String, Map<String, dynamic>>{};
      final productIds =
          popularItems.map((p) => p['id'] as String).toList();
      for (var i = 0; i < productIds.length; i += 10) {
        final batch = productIds.skip(i).take(10).toList();
        final productSnapshot = await FirebaseFirestore.instance
            .collection(PRODUCTS)
            .where(FieldPath.documentId, whereIn: batch)
            .get();

        for (final doc in productSnapshot.docs) {
          final d = doc.data();
          productDetails[doc.id] = {
            'name': (d['name'] ?? 'Unknown').toString(),
            'description': (d['description'] ?? '').toString(),
            'price': (d['price'] ?? '0').toString(),
            'photo': (d['photo'] ?? '').toString(),
            'reviewsCount': d['reviewsCount'] as num? ?? 0,
            'reviewsSum': d['reviewsSum'] as num? ?? 0,
          };
        }
      }

      final result = <Map<String, dynamic>>[];
      for (final item in popularItems) {
        final productId = item['id'] as String;
        final details = productDetails[productId] ?? {
          'name': item['name'],
          'description': '',
          'price': item['price'],
          'photo': '',
          'reviewsCount': 0,
          'reviewsSum': 0,
        };

        final revCount = details['reviewsCount'] as num;
        final revSum = details['reviewsSum'] as num;
        final rating = revCount > 0 ? revSum / revCount : 0.0;

        result.add({
          'id': productId,
          'name': details['name'],
          'price': details['price'],
          'vendorID': vendorId,
          'vendorName': vendorName,
          'imageUrl': getImageVAlidUrl(details['photo'] as String),
          'orderCount': item['count'] as int,
          'rating': rating.toStringAsFixed(1),
        });
      }

      return result;
    } catch (e, stack) {
      debugPrint('❌ [POPULARITY] Error: $e');
      debugPrint('💥 Stack: $stack');
      return [];
    }
  }

  /// Resolve vendor ID from restaurant name (client-side filtering).
  static Future<String?> findVendorIdByName(String restaurantName) async {
    try {
      final lowerName = restaurantName.trim().toLowerCase();
      if (lowerName.isEmpty) return null;

      final snapshot = await FirebaseFirestore.instance
          .collection(VENDORS)
          .where('reststatus', isEqualTo: true)
          .limit(100)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final title = (data['title'] ?? '').toString().toLowerCase();
        if (title.contains(lowerName) || lowerName.contains(title)) {
          return doc.id;
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ [POPULARITY] findVendorIdByName error: $e');
      return null;
    }
  }
}
