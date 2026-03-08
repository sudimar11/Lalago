import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_restaurant/constants.dart';

/// Service for demand forecasts and aggregates.
class ForecastService {
  static final _firestore = FirebaseFirestore.instance;

  static String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Get demand forecast for a vendor on a specific date.
  static Future<Map<String, dynamic>?> getDemandForecast(
    String vendorId,
    DateTime date,
  ) async {
    try {
      final dateKey = _formatDate(date);
      final doc = await _firestore
          .collection(DEMAND_FORECASTS)
          .doc('${vendorId}_$dateKey')
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  /// Get forecasts for multiple dates (e.g. next 7 days).
  static Future<List<Map<String, dynamic>>> getDemandForecastsForRange(
    String vendorId,
    DateTime start,
    DateTime end,
  ) async {
    final results = <Map<String, dynamic>>[];
    var current = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    while (!current.isAfter(endDate)) {
      final forecast = await getDemandForecast(vendorId, current);
      if (forecast != null) {
        results.add(forecast);
      }
      current = current.add(const Duration(days: 1));
    }
    return results;
  }

  /// Get aggregate data for comparison (actual vs predicted for past dates).
  static Future<Map<String, dynamic>?> getForecastAggregatesForComparison(
    String vendorId,
    DateTime date,
  ) async {
    try {
      final dateKey = _formatDate(date);
      final doc = await _firestore
          .collection(FORECAST_AGGREGATES)
          .doc('${vendorId}_$dateKey')
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data();
    } catch (_) {
      return null;
    }
  }
}
