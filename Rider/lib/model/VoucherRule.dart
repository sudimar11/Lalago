class VoucherRule {
  final int minDeliveries;
  final int maxDeliveries;
  final double voucherAmount;

  VoucherRule({
    required this.minDeliveries,
    required this.maxDeliveries,
    required this.voucherAmount,
  });

  factory VoucherRule.fromJson(Map<String, dynamic> json) {
    return VoucherRule(
      minDeliveries: json['minDeliveries'] ?? 0,
      maxDeliveries: json['maxDeliveries'] ?? 0,
      voucherAmount: (json['voucherAmount'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'minDeliveries': minDeliveries,
      'maxDeliveries': maxDeliveries,
      'voucherAmount': voucherAmount,
    };
  }

  /// Check if a delivery count falls within this rule's range
  bool appliesToDeliveryCount(int deliveryCount) {
    return deliveryCount >= minDeliveries && deliveryCount <= maxDeliveries;
  }
}

class DriverIncentiveRules {
  final bool active;
  final int attendanceWindow;
  final List<VoucherRule> voucherRules;

  DriverIncentiveRules({
    required this.active,
    required this.attendanceWindow,
    required this.voucherRules,
  });

  factory DriverIncentiveRules.fromJson(Map<String, dynamic> json) {
    List<VoucherRule> rules = [];
    if (json['voucherRules'] != null) {
      final voucherRulesData = json['voucherRules'];

      if (voucherRulesData is List) {
        // Handle array format
        rules =
            voucherRulesData.map((rule) => VoucherRule.fromJson(rule)).toList();
      } else if (voucherRulesData is Map) {
        // Handle map format (Firebase console style)
        rules = voucherRulesData.values
            .map((rule) => VoucherRule.fromJson(rule))
            .toList();
      }
    }

    return DriverIncentiveRules(
      active: json['active'] ?? false,
      attendanceWindow: json['attendanceWindow'] ?? 6,
      voucherRules: rules,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'active': active,
      'attendanceWindow': attendanceWindow,
      'voucherRules': voucherRules.map((rule) => rule.toJson()).toList(),
    };
  }

  /// Find the appropriate voucher rule for a given delivery count
  VoucherRule? getVoucherRuleForDeliveryCount(int deliveryCount) {
    for (var rule in voucherRules) {
      if (rule.appliesToDeliveryCount(deliveryCount)) {
        return rule;
      }
    }
    return null;
  }
}
