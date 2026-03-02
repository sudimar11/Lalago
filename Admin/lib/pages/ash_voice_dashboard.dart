import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AshVoiceDashboard extends StatelessWidget {
  const AshVoiceDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ash Voice Performance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVoiceMetrics(context),
            const SizedBox(height: 24),
            _buildToneComparison(context),
            const SizedBox(height: 24),
            _buildRecentAshMessages(context),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceMetrics(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_voice_analysis')
          .orderBy('date', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || (snapshot.data?.docs ?? []).isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Loading voice metrics...',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        final data = snapshot.data!.docs.first.data();
        final analysis = data['analysis'] as Map<String, dynamic>? ?? {};

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ash Voice Performance - ${data['date'] ?? 'N/A'}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                _buildMetricRow(
                  context,
                  'With "Ash:" prefix',
                  analysis['withAshPrefix'],
                ),
                _buildMetricRow(
                  context,
                  'Without prefix',
                  analysis['withoutAshPrefix'],
                ),
                const Divider(),
                _buildMetricRow(
                  context,
                  'With personalization',
                  analysis['withPersonalization'],
                ),
                _buildMetricRow(
                  context,
                  'Without personalization',
                  analysis['withoutPersonalization'],
                ),
                const Divider(),
                _buildMetricRow(
                  context,
                  'With emoji',
                  analysis['withEmoji'],
                ),
                _buildMetricRow(
                  context,
                  'Without emoji',
                  analysis['withoutEmoji'],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricRow(
    BuildContext context,
    String label,
    dynamic metricData,
  ) {
    final sent = (metricData is Map ? metricData['sent'] : null) as int? ?? 0;
    final opened =
        (metricData is Map ? metricData['opened'] : null) as int? ?? 0;
    final rate = sent > 0 ? (opened / sent) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: rate.clamp(0.0, 1.0),
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
          const SizedBox(width: 8),
          Text('${(rate * 100).toStringAsFixed(1)}% ($opened/$sent)'),
        ],
      ),
    );
  }

  Widget _buildToneComparison(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tone Performance by Type',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('ash_notification_history')
                  .where(
                    'sentAt',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(
                      DateTime.now().subtract(const Duration(days: 7)),
                    ),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final notifications = snapshot.data!.docs;
                final byType = <String, List<QueryDocumentSnapshot>>{};

                for (final doc in notifications) {
                  final type = doc.data()['type'] as String? ?? 'unknown';
                  byType.putIfAbsent(type, () => []).add(doc);
                }

                if (byType.isEmpty) {
                  return Text(
                    'No Ash notifications in the last 7 days.',
                    style: TextStyle(color: Colors.grey[600]),
                  );
                }

                return Column(
                  children: byType.entries.map((entry) {
                    final type = entry.key;
                    final notifs = entry.value;
                    final sent = notifs.length;
                    final opened = notifs
                        .where((n) =>
                            (n.data() as Map<String, dynamic>?)?['openedAt'] !=
                            null)
                        .length;
                    final rate = sent > 0 ? (opened / sent) : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(type),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: rate.clamp(0.0, 1.0),
                              backgroundColor: Colors.grey[200],
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${(rate * 100).toStringAsFixed(1)}%'),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentAshMessages(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ash_notification_history')
          .orderBy('sentAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent Ash Messages',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  Text(
                    'No Ash messages yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  )
                else
                  ...docs.map((doc) {
                    final data = doc.data();
                    final opened = data['openedAt'] != null;
                    return ListTile(
                      leading: Icon(
                        Icons.chat,
                        color: Colors.orange[700],
                      ),
                      title: Text(data['title']?.toString() ?? ''),
                      subtitle: Text(
                        data['body']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        opened ? Icons.check_circle : Icons.access_time,
                        color: opened ? Colors.green : Colors.orange,
                        size: 16,
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
}
