import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:brgy/constants.dart';

class SearchAnalyticsDashboard extends StatefulWidget {
  const SearchAnalyticsDashboard({super.key});

  @override
  State<SearchAnalyticsDashboard> createState() =>
      _SearchAnalyticsDashboardState();
}

class _SearchAnalyticsDashboardState extends State<SearchAnalyticsDashboard> {
  String _selectedPeriod = 'week';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  void _changePeriod(String value) {
    setState(() {
      _selectedPeriod = value;
      final now = DateTime.now();
      switch (value) {
        case 'today':
          _startDate = DateTime(now.year, now.month, now.day);
          _endDate = now;
          break;
        case 'week':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          break;
        case 'month':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        default:
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
      }
    });
  }

  Stream<QuerySnapshot> _getSearchStream() {
    final startTs = Timestamp.fromDate(_startDate);
    return FirebaseFirestore.instance
        .collection(SEARCH_ANALYTICS)
        .where('timestamp', isGreaterThanOrEqualTo: startTs)
        .orderBy('timestamp', descending: true)
        .limit(500)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Analytics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            onSelected: _changePeriod,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'today', child: Text('Today')),
              const PopupMenuItem(value: 'week', child: Text('This Week')),
              const PopupMenuItem(value: 'month', child: Text('This Month')),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(),
            const SizedBox(height: 24),
            _buildTopSearches(),
            const SizedBox(height: 24),
            _buildSearchToClickChart(),
            const SizedBox(height: 24),
            _buildZeroResultSearches(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getSearchStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        final totalSearches = docs.length;
        final searchesWithClicks =
            docs.where((d) => d.get('clickedRestaurantId') != null).length;
        final clickRate = totalSearches > 0
            ? (searchesWithClicks / totalSearches * 100).toStringAsFixed(1)
            : '0';
        int totalResults = 0;
        int zeroResults = 0;
        for (final d in docs) {
          final count = d.get('resultCount') ?? 0;
          totalResults += count is int ? count : 0;
          if (count == 0) zeroResults++;
        }
        final avgResults =
            totalSearches > 0 ? (totalResults / totalSearches).round() : 0;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildMetricCard(
              'Total Searches',
              '$totalSearches',
              Icons.search,
            ),
            _buildMetricCard(
              'Click Rate',
              '$clickRate%',
              Icons.touch_app,
            ),
            _buildMetricCard(
              'Avg Results',
              '$avgResults',
              Icons.list,
            ),
            _buildMetricCard(
              'Zero Results',
              '$zeroResults',
              Icons.warning_amber,
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.orange, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSearches() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getSearchStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final Map<String, int> queryCounts = {};
        final Map<String, int> queryClicks = {};
        for (final d in docs) {
          final q = (d.get('searchQuery') ?? '').toString().trim();
          if (q.isEmpty) continue;
          queryCounts[q] = (queryCounts[q] ?? 0) + 1;
          if (d.get('clickedRestaurantId') != null) {
            queryClicks[q] = (queryClicks[q] ?? 0) + 1;
          }
        }

        final sorted = queryCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top10 = sorted.take(10).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Top Search Queries',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (top10.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No search data in selected period'),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Query')),
                        DataColumn(label: Text('Count')),
                        DataColumn(label: Text('Click Rate')),
                      ],
                      rows: top10.map((e) {
                        final count = e.value;
                        final clicks = queryClicks[e.key] ?? 0;
                        final rate =
                            count > 0 ? (clicks / count * 100).toStringAsFixed(1) : '0';
                        return DataRow(
                          cells: [
                            DataCell(Text(e.key.isEmpty ? '(empty)' : e.key)),
                            DataCell(Text('$count')),
                            DataCell(Text('$rate%')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchToClickChart() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getSearchStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final totalSearches = docs.length;
        final clicks =
            docs.where((d) => d.get('clickedRestaurantId') != null).length;

        final values = [
          totalSearches.toDouble(),
          clicks.toDouble(),
        ];
        final maxVal = values.reduce((a, b) => a > b ? a : b);
        final maxY = maxVal > 0 ? maxVal + 2 : 5.0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Search to Click Funnel',
                  style: TextStyle(
                    fontSize: 18,
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
                              if (value.toInt() == 0) {
                                return const Text('Searches');
                              }
                              if (value.toInt() == 1) {
                                return const Text('Clicks');
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) =>
                                Text(value.toInt().toString()),
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(show: true),
                      borderData: FlBorderData(show: true),
                      barGroups: [
                        BarChartGroupData(
                          x: 0,
                          barRods: [
                            BarChartRodData(
                              toY: totalSearches.toDouble(),
                              color: Colors.orange,
                              width: 40,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ],
                          showingTooltipIndicators: [0],
                        ),
                        BarChartGroupData(
                          x: 1,
                          barRods: [
                            BarChartRodData(
                              toY: clicks.toDouble(),
                              color: Colors.green,
                              width: 40,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ],
                          showingTooltipIndicators: [0],
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

  Widget _buildZeroResultSearches() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getSearchStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final zeroResult =
            docs.where((d) => (d.get('resultCount') ?? 0) == 0).toList();

        final Map<String, int> zeroCounts = {};
        for (final d in zeroResult) {
          final q = (d.get('searchQuery') ?? '').toString().trim();
          if (q.isEmpty) continue;
          zeroCounts[q] = (zeroCounts[q] ?? 0) + 1;
        }

        final sorted = zeroCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top10 = sorted.take(10).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zero Result Searches',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (top10.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No zero-result searches in selected period'),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: top10.length,
                    itemBuilder: (context, index) {
                      final e = top10[index];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.orange[100],
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[800],
                            ),
                          ),
                        ),
                        title: Text(e.key.isEmpty ? '(empty)' : e.key),
                        trailing: Text(
                          '${e.value}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
