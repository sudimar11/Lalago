import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/coupon_eligibility_rules.dart';

class Coupon {
  String id;
  String code;
  String title;
  String shortDescription;
  String discountType; // "fixed_amount" | "percentage"
  double discountValue;
  double minOrderAmount;
  int? minItems; // Minimum number of items required
  Timestamp validFrom;
  Timestamp validTo;
  int? maxUsagePerUser; // null means unlimited
  int? globalUsageLimit; // null means unlimited
  String? imageUrl;
  bool isEnabled;
  bool isDeleted;
  Timestamp createdAt;
  Timestamp updatedAt;
  CouponEligibilityRules? eligibilityRules;

  Coupon({
    required this.id,
    required this.code,
    required this.title,
    required this.shortDescription,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    this.minItems,
    required this.validFrom,
    required this.validTo,
    this.maxUsagePerUser,
    this.globalUsageLimit,
    this.imageUrl,
    this.isEnabled = true,
    this.isDeleted = false,
    Timestamp? createdAt,
    Timestamp? updatedAt,
    this.eligibilityRules,
  })  : createdAt = createdAt ?? Timestamp.now(),
        updatedAt = updatedAt ?? Timestamp.now();

  factory Coupon.fromJson(Map<String, dynamic> json, String docId) {
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
        final oneYearLater = DateTime.now().add(const Duration(days: 365));
        validTo = Timestamp.fromDate(oneYearLater);
      }
    } else {
      final oneYearLater = DateTime.now().add(const Duration(days: 365));
      validTo = Timestamp.fromDate(oneYearLater);
    }

    Timestamp createdAt;
    if (json['createdAt'] != null) {
      if (json['createdAt'] is Timestamp) {
        createdAt = json['createdAt'] as Timestamp;
      } else if (json['createdAt'] is Map) {
        createdAt = Timestamp(
          json['createdAt']['_seconds'] ?? 0,
          json['createdAt']['_nanoseconds'] ?? 0,
        );
      } else {
        createdAt = Timestamp.now();
      }
    } else {
      createdAt = Timestamp.now();
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

    return Coupon(
      id: docId,
      code: json['code'] ?? '',
      title: json['title'] ?? '',
      shortDescription: json['shortDescription'] ?? '',
      discountType: json['discountType'] ?? 'fixed_amount',
      discountValue: (json['discountValue'] is num)
          ? (json['discountValue'] as num).toDouble()
          : double.tryParse(json['discountValue']?.toString() ?? '0') ?? 0.0,
      minOrderAmount: (json['minOrderAmount'] is num)
          ? (json['minOrderAmount'] as num).toDouble()
          : double.tryParse(json['minOrderAmount']?.toString() ?? '0') ?? 0.0,
      minItems: json['minItems'] != null
          ? (json['minItems'] is int
              ? json['minItems'] as int
              : int.tryParse(json['minItems'].toString()))
          : null,
      validFrom: validFrom,
      validTo: validTo,
      maxUsagePerUser: json['maxUsagePerUser'] != null
          ? (json['maxUsagePerUser'] is num
              ? (json['maxUsagePerUser'] as num).toInt()
              : int.tryParse(json['maxUsagePerUser']?.toString() ?? '0'))
          : null,
      globalUsageLimit: json['globalUsageLimit'] != null
          ? (json['globalUsageLimit'] is num
              ? (json['globalUsageLimit'] as num).toInt()
              : int.tryParse(json['globalUsageLimit']?.toString() ?? '0'))
          : null,
      imageUrl: json['imageUrl'],
      isEnabled: json['isEnabled'] ?? true,
      isDeleted: json['isDeleted'] ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
      eligibilityRules: CouponEligibilityRules.fromJson(
        json['eligibilityRules'] as Map<String, dynamic>?,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'title': title,
      'shortDescription': shortDescription,
      'discountType': discountType,
      'discountValue': discountValue,
      'minOrderAmount': minOrderAmount,
      'minItems': minItems,
      'validFrom': validFrom,
      'validTo': validTo,
      'maxUsagePerUser': maxUsagePerUser,
      'globalUsageLimit': globalUsageLimit,
      'imageUrl': imageUrl,
      'isEnabled': isEnabled,
      'isDeleted': isDeleted,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (eligibilityRules != null && eligibilityRules!.hasRules)
        'eligibilityRules': eligibilityRules!.toJson(),
    };
  }

  // Validation methods
  bool isValid() {
    if (code.trim().isEmpty) return false;
    if (title.trim().isEmpty) return false;
    if (shortDescription.trim().isEmpty) return false;
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
    if (maxUsagePerUser != null && maxUsagePerUser! < 0) {
      return false;
    }
    if (globalUsageLimit != null && globalUsageLimit! < 0) {
      return false;
    }
    // Validate minItems if provided (must be positive integer >= 1)
    if (minItems != null && minItems! < 1) {
      return false;
    }
    // Validate eligibility rules if present
    if (eligibilityRules != null && !eligibilityRules!.isValid()) {
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
    return isEnabled &&
        !isDeleted &&
        now.isAfter(from) &&
        now.isBefore(to);
  }

  bool get isExpired {
    final now = DateTime.now();
    final to = validTo.toDate();
    return now.isAfter(to);
  }

  bool get isNotYetActive {
    final now = DateTime.now();
    final from = validFrom.toDate();
    return now.isBefore(from);
  }
}

