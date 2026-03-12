import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:brgy/services/demand_health_service.dart';
import 'package:brgy/widgets/dashboard/health_score_gauge.dart';

class DemandHealthDashboard extends StatefulWidget {
  const DemandHealthDashboard({super.key});

  @override
  State<DemandHealthDashboard> createState() => _DemandHealthDashboardState();
}

class _DemandHealthDashboardState extends State<DemandHealthDashboard> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demand Health'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
        stream: DemandHealthService.streamLatestHealth(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docSnap = snapshot.data;
          if (docSnap == null || !docSnap.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.health_and_safety, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No health data yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Health scores are computed hourly.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          final data = docSnap!.data() ?? {};
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          'Overall Health Score',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        HealthScoreGauge(
                          score:
                              (data['overallScore'] as num?)?.toInt() ?? 0,
                          size: 120,
                          showLabel: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _ComponentBreakdown(components: data['components'] as Map<String, dynamic>? ?? {}),
                const SizedBox(height: 24),
                _HealthTrendChart(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComponentBreakdown extends StatelessWidget {
  const _ComponentBreakdown({required this.components});

  final Map<String, dynamic> components;

  static const _labels = {
    'orderVsForecast': 'Order vs Forecast',
    'wowGrowth': 'Week-over-Week Growth',
    'restaurantAvailability': 'Restaurant Availability',
    'riderAvailability': 'Rider Availability',
    'promoEffectiveness': 'Promo Effectiveness',
    'customerSatisfaction': 'Customer Satisfaction',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Component Breakdown',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ..._labels.entries.map((e) {
              final comp = components[e.key] as Map<String, dynamic>?;
              if (comp == null) return const SizedBox.shrink();
              final score = (comp['score'] as num?)?.toInt() ?? 0;
              final label = comp['label'] as String? ?? '-';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.value, style: const TextStyle(fontSize: 14)),
                    ),
                    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '$score',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: score >= 80 ? Colors.green : score >= 60 ? Colors.orange : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _HealthTrendChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DemandHealthService.getHealthHistory(30),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Health Trend (30 days)',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Not enough data yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }
        final history = snapshot.data!;
        final spots = history.asMap().entries.map((e) {
          final score = (e.value['overallScore'] as num?)?.toDouble() ?? 0;
          return FlSpot(e.key.toDouble(), score);
        }).toList();

        if (spots.isEmpty) {
          return const SizedBox.shrink();
        }

        final maxY = 100.0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Health Trend (30 days)',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (v) =>
                            FlLine(color: Colors.grey[300]!, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            getTitlesWidget: (v, meta) {
                              if (v.toInt() >= 0 && v.toInt() < history.length) {
                                final ts = history[v.toInt()]['timestamp'];
                                if (ts is Timestamp) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      DateFormat('M/d').format(ts.toDate()),
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 9,
                                      ),
                                    ),
                                  );
                                }
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 25,
                            getTitlesWidget: (v, meta) => Text(
                              v.toInt().toString(),
                              style: TextStyle(color: Colors.grey[600], fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      minX: 0,
                      maxX: (spots.length - 1).toDouble(),
                      minY: 0,
                      maxY: maxY,
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: Colors.green,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.green.withOpacity(0.1),
                          ),
                        ),
                      ],
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
}
