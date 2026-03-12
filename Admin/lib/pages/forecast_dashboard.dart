import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:brgy/constants.dart';

class ForecastDashboard extends StatefulWidget {
  const ForecastDashboard({super.key});

  @override
  State<ForecastDashboard> createState() => _ForecastDashboardState();
}

class _ForecastDashboardState extends State<ForecastDashboard> {
  String? _selectedVendorId;

  static String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forecast Dashboard'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterRow(),
            const SizedBox(height: 16),
            _TodayForecastCard(vendorId: _selectedVendorId),
            const SizedBox(height: 24),
            _WeeklyForecastChart(vendorId: _selectedVendorId),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('vendors').get(),
      builder: (context, snapshot) {
        final vendors = snapshot.data?.docs ?? [];
        return Row(
          children: [
            const Text('Restaurant: ', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            DropdownButton<String?>(
              value: _selectedVendorId,
              hint: const Text('All (platform)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All (platform)')),
                ...vendors.map((d) => DropdownMenuItem<String?>(
                      value: d.id,
                      child: Text(
                        (d.data()['title'] ?? d.id).toString(),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedVendorId = v),
            ),
          ],
        );
      },
    );
  }
}

class _TodayForecastCard extends StatelessWidget {
  const _TodayForecastCard({this.vendorId});

  final String? vendorId;

