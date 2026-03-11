import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CommunicationAnalyticsPage extends StatelessWidget {
  const CommunicationAnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communication Analytics'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('communication_metrics')
            .orderBy('generatedAt', descending: true)
            .limit(30)
            .snapshots(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No communication metrics yet'),
            );
          }
          final latest = docs.first.data();
          final avgResponseMs = (latest['avgResponseMs'] ?? 0) as int;
          final unresolvedIssues = (latest['unresolvedIssues'] ?? 0) as int;
          final totalMessages24h = (latest['totalMessages24h'] ?? 0) as int;
          final totalIssues24h = (latest['totalIssues24h'] ?? 0) as int;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _MetricCard(
                title: 'Average Response Time',
                value: '${(avgResponseMs / 1000).toStringAsFixed(0)} sec',
                icon: Icons.timer,
              ),
              _MetricCard(
                title: 'Unresolved Issues',
                value: '$unresolvedIssues',
                icon: Icons.report_problem,
              ),
              _MetricCard(
                title: 'Messages (24h)',
                value: '$totalMessages24h',
                icon: Icons.chat_bubble_outline,
              ),
              _MetricCard(
                title: 'Issues Opened (24h)',
                value: '$totalIssues24h',
                icon: Icons.warning_amber_rounded,
              ),
              const SizedBox(height: 16),
              const Text(
                'Recent Trend',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final d = doc.data();
                final avgMs = (d['avgResponseMs'] ?? 0).toString();
                final unresolved = (d['unresolvedIssues'] ?? 0).toString();
                final generatedAt = d['generatedAt'] as Timestamp?;
                return ListTile(
                  leading: const Icon(Icons.insights),
                  title: Text('Avg response: ${avgMs}ms'),
                  subtitle: Text(
                    'Unresolved: $unresolved'
                    '${generatedAt == null ? '' : ' • ${generatedAt.toDate()}'}',
                  ),
                );
              }),
              const SizedBox(height: 16),
              const Text(
                'Remote Config Experiment Keys',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const SelectableText(
                'quick_reply_variant\n'
                'comm_panel_layout_variant\n'
                'notification_timing_strategy',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

