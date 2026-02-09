import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/FirstOrderCouponConfig.dart';

class FirstOrderCouponService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static const String settingsDocId = 'FIRST_ORDER_AUTO';
  static const String settingsCollection = 'settings';
  static const String ordersCollection = 'restaurant_orders';
  static const String couponId = 'FIRST_ORDER_AUTO';

  // Get coupon configuration stream
  static Stream<FirstOrderCouponConfig> getCouponConfigStream() {
    return firestore
        .collection(settingsCollection)
        .doc(settingsDocId)
        .snapshots()
        .map((docSnapshot) {
      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return _getDefaultConfig();
      }

      final data = docSnapshot.data()!;
      return FirstOrderCouponConfig.fromJson(data);
    });
  }

  // Get coupon configuration (one-time)
  static Future<FirstOrderCouponConfig> getCouponConfig() async {
    try {
      final docSnapshot = await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return _getDefaultConfig();
      }

      final data = docSnapshot.data()!;
      return FirstOrderCouponConfig.fromJson(data);
    } catch (e) {
      print('Error getting coupon config: $e');
      return _getDefaultConfig();
    }
  }

  // Update coupon configuration
  static Future<void> updateCouponConfig(
      FirstOrderCouponConfig config) async {
    try {
      if (!config.isValid()) {
        throw Exception('Invalid coupon configuration');
      }

      config.updatedAt = Timestamp.now();

      await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .set(config.toJson(), SetOptions(merge: true));
    } catch (e) {
      print('Error updating coupon config: $e');
      throw Exception('Failed to update coupon configuration: $e');
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
  static Future<CouponUsageStats> getCouponUsageStats() async {
    try {
      // Query completed orders with the coupon applied
      final querySnapshot = await firestore
          .collection(ordersCollection)
          .where('status', isEqualTo: 'Order Completed')
          .where('appliedCouponId', isEqualTo: couponId)
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

        final discountAmount = (orderData['couponDiscountAmount'] is num)
            ? (orderData['couponDiscountAmount'] as num).toDouble()
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

      return CouponUsageStats(
        totalUsage: totalUsage,
        uniqueUsers: userIds.length,
        totalDiscountCost: totalDiscountCost,
        affectedOrders: affectedOrders,
        userIds: userIds.toList(),
      );
    } catch (e) {
      print('Error getting coupon usage stats: $e');
      return CouponUsageStats(
        totalUsage: 0,
        uniqueUsers: 0,
        totalDiscountCost: 0.0,
        affectedOrders: [],
        userIds: [],
      );
    }
  }

  // Get stream of usage statistics
  static Stream<CouponUsageStats> getCouponUsageStatsStream() {
    return firestore
        .collection(ordersCollection)
        .where('status', isEqualTo: 'Order Completed')
        .where('appliedCouponId', isEqualTo: couponId)
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

        final discountAmount = (orderData['couponDiscountAmount'] is num)
            ? (orderData['couponDiscountAmount'] as num).toDouble()
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

      return CouponUsageStats(
        totalUsage: totalUsage,
        uniqueUsers: userIds.length,
        totalDiscountCost: totalDiscountCost,
        affectedOrders: affectedOrders,
        userIds: userIds.toList(),
      );
    });
  }

  // Helper to get default configuration
  static FirstOrderCouponConfig _getDefaultConfig() {
    final now = DateTime.now();
    final oneYearLater = now.add(const Duration(days: 365));
    return FirstOrderCouponConfig(
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
class CouponUsageStats {
  final int totalUsage;
  final int uniqueUsers;
  final double totalDiscountCost;
  final List<Map<String, dynamic>> affectedOrders;
  final List<String> userIds;

  CouponUsageStats({
    required this.totalUsage,
    required this.uniqueUsers,
    required this.totalDiscountCost,
    required this.affectedOrders,
    required this.userIds,
  });
}

