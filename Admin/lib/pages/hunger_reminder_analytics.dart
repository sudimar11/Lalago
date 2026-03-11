import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class HungerReminderAnalytics extends StatelessWidget {
  const HungerReminderAnalytics({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Hunger Reminder Performance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryMetrics(context),
            const SizedBox(height: 24),
            _buildPerformanceByWindow(context),
            const SizedBox(height: 24),
            _buildTimeOfDayBreakdown(context),
            const SizedBox(height: 24),
            _buildRecentReminders(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetrics(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('type', isEqualTo: 'ash_hunger')
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
        final opened = docs.where((d) => d.data()['openedAt'] != null).length;
        final converted = docs.where((d) => d.data()['converted'] == true);
        final totalRevenue = converted.fold<double>(
          0,
          (acc, d) =>
              acc +
              (double.tryParse(
                    (d.data()['conversionValue'] ?? 0).toString(),
                  ) ??
                  0),
        );
        final openRate = sent > 0 ? opened / sent : 0.0;
        final conversionRate = opened > 0 ? converted.length / opened : 0.0;
        final revenuePerNotif = sent > 0 ? totalRevenue / sent : 0.0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary Metrics',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _metricRow(
                  context,
                  'Sent',
                  sent.toString(),
                ),
                _metricRow(
                  context,
                  'Open Rate',
                  '${(openRate * 100).toStringAsFixed(1)}%',
                ),
                _metricRow(
                  context,
                  'Conversion Rate (open → order)',
                  '${(conversionRate * 100).toStringAsFixed(1)}%',
                ),
                _metricRow(
                  context,
                  'Revenue per Notification',
                  '₱${revenuePerNotif.toStringAsFixed(2)}',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceByWindow(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('type', isEqualTo: 'ash_hunger')
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
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        final byWindow = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final doc in docs) {
          final w = doc.data()['window']?.toString() ?? 'unknown';
          byWindow.putIfAbsent(w, () => []).add(doc);
        }
        final windows = ['lunch', 'snack', 'dinner'];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performance by Window',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  Text(
                    'No hunger reminders sent yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  )
                else
                  ...windows.map((w) {
                    final list = byWindow[w] ?? [];
                    if (list.isEmpty) return const SizedBox.shrink();
                    final opened =
                        list.where((d) => d.data()['openedAt'] != null).length;
                    final convertedCount =
                        list.where((d) => d.data()['converted'] == true).length;
                    final rate = list.isEmpty ? 0.0 : opened / list.length;
                    final convRate =
                        opened > 0 ? convertedCount / opened : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w[0].toUpperCase() + w.substring(1),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: rate,
                                  backgroundColor: Colors.grey[200],
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.green,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(rate * 100).toStringAsFixed(0)}% open',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          Text(
                            '$convertedCount conversions '
                            '(${(convRate * 100).toStringAsFixed(0)}%) · '
                            '${list.length} sent',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
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

  Widget _buildTimeOfDayBreakdown(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .where('type', isEqualTo: 'ash_hunger')
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
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final Map<int, List<QueryDocumentSnapshot<Map<String, dynamic>>>> byHour =
            {};
        for (final doc in docs) {
          final sentAt = doc.data()['sentAt'] as Timestamp?;
          if (sentAt != null) {
            final hour = sentAt.toDate().hour;
            byHour.putIfAbsent(hour, () => []).add(doc);
          }
        }

        final sortedHours = byHour.keys.toList()..sort();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Performance by Time of Day',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                if (sortedHours.isEmpty)
                  Text(
                    'No hunger reminders sent yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  )
                else
                  ...sortedHours.map((hour) {
                    final hourNotifs = byHour[hour]!;
                    final opened = hourNotifs
                        .where((n) => n.data()['openedAt'] != null)
                        .length;
                    final rate = hourNotifs.isEmpty
                        ? 0.0
                        : opened / hourNotifs.length;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00 - '
                              '${(hour + 1).toString().padLeft(2, '0')}:00',
                            ),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: rate,
                              backgroundColor: Colors.grey[200],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(rate * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '($opened/${hourNotifs.length})',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
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

  Widget _buildRecentReminders(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Hunger Reminders',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('ash_notification_history')
              .where('type', isEqualTo: 'ash_hunger')
              .orderBy('sentAt', descending: true)
              .limit(50)
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
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No hunger reminders sent yet.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final data = docs[i].data();
                final opened = data['openedAt'] != null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      data['title']?.toString() ?? 'Hunger Reminder',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      data['body']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      opened ? Icons.check_circle : Icons.access_time,
                      color: opened ? Colors.green : Colors.orange,
                      size: 24,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
