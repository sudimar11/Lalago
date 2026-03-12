import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationActionsDashboard extends StatelessWidget {
  const NotificationActionsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Actions Performance'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildActionOverview(context),
            const SizedBox(height: 24),
            _buildActionBreakdown(context),
            const SizedBox(height: 24),
            _buildActionTrends(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActionOverview(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
          .collection('action_stats')
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
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
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snapshot.data!.docs;
        int totalActions = 0;
        final byAction = <String, int>{};

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>?;
          final count = (data?['count'] as num?)?.toInt() ?? 0;
          totalActions += count;
          final action = data?['action']?.toString() ?? 'unknown';
          byAction[action] = (byAction[action] ?? 0) + count;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Action Overview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetric(
                      'Total Actions',
                      totalActions.toString(),
                      Colors.blue,
                    ),
                  ],
                ),
                if (byAction.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ...byAction.entries.map((e) {
                    final pct = totalActions > 0
                        ? (e.value / totalActions * 100).toStringAsFixed(1)
                        : '0';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(e.key),
                          ),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: totalActions > 0
                                  ? e.value / totalActions
                                  : 0,
                              backgroundColor: Colors.grey[200],
                              valueColor:
                                  const AlwaysStoppedAnimation(Colors.green),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$pct%'),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionBreakdown(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('action_analytics')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
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
                const Text(
                  'Recent Actions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  const Text('No actions recorded yet.')
                else
                  ...docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>?;
                    final action = data?['action']?.toString() ?? '';
                    final type = data?['type']?.toString() ?? '';
                    final timeToAction =
                        (data?['timeToAction'] as num?)?.toDouble();
                    final timestamp = data?['timestamp'] as Timestamp?;
                    final timeStr = timestamp != null
                        ? '${timestamp.toDate().hour}:'
                            '${timestamp.toDate().minute.toString().padLeft(2, '0')}'
                        : '';
                    return ListTile(
                      leading: Icon(
                        _getIconForAction(action),
                        color: data?['converted'] == true
                            ? Colors.green
                            : Colors.blue,
                      ),
                      title: Text('$action - $type'),
                      subtitle: timeToAction != null
                          ? Text(
                              'Time to action: ${(timeToAction / 1000).toStringAsFixed(0)}s')
                          : null,
                      trailing: timeStr.isNotEmpty ? Text(timeStr) : null,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTrends(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Action Trends',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Charts for action rates over time can be added here.',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
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

  IconData _getIconForAction(String action) {
    switch (action) {
      case 'accept_order':
        return Icons.check_circle;
      case 'decline_order':
        return Icons.cancel;
      case 'reorder':
        return Icons.repeat;
      case 'remind_later':
        return Icons.notifications;
      case 'chat_reply':
        return Icons.chat;
      case 'mark_ready':
        return Icons.check;
      default:
        return Icons.touch_app;
    }
  }
}
