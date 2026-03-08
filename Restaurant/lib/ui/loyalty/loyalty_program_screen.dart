import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/services/helper.dart';

/// Loyalty program overview: metrics, tier distribution, reward catalog.
class LoyaltyProgramScreen extends StatefulWidget {
  const LoyaltyProgramScreen({Key? key}) : super(key: key);

  @override
  State<LoyaltyProgramScreen> createState() => _LoyaltyProgramScreenState();
}

class _LoyaltyProgramScreenState extends State<LoyaltyProgramScreen> {
  final _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _config;
  int _activeMembers = 0;
  int _rewardsRedeemed = 0;
  Map<String, int> _tierCounts = {};
  List<Map<String, dynamic>> _topCustomers = [];
  bool _isLoading = true;
  String? _error;

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
    EasyLoading.show(status: 'Loading...');

    try {
      final configSnap = await _firestore
          .collection(Setting)
          .doc('loyaltyConfig')
          .get();

      _config = configSnap.exists ? configSnap.data() : null;

      final usersSnap = await _firestore
          .collection(USERS)
          .where('role', isEqualTo: 'customer')
          .limit(500)
          .get();

      int active = 0;
      int redeemed = 0;
      final tiers = <String, int>{
        'bronze': 0,
        'silver': 0,
        'gold': 0,
        'diamond': 0,
      };
      final topByTokens = <Map<String, dynamic>>[];

      for (final doc in usersSnap.docs) {
        final d = doc.data();
        final loyalty = d['loyalty'] as Map?;
        if (loyalty == null) continue;

        if (loyalty['currentCycle'] != null) active++;

        final claimed = loyalty['rewardsClaimed'] as List?;
        if (claimed != null) redeemed += claimed.length;

        final tier = ((loyalty['currentTier'] ?? 'bronze') as String)
            .toLowerCase();
        if (tiers.containsKey(tier)) {
          tiers[tier] = tiers[tier]! + 1;
        }

        final tokens = (loyalty['tokensThisCycle'] as num?)?.toInt() ?? 0;
        topByTokens.add({
          'id': doc.id,
          'name': '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim(),
          'tokens': tokens,
          'tier': tier,
        });
      }

      topByTokens.sort((a, b) => (b['tokens'] as int).compareTo(a['tokens'] as int));

      if (mounted) {
        setState(() {
          _activeMembers = active;
          _rewardsRedeemed = redeemed;
          _tierCounts = tiers;
          _topCustomers = topByTokens.take(5).toList();
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
        title: const Text('Loyalty Program'),
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
                        if (_config != null && (_config!['enabled'] != true))
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange.shade800),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Loyalty program is currently disabled.',
                                    style: TextStyle(color: Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _buildKpiCards(isDark),
                        const SizedBox(height: 20),
                        _buildTierChart(isDark),
                        const SizedBox(height: 20),
                        _buildTopCustomers(isDark),
                        const SizedBox(height: 20),
                        _buildRewardCatalog(isDark),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildKpiCards(bool isDark) {
    final cardColor = isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _kpiCard(
          'Active Members',
          '$_activeMembers',
          Icons.people,
          cardColor,
          isDark,
        ),
        _kpiCard(
          'Rewards Redeemed',
          '$_rewardsRedeemed',
          Icons.card_giftcard,
          cardColor,
          isDark,
        ),
      ],
    );
  }

  Widget _kpiCard(
    String label,
    String value,
    IconData icon,
    Color bg,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
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
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Color(COLOR_PRIMARY), size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierChart(bool isDark) {
    final tiers = ['bronze', 'silver', 'gold', 'diamond'];
    final maxCount = _tierCounts.values.isEmpty
        ? 1
        : _tierCounts.values.reduce((a, b) => a > b ? a : b);
    final colors = [
      Colors.brown.shade400,
      Colors.grey.shade400,
      Colors.amber.shade700,
      Colors.cyan.shade300,
    ];

    return _chartCard(
      'Tier Distribution',
      SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: (maxCount + 1).toDouble(),
            minY: 0,
            barTouchData: BarTouchData(enabled: true),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i >= 0 && i < tiers.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          tiers[i],
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
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
                  reservedSize: 28,
                  getTitlesWidget: (v, _) => Text(
                    v.toInt().toString(),
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
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
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(
              show: true,
              border: Border.all(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
              ),
            ),
            barGroups: tiers.asMap().entries.map((e) {
              final count = _tierCounts[e.value] ?? 0;
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: count.toDouble(),
                    color: colors[e.key % colors.length],
                    width: 24,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
      isDark,
    );
  }

  Widget _buildTopCustomers(bool isDark) {
    return _chartCard(
      'Top 5 Customers',
      _topCustomers.isEmpty
          ? showEmptyState(
              'No loyalty data yet',
              'Customer activity will appear here.',
              isDarkMode: isDark,
            )
          : Column(
              children: _topCustomers.map((c) {
                final name = (c['name'] as String?) ?? 'Customer';
                final tokens = (c['tokens'] as int?) ?? 0;
                final tier = (c['tier'] as String?) ?? 'bronze';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: Color(COLOR_PRIMARY).withValues(alpha: 0.3),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(color: Color(COLOR_PRIMARY)),
                    ),
                  ),
                  title: Text(
                    name.isNotEmpty ? name : 'Unknown',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    '$tokens pts • $tier',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                );
              }).toList(),
            ),
      isDark,
    );
  }

  Widget _buildRewardCatalog(bool isDark) {
    final benefits = _config?['benefits'] as Map? ?? {};
    final tierOrder = ['bronze', 'silver', 'gold', 'diamond'];
    final entries = tierOrder
        .where((t) => benefits[t] != null)
        .map((t) => MapEntry(t, benefits[t] as List? ?? []));

    if (entries.isEmpty) {
      return _chartCard(
        'Reward Catalog',
        showEmptyState(
          'No rewards configured',
          'Rewards are managed in Admin settings.',
          isDarkMode: isDark,
        ),
        isDark,
      );
    }

    return _chartCard(
      'Reward Catalog',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: entries.map((e) {
          final tier = e.key;
          final list = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tier[0].toUpperCase() + tier.substring(1),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
                ...list.map((b) {
                  final desc = (b is Map ? b['description'] : null) ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            size: 16,
                            color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            desc.toString(),
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey.shade300
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
      isDark,
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
