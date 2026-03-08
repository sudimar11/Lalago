import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class GiftCardAnalyticsPage extends StatefulWidget {
  const GiftCardAnalyticsPage({super.key});

  @override
  State<GiftCardAnalyticsPage> createState() => _GiftCardAnalyticsPageState();
}

class _GiftCardAnalyticsPageState extends State<GiftCardAnalyticsPage> {
  String _period = 'last_30_days';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift Card Analytics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          DropdownButton<String>(
            value: _period,
            dropdownColor: Colors.grey[900],
            items: const [
              DropdownMenuItem(value: 'last_7_days', child: Text('Last 7 Days')),
              DropdownMenuItem(value: 'last_30_days', child: Text('Last 30 Days')),
              DropdownMenuItem(value: 'last_90_days', child: Text('Last 90 Days')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _period = v);
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchAnalytics(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? {};
          final pv = (data['purchaseVolume'] as num?)?.toDouble() ?? 0.0;
          final rv = (data['redemptionVolume'] as num?)?.toDouble() ?? 0.0;
          final br = (data['breakage'] as num?)?.toDouble() ?? 0.0;
          final pc = (data['purchaseCount'] as num?)?.toInt() ?? 0;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetricCard(
                  'Purchase Volume',
                  '₱${pv.toStringAsFixed(0)}',
                  Icons.shopping_cart,
                  Colors.green,
                ),
                const SizedBox(height: 12),
                _buildMetricCard(
                  'Redemption Volume',
                  '₱${rv.toStringAsFixed(0)}',
                  Icons.redeem,
                  Colors.blue,
                ),
                const SizedBox(height: 12),
                _buildMetricCard(
                  'Breakage (Expired)',
                  '₱${br.toStringAsFixed(0)}',
                  Icons.event_busy,
                  Colors.orange,
                ),
                const SizedBox(height: 12),
                _buildMetricCard(
                  'Purchases Count',
                  '$pc',
                  Icons.confirmation_number,
                  Colors.purple,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Top Denominations',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildDenominationList(data['denominations'] as Map<int, int>? ?? {}),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
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

  Widget _buildDenominationList(Map<int, int> denoms) {
    if (denoms.isEmpty) {
      return Card(
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No denomination data'),
        ),
      );
    }
    final sorted = denoms.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sorted
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('₱${e.key}'),
                      Text('${e.value} purchases'),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchAnalytics() async {
    final now = DateTime.now();
    DateTime start;
    switch (_period) {
      case 'last_7_days':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'last_90_days':
        start = now.subtract(const Duration(days: 90));
        break;
      default:
        start = now.subtract(const Duration(days: 30));
    }
    final startTs = Timestamp.fromDate(start);

    final db = FirebaseFirestore.instance;

    final purchaseSnap = await db
        .collection('gift_card_transactions')
        .where('type', isEqualTo: 'purchase')
        .where('timestamp', isGreaterThanOrEqualTo: startTs)
        .get();

    final redemptionSnap = await db
        .collection('gift_card_transactions')
        .where('type', isEqualTo: 'redemption')
        .where('timestamp', isGreaterThanOrEqualTo: startTs)
        .get();

    final expirySnap = await db
        .collection('gift_card_transactions')
        .where('type', isEqualTo: 'expiry')
        .where('timestamp', isGreaterThanOrEqualTo: startTs)
        .get();

    double purchaseVolume = 0;
    int purchaseCount = 0;
    final denominations = <int, int>{};
    for (final doc in purchaseSnap.docs) {
      final d = doc.data();
      final amt = (d['amount'] as num?)?.toDouble() ?? 0;
      purchaseVolume += amt;
      purchaseCount++;
      final denom = (d['amount'] as num?)?.toInt() ?? amt.round();
      denominations[denom] = (denominations[denom] ?? 0) + 1;
    }

    double redemptionVolume = 0;
    for (final doc in redemptionSnap.docs) {
      final d = doc.data();
      redemptionVolume += (d['amount'] as num?)?.toDouble() ?? 0;
    }

    double breakage = 0;
    for (final doc in expirySnap.docs) {
      final d = doc.data();
      breakage += (d['amount'] as num?)?.toDouble() ?? 0;
    }

    return {
      'purchaseVolume': purchaseVolume,
      'purchaseCount': purchaseCount,
      'redemptionVolume': redemptionVolume,
      'breakage': breakage,
      'denominations': denominations,
    };
  }
}
