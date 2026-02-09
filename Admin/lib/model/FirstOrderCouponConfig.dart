import 'package:cloud_firestore/cloud_firestore.dart';

class FirstOrderCouponConfig {
  bool enabled;
  String discountType; // "fixed_amount" | "percentage"
  double discountValue;
  double minOrderAmount;
  Timestamp validFrom;
  Timestamp validTo;
  Timestamp updatedAt;

  FirstOrderCouponConfig({
    this.enabled = false,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.validFrom,
    required this.validTo,
    Timestamp? updatedAt,
  }) : updatedAt = updatedAt ?? Timestamp.now();

  factory FirstOrderCouponConfig.fromJson(Map<String, dynamic> json) {
    Timestamp validFrom;
    if (json['validFrom'] != null) {
      if (json['validFrom'] is Timestamp) {
        validFrom = json['validFrom'] as Timestamp;
      } else if (json['validFrom'] is Map) {
        validFrom = Timestamp(
          json['validFrom']['_seconds'] ?? 0,
          json['validFrom']['_nanoseconds'] ?? 0,
        );
      } else {
        validFrom = Timestamp.now();
      }
    } else {
      validFrom = Timestamp.now();
    }

    Timestamp validTo;
    if (json['validTo'] != null) {
      if (json['validTo'] is Timestamp) {
        validTo = json['validTo'] as Timestamp;
      } else if (json['validTo'] is Map) {
        validTo = Timestamp(
          json['validTo']['_seconds'] ?? 0,
          json['validTo']['_nanoseconds'] ?? 0,
        );
      } else {
        // Default to 1 year from now
        final oneYearLater = DateTime.now().add(const Duration(days: 365));
        validTo = Timestamp.fromDate(oneYearLater);
      }
    } else {
      final oneYearLater = DateTime.now().add(const Duration(days: 365));
      validTo = Timestamp.fromDate(oneYearLater);
    }

    Timestamp updatedAt;
    if (json['updatedAt'] != null) {
      if (json['updatedAt'] is Timestamp) {
        updatedAt = json['updatedAt'] as Timestamp;
      } else if (json['updatedAt'] is Map) {
        updatedAt = Timestamp(
          json['updatedAt']['_seconds'] ?? 0,
          json['updatedAt']['_nanoseconds'] ?? 0,
        );
      } else {
        updatedAt = Timestamp.now();
      }
    } else {
      updatedAt = Timestamp.now();
    }

    return FirstOrderCouponConfig(
      enabled: json['enabled'] ?? false,
      discountType: json['discountType'] ?? 'fixed_amount',
      discountValue: (json['discountValue'] is num)
          ? (json['discountValue'] as num).toDouble()
          : double.tryParse(json['discountValue']?.toString() ?? '0') ?? 0.0,
      minOrderAmount: (json['minOrderAmount'] is num)
          ? (json['minOrderAmount'] as num).toDouble()
          : double.tryParse(json['minOrderAmount']?.toString() ?? '0') ?? 0.0,
      validFrom: validFrom,
      validTo: validTo,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'discountType': discountType,
      'discountValue': discountValue,
      'minOrderAmount': minOrderAmount,
      'validFrom': validFrom,
      'validTo': validTo,
      'updatedAt': updatedAt,
    };
  }

  // Validation methods
  bool isValid() {
    if (discountValue <= 0) return false;
    if (minOrderAmount < 0) return false;
    if (!['fixed_amount', 'percentage'].contains(discountType)) {
      return false;
    }
    if (discountType == 'percentage' &&
        (discountValue < 0 || discountValue > 100)) {
      return false;
    }
    if (validTo.toDate().isBefore(validFrom.toDate())) {
      return false;
    }
    return true;
  }

  String get discountTypeDisplay {
    switch (discountType) {
      case 'fixed_amount':
        return 'Fixed Amount';
      case 'percentage':
        return 'Percentage';
      default:
        return discountType;
    }
  }

  bool get isCurrentlyValid {
    final now = DateTime.now();
    final from = validFrom.toDate();
    final to = validTo.toDate();
    return enabled && now.isAfter(from) && now.isBefore(to);
  }
}

