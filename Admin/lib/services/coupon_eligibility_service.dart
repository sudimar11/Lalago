import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/coupon.dart';
import 'package:brgy/model/user.dart';

class CouponEligibilityService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String ordersCollection = 'restaurant_orders';

  /// Check if a user is eligible for a coupon based on its eligibility rules
  static Future<bool> checkUserEligibility(
    Coupon coupon,
    String userId,
    User? user,
  ) async {
    // If no eligibility rules, user is eligible (backward compatibility)
    if (coupon.eligibilityRules == null || !coupon.eligibilityRules!.hasRules) {
      return true;
    }

    final rules = coupon.eligibilityRules!;

    // Check user ID whitelist if present
    if (rules.userIds != null && rules.userIds!.isNotEmpty) {
      if (!rules.userIds!.contains(userId)) {
        return false;
      }
    }

    // Check user categories
    if (rules.userCategories != null && rules.userCategories!.isNotEmpty) {
      final userCategory = await getUserCategory(userId);
      if (!rules.userCategories!.contains(userCategory)) {
        return false;
      }
    }

    // Check minimum completed orders
    if (rules.minCompletedOrders != null) {
      final orderCount = await getUserCompletedOrderCount(userId);
      if (orderCount < rules.minCompletedOrders!) {
        return false;
      }
    }

    // Check first-time user only
    if (rules.firstTimeUserOnly == true) {
      final orderCount = await getUserCompletedOrderCount(userId);
      if (orderCount > 0) {
        return false;
      }
    }

    // Check prior coupon usage
    if (rules.priorCouponUsage != null &&
        rules.priorCouponUsage!.type != 'none') {
      final hasUsed = await checkPriorCouponUsage(
        userId,
        rules.priorCouponUsage!.type == 'this_coupon' ? coupon.id : null,
        rules.priorCouponUsage!.type,
      );

      // If allowed=true, user must have used the coupon
      // If allowed=false, user must NOT have used the coupon
      if (rules.priorCouponUsage!.allowed && !hasUsed) {
        return false;
      }
      if (!rules.priorCouponUsage!.allowed && hasUsed) {
        return false;
      }
    }

    // All checks passed
    return true;
  }

  /// Get the number of completed orders for a user
  static Future<int> getUserCompletedOrderCount(String userId) async {
    try {
      if (userId.isEmpty) {
        return 0;
      }

      // Query for completed orders
      // Check both authorID and author.id fields for compatibility
      final query1 = _firestore
          .collection(ordersCollection)
          .where('authorID', isEqualTo: userId)
          .where('status', isEqualTo: 'Order Completed');

      final query2 = _firestore
          .collection(ordersCollection)
          .where('author.id', isEqualTo: userId)
          .where('status', isEqualTo: 'Order Completed');

      final results = await Future.wait([
        query1.count().get(),
        query2.count().get(),
      ]);

      // Combine counts (might have duplicates but that's okay for counting)
      final count1 = results[0].count ?? 0;
      final count2 = results[1].count ?? 0;

      // Return the maximum to avoid double counting
      // (in practice, one query should return all results)
      return count1 > count2 ? count1 : count2;
    } catch (e) {
      log('Error getting user completed order count: $e');
      return 0;
    }
  }

  /// Check if user has used a coupon before
  /// If couponId is null, checks if user has used ANY coupon
  static Future<bool> checkPriorCouponUsage(
    String userId,
    String? couponId,
    String type,
  ) async {
    try {
      if (userId.isEmpty) {
        return false;
      }

      Query query = _firestore
          .collection(ordersCollection)
          .where('authorID', isEqualTo: userId)
          .where('status', isEqualTo: 'Order Completed');

      if (type == 'this_coupon' && couponId != null) {
        // Check for specific coupon usage
        query = query.where('manualCouponId', isEqualTo: couponId);
      } else if (type == 'any_coupon') {
        // Check if user has used any coupon
        query = query.where('manualCouponId', isNotEqualTo: null);
      } else {
        // type == 'none' - should not reach here, but return false
        return false;
      }

      final snapshot = await query.limit(1).get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      log('Error checking prior coupon usage: $e');
      return false;
    }
  }

  /// Determine user's category based on order history
  /// Returns: "new_user" (0 orders), "regular_customer" (1+ orders), or "vip" (future)
  static Future<String> getUserCategory(String userId) async {
    try {
      // TODO: Add VIP check when VIP system is implemented
      // For now, check if user has completed orders
      final orderCount = await getUserCompletedOrderCount(userId);

      if (orderCount == 0) {
        return 'new_user';
      } else {
        return 'regular_customer';
      }
    } catch (e) {
      log('Error getting user category: $e');
      return 'new_user'; // Default to new_user on error
    }
  }
}

