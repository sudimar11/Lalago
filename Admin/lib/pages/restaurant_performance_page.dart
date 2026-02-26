import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:brgy/pages/pickup_issues_page.dart';
import 'package:brgy/pages/restaurant_performance_details.dart';
import 'package:brgy/services/restaurant_performance_service.dart';

enum _DateRange { today, week, month }

class RestaurantPerformancePage extends StatefulWidget {
  const RestaurantPerformancePage({super.key});

  @override
  State<RestaurantPerformancePage> createState() =>
      _RestaurantPerformancePageState();
}

class _RestaurantPerformancePageState extends State<RestaurantPerformancePage> {
  _DateRange _dateRange = _DateRange.week;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  (DateTime, DateTime) _getRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_dateRange) {
      case _DateRange.today:
        return (today, today.add(const Duration(days: 1)));
      case _DateRange.week:
        final start = today.subtract(const Duration(days: 6));
        return (start, today.add(const Duration(days: 1)));
      case _DateRange.month:
        final start = today.subtract(const Duration(days: 29));
        return (start, today.add(const Duration(days: 1)));
    }
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (start, end) = _getRange();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Performance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.report_problem),
            tooltip: 'Pickup Issues',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PickupIssuesPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: FutureBuilder<Map<String, dynamic>>(
          future: RestaurantPerformanceService.getPerformanceSummary(
            start: start,
            end: end,
          ),
          builder: (context, summarySnap) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: RestaurantPerformanceService.getRestaurantsStream(),
              builder: (context, vendorsSnap) {
                if (vendorsSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (vendorsSnap.hasError) {
                  return Center(
                    child: Text('Error: ${vendorsSnap.error}'),
                  );
                }

                final vendors = vendorsSnap.data ?? [];
                final filtered = vendors.where((v) {
                  if (_query.isEmpty) return true;
                  final title =
                      (v['title'] ?? '').toString().toLowerCase();
                  return title.contains(_query);
                }).toList();

                final summary = summarySnap.data ?? {};

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSummaryCards(summary),
                      const SizedBox(height: 16),
                      _buildFilters(),
                      const SizedBox(height: 16),
                      _buildChartSection(start, end),
                      const SizedBox(height: 24),
                      const Text(
                        'Restaurants',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildRestaurantTable(
                        context,
                        filtered,
                        start,
                        end,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCards(Map<String, dynamic> summary) {
    final total = summary['totalRestaurants'] as int? ?? 0;
    final active = summary['activeToday'] as int? ?? 0;
    final paused = summary['paused'] as int? ?? 0;
    final flagged = summary['flagged'] as int? ?? 0;
    final avgRate =
        (summary['avgAcceptanceRate'] as num?)?.toDouble() ?? 100.0;
    final activePct = total > 0 ? (active / total * 100).toStringAsFixed(1) : '0';
    final pausedPct = total > 0 ? (paused / total * 100).toStringAsFixed(1) : '0';
    final flaggedPct =
        total > 0 ? (flagged / total * 100).toStringAsFixed(1) : '0';

    return Row(
      children: [
        Expanded(
          child: _summaryCard('Total', '$total', Colors.grey),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryCard('Active', '$active ($activePct%)', Colors.green),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryCard('Paused', '$paused ($pausedPct%)', Colors.orange),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryCard('Flagged', '$flagged ($flaggedPct%)', Colors.red),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _summaryCard(
            'Avg Rate',
            '${avgRate.toStringAsFixed(1)}%',
            Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Date Range',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_DateRange>(
              segments: const [
                ButtonSegment(
                  value: _DateRange.today,
                  label: Text('Today'),
                  icon: Icon(Icons.today, size: 18),
                ),
                ButtonSegment(
                  value: _DateRange.week,
                  label: Text('This Week'),
                  icon: Icon(Icons.date_range, size: 18),
                ),
                ButtonSegment(
                  value: _DateRange.month,
                  label: Text('This Month'),
                  icon: Icon(Icons.calendar_month, size: 18),
                ),
              ],
              selected: {_dateRange},
              onSelectionChanged: (s) =>
                  setState(() => _dateRange = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search restaurants',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartSection(DateTime start, DateTime end) {
    return FutureBuilder<Map<String, double>>(
      future: RestaurantPerformanceService.getAcceptanceRateByDay(
        start: start,
        end: end,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
            child: SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snap.data ?? {};
        if (data.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No chart data for selected range',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        final sortedDates = data.keys.toList()..sort();
        final spots = <FlSpot>[];
        for (var i = 0; i < sortedDates.length; i++) {
          spots.add(FlSpot(i.toDouble(), data[sortedDates[i]]!));
        }
        final maxY =
            data.values.isEmpty ? 100.0 : data.values.reduce((a, b) => a > b ? a : b);
        final minY =
            data.values.isEmpty ? 0.0 : data.values.reduce((a, b) => a < b ? a : b);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Average Acceptance Rate Over Time',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      gridData: FlGridData(
                        show: true,
                        horizontalInterval: 20,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: Colors.grey[300]!,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}%',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: 1,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i >= 0 && i < sortedDates.length) {
                                final d = sortedDates[i];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    d.length >= 10 ? d.substring(5) : d,
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
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      minX: 0,
                      maxX: (sortedDates.length - 1).toDouble(),
                      minY: (minY - 5).clamp(0, 100),
                      maxY: (maxY + 5).clamp(0, 100),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: Colors.orange,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.orange.withValues(alpha: 0.1),
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

  Widget _buildRestaurantTable(
    BuildContext context,
    List<Map<String, dynamic>> vendors,
    DateTime start,
    DateTime end,
  ) {
    if (vendors.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No restaurants found')),
        ),
      );
    }

    return Card(
      child: Column(
        children: vendors.map((v) => _buildRestaurantRow(context, v, start, end)).toList(),
      ),
    );
  }

  Widget _buildRestaurantRow(
    BuildContext context,
    Map<String, dynamic> v,
    DateTime start,
    DateTime end,
  ) {
    final id = v['id'] as String;
    final title = (v['title'] ?? 'Unknown').toString();
    final reststatus = v['reststatus'] as bool? ?? false;
    final autoPause = v['autoPause'] as Map<String, dynamic>? ?? {};
    final isPaused = autoPause['isPaused'] == true;
    final metrics = v['acceptanceMetrics'] as Map<String, dynamic>? ?? {};
    final consecutive =
        (metrics['consecutiveUnaccepted'] as num?)?.toInt() ?? 0;

    String statusText = 'Offline';
    Color statusColor = Colors.grey;
    if (isPaused) {
      statusText = 'Paused';
      statusColor = Colors.orange;
    } else if (reststatus) {
      statusText = 'Active';
      statusColor = Colors.green;
    }

    return FutureBuilder<Map<String, int>>(
      future: RestaurantPerformanceService.getOrderCountsForVendor(
        vendorId: id,
        start: start,
        end: end,
      ),
      builder: (context, countsSnap) {
        final total = countsSnap.data?['total'] ?? 0;
        final accepted = countsSnap.data?['accepted'] ?? 0;
        final missed = countsSnap.data?['missed'] ?? 0;
        final rate = total > 0 ? (accepted / total * 100) : 100.0;

        return ListTile(
          title: InkWell(
            onTap: () => _openRestaurantDetails(context, id, title),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          subtitle: Text('$statusText • Orders: $total • Accepted: $accepted '
              '• Missed: $missed • Rate: ${rate.toStringAsFixed(1)}% • '
              'Consecutive misses: $consecutive'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'View details',
                onPressed: () => _openRestaurantDetails(context, id, title),
              ),
              IconButton(
                icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                tooltip: isPaused ? 'Resume' : 'Pause',
                onPressed: () => _showPauseDialog(context, id, title, isPaused),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openRestaurantDetails(BuildContext context, String id, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestaurantPerformanceDetailsPage(
          vendorId: id,
          vendorName: title,
        ),
      ),
    );
  }

  void _showPauseDialog(
    BuildContext context,
    String vendorId,
    String title,
    bool isPaused,
  ) async {
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isPaused ? 'Resume $title?' : 'Pause $title?'),
        content: Text(
          isPaused
              ? 'This restaurant will start receiving orders again.'
              : 'This restaurant will stop receiving orders until resumed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isPaused ? Colors.green : Colors.red,
            ),
            child: Text(isPaused ? 'Resume' : 'Pause'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await RestaurantPerformanceService.setRestaurantPauseStatus(
        vendorId: vendorId,
        isPaused: !isPaused,
        reason: isPaused ? 'admin_unpause' : 'manual',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isPaused ? 'Restaurant is now online' : 'Restaurant paused',
          ),
          backgroundColor: isPaused ? Colors.green : Colors.orange,
        ),
      );
      setState(() {});
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
