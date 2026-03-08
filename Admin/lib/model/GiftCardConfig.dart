import 'package:cloud_firestore/cloud_firestore.dart';

class GiftCardConfig {
  bool enabled;
  List<int> denominations;
  bool allowCustomAmount;
  int customAmountMin;
  int customAmountMax;
  int validityDays;
  List<String> deliveryMethods;
  bool allowSelfPurchase;
  bool allowGiftPurchase;
  bool canCombineWithOtherPayments;
  int maxPerTransaction;
  bool earnLoyaltyTokens;
  List<int> expiryNotificationDays;
  Timestamp? updatedAt;

  GiftCardConfig({
    this.enabled = true,
    List<int>? denominations,
    this.allowCustomAmount = true,
    this.customAmountMin = 50,
    this.customAmountMax = 10000,
    this.validityDays = 365,
    List<String>? deliveryMethods,
    this.allowSelfPurchase = true,
    this.allowGiftPurchase = true,
    this.canCombineWithOtherPayments = true,
    this.maxPerTransaction = 5,
    this.earnLoyaltyTokens = true,
    List<int>? expiryNotificationDays,
    this.updatedAt,
  })  : denominations = denominations ?? [100, 250, 500, 1000],
        deliveryMethods =
            deliveryMethods ?? ['email', 'sms', 'direct'],
        expiryNotificationDays =
            expiryNotificationDays ?? [30, 7, 1];

  factory GiftCardConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) {
      return GiftCardConfig();
    }
    List<int> denomList = [];
    if (json['denominations'] is List) {
      for (final e in json['denominations'] as List) {
        final n = e is num ? e.toInt() : int.tryParse(e.toString());
        if (n != null) denomList.add(n);
      }
    }
    if (denomList.isEmpty) denomList = [100, 250, 500, 1000];

    List<String> dmList = [];
    if (json['deliveryMethods'] is List) {
      for (final e in json['deliveryMethods'] as List) {
        dmList.add(e.toString());
      }
    }
    if (dmList.isEmpty) dmList = ['email', 'sms', 'direct'];

    List<int> expList = [];
    if (json['expiryNotificationDays'] is List) {
      for (final e in json['expiryNotificationDays'] as List) {
        final n = e is num ? e.toInt() : int.tryParse(e.toString());
        if (n != null) expList.add(n);
      }
    }
    if (expList.isEmpty) expList = [30, 7, 1];

    return GiftCardConfig(
      enabled: json['enabled'] == true,
      denominations: denomList,
      allowCustomAmount: json['allowCustomAmount'] != false,
      customAmountMin: (json['customAmountMin'] is num)
          ? (json['customAmountMin'] as num).toInt()
          : int.tryParse(json['customAmountMin']?.toString() ?? '50') ?? 50,
      customAmountMax: (json['customAmountMax'] is num)
          ? (json['customAmountMax'] as num).toInt()
          : int.tryParse(json['customAmountMax']?.toString() ?? '10000') ?? 10000,
      validityDays: (json['validityDays'] is num)
          ? (json['validityDays'] as num).toInt()
          : int.tryParse(json['validityDays']?.toString() ?? '365') ?? 365,
      deliveryMethods: dmList,
      allowSelfPurchase: json['allowSelfPurchase'] != false,
      allowGiftPurchase: json['allowGiftPurchase'] != false,
      canCombineWithOtherPayments:
          json['canCombineWithOtherPayments'] != false,
      maxPerTransaction: (json['maxPerTransaction'] is num)
          ? (json['maxPerTransaction'] as num).toInt()
          : int.tryParse(json['maxPerTransaction']?.toString() ?? '5') ?? 5,
      earnLoyaltyTokens: json['earnLoyaltyTokens'] != false,
      expiryNotificationDays: expList,
      updatedAt: json['updatedAt'] is Timestamp
          ? json['updatedAt'] as Timestamp
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'denominations': denominations,
      'allowCustomAmount': allowCustomAmount,
      'customAmountMin': customAmountMin,
      'customAmountMax': customAmountMax,
      'validityDays': validityDays,
      'deliveryMethods': deliveryMethods,
      'allowSelfPurchase': allowSelfPurchase,
      'allowGiftPurchase': allowGiftPurchase,
      'canCombineWithOtherPayments': canCombineWithOtherPayments,
      'maxPerTransaction': maxPerTransaction,
      'earnLoyaltyTokens': earnLoyaltyTokens,
      'expiryNotificationDays': expiryNotificationDays,
      'updatedAt': updatedAt ?? Timestamp.now(),
    };
  }
}
