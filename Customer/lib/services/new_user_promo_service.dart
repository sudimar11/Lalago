import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';

class NewUserPromoConfig {
  final bool isEnabled;
  final String promoId;
  final String promoCode;
  final double minOrderAmount;
  final double discount;
  final String discountType; // "percentage" or "fixed"

  NewUserPromoConfig({
    required this.isEnabled,
    required this.promoId,
    required this.promoCode,
    required this.minOrderAmount,
    required this.discount,
    required this.discountType,
  });

  factory NewUserPromoConfig.fromJson(Map<String, dynamic> json) {
    return NewUserPromoConfig(
      isEnabled: json['isEnabled'] is bool ? json['isEnabled'] : false,
      promoId: json['promoId'] ?? 'NEW_USER_PROMO',
      promoCode: json['promoCode'] ?? 'NEWUSER',
      minOrderAmount: (json['minOrderAmount'] ?? 0.0).toDouble(),
      discount: (json['discount'] ?? 0.0).toDouble(),
      discountType: json['discountType'] ?? 'fixed',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': this.isEnabled,
      'promoId': this.promoId,
      'promoCode': this.promoCode,
      'minOrderAmount': this.minOrderAmount,
      'discount': this.discount,
      'discountType': this.discountType,
    };
  }

  static NewUserPromoConfig getDefault() {
    return NewUserPromoConfig(
      isEnabled: false,
      promoId: 'NEW_USER_PROMO',
      promoCode: 'NEWUSER',
      minOrderAmount: 0.0,
      discount: 0.0,
      discountType: 'fixed',
    );
  }
}

class NewUserPromoService {
  static const String settingsDocId = 'NEW_USER_PROMO';
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Get promo configuration (one-time fetch)
  static Future<NewUserPromoConfig> getNewUserPromoConfig() async {
    try {
      final doc = await firestore
          .collection(Setting)
          .doc(settingsDocId)
          .get();

      if (doc.exists && doc.data() != null) {
        return NewUserPromoConfig.fromJson(doc.data()!);
      } else {
        return NewUserPromoConfig.getDefault();
      }
    } catch (e) {
      print('Error getting new user promo config: $e');
      return NewUserPromoConfig.getDefault();
    }
  }

  /// Get promo configuration stream (for real-time updates)
  static Stream<NewUserPromoConfig> getNewUserPromoConfigStream() {
    return firestore
        .collection(Setting)
        .doc(settingsDocId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return NewUserPromoConfig.fromJson(snapshot.data()!);
      } else {
        return NewUserPromoConfig.getDefault();
      }
    });
  }

  /// Check if user is eligible for New User Promo
  static bool isEligible({
    required bool hasCompletedFirstOrder,
    required bool hasOrderedBefore,
  }) {
    return !hasCompletedFirstOrder && !hasOrderedBefore;
  }

  /// Calculate discount amount based on order subtotal
  static double calculateDiscount({
    required NewUserPromoConfig config,
    required double orderSubtotal,
  }) {
    if (!config.isEnabled || orderSubtotal < config.minOrderAmount) {
      return 0.0;
    }

    if (config.discountType.toLowerCase() == 'percentage') {
      return (orderSubtotal * config.discount / 100).clamp(0.0, orderSubtotal);
    } else {
      // Fixed discount
      return config.discount.clamp(0.0, orderSubtotal);
    }
  }
}