  static String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    final today = _formatDate(DateTime.now());
    final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    return FutureBuilder<Map<String, dynamic>>(
      future: _loadTodayData(today, startOfDay),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snapshot.data ?? {};
        final predicted = (data['predicted'] as num?)?.toInt() ?? 0;
        final lowerBound = (data['lowerBound'] as num?)?.toInt() ?? 0;
        final actual = (data['actual'] as num?)?.toInt() ?? 0;

        Color statusColor;
        String statusLabel;
        if (actual >= lowerBound) {
          statusColor = Colors.green;
          statusLabel = 'On track';
        } else if (actual >= (predicted * 0.7).round()) {
          statusColor = Colors.orange;
          statusLabel = 'Slightly below';
        } else {
          statusColor = Colors.red;
          statusLabel = 'Underperforming';
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's Forecast",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$predicted',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('orders predicted', style: TextStyle(fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Actual so far: $actual orders',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                if (lowerBound > 0)
                  Text(
                    '80% confidence: $lowerBound - ${(data['upperBound'] as num?)?.toInt() ?? 0}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadTodayData(
    String today,
    DateTime startOfDay,
  ) async {
    final db = FirebaseFirestore.instance;

    int predicted = 0;
    int lowerBound = 0;
    int upperBound = 0;

    if (vendorId != null) {
      final forecastDoc = await db
          .collection(DEMAND_FORECASTS)
          .doc('${vendorId}_$today')
          .get();
      if (forecastDoc.exists) {
        final d = forecastDoc.data();
        final hp = d?['hourlyPredictions'] as Map<String, dynamic>?;
        if (hp != null) {
          for (final v in hp.values) {
            if (v is num) predicted += v.toInt();
          }
        }
        lowerBound = (predicted * 0.8).round();
        upperBound = (predicted * 1.2).round();
      }
    } else {
      final forecastDoc = await db.collection(ORDER_FORECASTS).doc(today).get();
      if (forecastDoc.exists) {
        final d = forecastDoc.data();
        predicted = (d?['predictedOrders'] as num?)?.toInt() ?? 0;
        lowerBound = (d?['lowerBound'] as num?)?.toInt() ?? 0;
        upperBound = (d?['upperBound'] as num?)?.toInt() ?? 0;
      }
    }

    int actual = 0;
    Query ordersQuery = db
        .collection('restaurant_orders')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay));

    if (vendorId != null) {
      ordersQuery = ordersQuery.where('vendorID', isEqualTo: vendorId);
    }
    final ordersSnap = await ordersQuery.get();
    actual = ordersSnap.docs.length;

    return {
      'predicted': predicted,
      'lowerBound': lowerBound,
      'upperBound': upperBound,
      'actual': actual,
    };
  }
}

class _WeeklyForecastChart extends StatelessWidget {
  const _WeeklyForecastChart({this.vendorId});

  final String? vendorId;

  static String _formatDate(DateTime d) {
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadWeeklyData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: SizedBox(
              height: 280,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snapshot.data ?? {};
        final actualSpots = data['actualSpots'] as List<FlSpot>? ?? [];
        final predictedSpots = data['predictedSpots'] as List<FlSpot>? ?? [];
        final lowerSpots = data['lowerSpots'] as List<FlSpot>? ?? [];
        final upperSpots = data['upperSpots'] as List<FlSpot>? ?? [];
        final labels = data['labels'] as List<String>? ?? [];
        final maxY = (data['maxY'] as num?)?.toDouble() ?? 10.0;

        if (actualSpots.isEmpty && predictedSpots.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Forecast',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No forecast data available yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        final lineBars = <LineChartBarData>[];
        if (actualSpots.isNotEmpty) {
          lineBars.add(
            LineChartBarData(
              spots: actualSpots,
              isCurved: true,
              color: Colors.blue,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withOpacity(0.1),
              ),
            ),
          );
        }
        if (predictedSpots.isNotEmpty) {
          lineBars.add(
            LineChartBarData(
              spots: predictedSpots,
              isCurved: true,
              color: Colors.orange,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: lowerSpots.isNotEmpty && upperSpots.isNotEmpty,
                color: Colors.orange.withOpacity(0.15),
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly Forecast',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Actual (blue) vs Predicted (orange) with 80% confidence',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 220,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        horizontalInterval: maxY / 5,
                        getDrawingHorizontalLine: (v) =>
                            FlLine(color: Colors.grey[300]!, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (i >= 0 && i < labels.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    labels[i],
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: maxY / 5,
                            getTitlesWidget: (v, meta) => Text(
                              v.toInt().toString(),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      minX: 0,
                      maxX: 13,
                      minY: 0,
                      maxY: maxY,
                      lineBarsData: lineBars,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadWeeklyData() async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final pastStart = now.subtract(const Duration(days: 6));
    final pastStartDate = DateTime(pastStart.year, pastStart.month, pastStart.day);

    final actualSpots = <FlSpot>[];
    final predictedSpots = <FlSpot>[];
    final lowerSpots = <FlSpot>[];
    final upperSpots = <FlSpot>[];
    final labels = <String>[];
    double maxY = 10;

    if (vendorId != null) {
      for (int i = 0; i < 7; i++) {
        final d = pastStartDate.add(Duration(days: i));
        final dateKey = _formatDate(d);
        labels.add(DateFormat('M/d').format(d));

        final aggDoc =
            await db.collection(FORECAST_AGGREGATES).doc('${vendorId}_$dateKey').get();
        int actual = 0;
        if (aggDoc.exists) {
          actual = (aggDoc.data()?['totalDailyOrders'] as num?)?.toInt() ?? 0;
        }
        actualSpots.add(FlSpot(i.toDouble(), actual.toDouble()));
        if (actual > maxY) maxY = actual.toDouble();
      }
      for (int i = 0; i < 7; i++) {
        final d = now.add(Duration(days: i + 1));
        final dateKey = _formatDate(d);
        labels.add(DateFormat('M/d').format(d));

        final forecastDoc =
            await db.collection(DEMAND_FORECASTS).doc('${vendorId}_$dateKey').get();
        int pred = 0;
        if (forecastDoc.exists) {
          final hp = forecastDoc.data()?['hourlyPredictions'] as Map<String, dynamic>?;
          if (hp != null) {
            for (final v in hp.values) {
              if (v is num) pred += v.toInt();
            }
          }
        }
        predictedSpots.add(FlSpot((7 + i).toDouble(), pred.toDouble()));
        lowerSpots.add(FlSpot((7 + i).toDouble(), (pred * 0.8).toDouble()));
        upperSpots.add(FlSpot((7 + i).toDouble(), (pred * 1.2).toDouble()));
        if (pred > maxY) maxY = pred.toDouble();
      }
    } else {
      for (int i = 0; i < 7; i++) {
        final d = pastStartDate.add(Duration(days: i));
        final dateKey = _formatDate(d);
        labels.add(DateFormat('M/d').format(d));

        final aggSnap = await db
            .collection(FORECAST_AGGREGATES)
            .where('date', isEqualTo: dateKey)
            .get();
        int actual = 0;
        for (final doc in aggSnap.docs) {
          actual += (doc.data()['totalDailyOrders'] as num?)?.toInt() ?? 0;
        }
        actualSpots.add(FlSpot(i.toDouble(), actual.toDouble()));
        if (actual > maxY) maxY = actual.toDouble();
      }
      for (int i = 0; i < 7; i++) {
        final d = now.add(Duration(days: i + 1));
        final dateKey = _formatDate(d);
        labels.add(DateFormat('M/d').format(d));

        final forecastDoc = await db.collection(ORDER_FORECASTS).doc(dateKey).get();
        int pred = 0;
        int low = 0;
        int up = 0;
        if (forecastDoc.exists) {
          final data = forecastDoc.data();
          pred = (data?['predictedOrders'] as num?)?.toInt() ?? 0;
          low = (data?['lowerBound'] as num?)?.toInt() ?? 0;
          up = (data?['upperBound'] as num?)?.toInt() ?? 0;
        }
        predictedSpots.add(FlSpot((7 + i).toDouble(), pred.toDouble()));
        lowerSpots.add(FlSpot((7 + i).toDouble(), low.toDouble()));
        upperSpots.add(FlSpot((7 + i).toDouble(), up.toDouble()));
        if (up > maxY) maxY = up.toDouble();
      }
    }

    maxY = (maxY * 1.15).clamp(5, double.infinity);

    return {
      'actualSpots': actualSpots,
      'predictedSpots': predictedSpots,
      'lowerSpots': lowerSpots,
      'upperSpots': upperSpots,
      'labels': labels,
      'maxY': maxY,
    };
  }
}
