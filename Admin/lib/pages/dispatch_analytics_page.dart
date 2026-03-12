import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/dispatch_analytics_service.dart';
import 'package:intl/intl.dart';

class DispatchAnalyticsPage extends StatefulWidget {
  const DispatchAnalyticsPage({super.key});

  @override
  State<DispatchAnalyticsPage> createState() =>
      _DispatchAnalyticsPageState();
}

class _DispatchAnalyticsPageState
    extends State<DispatchAnalyticsPage> {
  final _service = DispatchAnalyticsService();

  Map<String, dynamic>? _todayStats;
  List<Map<String, dynamic>> _weekStats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final results = await Future.wait([
      _service.getDailyStats(now),
      _service.getDailyStatsRange(from: weekAgo, to: now),
    ]);
    setState(() {
      _todayStats = results[0] as Map<String, dynamic>?;
      _weekStats =
          results[1] as List<Map<String, dynamic>>;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch Analytics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildKpiSection(),
                  const SizedBox(height: 24),
                  _buildTrendSection(),
                  const SizedBox(height: 24),
                  _buildRiderTable(),
                  const SizedBox(height: 24),
                  _buildZoneBreakdown(),
                  const SizedBox(height: 24),
                  _buildRecentEvents(),
                ],
              ),
            ),
    );
  }

  // --- Section 1: KPI Cards ---

  Widget _buildKpiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Today's Dispatch Metrics",
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_todayStats == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No dispatch data for today yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          )
        else
          _buildKpiGrid(),
      ],
    );
  }

  Widget _buildKpiGrid() {
    final s = _todayStats!;
    final cards = [
      _KpiData(
        'Success Rate',
        '${_num(s['successRate'])}%',
        Icons.check_circle,
        _num(s['successRate']) >= 80
            ? Colors.green
            : Colors.red,
      ),
      _KpiData(
        'Avg Response',
        '${_num(s['avgResponseTime']).round()}s',
        Icons.timer,
        Colors.blue,
      ),
      _KpiData(
        'Avg Delivery',
        '${_num(s['avgDeliveryTime']).toStringAsFixed(1)}m',
        Icons.delivery_dining,
        Colors.orange,
      ),
      _KpiData(
        'On-Time Rate',
        '${_num(s['onTimeRate'])}%',
        Icons.schedule,
        _num(s['onTimeRate']) >= 85
            ? Colors.green
            : Colors.amber,
      ),
      _KpiData(
        'Batch Rate',
        '${_num(s['batchRate'])}%',
        Icons.layers,
        Colors.deepPurple,
      ),
      _KpiData(
        'Total Dispatches',
        '${_num(s['totalDispatches']).round()}',
        Icons.local_shipping,
        Colors.teal,
      ),
      _KpiData(
        'Cust. Wait',
        '${_num(s['avgCustomerWaitMinutes']).round()}m',
        Icons.hourglass_bottom,
        _num(s['avgCustomerWaitMinutes']) <= 45
            ? Colors.green
            : Colors.red,
      ),
      _KpiData(
        'Avg Rejects',
        _num(s['avgRejectionsPerOrder'])
            .toStringAsFixed(1),
        Icons.thumb_down_alt,
        _num(s['avgRejectionsPerOrder']) <= 2
            ? Colors.green
            : Colors.red,
      ),
      _KpiData(
        'Dispatch Latency',
        '${_num(s['avgDispatchLatencySeconds']).round()}s',
        Icons.speed,
        _num(s['avgDispatchLatencySeconds']) <= 30
            ? Colors.green
            : Colors.amber,
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.4,
      children: cards.map(_buildKpiCard).toList(),
    );
  }

  Widget _buildKpiCard(_KpiData kpi) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(kpi.icon, color: kpi.color, size: 24),
            const SizedBox(height: 4),
            Text(
              kpi.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kpi.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              kpi.label,
              style: const TextStyle(
                  fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- Section 2: 7-Day Trend ---

  Widget _buildTrendSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('7-Day Trend',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_weekStats.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No weekly data available.'),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildBarChart(
                    'Success Rate %',
                    _weekStats,
                    'successRate',
                    Colors.green,
                  ),
                  const SizedBox(height: 16),
                  _buildBarChart(
                    'On-Time Rate %',
                    _weekStats,
                    'onTimeRate',
                    Colors.blue,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBarChart(
    String title,
    List<Map<String, dynamic>> data,
    String key,
    Color color,
  ) {
    final maxVal = data.fold<double>(
      1.0,
      (prev, e) {
        final v = _num(e[key]);
        return v > prev ? v : prev;
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.map((e) {
              final val = _num(e[key]);
              final frac =
                  maxVal > 0 ? val / maxVal : 0.0;
              final date =
                  (e['date'] ?? '').toString();
              final shortDate = date.length >= 5
                  ? date.substring(5)
                  : date;
              return Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(
                          horizontal: 2),
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.end,
                    children: [
                      Text(
                        '${val.round()}',
                        style: TextStyle(
                            fontSize: 9,
                            color: color),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        height: 36 * frac,
                        decoration: BoxDecoration(
                          color:
                              color.withOpacity(0.7),
                          borderRadius:
                              BorderRadius.circular(
                                  3),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(shortDate,
                          style: const TextStyle(
                              fontSize: 8)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // --- Section 3: Rider Acceptance Table ---

  Widget _buildRiderTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rider Acceptance Rates',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream:
              _service.streamRecentEvents(limit: 100),
          builder: (context, snap) {
            if (snap.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator());
            }
            final events = snap.data ?? [];
            if (events.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('No events yet.')),
                ),
              );
            }

            final riderMap =
                <String, _RiderStats>{};
            for (final e in events) {
              final rid =
                  (e['riderId'] ?? '').toString();
              if (rid.isEmpty) continue;
              riderMap.putIfAbsent(
                  rid, () => _RiderStats());
              riderMap[rid]!.total++;
              final out = e['outcome'] as Map?;
              if (out != null &&
                  out['wasAccepted'] == true) {
                riderMap[rid]!.accepted++;
              }
              final rt = out?['responseTimeSeconds'];
              if (rt is num) {
                riderMap[rid]!.totalResponseTime +=
                    rt.toDouble();
                riderMap[rid]!.responseCount++;
              }
            }

            final sorted = riderMap.entries.toList()
              ..sort((a, b) => b.value.rate
                  .compareTo(a.value.rate));
            final top =
                sorted.take(20).toList();

            return Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Rider')),
                    DataColumn(
                        label: Text('Accept %')),
                    DataColumn(
                        label: Text('Total')),
                    DataColumn(
                        label: Text('Avg Resp')),
                  ],
                  rows: top.map((entry) {
                    final s = entry.value;
                    final avgResp = s.responseCount > 0
                        ? (s.totalResponseTime /
                                s.responseCount)
                            .round()
                        : 0;
                    return DataRow(cells: [
                      DataCell(Text(
                        entry.key.length > 8
                            ? '${entry.key.substring(0, 8)}...'
                            : entry.key,
                        style: const TextStyle(
                            fontSize: 12),
                      )),
                      DataCell(Text(
                        '${s.rate.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                          color: s.rate >= 80
                              ? Colors.green
                              : Colors.red,
                        ),
                      )),
                      DataCell(
                          Text('${s.total}')),
                      DataCell(
                          Text('${avgResp}s')),
                    ]);
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // --- Section: Zone Breakdown ---

  Widget _buildZoneBreakdown() {
    final zoneData =
        _todayStats?['zoneBreakdown'] as Map<String, dynamic>?;
    if (zoneData == null || zoneData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Zone Breakdown',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...zoneData.entries.map((entry) {
          final zoneName = entry.key;
          final data =
              entry.value as Map<String, dynamic>? ?? {};
          final rate =
              (data['successRate'] as num?)?.toDouble() ?? 0;
          final total =
              (data['totalDispatches'] as num?)?.toInt() ?? 0;
          final color = rate >= 80
              ? Colors.green
              : rate >= 50
                  ? Colors.amber
                  : Colors.red;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        zoneName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${rate.round()}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$total orders',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- Section 4: Recent Events ---

  Widget _buildRecentEvents() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Dispatch Events',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream:
              _service.streamRecentEvents(limit: 20),
          builder: (context, snap) {
            if (snap.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator());
            }
            final events = snap.data ?? [];
            if (events.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text(
                          'No dispatch events.')),
                ),
              );
            }

            return Column(
              children: events
                  .map(_buildEventCard)
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEventCard(Map<String, dynamic> e) {
    final orderId =
        (e['orderId'] ?? '').toString();
    final riderId =
        (e['riderId'] ?? '').toString();
    final type = (e['type'] ?? '').toString();
    final score = e['totalScore'];
    final outcome = e['outcome'] as Map?;
    final accepted = outcome?['wasAccepted'];

    final ts = e['createdAt'];
    String timeStr = '';
    if (ts is Timestamp) {
      timeStr = DateFormat('HH:mm')
          .format(ts.toDate());
    }

    IconData statusIcon;
    Color statusColor;
    if (accepted == true) {
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
    } else if (accepted == false) {
      statusIcon = Icons.cancel;
      statusColor = Colors.red;
    } else {
      statusIcon = Icons.hourglass_empty;
      statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(statusIcon,
            color: statusColor, size: 20),
        title: Text(
          'Order ${orderId.length > 8 ? orderId.substring(0, 8) : orderId}...',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          '$type  |  $timeStr  |  '
          'Score: ${score != null ? (score as num).toStringAsFixed(3) : 'N/A'}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          riderId.length > 6
              ? '${riderId.substring(0, 6)}...'
              : riderId,
          style: const TextStyle(
              fontSize: 10, color: Colors.grey),
        ),
        children: [
          if (e['factors'] is Map)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: _buildFactorsTable(
                  e['factors'] as Map),
            ),
          if (e['scoringComponents'] is Map)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              child: _buildFactorsTable(
                  e['scoringComponents'] as Map),
            ),
        ],
      ),
    );
  }

  Widget _buildFactorsTable(Map factors) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: factors.entries.map((e) {
        final val = e.value;
        final display = val is double
            ? val.toStringAsFixed(3)
            : '$val';
        return Chip(
          label: Text(
            '${e.key}: $display',
            style: const TextStyle(fontSize: 10),
          ),
          padding: EdgeInsets.zero,
          materialTapTargetSize:
              MaterialTapTargetSize.shrinkWrap,
        );
      }).toList(),
    );
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return 0.0;
  }
}

class _KpiData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiData(
      this.label, this.value, this.icon, this.color);
}

class _RiderStats {
  int total = 0;
  int accepted = 0;
  double totalResponseTime = 0;
  int responseCount = 0;
  double get rate =>
      total > 0 ? (accepted / total) * 100 : 0;
}
