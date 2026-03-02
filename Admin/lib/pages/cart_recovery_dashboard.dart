import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CartRecoveryDashboard extends StatelessWidget {
  const CartRecoveryDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cart Recovery Analytics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MetricsCard(),
            const SizedBox(height: 24),
            _RecentHistoryList(),
          ],
        ),
      ),
    );
  }
}

class _MetricsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_scheduled_notifications')
          .where('type', isEqualTo: 'ash_cart')
          .snapshots(),
      builder: (context, scheduledSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('ash_notification_history')
              .where('type', isEqualTo: 'ash_cart')
              .snapshots(),
          builder: (context, historySnapshot) {
            final pending = scheduledSnapshot.data?.docs.length ?? 0;
            final sent = historySnapshot.data?.docs.length ?? 0;

            if (scheduledSnapshot.connectionState == ConnectionState.waiting ||
                historySnapshot.connectionState == ConnectionState.waiting) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (scheduledSnapshot.hasError || historySnapshot.hasError) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error: ${scheduledSnapshot.hasError ? scheduledSnapshot.error : historySnapshot.error}',
                    style: const TextStyle(color: Colors.red),
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
                    Text(
                      'Cart Recovery Performance',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _buildMetricRow(context, 'Pending (scheduled)', pending.toString()),
                    const SizedBox(height: 8),
                    _buildMetricRow(context, 'Sent', sent.toString()),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _RecentHistoryList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('type', isEqualTo: 'ash_cart')
          .orderBy('sentAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No cart recovery notifications sent yet.',
                style: Theme.of(context).textTheme.bodyLarge,
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
                Text(
                  'Recent Cart Recovery Notifications',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                ...docs.map((doc) {
                  final d = doc.data();
                  final sentAt = d['sentAt'] as Timestamp?;
                  final userId = d['userId'] as String? ?? '-';
                  final title = d['title'] as String? ?? '-';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'User: ${userId.length > 12 ? '${userId.substring(0, 12)}...' : userId} • '
                        '${sentAt != null ? _formatDate(sentAt.toDate()) : '-'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
