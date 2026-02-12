import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/offer_model.dart';

class CouponEligibilityService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if a user is eligible for a coupon based on its eligibility rules
  static Future<bool> checkEligibility(
    OfferModel coupon,
    String userId,
  ) async {
    try {
      // If no eligibility rules, user is eligible (backward compatibility)
      if (coupon.eligibilityRules == null || coupon.eligibilityRules!.isEmpty) {
        return true;
      }

      final rules = coupon.eligibilityRules!;

      // Check user ID whitelist if present
      if (rules['userIds'] != null) {
        final userIds = rules['userIds'] as List<dynamic>?;
        if (userIds != null && userIds.isNotEmpty) {
          final userIdList = userIds.map((e) => e.toString()).toList();
          if (!userIdList.contains(userId)) {
            return false;
          }
        }
      }

      // Check user categories
      if (rules['userCategories'] != null) {
        final categories = rules['userCategories'] as List<dynamic>?;
        if (categories != null && categories.isNotEmpty) {
          final categoryList = categories.map((e) => e.toString()).toList();
          final userCategory = await getUserCategory(userId);
          if (!categoryList.contains(userCategory)) {
            return false;
          }
        }
      }

      // Check minimum completed orders
      if (rules['minCompletedOrders'] != null) {
        final minOrders = rules['minCompletedOrders'] is int
            ? rules['minCompletedOrders'] as int
            : int.tryParse(rules['minCompletedOrders'].toString());
        if (minOrders != null) {
          final orderCount = await getUserCompletedOrderCount(userId);
          if (orderCount < minOrders) {
            return false;
          }
        }
      }

      // Check first-time user only
      if (rules['firstTimeUserOnly'] == true) {
        final orderCount = await getUserCompletedOrderCount(userId);
        if (orderCount > 0) {
          return false;
        }
      }

      // Check prior coupon usage
      if (rules['priorCouponUsage'] != null) {
        final priorUsage = rules['priorCouponUsage'] as Map<String, dynamic>?;
        if (priorUsage != null && priorUsage['type'] != 'none') {
          final usageType = priorUsage['type'] as String? ?? 'none';
          final allowed = priorUsage['allowed'] as bool? ?? false;

          final hasUsed = await checkPriorCouponUsage(
            userId,
            usageType == 'this_coupon' ? coupon.offerId : null,
            usageType,
          );

          // If allowed=true, user must have used the coupon
          // If allowed=false, user must NOT have used the coupon
          if (allowed && !hasUsed) {
            return false;
          }
          if (!allowed && hasUsed) {
            return false;
          }
        }
      }

      // All checks passed
      return true;
    } catch (e) {
      log('Error checking coupon eligibility: $e');
      // On error, default to not eligible for security
      return false;
    }
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
          .collection(ORDERS)
          .where('authorID', isEqualTo: userId)
          .where('status', isEqualTo: 'Order Completed');

      final query2 = _firestore
          .collection(ORDERS)
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
          .collection(ORDERS)
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

