import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:brgy/pages/coupon_add_edit_page.dart';

class DemandAlertsPage extends StatefulWidget {
  const DemandAlertsPage({super.key});

  @override
  State<DemandAlertsPage> createState() => _DemandAlertsPageState();
}

class _DemandAlertsPageState extends State<DemandAlertsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demand Alerts'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ActiveAlertsTab(),
          _HistoricalAlertsTab(),
        ],
      ),
    );
  }
}

class _ActiveAlertsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('demand_alerts')
          .where('resolvedAt', isNull: true)
          .orderBy('detectedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
                const SizedBox(height: 16),
                Text(
                  'No active alerts',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Demand is within expected range.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final suggestedIds = (doc.data()['suggestedActions'] as List<dynamic>?)?.cast<String>() ?? [];
            return _AlertCard(
              alertId: doc.id,
              data: doc.data(),
              isActive: true,
              onResolve: () => _resolveAlert(doc.reference),
              suggestions: suggestedIds.isNotEmpty ? [{'id': suggestedIds.first}] : [],
            );
          },
        );
      },
    );
  }

  Future<void> _resolveAlert(DocumentReference ref) async {
    await ref.update({
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}

class _HistoricalAlertsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('demand_alerts')
          .where('resolvedAt', isNull: false)
          .orderBy('resolvedAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
              ],
            ),
          );
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No resolved alerts yet.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            return _AlertCard(
              alertId: doc.id,
              data: doc.data(),
              isActive: false,
            );
          },
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alertId,
    required this.data,
    required this.isActive,
    this.onResolve,
    this.suggestions = const [],
  });

  final String alertId;
  final Map<String, dynamic> data;
  final bool isActive;
  final VoidCallback? onResolve;
  final List<Map<String, dynamic>> suggestions;

  Color _severityColor() {
    switch ((data['severity'] ?? '').toString().toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final severity = (data['severity'] ?? 'info').toString();
    final type = (data['type'] ?? 'overall_drop').toString();
    final expected = (data['expected'] as num?)?.toInt() ?? 0;
    final actual = (data['actual'] as num?)?.toInt() ?? 0;
    final detectedAt = data['detectedAt'] as Timestamp?;
    final resolvedAt = data['resolvedAt'] as Timestamp?;

    final detectedStr = detectedAt != null
        ? DateFormat('MMM d, yyyy HH:mm').format(detectedAt.toDate())
        : '-';
    final resolvedStr = resolvedAt != null
        ? DateFormat('MMM d, yyyy HH:mm').format(resolvedAt.toDate())
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _severityColor().withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            severity == 'critical' ? Icons.warning : Icons.info_outline,
            color: _severityColor(),
            size: 28,
          ),
        ),
        title: Text(
          '${severity.toUpperCase()}: $type',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _severityColor(),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('Expected: $expected | Actual: $actual'),
            Text('Detected: $detectedStr', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (resolvedStr != null)
              Text('Resolved: $resolvedStr', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        isThreeLine: true,
        trailing: isActive && onResolve != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (suggestions.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CouponAddEditPage(
                              prefill: {
                                'title': 'Lapsed user promo (demand recovery)',
                                'discountType': 'percentage',
                                'discountValue': 20,
                                'validTo': DateTime.now().add(const Duration(days: 7)),
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.bolt, size: 18),
                      label: const Text('Execute'),
                    ),
                  TextButton(
                    onPressed: onResolve,
                    child: const Text('Resolve'),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
