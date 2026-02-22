import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Predicts rider acceptance probability using historical data.
/// Mirrors the Cloud Function calculateAcceptanceProbability logic.
class AcceptanceProbabilityService {
  static final _firestore = FirebaseFirestore.instance;
  static double _baseAcceptanceRate = 0.7;
  static DateTime? _configLoadedAt;

  static Future<double> _getBaseRate() async {
    final now = DateTime.now();
    if (_configLoadedAt != null &&
        now.difference(_configLoadedAt!).inSeconds < 60) {
      return _baseAcceptanceRate;
    }
    try {
      final doc = await _firestore
          .collection('config')
          .doc('dispatch_weights')
          .get();
      if (doc.exists) {
        final rate =
            (doc.data()?['baseAcceptanceRate'] as num?)
                ?.toDouble();
        if (rate != null && rate > 0) {
          _baseAcceptanceRate = rate;
        }
      }
    } catch (_) {}
    _configLoadedAt = now;
    return _baseAcceptanceRate;
  }

  /// Calculate predicted acceptance probability for a rider/order pair.
  /// Returns 0.0 – 1.0 where higher = more likely to accept.
  static Future<double> calculate({
    required String riderId,
    required double distanceKm,
    required int currentOrders,
  }) async {
    double baseRate = await _getBaseRate();
    try {
      final logs = await _firestore
          .collection('assignments_log')
          .where('driverId', isEqualTo: riderId)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      if (logs.docs.isNotEmpty) {
        int accepted = 0;
        int recentRejects = 0;
        bool countingStreak = true;
        for (final doc in logs.docs) {
          final s = doc.data()['status'] as String? ?? '';
          if (s == 'accepted') {
            accepted++;
            countingStreak = false;
          } else if (s == 'rejected' || s == 'timeout') {
            if (countingStreak) recentRejects++;
          } else {
            countingStreak = false;
          }
        }
        baseRate = logs.docs.isEmpty
            ? 0.7
            : accepted / logs.docs.length;

        if (recentRejects >= 2) {
          baseRate *= 0.7;
        }
      }
    } catch (_) {}

    final distancePenalty =
        (distanceKm / 20.0).clamp(0.0, 0.3);
    final workloadPenalty = currentOrders * 0.15;

    final hour = DateTime.now().hour;
    double timeBonus = 0.0;
    if (hour >= 10 && hour <= 21) timeBonus = 0.05;

    final prob =
        (baseRate - distancePenalty - workloadPenalty + timeBonus)
            .clamp(0.05, 0.95);
    return prob;
  }

  /// Batch-calculate acceptance probability for multiple riders at once.
  /// Uses chunked Firestore 'in' queries instead of N individual queries.
  static Future<Map<String, double>> calculateBatch({
    required List<String> riderIds,
    required Map<String, double> distances,
    required Map<String, int> orderCounts,
  }) async {
    if (riderIds.isEmpty) return {};

    final Map<String, List<String>> statusesByRider = {};
    for (final id in riderIds) {
      statusesByRider[id] = [];
    }

    try {
      // Firestore 'whereIn' max 30 IDs per query, chunk accordingly
      for (int i = 0; i < riderIds.length; i += 30) {
        final chunk = riderIds.sublist(
          i,
          min(i + 30, riderIds.length),
        );
        final logs = await _firestore
            .collection('assignments_log')
            .where('driverId', whereIn: chunk)
            .orderBy('createdAt', descending: true)
            .limit(20 * chunk.length)
            .get();

        for (final doc in logs.docs) {
          final data = doc.data();
          final driverId = data['driverId'] as String? ?? '';
          final status = data['status'] as String? ?? '';
          if (statusesByRider.containsKey(driverId)) {
            final list = statusesByRider[driverId]!;
            if (list.length < 20) {
              list.add(status);
            }
          }
        }
      }
    } catch (_) {}

    final hour = DateTime.now().hour;
    final timeBonus = (hour >= 10 && hour <= 21) ? 0.05 : 0.0;

    final configBaseRate = await _getBaseRate();
    final Map<String, double> results = {};
    for (final riderId in riderIds) {
      final statuses = statusesByRider[riderId] ?? [];
      double baseRate = configBaseRate;

      if (statuses.isNotEmpty) {
        int accepted = 0;
        int recentRejects = 0;
        bool countingStreak = true;
        for (final s in statuses) {
          if (s == 'accepted') {
            accepted++;
            countingStreak = false;
          } else if (s == 'rejected' || s == 'timeout') {
            if (countingStreak) recentRejects++;
          } else {
            countingStreak = false;
          }
        }
        baseRate = accepted / statuses.length;
        if (recentRejects >= 2) baseRate *= 0.7;
      }

      final dist = distances[riderId] ?? 0.0;
      final orders = orderCounts[riderId] ?? 0;
      final distancePenalty = (dist / 20.0).clamp(0.0, 0.3);
      final workloadPenalty = orders * 0.15;

      results[riderId] =
          (baseRate - distancePenalty - workloadPenalty + timeBonus)
              .clamp(0.05, 0.95);
    }
    return results;
  }
}
