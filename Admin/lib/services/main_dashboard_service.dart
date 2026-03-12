import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/services/demand_health_service.dart';

const _fulfilledStatuses = [
  'Order Completed',
  'order completed',
  'completed',
  'Completed',
  'Order Shipped',
  'Order Delivered',
  'In Transit',
];

bool _isFulfilled(String? status) {
  final s = (status ?? '').toString().toLowerCase();
  return _fulfilledStatuses
      .any((f) => s.contains(f.toLowerCase()));
}

String _formatDate(DateTime d) {
  final y = d.year;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Forecast data source for UI display.
enum ForecastSource {
  orderForecasts,
  forecastAggregates,
  restaurantOrders,
}

/// Today's forecast data for main dashboard.
class TodayForecastData {
  const TodayForecastData({
    required this.predicted,
    required this.actual,
    required this.lowerBound,
    required this.upperBound,
    this.source = ForecastSource.orderForecasts,
  });

  final int predicted;
  final int actual;
  final int lowerBound;
  final int upperBound;
  final ForecastSource source;
}

/// Aggregates data for main dashboard.
class MainDashboardService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Platform-level today forecast + actual (fulfilled orders).
  static Future<TodayForecastData> getTodayForecast() async {
    try {
      final now = DateTime.now();
      final today = _formatDate(now);
      final startOfDay =
          DateTime(now.year, now.month, now.day);

      final forecastDoc =
          await _db.collection(ORDER_FORECASTS).doc(today).get();
      int predicted = 0;
      int lowerBound = 0;
      int upperBound = 0;
      ForecastSource source = ForecastSource.orderForecasts;
      if (forecastDoc.exists) {
        final d = forecastDoc.data();
        predicted = (d?['predictedOrders'] as num?)?.toInt() ?? 0;
        lowerBound = (d?['lowerBound'] as num?)?.toInt() ?? 0;
        upperBound = (d?['upperBound'] as num?)?.toInt() ?? 0;
        source = ForecastSource.orderForecasts;
      } else {
        final fallback =
            await MainDashboardService._getFallbackForecastFromAggregates();
        predicted = fallback.predicted;
        lowerBound = fallback.lowerBound;
        upperBound = fallback.upperBound;
        source = fallback.source;
      }

      final endOfDay =
          DateTime(now.year, now.month, now.day, 23, 59, 59);
      final ordersSnap = await _db
          .collection('restaurant_orders')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get();

      int actual = 0;
      for (final doc in ordersSnap.docs) {
        if (_isFulfilled(doc.data()['status'] as String?)) {
          actual++;
        }
      }

      return TodayForecastData(
        predicted: predicted,
        actual: actual,
        lowerBound: lowerBound,
        upperBound: upperBound,
        source: source,
      );
    } catch (_) {
      return const TodayForecastData(
        predicted: 0,
        actual: 0,
        lowerBound: 0,
        upperBound: 0,
        source: ForecastSource.orderForecasts,
      );
    }
  }

  /// Active unresolved alerts, most recent first.
  static Stream<List<Map<String, dynamic>>> streamActiveAlerts({
    int limit = 5,
  }) {
    return _db
        .collection('demand_alerts')
        .where('resolvedAt', isNull: true)
        .orderBy('detectedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Count of active alerts for badge.
  static Stream<int> streamActiveAlertCount() {
    return _db
        .collection('demand_alerts')
        .where('resolvedAt', isNull: true)
        .snapshots()
        .map((s) => s.docs.length);
  }

  /// Latest health score.
  static Stream<DocumentSnapshot<Map<String, dynamic>>?> streamLatestHealth() {
    return DemandHealthService.streamLatestHealth();
  }

  /// Health history for sparkline.
  static Future<List<Map<String, dynamic>>> getHealthHistory(int days) async {
    try {
      return await DemandHealthService.getHealthHistory(days);
    } catch (_) {
      return [];
    }
  }

  /// Top promos by incremental orders (fetch recent, sort in-memory).
  static Future<List<Map<String, dynamic>>> getTopPromosByIncrementalOrders({
    int limit = 3,
  }) async {
    try {
      final snap = await _db
          .collection('promo_impact')
          .orderBy('analysisDate', descending: true)
          .limit(50)
          .get();

      final list = snap.docs.map((d) {
        final data = d.data();
        final promoId = d.id.split('_').first;
        return {'id': d.id, 'promoId': promoId, ...data};
      }).toList();

      list.sort((a, b) {
        final aVal = (a['incrementalOrders'] as num?)?.toInt() ?? 0;
        final bVal = (b['incrementalOrders'] as num?)?.toInt() ?? 0;
        return bVal.compareTo(aVal);
      });

      return list.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fallback when order_forecasts doc is missing: compute from aggregates.
  static Future<
      ({int predicted, int lowerBound, int upperBound, ForecastSource source})>
      _getFallbackForecastFromAggregates() async {
    try {
      final now = DateTime.now();
      final endKey = _formatDate(now);
      final startDate = now.subtract(const Duration(days: 14));
      final startKey = _formatDate(startDate);

      final snap = await _db
          .collection(FORECAST_AGGREGATES)
          .where('date', isGreaterThanOrEqualTo: startKey)
          .where('date', isLessThanOrEqualTo: endKey)
          .get();

      final byDate = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final date = data['date'] as String?;
        if (date == null) continue;
        final orders = (data['totalDailyOrders'] as num?)?.toInt() ?? 0;
        byDate[date] = (byDate[date] ?? 0) + orders;
      }

      if (byDate.isNotEmpty) {
        final total = byDate.values.reduce((a, b) => a + b);
        final predicted = (total / byDate.length).round();
        final lowerBound = (predicted * 0.8).round();
        final upperBound = (predicted * 1.2).round();
        return (
          predicted: predicted,
          lowerBound: lowerBound,
          upperBound: upperBound,
          source: ForecastSource.forecastAggregates,
        );
      }

      return await MainDashboardService._getFallbackFromRestaurantOrders();
    } catch (_) {
      return (
        predicted: 0,
        lowerBound: 0,
        upperBound: 0,
        source: ForecastSource.forecastAggregates,
      );
    }
  }

  /// Last-resort fallback: count fulfilled orders from restaurant_orders.
  static Future<
      ({int predicted, int lowerBound, int upperBound, ForecastSource source})>
      _getFallbackFromRestaurantOrders() async {
    try {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 14));
      final startOfRange = DateTime(startDate.year, startDate.month, startDate.day);
      final endOfRange = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final snap = await _db
          .collection('restaurant_orders')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfRange))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfRange))
          .get();

      final byDate = <String, int>{};
      for (final doc in snap.docs) {
        if (!_isFulfilled(doc.data()['status'] as String?)) continue;
        final createdAt = doc.data()['createdAt'] as Timestamp?;
        if (createdAt == null) continue;
        final dt = createdAt.toDate();
        final dateKey = _formatDate(dt);
        byDate[dateKey] = (byDate[dateKey] ?? 0) + 1;
      }

      if (byDate.isEmpty) {
        return (
          predicted: 0,
          lowerBound: 0,
          upperBound: 0,
          source: ForecastSource.restaurantOrders,
        );
      }

      final total = byDate.values.reduce((a, b) => a + b);
      final predicted = (total / byDate.length).round();
      final lowerBound = (predicted * 0.8).round();
      final upperBound = (predicted * 1.2).round();
      return (
        predicted: predicted,
        lowerBound: lowerBound,
        upperBound: upperBound,
        source: ForecastSource.restaurantOrders,
      );
    } catch (_) {
      return (
        predicted: 0,
        lowerBound: 0,
        upperBound: 0,
        source: ForecastSource.restaurantOrders,
      );
    }
  }

  /// Forecast trend for next 7 days (for mini sparkline).
  static Future<List<FlSpot>> getForecastTrendNext7Days() async {
    try {
      final now = DateTime.now();
      final spots = <FlSpot>[];
      for (int i = 1; i <= 7; i++) {
        final d = now.add(Duration(days: i));
        final dateKey = _formatDate(d);
        final doc = await _db.collection(ORDER_FORECASTS).doc(dateKey).get();
        final pred = (doc.data()?['predictedOrders'] as num?)?.toInt() ?? 0;
        spots.add(FlSpot((i - 1).toDouble(), pred.toDouble()));
      }
      return spots;
    } catch (_) {
      return [];
    }
  }
}
