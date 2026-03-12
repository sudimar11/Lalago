import 'dart:math';
import 'package:brgy/services/dispatch_scoring_service.dart';

class DynamicCapacityService {
  /// Compute effective max-orders capacity for a rider.
  /// Returns an int clamped to [1, 4].
  /// If [multipleOrders] is false the rider is always capped at 1.
  /// When [dynamicCapacityEnabled] is false (from config),
  /// falls back to the static [baseCapacity].
  static int calculateEffectiveCapacity({
    required DispatchWeights w,
    required bool isPeakHour,
    required double driverPerformance,
    required bool multipleOrders,
  }) {
    if (!multipleOrders) return 1;
    if (!w.dynamicCapacityEnabled) {
      return w.maxActiveOrdersPerRider;
    }

    int cap = w.baseCapacity;

    // Peak-hour reduction
    if (isPeakHour) {
      cap -= w.peakCapacityReduction;
    }

    // Rider performance adjustment
    if (driverPerformance >= w.performanceBoostThreshold) {
      cap += 1;
    } else if (driverPerformance < w.performancePenaltyThreshold) {
      cap -= 1;
    }

    // Weather override
    switch (w.weatherCondition) {
      case 'rain':
        cap -= 1;
        break;
      case 'storm':
        cap -= 2;
        break;
    }

    return cap.clamp(1, 4);
  }

  /// How many capacity "slots" a single order uses based on item count.
  /// Returns 1.0, 1.5, or 2.0.
  static double orderComplexityWeight({
    required int itemCount,
    int complexityThreshold = 5,
    int heavyThreshold = 8,
  }) {
    if (itemCount >= heavyThreshold) return 2.0;
    if (itemCount >= complexityThreshold) return 1.5;
    return 1.0;
  }

  /// Returns 1.0 or 1.5 depending on whether the delivery
  /// distance exceeds the long-distance threshold.
  static double distanceWeight({
    required double distanceKm,
    double threshold = 5.0,
  }) {
    return distanceKm > threshold ? 1.5 : 1.0;
  }

  /// Weighted active load: sums complexity & distance weights
  /// for each existing active order. Falls back to raw count
  /// when details are unavailable.
  static double weightedActiveLoad({
    required List<Map<String, dynamic>> activeOrders,
    required DispatchWeights w,
  }) {
    if (activeOrders.isEmpty) return 0;
    double load = 0;
    for (final o in activeOrders) {
      final items = _countItems(o);
      final dist = (o['deliveryDistanceKm'] as num?)?.toDouble()
          ?? 0.0;
      final cw = orderComplexityWeight(
        itemCount: items,
        complexityThreshold: w.complexityThresholdItems,
        heavyThreshold: w.complexityThresholdHeavy,
      );
      final dw = distanceWeight(
        distanceKm: dist,
        threshold: w.longDistanceThresholdKm,
      );
      load += max(cw, dw);
    }
    return load;
  }

  static int _countItems(Map<String, dynamic> order) {
    final products = order['products'];
    if (products is List) return products.length;
    final count = order['orderItemCount'];
    if (count is num) return count.toInt();
    return 1;
  }
}
