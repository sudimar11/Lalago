import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:brgy/services/pautos_dispute_service.dart';
import 'package:url_launcher/url_launcher.dart';

class PautosDisputePage extends StatefulWidget {
  const PautosDisputePage({
    super.key,
    required this.orderId,
  });

  final String orderId;

  @override
  State<PautosDisputePage> createState() => _PautosDisputePageState();
}

class _PautosDisputePageState extends State<PautosDisputePage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await PautosDisputeService.getOrderForAdmin(widget.orderId);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PAUTOS Dispute: ${widget.orderId}'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        SelectableText(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: _data == null
                        ? const SizedBox.shrink()
                        : _BuildContent(
                            data: _data!,
                            orderId: widget.orderId,
                            onAction: _load,
                          ),
                  ),
                ),
    );
  }
}

class _BuildContent extends StatelessWidget {
  final Map<String, dynamic> data;
  final String orderId;
  final VoidCallback onAction;

  const _BuildContent({
    required this.data,
    required this.orderId,
    required this.onAction,
  });

  static String _formatAddr(Map<String, dynamic>? addr) {
    if (addr == null) return '—';
    final a = addr['address'] ?? '';
    final loc = addr['locality'] ?? '';
    final land = addr['landmark'] ?? '';
    return '$a $loc $land'.trim().isEmpty ? '—' : '$a $loc $land'.trim();
  }

  static String _formatDate(dynamic t) {
    if (t == null) return '—';
    if (t is Map && t['_seconds'] != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        (t['_seconds'] as num).toInt() * 1000,
      );
      return DateFormat('MMM d, yyyy h:mm a').format(dt);
    }
    return t.toString();
  }

  static double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final order = Map<String, dynamic>.from(
      data['order'] as Map? ?? {},
    );
    final messages = data['messages'] as List<dynamic>? ?? [];
    final substitutions = data['substitutions'] as List<dynamic>? ?? [];
    final status = order['status']?.toString() ?? '—';
    final shoppingList = order['shoppingList']?.toString() ?? '—';
    final driverID = order['driverID']?.toString();
    final authorID = order['authorID']?.toString();
    final actualItemCost = _num(order['actualItemCost']);
    final deliveryFee = _num(order['deliveryFee']);
    final serviceFee = _num(order['serviceFee']);
    final totalAmount = _num(order['totalAmount']);
    final receiptUrl = order['receiptPhotoUrl']?.toString();
    final paymentMethod = order['paymentMethod']?.toString() ?? 'COD';
    final addr = order['address'] as Map<String, dynamic>?;

    final hasRider = driverID != null && driverID.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: 'Order Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Status', status),
              _row('Customer', authorID ?? '—'),
              _row('Rider', driverID ?? '—'),
              _row('Address', _formatAddr(addr)),
              const SizedBox(height: 8),
              Text(
                shoppingList.length > 200
                    ? '${shoppingList.substring(0, 200)}...'
                    : shoppingList,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Bill',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Actual item cost', '₱${actualItemCost.toStringAsFixed(2)}'),
              _row('Delivery fee', '₱${deliveryFee.toStringAsFixed(2)}'),
              _row('Service fee', '₱${serviceFee.toStringAsFixed(2)}'),
              _row('Total', '₱${totalAmount.toStringAsFixed(2)}'),
              _row('Payment', paymentMethod),
            ],
          ),
        ),
        if (receiptUrl != null && receiptUrl.isNotEmpty)
          _Section(
            title: 'Receipt',
            child: InkWell(
              onTap: () => launchUrl(Uri.parse(receiptUrl)),
              child: Image.network(
                receiptUrl,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
          ),
        if (substitutions.isNotEmpty)
          _Section(
            title: 'Substitutions',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: substitutions.map<Widget>((s) {
                final m = Map<String, dynamic>.from(s as Map);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${m['originalItem']} → ${m['proposedItem']}"),
                          Text(
                            "Status: ${m['status'] ?? '—'}",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        _Section(
          title: 'Chat',
          child: messages.isEmpty
              ? const Text('No messages')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: messages.map<Widget>((m) {
                    final msg = Map<String, dynamic>.from(m as Map);
                    final text = msg['messageText']?.toString() ?? '';
                    final sender = msg['senderName'] ?? msg['senderType'] ?? '—';
                    final createdAt = _formatDate(msg['createdAt']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 16,
                            child: Text(
                              (sender.toString().isNotEmpty
                                      ? sender.toString()[0]
                                      : '?')
                                  .toUpperCase(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sender.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(text),
                                Text(
                                  createdAt,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const Text(
          'Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              label: 'Issue refund',
              icon: Icons.money_off,
              onTap: () => _showRefundDialog(context),
            ),
            if (hasRider)
              _ActionButton(
                label: 'Adjust rider earnings',
                icon: Icons.trending_up,
                onTap: () => _showAdjustDialog(context),
              ),
            _ActionButton(
              label: 'Add dispute note',
              icon: Icons.note_add,
              onTap: () => _showNoteDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showRefundDialog(BuildContext context) {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Issue Refund'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (₱)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountController.text.trim());
              if (amt == null || amt <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter valid amount'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await PautosDisputeService.issueRefund(
                  orderId: orderId,
                  amount: amt,
                  reason: reasonController.text.trim().isEmpty
                      ? null
                      : reasonController.text.trim(),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Refund issued'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  onAction();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Issue'),
          ),
        ],
      ),
    );
  }

  void _showAdjustDialog(BuildContext context) {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adjust Rider Earnings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Adjustment (₱) - use negative to deduct',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amountController.text.trim());
              if (amt == null || amt == 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter non-zero adjustment'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await PautosDisputeService.adjustRiderEarnings(
                  orderId: orderId,
                  adjustmentAmount: amt,
                  reason: reasonController.text.trim().isEmpty
                      ? null
                      : reasonController.text.trim(),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Earnings adjusted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  onAction();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Adjust'),
          ),
        ],
      ),
    );
  }

  void _showNoteDialog(BuildContext context) {
    final noteController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Dispute Note'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final note = noteController.text.trim();
              if (note.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a note'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
              try {
                await PautosDisputeService.addDisputeNote(
                  orderId: orderId,
                  note: note,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Note added'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  onAction();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
