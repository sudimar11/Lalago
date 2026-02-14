import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:brgy/constants.dart';

// Match Rider DriverPerformanceService constants
const double _adjLateCheckin = -1.0;
const double _adjUndertime = -2.0;
const double _adjAbsent = -3.0;
const double _adjComplete5Hours = 1.0;
const double _adjOnTimeCheckin = 0.5;

class RiderPerformancePage extends StatefulWidget {
  const RiderPerformancePage({super.key});

  @override
  State<RiderPerformancePage> createState() => _RiderPerformancePageState();
}

class _RiderPerformancePageState extends State<RiderPerformancePage> {
  Future<void> _onRefresh() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  String _formatDuration(int totalMinutes) {
    if (totalMinutes < 60) return '${totalMinutes}m';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final thirtyDaysAgo =
        DateTime.now().subtract(const Duration(days: 30)).toUtc();
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Performance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            FirebaseFirestore.instance
                .collection(USERS)
                .where('role', isEqualTo: USER_ROLE_DRIVER)
                .orderBy('firstName')
                .get(),
            FirebaseFirestore.instance
                .collection('restaurant_orders')
                .where('createdAt',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
                .get(),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Failed to load data'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final results = snapshot.data!;
            final ridersSnap = results[0] as QuerySnapshot;
            final ordersSnap = results[1] as QuerySnapshot;

            final Map<String, String> riderNames = {};
            final Map<String, double?> riderPerformance = {};
            for (final doc in ridersSnap.docs) {
              final d = doc.data() as Map<String, dynamic>? ?? {};
              final name =
                  '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
              riderNames[doc.id] =
                  name.isEmpty ? 'Rider ${doc.id.substring(0, 8)}' : name;
              final perf = d['driver_performance'];
              riderPerformance[doc.id] =
                  perf is num ? perf.toDouble() : null;
            }

            final Map<String, _RiderStats> stats = {};
            for (final id in riderNames.keys) {
              stats[id] = _RiderStats(
                riderId: id,
                riderName: riderNames[id]!,
                performancePercent: riderPerformance[id],
              );
            }

            for (final orderDoc in ordersSnap.docs) {
              try {
                final data = orderDoc.data() as Map<String, dynamic>;
                final status =
                    (data['status'] ?? '').toString().toLowerCase();
                if (status != 'order completed' && status != 'completed') {
                  continue;
                }

                final driverIdRaw =
                    data['driverID'] ?? data['driverId'] ?? data['driver_id'];
                if (driverIdRaw == null) continue;
                final driverId = driverIdRaw.toString();
                if (!stats.containsKey(driverId)) continue;

                final createdAt = data['createdAt'] as Timestamp?;
                if (createdAt == null) continue;
                final created = createdAt.toDate();

                if (!created.isBefore(sevenDaysAgo)) {
                  stats[driverId]!.orders7d++;
                }
                stats[driverId]!.orders30d++;

                final deliveredAt = data['deliveredAt'] as Timestamp?;
                if (deliveredAt != null) {
                  final minutes = deliveredAt
                      .toDate()
                      .difference(created)
                      .inMinutes;
                  if (minutes > 0) {
                    stats[driverId]!.totalMinutes += minutes;
                    stats[driverId]!.completedWithTime++;
                  }
                }
              } catch (_) {
                continue;
              }
            }

            final list = stats.values.toList()
              ..sort((a, b) => b.orders30d.compareTo(a.orders30d));

            if (list.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.drive_eta, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No rider data in last 30 days',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last 7 days / Last 30 days',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final s = list[index];
                      final avgMin = s.completedWithTime > 0
                          ? (s.totalMinutes / s.completedWithTime).round()
                          : null;
                      return Card(
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange[100],
                              child: Text(
                                '${s.orders30d}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ),
                            title: Text(
                              s.riderName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Wrap(
                              spacing: 6,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '7d: ${s.orders7d} • 30d: ${s.orders30d} orders',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                if (s.performancePercent != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _perfColor(s.performancePercent!)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _perfColor(
                                            s.performancePercent!),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      '${s.performancePercent!.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        color: _perfColor(
                                            s.performancePercent!),
                                      ),
                                    ),
                                  ),
                                ],
                                Text(
                                  avgMin != null
                                      ? '${_formatDuration(avgMin)} avg'
                                      : '—',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: avgMin != null
                                        ? (avgMin <= 30
                                            ? Colors.green
                                            : avgMin <= 45
                                                ? Colors.orange
                                                : Colors.red)
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              _PerformanceHistorySection(
                                driverId: s.riderId,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Color _perfColor(double score) {
    if (score >= 85) return Colors.green;
    if (score >= 75) return Colors.orange;
    return Colors.red;
  }
}

class _RiderStats {
  final String riderId;
  final String riderName;
  final double? performancePercent;
  int orders7d = 0;
  int orders30d = 0;
  int totalMinutes = 0;
  int completedWithTime = 0;

  _RiderStats({
    required this.riderId,
    required this.riderName,
    this.performancePercent,
  });
}

class _PerformanceHistorySection extends StatelessWidget {
  final String driverId;

  const _PerformanceHistorySection({required this.driverId});

  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    final ninetyDaysAgo =
        DateTime.now().subtract(const Duration(days: 90));
    final startDate = DateFormat('yyyy-MM-dd').format(ninetyDaysAgo);
    final endDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final snapshot = await FirebaseFirestore.instance
        .collection(USERS)
        .doc(driverId)
        .collection('attendance_history')
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate)
        .get();

    final records = snapshot.docs.map((d) => d.data()).toList();
    records.sort((a, b) {
      final da = a['date'] as String? ?? '';
      final db = b['date'] as String? ?? '';
      return db.compareTo(da);
    });
    return records;
  }

  String _getStatusAndImpact(Map<String, dynamic> record) {
    final isExcused = record['isExcused'] as bool? ?? false;
    final isAbsent = record['isAbsent'] as bool? ?? false;
    final isLate = record['isLate'] as bool? ?? false;
    final isUndertime = record['isUndertime'] as bool? ?? false;
    final isOnTime = record['isOnTime'] as bool? ?? false;
    final workHoursMinutes = record['workHours'] as int? ?? 0;
    final workHours = workHoursMinutes / 60.0;

    double impact = 0.0;
    if (isExcused) return 'Excused (0.0 pts)';
    if (isAbsent) {
      impact = _adjAbsent;
      return 'Absent (${impact.toStringAsFixed(1)} pts)';
    }

    final parts = <String>[];
    if (isLate) {
      parts.add('Late');
      impact += _adjLateCheckin;
    } else if (isOnTime) {
      parts.add('On-time');
      impact += _adjOnTimeCheckin;
    }
    if (isUndertime) {
      parts.add('Undertime');
      impact += _adjUndertime;
    }
    if (workHours >= 5.0) {
      impact += _adjComplete5Hours;
    }

    final status = parts.isEmpty ? 'Unknown' : parts.join(' + ');
    final impactStr =
        impact >= 0 ? '+${impact.toStringAsFixed(1)} pts' : '${impact.toStringAsFixed(1)} pts';
    return '$status ($impactStr)';
  }

  Color _getImpactColor(String status) {
    if (status.contains('Absent')) return Colors.red;
    if (status.contains('Undertime') || status.contains('Late')) {
      return Colors.orange;
    }
    if (status.contains('On-time') || status.contains('Excused')) {
      return Colors.green;
    }
    return Colors.grey;
  }

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      return DateFormat('EEE, MMM d').format(d);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Failed to load history',
              style: TextStyle(color: Colors.red[700], fontSize: 13),
            ),
          );
        }

        final records = snapshot.data ?? [];
        if (records.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'No performance history in last 90 days',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Performance history (last 90 days)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              ...records.take(30).map((r) {
                final date = r['date'] as String? ?? '';
                final status = _getStatusAndImpact(r);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          _formatDate(date),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getImpactColor(status)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _getImpactColor(status),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _getImpactColor(status),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (records.length > 30)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '... and ${records.length - 30} more',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
