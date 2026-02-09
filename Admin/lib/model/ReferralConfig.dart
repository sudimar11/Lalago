import 'package:cloud_firestore/cloud_firestore.dart';

class ReferralConfig {
  bool enabled;
  double rewardAmount;
  double minOrderAmount;
  Timestamp updatedAt;

  ReferralConfig({
    this.enabled = false,
    required this.rewardAmount,
    required this.minOrderAmount,
    Timestamp? updatedAt,
  }) : updatedAt = updatedAt ?? Timestamp.now();

  factory ReferralConfig.fromJson(Map<String, dynamic> json) {
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

    return ReferralConfig(
      enabled: json['enabled'] ?? false,
      rewardAmount: (json['rewardAmount'] is num)
          ? (json['rewardAmount'] as num).toDouble()
          : double.tryParse(json['rewardAmount']?.toString() ?? '0') ?? 0.0,
      minOrderAmount: (json['minOrderAmount'] is num)
          ? (json['minOrderAmount'] as num).toDouble()
          : double.tryParse(json['minOrderAmount']?.toString() ?? '0') ?? 0.0,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'rewardAmount': rewardAmount,
      'minOrderAmount': minOrderAmount,
      'updatedAt': updatedAt,
    };
  }

  // Validation methods
  bool isValid() {
    if (rewardAmount <= 0) return false;
    if (minOrderAmount < 0) return false;
    return true;
  }
}

