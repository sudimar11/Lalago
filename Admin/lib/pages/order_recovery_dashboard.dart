import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class OrderRecoveryDashboard extends StatelessWidget {
  const OrderRecoveryDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Recovery Dashboard'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFailureOverview(context),
            const SizedBox(height: 24),
            _buildRecoveryPerformance(context),
            const SizedBox(height: 24),
            _buildRecentFailures(context),
          ],
        ),
      ),
    );
  }

  Widget _buildFailureOverview(BuildContext context) {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final startTs = Timestamp.fromDate(thirtyDaysAgo);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('order_failures')
          .where('createdAt', isGreaterThanOrEqualTo: startTs)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        final total = docs.length;
        final byType = <String, int>{};
        for (final d in docs) {
          final t = d.data()['failureType']?.toString() ?? 'unknown';
          byType[t] = (byType[t] ?? 0) + 1;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Failure Overview (30 days)',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricColumn('Total Failures', total.toString(), Colors.red),
                    _metricColumn('--', 'Recovery Rate', Colors.green),
                  ],
                ),
                const SizedBox(height: 16),
                ...byType.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(e.key),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: total > 0 ? e.value / total : 0,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation(Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${e.value} (${total > 0 ? (e.value / total * 100).toStringAsFixed(1) : 0}%)',
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

  Widget _metricColumn(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildRecoveryPerformance(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('type', isEqualTo: 'ash_order_recovery')
          .snapshots(),
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
        final sent = docs.length;
        final opened = docs.where((d) => d.data()['openedAt'] != null).length;
        final dataList = docs.map((d) => d.data()).toList();
        final recovered =
            dataList.where((d) => d['data']?['recovered'] == true).length;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recovery Performance',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _buildMetricRow('Recovery Notifications', sent.toString()),
                _buildMetricRow(
                  'Opened',
                  sent > 0 ? '$opened (${_pct(opened, sent)})' : '0',
                ),
                _buildMetricRow(
                  'Recovered',
                  opened > 0 ? '$recovered (${_pct(recovered, opened)})' : '0',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: sent > 0 ? recovered / sent : 0,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation(Colors.green),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _pct(int a, int b) =>
      b > 0 ? '${(a / b * 100).toStringAsFixed(1)}%' : '0%';

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildRecentFailures(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('order_failures')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Failures',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                ...docs.map((doc) {
                  final d = doc.data();
                  final ts = d['createdAt'] as Timestamp?;
                  final date = ts?.toDate();
                  return ListTile(
                    leading: Icon(
                      _iconForType(d['failureType']?.toString() ?? ''),
                      color: Colors.red,
                    ),
                    title: Text(
                      '${d['failureType'] ?? 'unknown'} - ${d['failureDetails']?['reason'] ?? d['failureType'] ?? 'No reason'}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text('Order: ${d['orderId']}'),
                    trailing: date != null
                        ? Text(
                            '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'payment_failed':
        return Icons.payment;
      case 'out_of_stock':
      case 'item_not_available':
        return Icons.inventory;
      case 'restaurant_closed':
        return Icons.restaurant;
      case 'too_busy':
        return Icons.timer;
      case 'distance_too_far':
        return Icons.place;
      case 'timeout':
        return Icons.timer_off;
      default:
        return Icons.error;
    }
  }
}
