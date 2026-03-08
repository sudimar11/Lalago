import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/model/LoyaltyData.dart';

class LoyaltyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _settingsCollection = 'settings';
  static const String _loyaltyConfigDoc = 'loyaltyConfig';
  static const String _usersCollection = 'users';

  /// Stream of loyalty data for a user.
  static Stream<LoyaltyData?> getLoyaltyStream(String userId) {
    return _firestore
        .collection(_usersCollection)
        .doc(userId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      final loyaltyJson = snap.data()!['loyalty'];
      if (loyaltyJson == null) return null;
      return LoyaltyData.fromJson(
        loyaltyJson as Map<String, dynamic>?,
      );
    });
  }

  /// One-time fetch of loyalty data.
  static Future<LoyaltyData?> getLoyalty(String userId) async {
    try {
      final doc = await _firestore
          .collection(_usersCollection)
          .doc(userId)
          .get();
      if (!doc.exists || doc.data() == null) return null;
      final loyaltyJson = doc.data()!['loyalty'];
      if (loyaltyJson == null) return null;
      return LoyaltyData.fromJson(
        loyaltyJson as Map<String, dynamic>?,
      );
    } catch (e) {
      log('LoyaltyService.getLoyalty error: $e');
      return null;
    }
  }

  /// Stream of loyalty config (enabled, tiers, benefits, etc.).
  static Stream<Map<String, dynamic>?> getLoyaltyConfigStream() {
    return _firestore
        .collection(_settingsCollection)
        .doc(_loyaltyConfigDoc)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return snap.data() as Map<String, dynamic>;
    });
  }

  /// One-time fetch of loyalty config.
  static Future<Map<String, dynamic>?> getLoyaltyConfig() async {
    try {
      final doc = await _firestore
          .collection(_settingsCollection)
          .doc(_loyaltyConfigDoc)
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data() as Map<String, dynamic>;
    } catch (e) {
      log('LoyaltyService.getLoyaltyConfig error: $e');
      return null;
    }
  }

  /// Check if loyalty program is enabled.
  static Future<bool> isLoyaltyEnabled() async {
    final config = await getLoyaltyConfig();
    return config?['enabled'] == true;
  }

  /// Get tokens needed to reach next tier from config.
  static int getTokensToNextTier(
    int tokensThisCycle,
    Map<String, dynamic>? config,
  ) {
    if (config == null) return 0;
    final tiers = config['tiers'] as Map<String, dynamic>?;
    if (tiers == null) return 0;

    const order = ['bronze', 'silver', 'gold', 'diamond'];
    String currentTier = 'bronze';
    for (final t in order) {
      final tc = tiers[t] as Map<String, dynamic>?;
      if (tc == null) continue;
      final min = (tc['minTokens'] as num?)?.toInt() ?? 0;
      final max = tc['maxTokens'];
      final maxVal = max == null
          ? 999
          : (max is num ? max.toInt() : int.tryParse(max.toString()) ?? 999);
      if (tokensThisCycle >= min && tokensThisCycle <= maxVal) {
        currentTier = t;
        break;
      }
    }

    final currentIdx = order.indexOf(currentTier);
    if (currentIdx < 0 || currentIdx >= order.length - 1) return 0;

    final nextTier = order[currentIdx + 1];
    final nextConfig = tiers[nextTier] as Map<String, dynamic>?;
    if (nextConfig == null) return 0;

    final minForNext = (nextConfig['minTokens'] as num?)?.toInt() ?? 0;
    return (minForNext - tokensThisCycle).clamp(0, 999);
  }

  /// Get next tier name from config.
  static String? getNextTierName(
    int tokensThisCycle,
    Map<String, dynamic>? config,
  ) {
    if (config == null) return null;
    final tiers = config['tiers'] as Map<String, dynamic>?;
    if (tiers == null) return null;

    const order = ['bronze', 'silver', 'gold', 'diamond'];
    String currentTier = 'bronze';
    for (final t in order) {
      final tc = tiers[t] as Map<String, dynamic>?;
      if (tc == null) continue;
      final min = (tc['minTokens'] as num?)?.toInt() ?? 0;
      final max = tc['maxTokens'];
      final maxVal = max == null
          ? 999
          : (max is num ? max.toInt() : int.tryParse(max.toString()) ?? 999);
      if (tokensThisCycle >= min && tokensThisCycle <= maxVal) {
        currentTier = t;
        break;
      }
    }

    final currentIdx = order.indexOf(currentTier);
    if (currentIdx < 0 || currentIdx >= order.length - 1) return null;

    return order[currentIdx + 1];
  }

  /// Progress (0.0 to 1.0) to next tier.
  static double getProgressToNextTier(
    int tokensThisCycle,
    Map<String, dynamic>? config,
  ) {
    final tokensNeeded = getTokensToNextTier(tokensThisCycle, config);
    if (tokensNeeded <= 0) return 1.0;

    final nextTier = getNextTierName(tokensThisCycle, config);
    if (nextTier == null) return 1.0;

    final tiers = config?['tiers'] as Map<String, dynamic>?;
    final nextConfig = tiers?[nextTier] as Map<String, dynamic>?;
    if (nextConfig == null) return 0.0;

    final minForNext = (nextConfig['minTokens'] as num?)?.toInt() ?? 0;
    final currentTier = _getCurrentTierFromTokens(tokensThisCycle, config);
    final minCurrent = _getMinTokensForTier(currentTier, config);
    final range = minForNext - minCurrent;
    if (range <= 0) return 1.0;
    final progress = (tokensThisCycle - minCurrent) / range;
    return progress.clamp(0.0, 1.0);
  }

  static String _getCurrentTierFromTokens(
    int tokens,
    Map<String, dynamic>? config,
  ) {
    if (config == null) return 'bronze';
    final tiers = config['tiers'] as Map<String, dynamic>?;
    if (tiers == null) return 'bronze';

    const order = ['diamond', 'gold', 'silver', 'bronze'];
    for (final t in order) {
      final tc = tiers[t] as Map<String, dynamic>?;
      if (tc == null) continue;
      final min = (tc['minTokens'] as num?)?.toInt() ?? 0;
      final max = tc['maxTokens'];
      final maxVal = max == null
          ? 999
          : (max is num ? max.toInt() : int.tryParse(max.toString()) ?? 999);
      if (tokens >= min && tokens <= maxVal) return t;
    }
    return 'bronze';
  }

  static int _getMinTokensForTier(
    String tier,
    Map<String, dynamic>? config,
  ) {
    if (config == null) return 0;
    final tiers = config['tiers'] as Map<String, dynamic>?;
    final tc = tiers?[tier] as Map<String, dynamic>?;
    if (tc == null) return 0;
    return (tc['minTokens'] as num?)?.toInt() ?? 0;
  }
}
