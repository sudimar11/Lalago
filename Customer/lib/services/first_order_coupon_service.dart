import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';

class FirstOrderCouponConfig {
  final bool isEnabled;
  final String couponId;
  final String couponCode;
  final double minOrderAmount;
  final double discount;
  final String discountType; // "Percentage" or "fixed"
  final Timestamp? validFrom;
  final Timestamp? validTo;

  FirstOrderCouponConfig({
    required this.isEnabled,
    required this.couponId,
    required this.couponCode,
    required this.minOrderAmount,
    required this.discount,
    required this.discountType,
    this.validFrom,
    this.validTo,
  });

  factory FirstOrderCouponConfig.fromJson(Map<String, dynamic> json) {
    Timestamp? validFrom;
    Timestamp? validTo;

    if (json['validFrom'] != null) {
      if (json['validFrom'] is Timestamp) {
        validFrom = json['validFrom'] as Timestamp;
      }
    }

    if (json['validTo'] != null) {
      if (json['validTo'] is Timestamp) {
        validTo = json['validTo'] as Timestamp;
      }
    }

    return FirstOrderCouponConfig(
      isEnabled: (json['isEnabled'] ?? json['enabled'] ?? false) is bool
          ? (json['isEnabled'] ?? json['enabled'] ?? false) as bool
          : false,
      couponId: json['couponId'] ?? 'FIRST_ORDER_AUTO',
      couponCode: json['couponCode'] ?? 'FIRSTORDER',
      minOrderAmount: (json['minOrderAmount'] ?? 0.0).toDouble(),
      discount: (json['discount'] ?? json['discountValue'] ?? 0.0).toDouble(),
      discountType: json['discountType'] ?? 'fixed',
      validFrom: validFrom,
      validTo: validTo,
    );
  }

  bool get isValidDateRange {
    if (validFrom == null && validTo == null) return true;
    final now = Timestamp.now();
    if (validFrom != null && now.compareTo(validFrom!) < 0) return false;
    if (validTo != null && now.compareTo(validTo!) > 0) return false;
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': this.isEnabled,
      'couponId': this.couponId,
      'couponCode': this.couponCode,
      'minOrderAmount': this.minOrderAmount,
      'discount': this.discount,
      'discountType': this.discountType,
    };
  }

  static FirstOrderCouponConfig getDefault() {
    return FirstOrderCouponConfig(
      isEnabled: false,
      couponId: 'FIRST_ORDER_AUTO',
      couponCode: 'FIRSTORDER',
      minOrderAmount: 0.0,
      discount: 0.0,
      discountType: 'fixed',
      validFrom: null,
      validTo: null,
    );
  }
}

class FirstOrderCouponService {
  static const String settingsDocId = 'FIRST_ORDER_AUTO';
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Get coupon configuration (one-time fetch)
  static Future<FirstOrderCouponConfig> getFirstOrderCouponConfig() async {
    try {
      final doc = await firestore.collection(Setting).doc(settingsDocId).get();

      if (doc.exists && doc.data() != null) {
        return FirstOrderCouponConfig.fromJson(doc.data()!);
      } else {
        return FirstOrderCouponConfig.getDefault();
      }
    } catch (e) {
      print('Error getting first-order coupon config: $e');
      return FirstOrderCouponConfig.getDefault();
    }
  }

  /// Get coupon configuration stream (for real-time updates)
  static Stream<FirstOrderCouponConfig> getFirstOrderCouponConfigStream() {
    return firestore
        .collection(Setting)
        .doc(settingsDocId)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return FirstOrderCouponConfig.fromJson(snapshot.data()!);
      } else {
        return FirstOrderCouponConfig.getDefault();
      }
    });
  }
}
