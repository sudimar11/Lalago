import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/widgets/orders/order_helpers.dart';

/// Assignments Log List Widget
/// Displays AI assignment log entries from Firestore
class AssignmentsLogList extends StatelessWidget {
  const AssignmentsLogList({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('assignments_log')
        .orderBy('createdAt', descending: true)
        .limit(50);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return CenteredMessage('Error: ${snap.error}');
        }
        if (!snap.hasData) {
          return const CenteredLoading();
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const CenteredMessage('No assignments yet.');
        }

        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final orderId = (d['order_id'] ?? '') as String? ?? '';
            final driverId = (d['driverId'] ?? '') as String? ?? '';
            final status = (d['status'] ?? 'offered') as String? ?? 'offered';
            final eta = asInt(d['etaMinutes']);
            final score = asDouble(d['score']);
            final km = asDouble(d['km']);
            final prob = asDouble(d['acceptanceProb']);
            final createdAt = asTimestamp(d['createdAt']);

            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    (eta ?? 0).toString(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                title: Text('Order: $orderId'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    // Driver name display
                    if (driverId.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DriverNameChip(driverId: driverId),
                      ),
                    // Restaurant owner display
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RestaurantOwnerChip(orderData: d),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OrderChip('Status', status),
                        OrderChip('ETA', eta != null ? '$eta min' : '—'),
                        OrderChip('Distance',
                            km != null ? '${km.toStringAsFixed(2)} km' : '—'),
                        OrderChip('Score',
                            score != null ? score.toStringAsFixed(3) : '—'),
                        OrderChip('ML Prob',
                            prob != null ? prob.toStringAsFixed(2) : '—'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (createdAt != null)
                      OrderPlacedTimer(
                        orderCreatedAt: createdAt,
                        status: status,
                      )
                    else
                      Text(
                        '—',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          },
        );
      },
    );
  }
}
