import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UnifiedAnalyticsDashboard extends StatefulWidget {
  const UnifiedAnalyticsDashboard({super.key});

  @override
  State<UnifiedAnalyticsDashboard> createState() =>
      _UnifiedAnalyticsDashboardState();
}

class _UnifiedAnalyticsDashboardState extends State<UnifiedAnalyticsDashboard> {
  String _selectedTimeRange = 'last_30_days';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unified Analytics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          DropdownButton<String>(
            value: _selectedTimeRange,
            dropdownColor: Colors.grey[900],
            items: const [
              DropdownMenuItem(value: 'today', child: Text('Today')),
              DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
              DropdownMenuItem(value: 'last_7_days', child: Text('Last 7 Days')),
              DropdownMenuItem(
                value: 'last_30_days',
                child: Text('Last 30 Days'),
              ),
              DropdownMenuItem(
                value: 'last_90_days',
                child: Text('Last 90 Days'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedTimeRange = value);
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _KPICards(),
            const SizedBox(height: 24),
            _PerformanceCharts(),
            const SizedBox(height: 24),
            _SegmentationBreakdown(),
            const SizedBox(height: 24),
            _NotificationPerformance(),
            const SizedBox(height: 24),
            _RevenueAttribution(),
            const SizedBox(height: 24),
            _TopPerformingRestaurants(),
          ],
        ),
      ),
    );
  }

  Widget _KPICards() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _fetchAggregatedMetrics(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final metrics = snapshot.data ?? {};
        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount =
                constraints.maxWidth > 800 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.8,
              children: [
                _buildKPICard(
                  'Active Users',
                  metrics['activeUsers']?.toString() ?? '0',
                  Icons.people,
                  Colors.blue,
                ),
                _buildKPICard(
                  'Total Orders',
                  metrics['totalOrders']?.toString() ?? '0',
                  Icons.shopping_bag,
                  Colors.green,
                ),
                _buildKPICard(
                  'Revenue',
                  '₱${(metrics['totalRevenue'] as num?)?.toStringAsFixed(0) ?? '0'}',
                  Icons.attach_money,
                  Colors.orange,
                ),
                _buildKPICard(
                  'Conversion Rate',
                  '${(metrics['conversionRate'] as num?)?.toStringAsFixed(1) ?? '0'}%',
                  Icons.trending_up,
                  Colors.purple,
                ),
                _buildKPICard(
                  'Notification Opens',
                  metrics['notificationOpens']?.toString() ?? '0',
                  Icons.notifications,
                  Colors.red,
                ),
                _buildKPICard(
                  'Avg Order Value',
                  '₱${(metrics['avgOrderValue'] as num?)?.toStringAsFixed(0) ?? '0'}',
                  Icons.receipt,
                  Colors.indigo,
                ),
                _buildKPICard(
                  'Avg LTV',
                  '₱${(metrics['avgLTV'] as num?)?.toStringAsFixed(0) ?? '0'}',
                  Icons.timeline,
                  Colors.pink,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildKPICard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _PerformanceCharts() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Trends',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: _buildTimeSeriesChart(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSeriesChart() {
    final days = _getDaysForRange();
    return FutureBuilder<List<_ChartData>>(
      future: _fetchChartData(days),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'No data yet',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }
        final data = snapshot.data!;
        return LineChart(
          LineChartData(
            gridData: FlGridData(show: true),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    if (value.toInt() >= 0 && value.toInt() < data.length) {
                      final d = data[value.toInt()];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          d.dateStr,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10,
                          ),
                        ),
                      );
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
                    '₱${value.toInt()}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10,
                    ),
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
            borderData: FlBorderData(show: true),
            lineBarsData: [
              LineChartBarData(
                spots: data
                    .asMap()
                    .entries
                    .map((e) => FlSpot(
                          e.key.toDouble(),
                          e.value.revenue,
                        ))
                    .toList(),
                isCurved: true,
                color: Colors.green,
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 250),
        );
      },
    );
  }

  Widget _SegmentationBreakdown() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User Segments',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('user_daily_metrics')
                  .orderBy(FieldPath.documentId, descending: true)
                  .limit(1)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Text(
                    'No segment data yet',
                    style: TextStyle(color: Colors.grey[600]),
                  );
                }
                final doc = snapshot.data!.docs.first;
                final data = doc.data();
                final bySegment =
                    (data['bySegment'] as Map<String, dynamic>?) ?? {};
                final total = (data['activeUsers'] as int?) ?? 1;

                return Column(
                  children: bySegment.entries.map((entry) {
                    final segment = entry.key;
                    final count = (entry.value as num).toInt();
                    final pct =
                        total > 0 ? (count / total * 100).toStringAsFixed(1) : '0';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              segment,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: total > 0 ? count / total : 0,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _segmentColor(segment),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$count ($pct%)'),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _segmentColor(String segment) {
    switch (segment) {
      case 'power_user':
        return Colors.purple;
      case 'regular':
        return Colors.blue;
      case 'active':
        return Colors.green;
      case 'new':
        return Colors.orange;
      case 'inactive':
        return Colors.grey;
      case 'at_risk':
        return Colors.red;
      case 'churned':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  Widget _NotificationPerformance() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Performance',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notification_aggregates')
                  .orderBy(FieldPath.documentId, descending: true)
                  .limit(7)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Text(
                    'No notification aggregates yet',
                    style: TextStyle(color: Colors.grey[600]),
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Sent')),
                      DataColumn(label: Text('Opens')),
                      DataColumn(label: Text('Open Rate')),
                      DataColumn(label: Text('Conversions')),
                      DataColumn(label: Text('Conv. Rate')),
                    ],
                    rows: docs.map((doc) {
                      final d = doc.data();
                      final total = (d['total'] as num?)?.toInt() ?? 0;
                      final opened = (d['opened'] as num?)?.toInt() ??
                          ((d['byAction'] as Map?)?['opened'] as num?)?.toInt() ??
                          0;
                      final conversions = (d['conversions'] as num?)?.toInt() ?? 0;
                      final openRate = (d['openRate'] as num?) ?? 0.0;
                      final convRate = (d['conversionRate'] as num?) ?? 0.0;
                      return DataRow(
                        cells: [
                          DataCell(Text(d['date']?.toString() ?? '')),
                          DataCell(Text(total.toString())),
                          DataCell(Text(opened.toString())),
                          DataCell(Text('${openRate.toStringAsFixed(1)}%')),
                          DataCell(Text(conversions.toString())),
                          DataCell(Text('${convRate.toStringAsFixed(1)}%')),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _RevenueAttribution() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Revenue Attribution',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('conversion_events')
                  .orderBy('convertedAt', descending: true)
                  .limit(500)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final conversions = snapshot.data!.docs;
                final bySource = <String, double>{};
                double totalRevenue = 0;
                final startDate = _getStartDate();

                for (final doc in conversions) {
                  final data = doc.data();
                  final ts = data['convertedAt'] as Timestamp?;
                  if (ts != null && ts.toDate().isBefore(startDate)) {
                    continue;
                  }
                  final source = (data['sourceType'] as String?) ?? 'direct';
                  final value =
                      (data['orderValue'] as num?)?.toDouble() ?? 0.0;
                  bySource[source] = (bySource[source] ?? 0) + value;
                  totalRevenue += value;
                }

                if (bySource.isEmpty) {
                  return Text(
                    'No conversion data yet',
                    style: TextStyle(color: Colors.grey[600]),
                  );
                }

                return Column(
                  children: bySource.entries.map((entry) {
                    final pct = totalRevenue > 0
                        ? (entry.value / totalRevenue * 100)
                            .toStringAsFixed(1)
                        : '0';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: totalRevenue > 0
                                  ? entry.value / totalRevenue
                                  : 0,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₱${entry.value.toStringAsFixed(0)} ($pct%)',
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _TopPerformingRestaurants() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Performing Restaurants',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: _getLatestRevenueDoc(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return Text(
                    'No revenue data yet',
                    style: TextStyle(color: Colors.grey[600]),
                  );
                }
                final data = snapshot.data!.data() ?? {};
                final byRestaurant =
                    (data['byRestaurant'] as Map<String, dynamic>?) ?? {};
                final sorted = byRestaurant.entries.toList()
                  ..sort((a, b) =>
                      (b.value as num).compareTo(a.value as num));

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sorted.length > 10 ? 10 : sorted.length,
                  itemBuilder: (ctx, i) {
                    final entry = sorted[i];
                    final id = entry.key;
                    final shortId =
                        id.length > 8 ? '${id.substring(0, 8)}...' : id;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.amber,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      title: Text('Restaurant $shortId'),
                      trailing: Text(
                        '₱${(entry.value as num).toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getDaysForRange() {
    final now = DateTime.now();
    final count = _selectedTimeRange == 'last_7_days'
        ? 7
        : _selectedTimeRange == 'last_30_days'
            ? 30
            : 90;
    return List.generate(count, (i) {
      final d = now.subtract(Duration(days: count - 1 - i));
      return DateFormat('yyyy-MM-dd').format(d);
    });
  }

  DateTime _getStartDate() {
    final now = DateTime.now();
    switch (_selectedTimeRange) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        return DateTime(y.year, y.month, y.day);
      case 'last_7_days':
        return now.subtract(const Duration(days: 7));
      case 'last_30_days':
        return now.subtract(const Duration(days: 30));
      case 'last_90_days':
        return now.subtract(const Duration(days: 90));
      default:
        return now.subtract(const Duration(days: 30));
    }
  }

  Future<Map<String, dynamic>> _fetchAggregatedMetrics() async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final yesterday =
        DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

    final notifSnap =
        await db.collection('notification_aggregates').doc(yesterday).get();
    final userSnap =
        await db.collection('user_daily_metrics').doc(yesterday).get();
    final revenueSnap =
        await db.collection('revenue_daily_metrics').doc(yesterday).get();
    final ltvSnap = await db
        .collection('ltv_aggregates')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    final notifData = notifSnap.data();
    final userData = userSnap.data();
    final revenueData = revenueSnap.data();
    final ltvData = ltvSnap.docs.isNotEmpty ? ltvSnap.docs.first.data() : null;

    return {
      'activeUsers': (userData?['activeUsers'] as num?)?.toInt() ?? 0,
      'totalOrders': (revenueData?['orderCount'] as num?)?.toInt() ?? 0,
      'totalRevenue': (revenueData?['totalRevenue'] as num?)?.toDouble() ?? 0,
      'avgOrderValue':
          (revenueData?['averageOrderValue'] as num?)?.toDouble() ?? 0,
      'conversionRate':
          (notifData?['conversionRate'] as num?)?.toDouble() ?? 0,
      'notificationOpens': (notifData?['opened'] as num?)?.toInt() ?? 0,
      'avgLTV': (ltvData?['averageLTV'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<List<_ChartData>> _fetchChartData(List<String> days) async {
    final db = FirebaseFirestore.instance;
    final result = <_ChartData>[];
    for (final dateStr in days) {
      final doc = await db
          .collection('revenue_daily_metrics')
          .doc(dateStr)
          .get();
      if (doc.exists) {
        final d = doc.data() ?? {};
        result.add(_ChartData(
          DateTime.parse(dateStr),
          (d['totalRevenue'] as num?)?.toDouble() ?? 0,
          (d['orderCount'] as num?)?.toInt() ?? 0,
        ));
      }
    }
    return result;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getLatestRevenueDoc() async {
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(d);
      final doc = await FirebaseFirestore.instance
          .collection('revenue_daily_metrics')
          .doc(dateStr)
          .get();
      if (doc.exists) return doc;
    }
    return FirebaseFirestore.instance
        .collection('revenue_daily_metrics')
        .doc('1970-01-01')
        .get();
  }
}

class _ChartData {
  final DateTime date;
  final double revenue;
  final int orders;

  _ChartData(this.date, this.revenue, this.orders);

  String get dateStr => DateFormat('MM/dd').format(date);
}
