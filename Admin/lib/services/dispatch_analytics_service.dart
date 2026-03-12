import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Read-only service for querying dispatch analytics data
/// from the Admin UI. Data is populated by Cloud Functions
/// (dailyDispatchAnalytics cron and orderCompletionEnrichment).
class DispatchAnalyticsService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  /// Get daily aggregate stats for a specific date.
  /// Returns null if no data exists for that date.
  Future<Map<String, dynamic>?> getDailyStats(
    DateTime date,
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final doc = await _firestore
        .collection('dispatch_analytics_daily')
        .doc(dateStr)
        .get();
    if (!doc.exists) return null;
    return {'id': doc.id, ...doc.data()!};
  }

  /// Stream the most recent dispatch events.
  Stream<List<Map<String, dynamic>>> streamRecentEvents({
    int limit = 50,
  }) {
    return _firestore
        .collection('dispatch_events')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  /// Get weight change history, most recent first.
  Future<List<Map<String, dynamic>>> getWeightsHistory({
    int limit = 30,
  }) async {
    final snap = await _firestore
        .collection('config_weights_history')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .toList();
  }

  /// Get current dispatch scoring weights.
  Future<Map<String, double>> getCurrentWeights() async {
    final doc = await _firestore
        .collection('config')
        .doc('dispatch_weights')
        .get();
    if (!doc.exists || doc.data() == null) return {};
    final data = doc.data()!;
    final result = <String, double>{};
    for (final key in [
      'weightETA',
      'weightWorkload',
      'weightDirection',
      'weightAcceptanceProb',
      'weightFairness',
    ]) {
      result[key] =
          (data[key] as num?)?.toDouble() ?? 0.0;
    }
    return result;
  }

  /// Get daily stats for a range of dates (for charts).
  Future<List<Map<String, dynamic>>> getDailyStatsRange({
    required DateTime from,
    required DateTime to,
  }) async {
    final fromStr = DateFormat('yyyy-MM-dd').format(from);
    final toStr = DateFormat('yyyy-MM-dd').format(to);
    final snap = await _firestore
        .collection('dispatch_analytics_daily')
        .where('date', isGreaterThanOrEqualTo: fromStr)
        .where('date', isLessThanOrEqualTo: toStr)
        .orderBy('date')
        .get();
    return snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .toList();
  }
}
