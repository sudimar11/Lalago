import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:brgy/pages/pautos_dispute_page.dart';
import 'package:brgy/services/pautos_manual_dispatch_service.dart';
import 'package:brgy/widgets/orders/order_helpers.dart';

/// PAUTOS queue: unassigned requests (status Request Posted, driverID null).
class PautosQueueList extends StatelessWidget {
  const PautosQueueList({super.key});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('pautos_orders')
        .where('status', isEqualTo: 'Request Posted')
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
        final unassigned = docs.where((d) {
          final data = d.data();
          final driverId = data['driverID'];
          return driverId == null || driverId.toString().isEmpty;
        }).toList();

        if (unassigned.isEmpty) {
          return const CenteredMessage('No unassigned PAUTOS requests.');
        }

        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: unassigned.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final doc = unassigned[i];
            final data = doc.data();
            data['id'] = doc.id;
            return _PautosQueueCard(orderId: doc.id, data: data);
          },
        );
      },
    );
  }
}

class _PautosQueueCard extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> data;

  const _PautosQueueCard({
    required this.orderId,
    required this.data,
  });

  @override
  State<_PautosQueueCard> createState() => _PautosQueueCardState();
}

class _PautosQueueCardState extends State<_PautosQueueCard> {
  bool _isAssigning = false;
  final PautosManualDispatchService _service = PautosManualDispatchService();

  String _getAddress() {
    final addr = widget.data['address'];
    if (addr is! Map) return '—';
    final a = addr['address'] ?? '';
    final loc = addr['locality'] ?? '';
    final land = addr['landmark'] ?? '';
    return '$a $loc $land'.trim().isEmpty ? '—' : '$a $loc $land'.trim();
  }

  Future<void> _assignRider() async {
    final drivers = await _fetchPautosEligibleDrivers();
    if (!mounted) return;
    if (drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible riders available.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _PautosDriverPickerDialog(drivers: drivers),
    );
    if (selected == null || !mounted) return;

    setState(() => _isAssigning = true);
    final ok = await _service.assignPautosOrder(
      orderId: widget.orderId,
      driverId: selected['id'] as String,
    );
    if (!mounted) return;
    setState(() => _isAssigning = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assigned to ${selected['name']}'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assignment failed. Order may have changed.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPautosEligibleDrivers() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .get();

    final drivers = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['pautosEligible'] == false) continue;
      final avail = d['riderAvailability'] ?? '';
      final online = d['isOnline'] == true;
      if (avail != 'available' && !online) continue;
      if (d['checkedOutToday'] == true) continue;

      drivers.add({
        'id': doc.id,
        'firstName': d['firstName'] ?? '',
        'lastName': d['lastName'] ?? '',
        'phoneNumber': d['phoneNumber'] ?? '',
        'name': '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim(),
      });
    }
    return drivers;
  }

  @override
  Widget build(BuildContext context) {
    final shoppingList = (widget.data['shoppingList'] ?? '').toString();
    final maxBudget = widget.data['maxBudget'];
    final budgetStr = maxBudget != null
        ? '₱${(maxBudget is num ? maxBudget.toDouble() : double.tryParse(maxBudget.toString()) ?? 0).toStringAsFixed(2)}'
        : '—';
    final createdAt = widget.data['createdAt'];
    final dateStr = createdAt is Timestamp
        ? DateFormat('MMM d, yyyy • h:mm a').format(createdAt.toDate())
        : '—';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shoppingList.length > 80
                  ? '${shoppingList.substring(0, 80)}...'
                  : shoppingList,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Chip(
                  label: Text('Budget: $budgetStr'),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text(dateStr),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _getAddress(),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PautosDisputePage(
                            orderId: widget.orderId,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.visibility, size: 18),
                    label: const Text('View / Dispute'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isAssigning ? null : _assignRider,
                    icon: _isAssigning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.person_add),
                    label: Text(_isAssigning ? 'Assigning...' : 'Assign rider'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PautosDriverPickerDialog extends StatelessWidget {
  final List<Map<String, dynamic>> drivers;

  const _PautosDriverPickerDialog({required this.drivers});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Rider'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: drivers.length,
          itemBuilder: (context, index) {
            final d = drivers[index];
            final name = (d['name'] ?? '').toString().trim();
            final displayName = name.isEmpty ? 'Unknown' : name;
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(displayName),
              subtitle: (d['phoneNumber'] ?? '').toString().isNotEmpty
                  ? Text(d['phoneNumber'] as String)
                  : null,
              onTap: () => Navigator.of(context).pop(d),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
