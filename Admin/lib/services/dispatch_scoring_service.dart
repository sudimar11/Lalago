import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class DispatchScore {
  final double total;
  final Map<String, double> components;

  const DispatchScore({required this.total, required this.components});
}

class DispatchWeights {
  final double eta;
  final double workload;
  final double direction;
  final double acceptanceProb;
  final double fairness;
  final double prepAlignmentBase;
  final double prepAlignmentPeak;
  final int peakHourStart;
  final int peakHourEnd;
  final int peakHourStart2;
  final int peakHourEnd2;
  final int maxActiveOrdersPerRider;
  final int riderTimeoutSeconds;
  final bool dynamicCapacityEnabled;
  final int baseCapacity;
  final int peakCapacityReduction;
  final int complexityThresholdItems;
  final int complexityThresholdHeavy;
  final double longDistanceThresholdKm;
  final double performanceBoostThreshold;
  final double performancePenaltyThreshold;
  final String weatherCondition;

  const DispatchWeights({
    this.eta = 0.35,
    this.workload = 0.20,
    this.direction = 0.15,
    this.acceptanceProb = 0.20,
    this.fairness = 0.10,
    this.prepAlignmentBase = 0.05,
    this.prepAlignmentPeak = 0.10,
    this.peakHourStart = 11,
    this.peakHourEnd = 14,
    this.peakHourStart2 = 17,
    this.peakHourEnd2 = 21,
    this.maxActiveOrdersPerRider = 2,
    this.riderTimeoutSeconds = 60,
    this.dynamicCapacityEnabled = true,
    this.baseCapacity = 2,
    this.peakCapacityReduction = 1,
    this.complexityThresholdItems = 5,
    this.complexityThresholdHeavy = 8,
    this.longDistanceThresholdKm = 5.0,
    this.performanceBoostThreshold = 90.0,
    this.performancePenaltyThreshold = 65.0,
    this.weatherCondition = 'normal',
  });

  factory DispatchWeights.fromMap(Map<String, dynamic> m) {
    return DispatchWeights(
      eta: (m['weightETA'] as num?)?.toDouble() ?? 0.35,
      workload: (m['weightWorkload'] as num?)?.toDouble() ?? 0.20,
      direction: (m['weightDirection'] as num?)?.toDouble() ?? 0.15,
      acceptanceProb:
          (m['weightAcceptanceProb'] as num?)?.toDouble() ?? 0.20,
      fairness: (m['weightFairness'] as num?)?.toDouble() ?? 0.10,
      prepAlignmentBase:
          (m['prepAlignmentPenaltyBase'] as num?)?.toDouble() ?? 0.05,
      prepAlignmentPeak:
          (m['prepAlignmentPenaltyPeak'] as num?)?.toDouble() ?? 0.10,
      peakHourStart: (m['peakHourStart'] as num?)?.toInt() ?? 11,
      peakHourEnd: (m['peakHourEnd'] as num?)?.toInt() ?? 14,
      peakHourStart2: (m['peakHourStart2'] as num?)?.toInt() ?? 17,
      peakHourEnd2: (m['peakHourEnd2'] as num?)?.toInt() ?? 21,
      maxActiveOrdersPerRider:
          (m['maxActiveOrdersPerRider'] as num?)?.toInt() ?? 2,
      riderTimeoutSeconds:
          (m['riderTimeoutSeconds'] as num?)?.toInt() ?? 60,
      dynamicCapacityEnabled:
          m['dynamicCapacityEnabled'] as bool? ?? true,
      baseCapacity:
          (m['baseCapacity'] as num?)?.toInt() ?? 2,
      peakCapacityReduction:
          (m['peakCapacityReduction'] as num?)?.toInt() ?? 1,
      complexityThresholdItems:
          (m['complexityThresholdItems'] as num?)?.toInt() ?? 5,
      complexityThresholdHeavy:
          (m['complexityThresholdHeavy'] as num?)?.toInt() ?? 8,
      longDistanceThresholdKm:
          (m['longDistanceThresholdKm'] as num?)?.toDouble() ?? 5.0,
      performanceBoostThreshold:
          (m['performanceBoostThreshold'] as num?)?.toDouble() ?? 90.0,
      performancePenaltyThreshold:
          (m['performancePenaltyThreshold'] as num?)?.toDouble() ?? 65.0,
      weatherCondition:
          m['weatherCondition'] as String? ?? 'normal',
    );
  }
}

