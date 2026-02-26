import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'package:brgy/services/restaurant_performance_service.dart';
import 'package:brgy/widgets/pause_management_section.dart';

class RestaurantPerformanceDetailsPage extends StatefulWidget {
  const RestaurantPerformanceDetailsPage({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  final String vendorId;
  final String vendorName;

  @override
  State<RestaurantPerformanceDetailsPage> createState() =>
      _RestaurantPerformanceDetailsPageState();
}

class _RestaurantPerformanceDetailsPageState
    extends State<RestaurantPerformanceDetailsPage> {
  Map<String, dynamic>? _vendorData;

  @override
  void initState() {
    super.initState();
    _loadVendor();
  }

  Future<void> _loadVendor() async {
    final doc = await FirebaseFirestore.instance
        .collection('vendors')
        .doc(widget.vendorId)
        .get();
    if (mounted) {
      setState(() {
        _vendorData = doc.exists ? doc.data() : null;
      });
    }
  }

  (DateTime, DateTime) _getLast30Days() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day).add(
      const Duration(days: 1),
    );
    final start = end.subtract(const Duration(days: 30));
    return (start, end);
  }

  @override
  Widget build(BuildContext context) {
    final vendorData = _vendorData ?? {};
    final autoPause = vendorData['autoPause'] as Map<String, dynamic>? ?? {};
    final isPaused = autoPause['isPaused'] == true;
    final reststatus = vendorData['reststatus'] == true;

    String statusText = 'Offline';
    Color statusColor = Colors.grey;
    if (isPaused) {
      statusText = 'Paused';
      statusColor = Colors.orange;
    } else if (reststatus) {
      statusText = 'Active';
      statusColor = Colors.green;
    }

    final (start, end) = _getLast30Days();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vendorName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadVendor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(statusText, statusColor),
              const SizedBox(height: 16),
              _buildSummaryCards(start, end),
              const SizedBox(height: 24),
              _buildAcceptanceRateChart(start, end),
              const SizedBox(height: 24),
              _buildCoordinationSection(),
              const SizedBox(height: 24),
              _buildMissedOrdersChart(start, end),
              const SizedBox(height: 24),
              _buildPauseHistorySection(),
              const SizedBox(height: 24),
              PauseManagementSection(
                vendorId: widget.vendorId,
                currentPauseStatus: autoPause,
                onStatusChanged: _loadVendor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String statusText, Color statusColor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.vendorName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 14,
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(DateTime start, DateTime end) {
    return FutureBuilder<Map<String, int>>(
      future: RestaurantPerformanceService.getOrderCountsForVendor(
        vendorId: widget.vendorId,
        start: start,
        end: end,
      ),
      builder: (context, snap) {
        final total = snap.data?['total'] ?? 0;
        final accepted = snap.data?['accepted'] ?? 0;
        final missed = snap.data?['missed'] ?? 0;
        final rate = total > 0 ? (accepted / total * 100) : 100.0;
        final metrics = _vendorData?['acceptanceMetrics'] ?? {};
        final consecutive =
            (metrics['consecutiveUnaccepted'] as num?)?.toInt() ?? 0;

        return Row(
          children: [
            Expanded(
              child: _detailCard('Orders (30d)', '$total', Colors.blue),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _detailCard('Accepted', '$accepted', Colors.green),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _detailCard('Missed', '$missed', Colors.red),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _detailCard('Rate', '${rate.toStringAsFixed(1)}%', Colors.orange),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _detailCard('Consec. Misses', '$consecutive', Colors.purple),
            ),
          ],
        );
      },
    );
  }

  Widget _detailCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

  Widget _buildAcceptanceRateChart(DateTime start, DateTime end) {
    return FutureBuilder<Map<String, double>>(
      future: _getAcceptanceRateByDayForVendor(start, end),
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
                'No acceptance rate data for last 30 days',
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
        final maxY = data.values.fold(100.0, (a, b) => a > b ? a : b);
        final minY = data.values.fold(0.0, (a, b) => a < b ? a : b);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Acceptance Rate (Last 30 Days)',
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
                            interval: (sortedDates.length / 5).ceilToDouble(),
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i >= 0 && i < sortedDates.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    sortedDates[i].substring(5),
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
                      minY: (minY - 5).clamp(0.0, 100.0),
                      maxY: (maxY + 5).clamp(0.0, 100.0),
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

  Future<Map<String, double>> _getAcceptanceRateByDayForVendor(
    DateTime start,
    DateTime end,
  ) async {
    final ordersSnap = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('vendorID', isEqualTo: widget.vendorId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final q2 = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('vendor.id', isEqualTo: widget.vendorId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final byDay = <String, List<bool>>{};
    final seen = <String>{};

    for (final doc in ordersSnap.docs) {
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      final dateStr = DateFormat('yyyy-MM-dd').format(createdAt.toDate());
      byDay.putIfAbsent(dateStr, () => []);
      final status = (data['status'] ?? '').toString().toLowerCase();
      byDay[dateStr]!.add(status == 'order accepted');
    }
    for (final doc in q2.docs) {
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);
      final data = doc.data();
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      final dateStr = DateFormat('yyyy-MM-dd').format(createdAt.toDate());
      byDay.putIfAbsent(dateStr, () => []);
      final status = (data['status'] ?? '').toString().toLowerCase();
      byDay[dateStr]!.add(status == 'order accepted');
    }

    final result = <String, double>{};
    for (final e in byDay.entries) {
      final list = e.value;
      final accepted = list.where((x) => x).length;
      result[e.key] = list.isEmpty ? 100.0 : (accepted / list.length) * 100;
    }
    return result;
  }

  Widget _buildCoordinationSection() {
    final pm = _vendorData?['publicMetrics'] as Map<String, dynamic>?;
    final score = pm?['coordinationScore'];
    final avgWait = pm?['avgRiderWaitSeconds'];
    final readyRate = pm?['readyOnTimeRate'];

    Color scoreColor(int? s) {
      if (s == null) return Colors.grey;
      if (s >= 80) return Colors.green;
      if (s >= 60) return Colors.orange;
      return Colors.red;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Coordination Performance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _detailCard(
                    'Coordination Score',
                    score != null ? '$score/100' : 'N/A',
                    scoreColor(score is num ? score.toInt() : null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _detailCard(
                    'Avg Rider Wait',
                    avgWait != null
                        ? '${((avgWait as num) / 60).toStringAsFixed(1)} min'
                        : 'N/A',
                    (avgWait != null && (avgWait as num) > 300)
                        ? Colors.orange
                        : Colors.green,
                  ),
                ),
              ],
            ),
            if (readyRate != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (readyRate as num) / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 4),
              Text(
                'Ready on time: ${(readyRate).toStringAsFixed(1)}%',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
            if (score == null && avgWait == null && readyRate == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No coordination data yet (requires arrivedAtRestaurant tracking)',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissedOrdersChart(DateTime start, DateTime end) {
    return FutureBuilder<Map<String, int>>(
      future: _getMissedOrdersByDay(start, end),
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
                'No missed orders data',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        final sortedDates = data.keys.toList()..sort();
        final barGroups = sortedDates.asMap().entries.map((e) {
          final count = data[e.value] ?? 0;
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: count.toDouble(),
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
                width: 12,
              ),
            ],
          );
        }).toList();
        final maxY = data.values.isEmpty ? 5.0 : data.values.reduce((a, b) => a > b ? a : b).toDouble() + 1;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Missed Orders (Last 30 Days)',
                  style: TextStyle(
                    fontSize: 16,
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
                      barGroups: barGroups,
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            interval: (sortedDates.length / 5).ceilToDouble(),
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i >= 0 && i < sortedDates.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    sortedDates[i].substring(5),
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
                            reservedSize: 30,
                            getTitlesWidget: (v, _) => Text(
                              v.toInt().toString(),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
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

  Future<Map<String, int>> _getMissedOrdersByDay(
    DateTime start,
    DateTime end,
  ) async {
    final ordersSnap = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('vendorID', isEqualTo: widget.vendorId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final q2 = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('vendor.id', isEqualTo: widget.vendorId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final byDay = <String, int>{};
    final seen = <String>{};

    void process(dynamic doc) {
      if (seen.contains(doc.id)) return;
      seen.add(doc.id);
      final data = doc.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status != 'order rejected' && status != 'order placed') return;
      if (status == 'order placed') {
        final expiresAt = data['expiresAt'] as Timestamp?;
        if (expiresAt != null &&
            expiresAt.toDate().isAfter(DateTime.now())) {
          return;
        }
      }
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) {
        return;
      }
      final dateStr = DateFormat('yyyy-MM-dd').format(createdAt.toDate());
      byDay[dateStr] = (byDay[dateStr] ?? 0) + 1;
    }

    for (final doc in ordersSnap.docs) {
      process(doc);
    }
    for (final doc in q2.docs) {
      process(doc);
    }

    return byDay;
  }

  Widget _buildPauseHistorySection() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: RestaurantPerformanceService.getPauseHistoryStream(
        widget.vendorId,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final history = snap.data ?? [];
        if (history.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No pause history')),
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
                  'Pause History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...history.take(10).map((h) {
                  final pausedAt = h['pausedAt'] as Timestamp?;
                  final resumedAt = h['resumedAt'] as Timestamp?;
                  final reason = (h['pauseReason'] ?? '').toString();
                  final pausedStr = pausedAt != null
                      ? DateFormat('MMM dd, yyyy HH:mm')
                          .format(pausedAt.toDate())
                      : '—';
                  final resumedStr = resumedAt != null
                      ? DateFormat('MMM dd, yyyy HH:mm')
                          .format(resumedAt.toDate())
                      : 'Ongoing';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          resumedAt != null
                              ? Icons.check_circle
                              : Icons.pause_circle,
                          size: 20,
                          color: resumedAt != null
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reason,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Paused: $pausedStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                'Resumed: $resumedStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
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
      },
    );
  }
}
