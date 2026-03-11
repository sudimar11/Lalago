import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';

/// Result for today's performance metrics.
class TodayPerformanceResult {
  final double avgMinutes;
  final int totalOrders;
  final double? avgRating;
  final int ratingCount;

  const TodayPerformanceResult({
    required this.avgMinutes,
    required this.totalOrders,
    this.avgRating,
    required this.ratingCount,
  });

  bool get hasData => totalOrders > 0;
}

/// Fetches today's performance metrics: avg preparation time and customer
/// ratings from completed orders.
class TodayPerformanceService {
  static Future<TodayPerformanceResult> fetch(String? vendorID) async {
    if (vendorID == null) {
      return const TodayPerformanceResult(
        avgMinutes: 0.0,
        totalOrders: 0,
        ratingCount: 0,
      );
    }
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final querySnapshot = await FirebaseFirestore.instance
          .collection(ORDERS)
          .where('vendorID', isEqualTo: vendorID)
          .where('status',
              whereIn: ['Order Shipped', 'Order Completed', 'Order Delivered'])
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      if (querySnapshot.docs.isEmpty) {
        return const TodayPerformanceResult(
          avgMinutes: 0.0,
          totalOrders: 0,
          ratingCount: 0,
        );
      }

      double totalPreparationTime = 0.0;
      int validOrders = 0;
      final completedOrderIds = <String>[];

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final orderId = doc.id;
        final createdAt = data['createdAt'] as Timestamp?;
        final shippedAt = data['shippedAt'] as Timestamp?;
        final deliveredAt = data['deliveredAt'] as Timestamp?;

        if (createdAt != null) {
          DateTime? endTime =
              deliveredAt != null ? deliveredAt.toDate() : shippedAt?.toDate();
          if (endTime != null) {
            final minutes = endTime.difference(createdAt.toDate()).inMinutes;
            if (minutes >= 1 && minutes <= 120) {
              totalPreparationTime += minutes;
              validOrders++;
              completedOrderIds.add(orderId);
            }
          }
        }
      }

      double? avgRating;
      int ratingCount = 0;

      if (completedOrderIds.isNotEmpty) {
        final reviews =
            await FireStoreUtils().getReviewsByVendorOnce(vendorID);
        final todayReviews = reviews.where((r) {
          final oid = r.orderId ?? '';
          return oid.isNotEmpty && completedOrderIds.contains(oid);
        }).toList();

        if (todayReviews.isNotEmpty) {
          final sum =
              todayReviews.fold<double>(0, (s, r) => s + (r.rating ?? 0));
          avgRating = sum / todayReviews.length;
          ratingCount = todayReviews.length;
        }
      }

      final avgMinutes = validOrders > 0 ? totalPreparationTime / validOrders : 0.0;

      return TodayPerformanceResult(
        avgMinutes: avgMinutes,
        totalOrders: validOrders,
        avgRating: avgRating,
        ratingCount: ratingCount,
      );
    } catch (e) {
      return const TodayPerformanceResult(
        avgMinutes: 0.0,
        totalOrders: 0,
        ratingCount: 0,
      );
    }
  }

  /// Convenience method using current user's vendor.
  static Future<TodayPerformanceResult> fetchForCurrentVendor() async {
    return fetch(MyAppState.currentUser?.vendorID);
  }
}
