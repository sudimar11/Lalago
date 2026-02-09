/// Prior coupon usage configuration
class PriorCouponUsage {
  final String type; // "none" | "this_coupon" | "any_coupon"
  final bool allowed; // true = must have used, false = must NOT have used

  PriorCouponUsage({
    required this.type,
    required this.allowed,
  });

  factory PriorCouponUsage.fromJson(Map<String, dynamic> json) {
    return PriorCouponUsage(
      type: json['type'] ?? 'none',
      allowed: json['allowed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'allowed': allowed,
    };
  }

  bool isValid() {
    return ['none', 'this_coupon', 'any_coupon'].contains(type);
  }
}

/// Eligibility rules for coupon access
class CouponEligibilityRules {
  final List<String>? userCategories; // ["new_user", "regular_customer", "vip"]
  final int? minCompletedOrders;
  final bool? firstTimeUserOnly;
  final PriorCouponUsage? priorCouponUsage;
  final List<String>? userIds; // Specific user ID whitelist

  CouponEligibilityRules({
    this.userCategories,
    this.minCompletedOrders,
    this.firstTimeUserOnly,
    this.priorCouponUsage,
    this.userIds,
  });

  factory CouponEligibilityRules.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return CouponEligibilityRules();
    }

    List<String>? userCategoriesList;
    if (json['userCategories'] != null) {
      userCategoriesList = List<String>.from(json['userCategories']);
    }

    List<String>? userIdsList;
    if (json['userIds'] != null) {
      userIdsList = List<String>.from(json['userIds']);
    }

    PriorCouponUsage? priorUsage;
    if (json['priorCouponUsage'] != null) {
      priorUsage = PriorCouponUsage.fromJson(
        json['priorCouponUsage'] as Map<String, dynamic>,
      );
    }

    return CouponEligibilityRules(
      userCategories: userCategoriesList,
      minCompletedOrders: json['minCompletedOrders'] != null
          ? (json['minCompletedOrders'] is int
              ? json['minCompletedOrders'] as int
              : int.tryParse(json['minCompletedOrders'].toString()))
          : null,
      firstTimeUserOnly: json['firstTimeUserOnly'] as bool?,
      priorCouponUsage: priorUsage,
      userIds: userIdsList,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    if (userCategories != null && userCategories!.isNotEmpty) {
      json['userCategories'] = userCategories;
    }

    if (minCompletedOrders != null) {
      json['minCompletedOrders'] = minCompletedOrders;
    }

    if (firstTimeUserOnly != null) {
      json['firstTimeUserOnly'] = firstTimeUserOnly;
    }

    if (priorCouponUsage != null) {
      json['priorCouponUsage'] = priorCouponUsage!.toJson();
    }

    if (userIds != null && userIds!.isNotEmpty) {
      json['userIds'] = userIds;
    }

    return json;
  }

  /// Check if any eligibility rules are configured
  bool get hasRules {
    return (userCategories != null && userCategories!.isNotEmpty) ||
        minCompletedOrders != null ||
        firstTimeUserOnly == true ||
        (priorCouponUsage != null &&
            priorCouponUsage!.type != 'none') ||
        (userIds != null && userIds!.isNotEmpty);
  }

  /// Validate the eligibility rules for logical consistency
  bool isValid() {
    // Can't require min orders AND first-time user only
    if (firstTimeUserOnly == true && minCompletedOrders != null) {
      return false;
    }

    // Validate prior coupon usage if present
    if (priorCouponUsage != null && !priorCouponUsage!.isValid()) {
      return false;
    }

    // Validate user categories if present
    if (userCategories != null) {
      final validCategories = ['new_user', 'regular_customer', 'vip'];
      for (final category in userCategories!) {
        if (!validCategories.contains(category)) {
          return false;
        }
      }
    }

    // Validate min completed orders
    if (minCompletedOrders != null && minCompletedOrders! < 0) {
      return false;
    }

    return true;
  }
}

