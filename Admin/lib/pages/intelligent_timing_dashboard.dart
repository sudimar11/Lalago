import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class IntelligentTimingDashboard extends StatelessWidget {
  const IntelligentTimingDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Intelligent Timing Optimization'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OpenRateByHourChart(),
            const SizedBox(height: 24),
            _ABTestPerformance(),
            const SizedBox(height: 24),
            _SegmentPerformancePlaceholder(),
            const SizedBox(height: 24),
            _FrequencyMetrics(),
          ],
        ),
      ),
    );
  }
}

class _OpenRateByHourChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final thirtyDaysAgo =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('sentAt', isGreaterThanOrEqualTo: thirtyDaysAgo)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final byHour = <int, List<Map<String, dynamic>>>{};
        for (final doc in snapshot.data!.docs) {
          final d = doc.data();
          final sentAt = d['sentAt'] as Timestamp?;
          if (sentAt == null) continue;
          final hour = sentAt.toDate().hour;
          byHour.putIfAbsent(hour, () => []).add(d);
        }

        final sortedHours = byHour.keys.toList()..sort();
        if (sortedHours.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Open Rate by Hour of Day',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notification data in the last 30 days.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        }

        final groups = sortedHours.map((hour) {
          final notifs = byHour[hour]!;
          final sent = notifs.length;
          final opened = notifs.where((n) => n['openedAt'] != null).length;
          final rate = sent > 0 ? opened / sent : 0.0;
          return _HourlyData(hour, rate, sent);
        }).toList();

        final maxRate =
            groups.map((g) => g.openRate).reduce((a, b) => a > b ? a : b);
        final maxY = maxRate > 0 ? maxRate + 0.1 : 1.0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Open Rate by Hour of Day',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barTouchData: BarTouchData(enabled: false),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 && idx < groups.length) {
                                return Text('${groups[idx].hour}h');
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) => Text(
                              '${(value * 100).toInt()}%',
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: const FlGridData(show: true),
                      borderData: FlBorderData(show: true),
                      barGroups: groups.asMap().entries.map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.openRate,
                              color: Colors.blue,
                              width: 16,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ],
                          showingTooltipIndicators: [0],
                        );
                      }).toList(),
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

class _HourlyData {
  final int hour;
  final double openRate;
  final int sent;

  _HourlyData(this.hour, this.openRate, this.sent);
}

class _ABTestPerformance extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final thirtyDaysAgo =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('sentAt', isGreaterThanOrEqualTo: thirtyDaysAgo)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final abNotifs = snapshot.data!.docs
            .where((d) {
              final data = d.data()['data'];
              if (data is! Map) return false;
              return data['abTest'] == 'recommendation_timing_test';
            })
            .toList();

        final byVariant = <String, List<Map<String, dynamic>>>{};
        for (final doc in abNotifs) {
          final d = doc.data();
          final variant =
              (d['data'] as Map?)?['abVariant']?.toString() ?? 'unknown';
          byVariant.putIfAbsent(variant, () => []).add(d);
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A/B Test: Recommendation Timing',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                if (byVariant.isEmpty)
                  Text(
                    'No A/B test data yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  )
                else
                  ...byVariant.entries.map((e) {
                    final variant = e.key;
                    final notifs = e.value;
                    final sent = notifs.length;
                    final opened =
                        notifs.where((n) => n['openedAt'] != null).length;
                    final rate =
                        sent > 0 ? (opened / sent * 100).toStringAsFixed(1) : '0';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              variant,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: sent > 0 ? opened / sent : 0,
                              backgroundColor: Colors.grey[200],
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(
                                    Colors.green,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$rate% ($opened/$sent)'),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SegmentPerformancePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Segment Performance',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Coming soon',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrequencyMetrics extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sevenDaysAgo =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('sentAt', isGreaterThanOrEqualTo: sevenDaysAgo)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final notifications = snapshot.data!.docs;
        final byUser = <String, int>{};
        for (final doc in notifications) {
          final userId = doc.data()['userId']?.toString() ?? '';
          if (userId.isNotEmpty) {
            byUser[userId] = (byUser[userId] ?? 0) + 1;
          }
        }

        final total = notifications.length;
        final avgPerUser =
            byUser.isEmpty ? 0.0 : total / byUser.length;
        final usersWithMany =
            byUser.values.where((c) => c > 5).length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frequency Management',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _buildMetricRow(
                  context,
                  'Total notifications (7d)',
                  total.toString(),
                ),
                _buildMetricRow(
                  context,
                  'Avg per user',
                  avgPerUser.toStringAsFixed(1),
                ),
                _buildMetricRow(
                  context,
                  'Users with >5 notifications',
                  usersWithMany.toString(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
