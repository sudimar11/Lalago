import 'package:cloud_firestore/cloud_firestore.dart';

class LoyaltyConfig {
  bool enabled;
  int tokensPerOrder;
  Map<String, dynamic> cycles;
  Map<String, dynamic> tiers;
  Map<String, dynamic> benefits;
  Timestamp? updatedAt;

  LoyaltyConfig({
    this.enabled = false,
    this.tokensPerOrder = 1,
    Map<String, dynamic>? cycles,
    Map<String, dynamic>? tiers,
    Map<String, dynamic>? benefits,
    this.updatedAt,
  })  : cycles = cycles ?? _defaultCycles,
        tiers = tiers ?? _defaultTiers,
        benefits = benefits ?? _defaultBenefits;

  static final Map<String, dynamic> _defaultCycles = {
    'durationMonths': 3,
    'startMonths': [1, 4, 7, 10],
    'timezone': 'Asia/Manila',
  };

  static final Map<String, dynamic> _defaultTiers = {
    'bronze': {'minTokens': 0, 'maxTokens': 4},
    'silver': {'minTokens': 5, 'maxTokens': 9},
    'gold': {'minTokens': 10, 'maxTokens': 14},
    'diamond': {'minTokens': 15, 'maxTokens': null},
  };

  static final Map<String, dynamic> _defaultBenefits = {
    'silver': [
      {'type': 'free_delivery', 'description': 'Free delivery on next order'},
    ],
    'gold': [
      {'type': 'wallet_credit', 'amount': 50, 'description': '₱50 wallet credit'},
      {'type': 'inherits', 'from': 'silver'},
    ],
    'diamond': [
      {'type': 'wallet_credit', 'amount': 100, 'description': '₱100 wallet credit'},
      {'type': 'badge', 'name': 'VIP', 'description': 'VIP customer badge'},
      {'type': 'inherits', 'from': 'gold'},
    ],
  };

  factory LoyaltyConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return LoyaltyConfig();
    }
    return LoyaltyConfig(
      enabled: json['enabled'] == true,
      tokensPerOrder: (json['tokensPerOrder'] is num)
          ? (json['tokensPerOrder'] as num).toInt()
          : int.tryParse(json['tokensPerOrder']?.toString() ?? '1') ?? 1,
      cycles: json['cycles'] is Map
          ? Map<String, dynamic>.from(json['cycles'] as Map)
          : _defaultCycles,
      tiers: json['tiers'] is Map
          ? Map<String, dynamic>.from(json['tiers'] as Map)
          : _defaultTiers,
      benefits: json['benefits'] is Map
          ? Map<String, dynamic>.from(json['benefits'] as Map)
          : _defaultBenefits,
      updatedAt: json['updatedAt'] is Timestamp
          ? json['updatedAt'] as Timestamp
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'tokensPerOrder': tokensPerOrder,
      'cycles': cycles,
      'tiers': tiers,
      'benefits': benefits,
      'updatedAt': updatedAt ?? Timestamp.now(),
    };
  }
}
