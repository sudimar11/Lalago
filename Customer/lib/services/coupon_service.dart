import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/coupon_eligibility_service.dart';

class CouponService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Validates a coupon code for a given order
  /// Returns Map with 'valid' (bool), 'coupon' (OfferModel?), 'error' (String?), 'itemsNeeded' (int?)
  static Future<Map<String, dynamic>> validateCoupon(
    String code,
    double orderSubtotal,
    String userId,
    String? vendorId, {
    int totalItemCount = 0,
  }) async {
    try {
      // Fetch coupon by code
      final coupon = await getCouponByCode(code);
      
      if (coupon == null) {
      return {
        'valid': false,
        'coupon': null,
        'error': 'Coupon code not found',
        'itemsNeeded': null,
      };
      }

      // Check if coupon is enabled
      if (coupon.isEnableOffer != true) {
        return {
          'valid': false,
          'coupon': null,
          'error': 'This coupon is not active',
          'itemsNeeded': null,
        };
      }

      // Check user eligibility rules (before other validations)
      final isEligible = await CouponEligibilityService.checkEligibility(
        coupon,
        userId,
      );
      if (!isEligible) {
        return {
          'valid': false,
          'coupon': null,
          'error': 'This coupon is not available for your account',
          'itemsNeeded': null,
        };
      }

      // Check expiration date (using expireOfferDate as fallback if validUntil is not set)
      final now = DateTime.now();
      if (coupon.expireOfferDate != null) {
        final expireDate = coupon.expireOfferDate!.toDate();
        if (now.isAfter(expireDate)) {
          return {
            'valid': false,
            'coupon': null,
            'error': 'This coupon has expired',
            'itemsNeeded': null,
          };
        }
      }

      // Check validity period (validFrom and validUntil)
      if (coupon.validFrom != null) {
        final validFromDate = coupon.validFrom!.toDate();
        if (now.isBefore(validFromDate)) {
          return {
            'valid': false,
            'coupon': null,
            'error': 'This coupon is not yet valid',
            'itemsNeeded': null,
          };
        }
      }

      if (coupon.validUntil != null) {
        final validUntilDate = coupon.validUntil!.toDate();
        if (now.isAfter(validUntilDate)) {
          return {
            'valid': false,
            'coupon': null,
            'error': 'This coupon has expired',
            'itemsNeeded': null,
          };
        }
      }

      // Check usage limits
      if (coupon.usageLimit != null && coupon.usedCount != null) {
        if (coupon.usedCount! >= coupon.usageLimit!) {
          return {
            'valid': false,
            'coupon': null,
            'error': 'This coupon has reached its usage limit',
            'itemsNeeded': null,
          };
        }
      }

      // Check minimum order amount
      if (coupon.minOrderAmount != null) {
        if (orderSubtotal < coupon.minOrderAmount!) {
          return {
            'valid': false,
            'coupon': null,
            'error':
                'Minimum order amount is ${coupon.minOrderAmount!.toStringAsFixed(2)}',
            'itemsNeeded': null,
          };
        }
      }

      // Check minimum item requirement
      if (coupon.minItems != null && totalItemCount < coupon.minItems!) {
        return {
          'valid': false,
          'coupon': coupon,
          'error':
              'Add ${coupon.minItems! - totalItemCount} more item(s) to use this coupon',
          'itemsNeeded': coupon.minItems! - totalItemCount,
        };
      }

      // Check user eligibility
      if (coupon.eligibleUserIds != null &&
          coupon.eligibleUserIds!.isNotEmpty) {
        if (!coupon.eligibleUserIds!.contains(userId)) {
          return {
            'valid': false,
            'coupon': null,
            'error': 'This coupon is not eligible for your account',
            'itemsNeeded': null,
          };
        }
      }

      // Check vendor eligibility
      if (coupon.restaurantId != null &&
          coupon.restaurantId!.isNotEmpty &&
          vendorId != null) {
        if (coupon.restaurantId != vendorId) {
          return {
            'valid': false,
            'coupon': null,
            'error': 'This coupon is not valid for this restaurant',
            'itemsNeeded': null,
          };
        }
      }

      // All validations passed
      return {
        'valid': true,
        'coupon': coupon,
        'error': null,
        'itemsNeeded': null,
      };
    } catch (e) {
      log('Error validating coupon: $e');
      return {
        'valid': false,
        'coupon': null,
        'error': 'An error occurred while validating the coupon',
        'itemsNeeded': null,
      };
    }
  }

  /// Gets a coupon by its code
  static Future<OfferModel?> getCouponByCode(String code) async {
    try {
      final querySnapshot = await _firestore
          .collection(COUPON)
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final doc = querySnapshot.docs.first;
      final docData = doc.data();
      // Add document ID to the data if id field is not present
      if (!docData.containsKey('id')) {
        docData['id'] = doc.id;
      }
      return OfferModel.fromJson(docData);
    } catch (e) {
      log('Error getting coupon by code: $e');
      return null;
    }
  }

  /// Gets active coupons (not expired, enabled, within validity period)
  /// Optionally filters by user eligibility if userId is provided
  static Future<List<OfferModel>> getActiveCoupons(
    String? vendorId, {
    String? userId,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(COUPON)
          .where('isEnabled', isEqualTo: true);

      // If vendorId is provided, filter by vendor (or global coupons with empty restaurantId)
      // Check both possible field names
      if (vendorId != null && vendorId.isNotEmpty) {
        // Note: Firestore doesn't support OR queries easily, so we'll filter in code
        // For now, we'll get all enabled coupons and filter by restaurantId in code
      }

      final querySnapshot = await query.get();
      final now = DateTime.now();
      final List<OfferModel> activeCoupons = [];

      for (var doc in querySnapshot.docs) {
        try {
          final docData = Map<String, dynamic>.from(doc.data());
          // Add document ID to the data if id field is not present
          if (!docData.containsKey('id')) {
            docData['id'] = doc.id;
          }
          
          log('Processing coupon document: ${doc.id}, imageUrl: ${docData['imageUrl']}');
          
          // Skip deleted coupons
          if (docData['isDeleted'] == true) {
            continue;
          }
          
          final coupon = OfferModel.fromJson(docData);
          log('Parsed coupon - imageOffer: ${coupon.imageOffer}, title: ${coupon.title}');

          // Filter by vendor if specified
          if (vendorId != null && vendorId.isNotEmpty) {
            final restaurantId = coupon.restaurantId ?? '';
            if (restaurantId.isNotEmpty && restaurantId != vendorId) {
              continue; // Skip coupons not for this vendor
            }
          }

          // Check expiration date (validTo or expiresAt)
          bool isExpired = false;
          if (coupon.expireOfferDate != null) {
            final expireDate = coupon.expireOfferDate!.toDate();
            if (now.isAfter(expireDate)) {
              isExpired = true;
            }
          }

          // Check validity period (validFrom and validUntil/validTo)
          if (!isExpired && coupon.validFrom != null) {
            final validFromDate = coupon.validFrom!.toDate();
            if (now.isBefore(validFromDate)) {
              isExpired = true;
            }
          }

          if (!isExpired && coupon.validUntil != null) {
            final validUntilDate = coupon.validUntil!.toDate();
            if (now.isAfter(validUntilDate)) {
              isExpired = true;
            }
          }

          // Check usage limits
          if (coupon.usageLimit != null && coupon.usedCount != null) {
            if (coupon.usedCount! >= coupon.usageLimit!) {
              continue; // Skip coupons that have reached usage limit
            }
          }

          // Check user eligibility if userId is provided
          if (userId != null && userId.isNotEmpty) {
            final isEligible = await CouponEligibilityService.checkEligibility(
              coupon,
              userId,
            );
            if (!isEligible) {
              continue; // Skip ineligible coupons
            }
          }

          if (!isExpired) {
            activeCoupons.add(coupon);
          }
        } catch (e) {
          log('Error parsing coupon document ${doc.id}: $e');
        }
      }

      return activeCoupons;
    } catch (e) {
      log('Error getting active coupons: $e');
      return [];
    }
  }

  /// Reserves a coupon by incrementing its usage count
  /// This is called when an order is placed (status: pending/accepted)
  static Future<bool> reserveCoupon(String couponId) async {
    try {
      final couponRef = _firestore.collection(COUPON).doc(couponId);

      // Use transaction to atomically increment usage count
      return await _firestore.runTransaction<bool>((transaction) async {
        final couponDoc = await transaction.get(couponRef);

        if (!couponDoc.exists) {
          log('Coupon document not found: $couponId');
          return false;
        }

        final currentCount = couponDoc.data()?['usedCount'] as int? ?? 0;
        final usageLimit = couponDoc.data()?['usageLimit'] as int?;

        // Check if limit is reached
        if (usageLimit != null && currentCount >= usageLimit) {
          log('Coupon usage limit reached: $couponId');
          return false;
        }

        // Increment usage count
        transaction.update(couponRef, {
          'usedCount': FieldValue.increment(1),
        });

        return true;
      });
    } catch (e) {
      log('Error reserving coupon: $e');
      return false;
    }
  }

  /// Finalizes or reverts coupon usage based on order completion status
  /// orderCompleted: true if order completed, false if cancelled/rejected/expired
  static Future<bool> finalizeCouponUsage(
    String couponId,
    String orderId,
    bool orderCompleted,
  ) async {
    try {
      // If order was completed, usage count was already incremented during reservation
      // If order was cancelled/rejected/expired, we need to decrement the count
      if (!orderCompleted) {
        final couponRef = _firestore.collection(COUPON).doc(couponId);

        return await _firestore.runTransaction<bool>((transaction) async {
          final couponDoc = await transaction.get(couponRef);

          if (!couponDoc.exists) {
            log('Coupon document not found for finalization: $couponId');
            return false;
          }

          final currentCount = couponDoc.data()?['usedCount'] as int? ?? 0;

          // Decrement usage count (but don't go below 0)
          if (currentCount > 0) {
            transaction.update(couponRef, {
              'usedCount': FieldValue.increment(-1),
            });
          }

          return true;
        });
      }

      // Order completed - usage count was already incremented during reservation
      // Nothing to do here
      return true;
    } catch (e) {
      log('Error finalizing coupon usage: $e');
      return false;
    }
  }

  /// Calculates the discount amount for a coupon based on order subtotal
  static double calculateDiscountAmount(
    OfferModel coupon,
    double orderSubtotal,
  ) {
    if (coupon.discount == null || coupon.discountType == null) {
      return 0.0;
    }

    final discountValue = double.tryParse(coupon.discount!) ?? 0.0;

    if (coupon.discountType!.toLowerCase() == 'percentage' ||
        coupon.discountType!.toLowerCase() == 'percent') {
      return (orderSubtotal * discountValue / 100);
    } else {
      // Fixed amount discount
      return discountValue;
    }
  }
}
