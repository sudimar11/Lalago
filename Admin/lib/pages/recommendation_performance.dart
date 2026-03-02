import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:brgy/constants.dart';

class RecommendationPerformance extends StatefulWidget {
  const RecommendationPerformance({super.key});

  @override
  State<RecommendationPerformance> createState() =>
      _RecommendationPerformanceState();
}

class _RecommendationPerformanceState extends State<RecommendationPerformance> {
  String _selectedPeriod = 'week';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  bool _autoBoost = true;
  double _boostPercentage = 15;

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
        .limit(2000)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommendation Performance'),
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
            _buildStrategyComparison(),
            const SizedBox(height: 24),
            _buildRecommendationNotifications(),
            const SizedBox(height: 24),
            _buildABTestConfig(),
            const SizedBox(height: 24),
            _buildManualBoostSettings(),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategyComparison() {
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

        final strategies = [
          'order_again',
          'trending_now',
          'time_based',
          'new_arrivals',
          'top_restaurants',
          'category_food',
          'all_restaurants',
          'popular_today',
          'search_results',
        ];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recommendation Strategy Performance',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Strategy')),
                      DataColumn(label: Text('Clicks')),
                      DataColumn(label: Text('Orders')),
                      DataColumn(label: Text('Conv. %')),
                    ],
                    rows: strategies.map((s) {
                      final clicks = sourceClicks[s] ?? 0;
                      final orders = sourceOrders[s] ?? 0;
                      final conv =
                          clicks > 0 ? (orders / clicks * 100).toStringAsFixed(1) : '0';
                      return DataRow(
                        cells: [
                          DataCell(Text(s)),
                          DataCell(Text('$clicks')),
                          DataCell(Text('$orders')),
                          DataCell(Text('$conv%')),
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

  Stream<QuerySnapshot> _getAshRecommendationStream() {
    final startTs = Timestamp.fromDate(_startDate);
    return FirebaseFirestore.instance
        .collection('ash_notification_history')
        .where('type', isEqualTo: 'ash_recommendation')
        .where('sentAt', isGreaterThanOrEqualTo: startTs)
        .orderBy('sentAt', descending: true)
        .limit(2000)
        .snapshots();
  }

  Widget _buildRecommendationNotifications() {
    return StreamBuilder<QuerySnapshot>(
      stream: _getAshRecommendationStream(),
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
        final byType = <String, List<QueryDocumentSnapshot<Object?>>>{};
        for (final d in docs) {
          var type = d.get('recommendationType')?.toString();
          if (type == null || type.isEmpty) {
            final data = d.get('data');
            if (data is Map && data['reason'] != null) {
              type = data['reason'].toString();
            }
          }
          type ??= 'unknown';
          byType.putIfAbsent(type, () => []).add(d);
        }
        final types = byType.keys.toList()..sort();
        if (types.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ash Recommendation Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No ash_recommendation notifications sent yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
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
                const Text(
                  'Ash Recommendation Notifications',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('Sent')),
                      DataColumn(label: Text('Opened')),
                      DataColumn(label: Text('Open %')),
                    ],
                    rows: types.map((type) {
                      final list = byType[type]!;
                      final sent = list.length;
                      final opened = list
                          .where((d) => d.get('openedAt') != null)
                          .length;
                      final openRate = sent > 0
                          ? (opened / sent * 100).toStringAsFixed(1)
                          : '0';
                      return DataRow(
                        cells: [
                          DataCell(Text(type)),
                          DataCell(Text('$sent')),
                          DataCell(Text('$opened')),
                          DataCell(Text('$openRate%')),
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

  Widget _buildABTestConfig() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A/B Test Configuration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Version A (Control)'),
              subtitle: const Text('Current algorithm - 50% of users'),
              trailing: Chip(
                label: const Text('50%'),
                backgroundColor: Colors.blue[100],
              ),
            ),
            LinearProgressIndicator(value: 0.5),
            ListTile(
              title: const Text('Version B (Test)'),
              subtitle: const Text('New collaborative filtering - 25%'),
              trailing: Chip(
                label: const Text('25%'),
                backgroundColor: Colors.orange[100],
              ),
            ),
            LinearProgressIndicator(value: 0.25),
            ListTile(
              title: const Text('Version C (Test)'),
              subtitle: const Text('Hybrid approach - 25%'),
              trailing: Chip(
                label: const Text('25%'),
                backgroundColor: Colors.orange[100],
              ),
            ),
            LinearProgressIndicator(value: 0.25),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Start New Test'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Stop Test'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualBoostSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manual Boost Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Auto-boost new restaurants'),
              subtitle: const Text(
                'Show new restaurants in discovery sections',
              ),
              value: _autoBoost,
              onChanged: (val) => setState(() => _autoBoost = val),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_boostPercentage.round()}% of recommendations '
                      'will be discovery items'),
                  Slider(
                    value: _boostPercentage,
                    min: 5,
                    max: 30,
                    divisions: 5,
                    label: '${_boostPercentage.round()}%',
                    onChanged: (val) =>
                        setState(() => _boostPercentage = val),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Boost specific restaurants',
                  hintText: 'Enter restaurant IDs (comma-separated)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
