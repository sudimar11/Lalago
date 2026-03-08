import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:brgy/constants.dart';
import 'package:intl/intl.dart';

class ReviewsAnalyticsPage extends StatefulWidget {
  const ReviewsAnalyticsPage({super.key});

  @override
  State<ReviewsAnalyticsPage> createState() => _ReviewsAnalyticsPageState();
}

class _ReviewsAnalyticsPageState extends State<ReviewsAnalyticsPage> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _isLoading = true;
  String? _error;
  final Map<String, Map<String, dynamic>> _vendorCache = {};
  final Map<String, Map<String, dynamic>> _driverCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FOODS_REVIEW)
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      if (mounted) {
        setState(() {
          _docs = snap.docs;
          _isLoading = false;
        });
        _loadVendorsAndDrivers();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadVendorsAndDrivers() async {
    final vendorIds =
        _docs.map((d) => d.data()['VendorId'] ?? d.data()['vendorId']).whereType<String>().toSet();
    final driverIds =
        _docs.map((d) => d.data()['driverId']).whereType<String>().where((s) => s.isNotEmpty).toSet();

    for (final id in vendorIds) {
      if (_vendorCache.containsKey(id)) continue;
      final doc = await FirebaseFirestore.instance.collection('vendors').doc(id).get();
      if (doc.exists && doc.data() != null) {
        _vendorCache[id] = doc.data()!;
      }
    }
    for (final id in driverIds) {
      if (_driverCache.containsKey(id)) continue;
      final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
      if (doc.exists && doc.data() != null) {
        _driverCache[id] = doc.data()!;
      }
    }
    if (mounted) setState(() {});
  }

  String _vendorName(String? vid) {
    if (vid == null) return 'Unknown';
    final v = _vendorCache[vid];
    return v?['title'] ?? v?['title_en'] ?? vid;
  }

  String _driverName(String? did) {
    if (did == null || did.isEmpty) return '--';
    final d = _driverCache[did];
    final f = d?['firstName'] ?? '';
    final l = d?['lastName'] ?? '';
    return '$f $l'.trim().isEmpty ? did : '$f $l'.trim();
  }

  void _exportCsv() {
    final sb = StringBuffer();
    sb.writeln('Date,Vendor,Driver,Rating,Comment,Status');
    for (final d in _docs) {
      final data = d.data();
      final ts = data['createdAt'] as Timestamp?;
      final date = ts != null ? DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate()) : '';
      final vid = data['VendorId'] ?? data['vendorId'] ?? '';
      final driver = data['driverId'] ?? '';
      final rating = (data['rating'] as num?)?.toString() ?? '';
      final comment = (data['comment'] ?? '').toString().replaceAll(',', ';');
      final status = data['status'] ?? 'approved';
      sb.writeln('$date,${_vendorName(vid)},${_driverName(driver)},$rating,"$comment",$status');
    }
    // In a real app, use share_plus or file_picker to save
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'CSV ready (${_docs.length} rows). Copy from debug console.',
        ),
      ),
    );
    debugPrint(sb.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reviews Analytics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _docs.isEmpty ? null : _exportCsv,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SelectableText(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildKpiCards(),
                        const SizedBox(height: 20),
                        _buildRestaurantBarChart(),
                        const SizedBox(height: 20),
                        _buildTopLowRestaurants(),
                        const SizedBox(height: 20),
                        _buildRiderComparison(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildKpiCards() {
    final total = _docs.length;
    final visible =
        _docs.where((d) => (d.data()['status'] ?? 'approved') != 'hidden').toList();
    final ratings =
        visible.map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0.0).where((r) => r > 0);
    final avgRating = ratings.isEmpty ? 0.0 : ratings.reduce((a, b) => a + b) / ratings.length;

    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total reviews',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Avg rating',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    avgRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRestaurantBarChart() {
    final byVendor = <String, List<double>>{};
    for (final d in _docs) {
      final status = d.data()['status'] ?? 'approved';
      if (status == 'hidden') continue;
      final vid = d.data()['VendorId'] ?? d.data()['vendorId'] ?? 'unknown';
      final r = (d.data()['rating'] as num?)?.toDouble() ?? 0.0;
      if (r > 0) {
        byVendor.putIfAbsent(vid, () => []).add(r);
      }
    }
    final entries = byVendor.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return MapEntry(_vendorName(e.key), avg);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: Text('No restaurant data', style: TextStyle(color: Colors.grey.shade600))),
        ),
      );
    }

    final top = entries.take(10).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Avg rating by restaurant',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 5.5,
                  minY: 0,
                  barGroups: top.asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.value,
                          color: Colors.blue.shade400,
                          width: 20,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                      showingTooltipIndicators: [0],
                    );
                  }).toList(),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, meta) {
                          final i = v.toInt();
                          if (i >= 0 && i < top.length) {
                            final name = top[i].key;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                name.length > 10 ? '${name.substring(0, 10)}...' : name,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) => Text(
                          v.toStringAsFixed(0),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                        ),
                        reservedSize: 24,
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopLowRestaurants() {
    final byVendor = <String, List<double>>{};
    for (final d in _docs) {
      final status = d.data()['status'] ?? 'approved';
      if (status == 'hidden') continue;
      final vid = d.data()['VendorId'] ?? d.data()['vendorId'] ?? 'unknown';
      final r = (d.data()['rating'] as num?)?.toDouble() ?? 0.0;
      if (r > 0) {
        byVendor.putIfAbsent(vid, () => []).add(r);
      }
    }
    final entries = byVendor.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return MapEntry(e.key, {'avg': avg, 'count': e.value.length});
    }).toList()
      ..sort((a, b) => b.value['avg']!.compareTo(a.value['avg']!));

    final top = entries.take(5).toList();
    final low = entries.reversed.take(5).where((e) => e.value['count']! >= 2).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top & low rated restaurants',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top 5', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                      ...top.map((e) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_vendorName(e.key)}: ${(e.value['avg'] as double).toStringAsFixed(1)}★ (${e.value['count']})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          )),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lowest (2+ reviews)', style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                      ...low.map((e) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_vendorName(e.key)}: ${(e.value['avg'] as double).toStringAsFixed(1)}★ (${e.value['count']})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          )),
                      if (low.isEmpty) Text('N/A', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiderComparison() {
    final byDriver = <String, List<double>>{};
    for (final d in _docs) {
      final did = d.data()['driverId'] as String?;
      if (did == null || did.isEmpty) continue;
      final status = d.data()['status'] ?? 'approved';
      if (status == 'hidden') continue;
      final r = (d.data()['rating'] as num?)?.toDouble() ?? 0.0;
      if (r > 0) {
        byDriver.putIfAbsent(did, () => []).add(r);
      }
    }
    final entries = byDriver.entries.map((e) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      return MapEntry(e.key, {'avg': avg, 'count': e.value.length});
    }).toList()
      ..sort((a, b) => b.value['avg']!.compareTo(a.value['avg']!));

    final top = entries.take(8).toList();
    if (top.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No rider reviews yet',
              style: TextStyle(color: Colors.grey.shade600),
            ),
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
              'Rider rating comparison',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...top.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _driverName(e.key),
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${(e.value['avg'] as double).toStringAsFixed(1)}★ (${e.value['count']} reviews)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