class DispatchScoringService {
  static DispatchWeights? _cachedWeights;
  static DateTime? _cacheTime;
  static const _cacheTtl = Duration(seconds: 60);

  /// Expose cached weights for sync callers (may be null).
  static DispatchWeights? get cachedWeights => _cachedWeights;

  /// Check peak hour status using the given weights.
  static bool isPeakHourNow(DispatchWeights w) => _isPeakHour(w);

  static double _speedKmPerMin = 0.5;
  static const double _etaBaselineMin = 30.0;

  /// Load weights from Firestore with 60-second cache.
  static Future<DispatchWeights> loadWeights() async {
    final now = DateTime.now();
    if (_cachedWeights != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!) < _cacheTtl) {
      return _cachedWeights!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('dispatch_weights')
          .get();
      if (doc.exists && doc.data() != null) {
        _cachedWeights = DispatchWeights.fromMap(doc.data()!);
        final speed =
            (doc.data()!['avgSpeedKmPerMin'] as num?)
                ?.toDouble();
        if (speed != null && speed > 0) {
          _speedKmPerMin = speed;
        }
      } else {
        _cachedWeights = const DispatchWeights();
      }
    } catch (_) {
      _cachedWeights ??= const DispatchWeights();
    }
    _cacheTime = now;
    return _cachedWeights!;
  }

  /// Calculate multi-factor score for a single driver. Lower is better.
  static DispatchScore calculateScore({
    required double distanceKm,
    double? durationMinutes,
    required int currentOrders,
    required double headingMatch,
    required double predictedAcceptanceProb,
    required int completedToday,
    required int avgCompletedToday,
    required double restaurantPrepMinutes,
    required DispatchWeights w,
    int? effectiveCapacity,
  }) {
    final isPeak = _isPeakHour(w);

    final etaMinutes =
        durationMinutes ?? (distanceKm / _speedKmPerMin);
    final etaFactor =
        (etaMinutes / _etaBaselineMin).clamp(0.0, 2.0);

    final capDenom = effectiveCapacity ?? w.maxActiveOrdersPerRider;
    final workloadFactor =
        currentOrders / capDenom;

    final directionFactor = 1.0 - headingMatch.clamp(0.0, 1.0);

    final acceptanceFactor =
        1.0 - predictedAcceptanceProb.clamp(0.0, 1.0);

    double fairnessFactor = 0.5;
    if (avgCompletedToday > 0) {
      fairnessFactor =
          ((avgCompletedToday - completedToday) / avgCompletedToday)
              .clamp(0.0, 1.0);
    }

    double prepPenalty = 0.0;
    if (restaurantPrepMinutes > 0 && etaMinutes < restaurantPrepMinutes) {
      final waitMin = restaurantPrepMinutes - etaMinutes;
      prepPenalty = (waitMin / 15.0).clamp(0.0, 1.0);
    }
    final prepWeight = isPeak ? w.prepAlignmentPeak : w.prepAlignmentBase;

    final total = (etaFactor * w.eta) +
        (workloadFactor * w.workload) +
        (directionFactor * w.direction) +
        (acceptanceFactor * w.acceptanceProb) +
        (fairnessFactor * w.fairness) +
        (prepPenalty * prepWeight);

    return DispatchScore(
      total: total,
      components: {
        'eta': etaFactor * w.eta,
        'workload': workloadFactor * w.workload,
        'direction': directionFactor * w.direction,
        'acceptance': acceptanceFactor * w.acceptanceProb,
        'fairness': fairnessFactor * w.fairness,
        'prepAlignment': prepPenalty * prepWeight,
      },
    );
  }

  /// Compute heading match (0 = opposite direction, 1 = heading toward
  /// the restaurant). Uses cosine similarity of rider movement vector
  /// vs rider-to-restaurant vector.
  /// Returns 0.5 (neutral) when previous location is unavailable.
  static double calculateHeadingMatch({
    required double riderLat,
    required double riderLng,
    double? prevLat,
    double? prevLng,
    required double restaurantLat,
    required double restaurantLng,
  }) {
    if (prevLat == null || prevLng == null) return 0.5;
    if (prevLat == riderLat && prevLng == riderLng) return 0.5;

    final moveDx = riderLng - prevLng;
    final moveDy = riderLat - prevLat;

    final targetDx = restaurantLng - riderLng;
    final targetDy = restaurantLat - riderLat;

    final dot = moveDx * targetDx + moveDy * targetDy;
    final magMove = sqrt(moveDx * moveDx + moveDy * moveDy);
    final magTarget = sqrt(targetDx * targetDx + targetDy * targetDy);

    if (magMove == 0 || magTarget == 0) return 0.5;

    final cosine = (dot / (magMove * magTarget)).clamp(-1.0, 1.0);
    return (cosine + 1.0) / 2.0; // Map [-1, 1] to [0, 1]
  }

  /// Calculate a combined score for a batch of orders.
  /// Uses the worst-case (max) distance for ETA and averages
  /// prep alignment across orders. Lower is better.
  static DispatchScore calculateBatchScore({
    required List<double> distancesKm,
    List<double>? durationsMinutes,
    required int currentOrders,
    required double headingMatch,
    required double predictedAcceptanceProb,
    required int completedToday,
    required int avgCompletedToday,
    required List<double> restaurantPrepMinutes,
    required DispatchWeights w,
    int? effectiveCapacity,
  }) {
    if (distancesKm.isEmpty) {
      return const DispatchScore(total: 999, components: {});
    }

    final isPeak = _isPeakHour(w);
    final batchSize = distancesKm.length;

    double etaMinutes;
    if (durationsMinutes != null && durationsMinutes.isNotEmpty) {
      etaMinutes = durationsMinutes.reduce(
          (a, b) => a > b ? a : b);
    } else {
      final maxDist = distancesKm.reduce(
          (a, b) => a > b ? a : b);
      etaMinutes = maxDist / _speedKmPerMin;
    }
    final etaFactor =
        (etaMinutes / _etaBaselineMin).clamp(0.0, 2.0);

    final effectiveLoad = currentOrders + batchSize;
    final capDenom = effectiveCapacity ?? w.maxActiveOrdersPerRider;
    final workloadFactor = effectiveLoad / capDenom;

    final directionFactor = 1.0 - headingMatch.clamp(0.0, 1.0);
    final acceptanceFactor =
        1.0 - predictedAcceptanceProb.clamp(0.0, 1.0);

    double fairnessFactor = 0.5;
    if (avgCompletedToday > 0) {
      fairnessFactor =
          ((avgCompletedToday - completedToday) / avgCompletedToday)
              .clamp(0.0, 1.0);
    }

    double prepPenaltySum = 0.0;
    for (int i = 0; i < batchSize; i++) {
      final prep = i < restaurantPrepMinutes.length
          ? restaurantPrepMinutes[i]
          : 0.0;
      if (prep > 0 && etaMinutes < prep) {
        prepPenaltySum +=
            ((prep - etaMinutes) / 15.0).clamp(0.0, 1.0);
      }
    }
    final prepPenalty = prepPenaltySum / batchSize;
    final prepWeight =
        isPeak ? w.prepAlignmentPeak : w.prepAlignmentBase;

    final total = (etaFactor * w.eta) +
        (workloadFactor * w.workload) +
        (directionFactor * w.direction) +
        (acceptanceFactor * w.acceptanceProb) +
        (fairnessFactor * w.fairness) +
        (prepPenalty * prepWeight);

    return DispatchScore(
      total: total,
      components: {
        'eta': etaFactor * w.eta,
        'workload': workloadFactor * w.workload,
        'direction': directionFactor * w.direction,
        'acceptance': acceptanceFactor * w.acceptanceProb,
        'fairness': fairnessFactor * w.fairness,
        'prepAlignment': prepPenalty * prepWeight,
      },
    );
  }

  /// Parse preparation time string (e.g. "15 min") to minutes.
  static double parsePrepMinutes(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    final s = raw.toString().trim().toLowerCase();
    final match = RegExp(r'(\d+)').firstMatch(s);
    if (match != null) return double.tryParse(match.group(1)!) ?? 0;
    return 0;
  }

  static bool _isPeakHour(DispatchWeights w) {
    final hour = DateTime.now().hour;
    return (hour >= w.peakHourStart && hour < w.peakHourEnd) ||
        (hour >= w.peakHourStart2 && hour < w.peakHourEnd2);
  }
}
