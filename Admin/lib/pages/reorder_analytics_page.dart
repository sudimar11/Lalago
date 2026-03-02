import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ReorderAnalyticsPage extends StatelessWidget {
  const ReorderAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reorder Reminder Analytics'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('ash_notification_history')
              .where('type', isEqualTo: 'ash_reorder')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              );
            }
            final docs = snapshot.data?.docs ?? [];
            final sent = docs.length;
            final opened = docs
                .where((d) => d.data()['openedAt'] != null)
                .length;
            final reordered = docs
                .where((d) => d.data()['actionTaken'] == 'reorder')
                .length;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reorder Reminder Performance',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    _buildMetricRow(
                      context,
                      'Sent',
                      sent.toString(),
                    ),
                    const SizedBox(height: 8),
                    _buildMetricRow(
                      context,
                      'Opened',
                      sent > 0
                          ? '$opened (${(opened / sent * 100).toStringAsFixed(1)}%)'
                          : '0',
                    ),
                    const SizedBox(height: 8),
                    _buildMetricRow(
                      context,
                      'Reordered',
                      opened > 0
                          ? '$reordered (${(reordered / opened * 100).toStringAsFixed(1)}% of opened)'
                          : '$reordered',
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetricRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
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
