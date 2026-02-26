import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:brgy/constants.dart';

class ClickAnalyticsDashboard extends StatefulWidget {
  const ClickAnalyticsDashboard({super.key});

  @override
  State<ClickAnalyticsDashboard> createState() => _ClickAnalyticsDashboardState();
}

class _ClickAnalyticsDashboardState extends State<ClickAnalyticsDashboard> {
  String _selectedPeriod = 'week';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));

  void _changePeriod(String value) {
    setState(() {
      _selectedPeriod = value;
      final now = DateTime.now();
      switch (value) {
        case 'today':
          _startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          _startDate = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          _startDate = now.subtract(const Duration(days: 30));
          break;
        default:
          _startDate = now.subtract(const Duration(days: 7));
      }
    });
  }

  Stream<QuerySnapshot> _getClicksStream() {
    final startTs = Timestamp.fromDate(_startDate);
    return FirebaseFirestore.instance
        .collection(USER_CLICKS)
        .where('timestamp', isGreaterThanOrEqualTo: startTs)
        .orderBy('timestamp', descending: true)
        .limit(1000)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Click Analytics'),
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
            _buildClickSourceChart(),
            const SizedBox(height: 24),
            _buildTopClickedRestaurants(),
            const SizedBox(height: 24),
            _buildClickConversionTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildClickSourceChart() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getClicksStream(),
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
        final Map<String, int> sourceCounts = {};
        for (final d in docs) {
          final src = (d.get('source') ?? 'unknown').toString();
          sourceCounts[src] = (sourceCounts[src] ?? 0) + 1;
        }

        final entries = sourceCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final colors = [
          Colors.orange,
          Colors.green,
          Colors.blue,
          Colors.purple,
          Colors.teal,
        ];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clicks by Source',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No click data in selected period'),
                  )
                else
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sections: List.generate(
                          entries.length > 5 ? 5 : entries.length,
                          (i) {
                            final e = entries[i];
                            return PieChartSectionData(
                              value: e.value.toDouble(),
                              title: e.key,
                              color: colors[i % colors.length],
                              radius: 60,
                              titleStyle: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                        sectionsSpace: 2,
                        centerSpaceRadius: 0,
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

  Widget _buildTopClickedRestaurants() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getClicksStream(),
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
        final Map<String, int> restCounts = {};
        final Map<String, int> restConversions = {};
        for (final d in docs) {
          final rid = (d.get('restaurantId') ?? '').toString();
          if (rid.isEmpty) continue;
          restCounts[rid] = (restCounts[rid] ?? 0) + 1;
          if (d.get('convertedToOrder') == true) {
            restConversions[rid] = (restConversions[rid] ?? 0) + 1;
          }
        }

        final sorted = restCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top10 = sorted.take(10).toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Top Clicked Restaurants',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (top10.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No click data in selected period'),
                  )
                else
                  FutureBuilder<Map<String, String>>(
                    future: _fetchRestaurantNames(
                      top10.map((e) => e.key).toList(),
                    ),
                    builder: (context, nameSnap) {
                      final names = nameSnap.data ?? {};
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: top10.length,
                        itemBuilder: (context, index) {
                          final e = top10[index];
                          final name = names[e.key] ?? e.key;
                          final conv = restConversions[e.key] ?? 0;
                          final rate = e.value > 0
                              ? (conv / e.value * 100).toStringAsFixed(1)
                              : '0';
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.orange,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            title: Text(name),
                            subtitle: Text(
                              '${e.value} clicks • $rate% conversion',
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
      },
    );
  }

  Future<Map<String, String>> _fetchRestaurantNames(
    List<String> restaurantIds,
  ) async {
    final Map<String, String> result = {};
    for (final id in restaurantIds) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('vendors')
            .doc(id)
            .get();
        if (doc.exists) {
          result[id] = doc.get('title') ?? id;
        } else {
          result[id] = id;
        }
      } catch (_) {
        result[id] = id;
      }
    }
    return result;
  }

  Widget _buildClickConversionTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getClicksStream(),
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
        final Map<String, int> sourceClicks = {};
        final Map<String, int> sourceOrders = {};
        for (final d in docs) {
          final src = (d.get('source') ?? 'unknown').toString();
          sourceClicks[src] = (sourceClicks[src] ?? 0) + 1;
          if (d.get('convertedToOrder') == true) {
            sourceOrders[src] = (sourceOrders[src] ?? 0) + 1;
          }
        }

        final sources = sourceClicks.keys.toList()..sort();
        final totalClicks = docs.length;
        final totalOrders =
            docs.where((d) => d.get('convertedToOrder') == true).length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Click to Order Conversion',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Table(
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(
                        color: Colors.orange,
                      ),
                      children: [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Source',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Clicks',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Orders',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            'Conv. %',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    TableRow(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('Total'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('$totalClicks'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('$totalOrders'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            totalClicks > 0
                                ? '${(totalOrders / totalClicks * 100).toStringAsFixed(1)}%'
                                : '0%',
                          ),
                        ),
                      ],
                    ),
                    ...sources.map(
                      (src) => TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(src),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('${sourceClicks[src] ?? 0}'),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('${sourceOrders[src] ?? 0}'),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              (sourceClicks[src] ?? 0) > 0
                                  ? '${((sourceOrders[src] ?? 0) / (sourceClicks[src] ?? 1) * 100).toStringAsFixed(1)}%'
                                  : '0%',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
