import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/driver_performance/incentive_rules_screen.dart';

/// Driver performance dashboard: metrics, leaderboard, incentives.
class DriverPerformanceScreen extends StatefulWidget {
  const DriverPerformanceScreen({Key? key}) : super(key: key);

  @override
  State<DriverPerformanceScreen> createState() => _DriverPerformanceScreenState();
}

class _DriverPerformanceScreenState extends State<DriverPerformanceScreen> {
  final _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _driverMetrics = [];
  List<Map<String, dynamic>> _incentives = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) {
      setState(() {
        _error = 'No restaurant selected';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    EasyLoading.show(status: 'Loading...');

    try {
      final perfSnap = await _firestore
          .collection(DRIVER_PERFORMANCE_HISTORY)
          .where('vendorId', isEqualTo: vendorId)
          .orderBy('date', descending: true)
          .limit(100)
          .get();

      final metrics = <Map<String, dynamic>>[];
      final byDriver = <String, List<Map<String, dynamic>>>{};
      for (final doc in perfSnap.docs) {
        final d = doc.data();
        d['id'] = doc.id;
        metrics.add(d);
        final did = (d['driverId'] ?? '').toString();
        if (did.isNotEmpty) {
          byDriver.putIfAbsent(did, () => []).add(d);
        }
      }

      final leaderboard = <Map<String, dynamic>>[];
      for (final entry in byDriver.entries) {
        final list = entry.value;
        list.sort(
          (a, b) =>
              ((b['efficiencyScore'] as num?) ?? 0)
                  .compareTo((a['efficiencyScore'] as num?) ?? 0),
        );
        leaderboard.add(list.first);
      }
      leaderboard.sort(
        (a, b) =>
            ((b['efficiencyScore'] as num?) ?? 0)
                .compareTo((a['efficiencyScore'] as num?) ?? 0),
      );

      final incSnap = await _firestore
          .collection(DRIVER_INCENTIVES)
          .where('vendorId', isEqualTo: vendorId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final incentives = incSnap.docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();

      if (mounted) {
        setState(() {
          _driverMetrics = leaderboard;
          _incentives = incentives;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      EasyLoading.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = isDarkMode(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Performance'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      backgroundColor: isDark ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: SelectableText(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: Color(COLOR_PRIMARY),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLeaderboard(isDark),
                        const SizedBox(height: 20),
                        _buildIncentivesSection(isDark),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildLeaderboard(bool isDark) {
    if (_driverMetrics.isEmpty) {
      return _chartCard(
        'Driver Leaderboard',
        showEmptyState(
          'No driver data yet',
          'Performance data is updated hourly.',
          isDarkMode: isDark,
        ),
        isDark,
      );
    }

    return _chartCard(
      'Driver Leaderboard',
      Column(
        children: _driverMetrics.asMap().entries.map((e) {
          final i = e.key;
          final d = e.value;
          final score = (d['efficiencyScore'] as num?)?.toInt() ?? 0;
          final badge = i == 0
              ? '🥇'
              : i == 1
                  ? '🥈'
                  : i == 2
                      ? '🥉'
                      : null;
          return InkWell(
            onTap: () => _showDriverDetail(d, isDark),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(badge, style: const TextStyle(fontSize: 20)),
                    )
                  else
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Driver ${(d['driverId'] ?? '').toString().substring(0, 8)}...',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Accept: ${(d['acceptanceRate'] ?? 0)}% | '
                          'On-time: ${(d['onTimePercentage'] ?? 0)}% | '
                          'Rating: ${(d['customerRating'] ?? '-')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Color(COLOR_PRIMARY).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$score',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(COLOR_PRIMARY),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      isDark,
    );
  }

  Widget _buildIncentivesSection(bool isDark) {
    return _chartCard(
      'Incentives',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const IncentiveRulesScreen(),
                ),
              ).then((_) => _loadData()),
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Manage rules'),
            ),
          ),
          _buildIncentivesContent(isDark),
        ],
      ),
      isDark,
    );
  }

  Widget _buildIncentivesContent(bool isDark) {
    final pending = _incentives
        .where((i) => (i['status'] ?? '').toString() == 'pending')
        .toList();
    final paid = _incentives
        .where((i) => (i['status'] ?? '').toString() == 'paid')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pending.isEmpty && paid.isEmpty)
            showEmptyState(
              'No incentives',
              'Incentives are calculated weekly based on rules.',
              isDarkMode: isDark,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pending.isNotEmpty) ...[
                  Text(
                    'Pending (${pending.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...pending.take(5).map((i) => _incentiveTile(i, isDark, true)),
                  const SizedBox(height: 16),
                ],
                if (paid.isNotEmpty) ...[
                  Text(
                    'Paid',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...paid.take(5).map((i) => _incentiveTile(i, isDark, false)),
                ],
              ],
            ),
      ],
    );
  }

  Widget _incentiveTile(
    Map<String, dynamic> i,
    bool isDark,
    bool isPending,
  ) {
    final amount = (i['amount'] as num?) ?? 0;
    final driverId = (i['driverId'] ?? '').toString();
    final status = (i['status'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Driver ${driverId.length > 8 ? driverId.substring(0, 8) : driverId}... - ₱${amount.toStringAsFixed(0)}',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (isPending && status == 'pending')
            TextButton(
              onPressed: () => _markIncentivePaid(i),
              child: const Text('Mark paid'),
            ),
          if (status == 'paid')
            Icon(Icons.check_circle, color: Colors.green, size: 20),
        ],
      ),
    );
  }

  Future<void> _markIncentivePaid(Map<String, dynamic> i) async {
    final id = i['id'] as String?;
    if (id == null) return;
    try {
      await _firestore.collection(DRIVER_INCENTIVES).doc(id).update({
        'status': 'paid',
        'paidAt': FieldValue.serverTimestamp(),
      });
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showDriverDetail(Map<String, dynamic> d, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Driver ${(d['driverId'] ?? '').toString()}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            _detailRow('Efficiency Score', '${d['efficiencyScore'] ?? '-'}'),
            _detailRow('Acceptance Rate', '${d['acceptanceRate'] ?? '-'}%'),
            _detailRow('On-time %', '${d['onTimePercentage'] ?? '-'}%'),
            _detailRow('Avg Delivery (min)', '${d['averageDeliveryTime'] ?? '-'}'),
            _detailRow('Customer Rating', '${d['customerRating'] ?? '-'}'),
            _detailRow('Deliveries', '${d['assignmentsCount'] ?? '-'}'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    final isDark = isDarkMode(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(String title, Widget child, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
