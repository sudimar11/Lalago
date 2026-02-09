import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/NewUserPromoConfig.dart';

class NewUserPromoService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static const String settingsDocId = 'NEW_USER_PROMO';
  static const String settingsCollection = 'settings';
  static const String ordersCollection = 'restaurant_orders';
  static const String promoId = 'NEW_USER_PROMO';

  // Get promo configuration stream
  static Stream<NewUserPromoConfig> getPromoConfigStream() {
    return firestore
        .collection(settingsCollection)
        .doc(settingsDocId)
        .snapshots()
        .map((docSnapshot) {
      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return _getDefaultConfig();
      }

      final data = docSnapshot.data()!;
      return NewUserPromoConfig.fromJson(data);
    });
  }

  // Get promo configuration (one-time)
  static Future<NewUserPromoConfig> getPromoConfig() async {
    try {
      final docSnapshot = await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return _getDefaultConfig();
      }

      final data = docSnapshot.data()!;
      return NewUserPromoConfig.fromJson(data);
    } catch (e) {
      print('Error getting promo config: $e');
      return _getDefaultConfig();
    }
  }

  // Update promo configuration
  static Future<void> updatePromoConfig(
      NewUserPromoConfig config) async {
    try {
      if (!config.isValid()) {
        throw Exception('Invalid promo configuration');
      }

      config.updatedAt = Timestamp.now();

      await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .set(config.toJson(), SetOptions(merge: true));
    } catch (e) {
      print('Error updating promo config: $e');
      throw Exception('Failed to update promo configuration: $e');
    }
  }

  // Update master toggle
  static Future<void> updateMasterToggle(bool enabled) async {
    try {
      await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .set({'enabled': enabled}, SetOptions(merge: true));
    } catch (e) {
      print('Error updating master toggle: $e');
      throw Exception('Failed to update master toggle: $e');
    }
  }

  // Get usage statistics
  static Future<PromoUsageStats> getPromoUsageStats() async {
    try {
      // Query completed orders with the promo applied
      final querySnapshot = await firestore
          .collection(ordersCollection)
          .where('status', isEqualTo: 'Order Completed')
          .where('appliedPromoId', isEqualTo: promoId)
          .get();

      final orders = querySnapshot.docs;
      final totalUsage = orders.length;

      // Extract unique user IDs
      final userIds = <String>{};
      double totalDiscountCost = 0.0;
      final affectedOrders = <Map<String, dynamic>>[];

      for (var orderDoc in orders) {
        final orderData = orderDoc.data();
        final userId = orderData['authorID'] ??
            orderData['userId'] ??
            orderData['user_id'] ??
            '';
        if (userId.isNotEmpty) {
          userIds.add(userId);
        }

        final discountAmount = (orderData['promoDiscountAmount'] is num)
            ? (orderData['promoDiscountAmount'] as num).toDouble()
            : 0.0;
        totalDiscountCost += discountAmount;

        affectedOrders.add({
          'orderId': orderDoc.id,
          'userId': userId,
          'discountAmount': discountAmount,
          'createdAt': orderData['createdAt'],
          'deliveredAt': orderData['deliveredAt'],
          'orderTotal': orderData['total'] ?? orderData['orderTotal'] ?? 0.0,
        });
      }

      // Sort orders by date (newest first)
      affectedOrders.sort((a, b) {
        final aDate = _getTimestamp(a['deliveredAt'] ?? a['createdAt']);
        final bDate = _getTimestamp(b['deliveredAt'] ?? b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return PromoUsageStats(
        totalUsage: totalUsage,
        uniqueUsers: userIds.length,
        totalDiscountCost: totalDiscountCost,
        affectedOrders: affectedOrders,
        userIds: userIds.toList(),
      );
    } catch (e) {
      print('Error getting promo usage stats: $e');
      return PromoUsageStats(
        totalUsage: 0,
        uniqueUsers: 0,
        totalDiscountCost: 0.0,
        affectedOrders: [],
        userIds: [],
      );
    }
  }

  // Get stream of usage statistics
  static Stream<PromoUsageStats> getPromoUsageStatsStream() {
    return firestore
        .collection(ordersCollection)
        .where('status', isEqualTo: 'Order Completed')
        .where('appliedPromoId', isEqualTo: promoId)
        .snapshots()
        .asyncMap((snapshot) async {
      final orders = snapshot.docs;
      final totalUsage = orders.length;

      final userIds = <String>{};
      double totalDiscountCost = 0.0;
      final affectedOrders = <Map<String, dynamic>>[];

      for (var orderDoc in orders) {
        final orderData = orderDoc.data();
        final userId = orderData['authorID'] ??
            orderData['userId'] ??
            orderData['user_id'] ??
            '';
        if (userId.isNotEmpty) {
          userIds.add(userId);
        }

        final discountAmount = (orderData['promoDiscountAmount'] is num)
            ? (orderData['promoDiscountAmount'] as num).toDouble()
            : 0.0;
        totalDiscountCost += discountAmount;

        affectedOrders.add({
          'orderId': orderDoc.id,
          'userId': userId,
          'discountAmount': discountAmount,
          'createdAt': orderData['createdAt'],
          'deliveredAt': orderData['deliveredAt'],
          'orderTotal': orderData['total'] ?? orderData['orderTotal'] ?? 0.0,
        });
      }

      affectedOrders.sort((a, b) {
        final aDate = _getTimestamp(a['deliveredAt'] ?? a['createdAt']);
        final bDate = _getTimestamp(b['deliveredAt'] ?? b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

      return PromoUsageStats(
        totalUsage: totalUsage,
        uniqueUsers: userIds.length,
        totalDiscountCost: totalDiscountCost,
        affectedOrders: affectedOrders,
        userIds: userIds.toList(),
      );
    });
  }

  // Helper to get default configuration
  static NewUserPromoConfig _getDefaultConfig() {
    final now = DateTime.now();
    final oneYearLater = now.add(const Duration(days: 365));
    return NewUserPromoConfig(
      enabled: false,
      discountType: 'fixed_amount',
      discountValue: 0.0,
      minOrderAmount: 0.0,
      validFrom: Timestamp.fromDate(now),
      validTo: Timestamp.fromDate(oneYearLater),
    );
  }

  // Helper to extract Timestamp from various formats
  static DateTime? _getTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is Map) {
      try {
        final ts = Timestamp(
          timestamp['_seconds'] ?? 0,
          timestamp['_nanoseconds'] ?? 0,
        );
        return ts.toDate();
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}

// Usage statistics model
class PromoUsageStats {
  final int totalUsage;
  final int uniqueUsers;
  final double totalDiscountCost;
  final List<Map<String, dynamic>> affectedOrders;
  final List<String> userIds;

  PromoUsageStats({
    required this.totalUsage,
    required this.uniqueUsers,
    required this.totalDiscountCost,
    required this.affectedOrders,
    required this.userIds,
  });
}

