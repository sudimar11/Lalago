import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PerformanceTierConfig {
  final double goldThreshold;
  final double silverThreshold;
  final double bronzeThreshold;

  const PerformanceTierConfig({
    this.goldThreshold = 90.0,
    this.silverThreshold = 75.0,
    this.bronzeThreshold = 60.0,
  });

  factory PerformanceTierConfig.fromMap(Map<String, dynamic> map) {
    return PerformanceTierConfig(
      goldThreshold:
          (map['gold_threshold'] as num?)?.toDouble() ?? 90.0,
      silverThreshold:
          (map['silver_threshold'] as num?)?.toDouble() ?? 75.0,
      bronzeThreshold:
          (map['bronze_threshold'] as num?)?.toDouble() ?? 60.0,
    );
  }
}

class PerformanceTier {
  final String name;
  final Color color;

  const PerformanceTier({
    required this.name,
    required this.color,
  });
}

class PerformanceTierHelper {
  static PerformanceTierConfig? _cached;
  static DateTime? _cachedAt;
  static const _cacheDuration = Duration(minutes: 5);

  static const defaultConfig = PerformanceTierConfig();

  static Future<PerformanceTierConfig> loadConfig() async {
    if (_cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheDuration) {
      return _cached!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('performance_tiers')
          .get();
      if (doc.exists && doc.data() != null) {
        _cached = PerformanceTierConfig.fromMap(doc.data()!);
      } else {
        _cached = defaultConfig;
      }
    } catch (_) {
      _cached = defaultConfig;
    }
    _cachedAt = DateTime.now();
    return _cached!;
  }

  static PerformanceTier getTier(
    double score, [
    PerformanceTierConfig config = defaultConfig,
  ]) {
    if (score >= config.goldThreshold) {
      return const PerformanceTier(
        name: 'Gold',
        color: Colors.green,
      );
    } else if (score >= config.silverThreshold) {
      return const PerformanceTier(
        name: 'Silver',
        color: Colors.orange,
      );
    } else if (score >= config.bronzeThreshold) {
      return const PerformanceTier(
        name: 'Bronze',
        color: Colors.amber,
      );
    } else {
      return const PerformanceTier(
        name: 'Needs Improvement',
        color: Colors.red,
      );
    }
  }

  /// Firestore field key for the commission percent of a tier.
  static String commissionKey(PerformanceTier tier) {
    switch (tier.name) {
      case 'Gold':
        return 'Gold';
      case 'Silver':
        return 'Silver';
      case 'Bronze':
        return 'Bronze';
      default:
        return 'Bronze';
    }
  }

  /// Firestore field key for the incentive amount of a tier.
  static String incentiveKey(PerformanceTier tier) {
    switch (tier.name) {
      case 'Gold':
        return 'incentive_gold';
      case 'Silver':
        return 'incentive_silver';
      case 'Bronze':
        return 'incentive_bronze';
      default:
        return 'incentive_bronze';
    }
  }

  static void clearCache() {
    _cached = null;
    _cachedAt = null;
  }
}
