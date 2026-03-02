import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class HungerReminderAnalytics extends StatelessWidget {
  const HungerReminderAnalytics({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hunger Reminder Performance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTimeOfDayBreakdown(context),
            const SizedBox(height: 24),
            _buildRecentReminders(context),
          ],
        ),
      ),
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
