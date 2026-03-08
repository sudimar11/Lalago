import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class GiftCardConfig {
  bool enabled;
  List<int> denominations;
  bool allowCustomAmount;
  int customAmountMin;
  int customAmountMax;
  int validityDays;
  bool allowGiftPurchase;

  GiftCardConfig({
    this.enabled = true,
    List<int>? denominations,
    this.allowCustomAmount = true,
    this.customAmountMin = 50,
    this.customAmountMax = 10000,
    this.validityDays = 365,
    this.allowGiftPurchase = true,
  }) : denominations = denominations ?? [100, 250, 500, 1000];

  factory GiftCardConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return GiftCardConfig();
    List<int> denomList = [];
    if (json['denominations'] is List) {
      for (final e in json['denominations'] as List) {
        final n = e is num ? e.toInt() : int.tryParse(e.toString());
        if (n != null) denomList.add(n);
      }
    }
    if (denomList.isEmpty) denomList = [100, 250, 500, 1000];
    return GiftCardConfig(
      enabled: json['enabled'] == true,
      denominations: denomList,
      allowCustomAmount: json['allowCustomAmount'] != false,
      customAmountMin: (json['customAmountMin'] is num)
          ? (json['customAmountMin'] as num).toInt()
          : int.tryParse(json['customAmountMin']?.toString() ?? '50') ?? 50,
      customAmountMax: (json['customAmountMax'] is num)
          ? (json['customAmountMax'] as num).toInt()
          : int.tryParse(json['customAmountMax']?.toString() ?? '10000') ??
              10000,
      validityDays: (json['validityDays'] is num)
          ? (json['validityDays'] as num).toInt()
          : int.tryParse(json['validityDays']?.toString() ?? '365') ?? 365,
      allowGiftPurchase: json['allowGiftPurchase'] != false,
    );
  }
}

class GiftCardService {
  static final _firestore = FirebaseFirestore.instance;

  static Stream<GiftCardConfig> getConfigStream() {
    return _firestore
        .collection('settings')
        .doc('giftCardConfig')
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return GiftCardConfig();
      return GiftCardConfig.fromJson(snap.data());
    });
  }

  static Future<GiftCardConfig> getConfig() async {
    final snap = await _firestore
        .collection('settings')
        .doc('giftCardConfig')
        .get();
    if (!snap.exists || snap.data() == null) {
      return GiftCardConfig();
    }
    return GiftCardConfig.fromJson(snap.data());
  }

  static Future<Map<String, dynamic>> createGiftCard({
    required double amount,
    String? giftMessage,
    String deliveryMethod = 'direct',
    String designTemplate = 'celebration',
    String? recipientEmail,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('createGiftCard');
    final result = await callable.call({
      'amount': amount,
      if (giftMessage != null && giftMessage.isNotEmpty) 'giftMessage': giftMessage,
      'deliveryMethod': deliveryMethod,
      'designTemplate': designTemplate,
      if (recipientEmail != null && recipientEmail.isNotEmpty) 'recipientEmail': recipientEmail,
    });
    final data = result.data as Map<String, dynamic>?;
    if (data == null) throw Exception('No response from createGiftCard');
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> validateGiftCard(String code) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('validateGiftCard');
    final result = await callable.call({'code': code.trim().toUpperCase()});
    final data = result.data as Map<String, dynamic>?;
    if (data == null) return {'valid': false, 'error': 'Invalid response'};
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>> getUserActiveGiftCards(
    String userId,
  ) async {
    final now = DateTime.now();
    final snap = await _firestore
        .collection('gift_cards')
        .where('ownedBy', isEqualTo: userId)
        .where('status', isEqualTo: 'active')
        .get();

    final list = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['code'] == null) continue;
      final balance = (d['remainingBalance'] as num?)?.toDouble() ?? 0;
      if (balance <= 0) continue;
      final expiresAt = d['expiresAt'];
      if (expiresAt != null && expiresAt is Timestamp) {
        if (expiresAt.toDate().isBefore(now)) continue;
      }
      final code = d['code'] as String;
      final masked = code.length > 8
          ? '${code.substring(0, 4)}****${code.substring(code.length - 4)}'
          : code;
      list.add({
        'cardId': doc.id,
        'code': code,
        'maskedCode': masked,
        'remainingBalance': balance,
      });
    }
    return list;
  }

  static Future<List<Map<String, dynamic>>> getUserGiftCards(
    String userId,
  ) async {
    final owned = await _firestore
        .collection('gift_cards')
        .where('ownedBy', isEqualTo: userId)
        .get();
    final purchased = await _firestore
        .collection('gift_cards')
        .where('purchasedBy', isEqualTo: userId)
        .get();

    final seen = <String>{};
    final list = <Map<String, dynamic>>[];
    for (final snap in [owned, purchased]) {
      for (final doc in snap.docs) {
        if (seen.contains(doc.id)) continue;
        final d = doc.data();
        if (d['code'] == null) continue;
        seen.add(doc.id);
        list.add({
          'id': doc.id,
          'code': d['code'],
          'originalAmount': (d['originalAmount'] as num?)?.toDouble() ?? 0,
          'remainingBalance': (d['remainingBalance'] as num?)?.toDouble() ?? 0,
          'status': d['status'] ?? 'active',
          'purchasedAt': d['purchasedAt'],
          'expiresAt': d['expiresAt'],
          'source': 'new',
        });
      }
    }
    return list;
  }

  static Future<Map<String, dynamic>> claimGiftCard(String code) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('claimGiftCard');
    final result = await callable.call({'code': code.trim().toUpperCase()});
    final data = result.data as Map<String, dynamic>?;
    if (data == null) throw Exception('No response from claimGiftCard');
    return Map<String, dynamic>.from(data);
  }

  static Future<Map<String, dynamic>> redeemGiftCard({
    required String cardId,
    required double amount,
    required String userId,
    String? orderId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('redeemGiftCard');
    final result = await callable.call({
      'cardId': cardId,
      'amount': amount,
      'userId': userId,
      if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
    });
    final data = result.data as Map<String, dynamic>?;
    if (data == null) throw Exception('No response from redeemGiftCard');
    return Map<String, dynamic>.from(data);
  }
}
