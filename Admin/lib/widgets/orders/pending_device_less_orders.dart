import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/services/order_acceptance_service.dart';
import 'package:brgy/services/order_rejection_service.dart';
import 'package:brgy/services/restaurant_settings_service.dart';
import 'package:brgy/widgets/orders/order_info_section.dart';
import 'package:brgy/widgets/orders/order_preparation_dialog.dart';
import 'package:brgy/widgets/orders/order_rejection_dialog.dart';

/// Section showing orders from restaurants without device, awaiting admin action.
class PendingDeviceLessOrders extends StatefulWidget {
  const PendingDeviceLessOrders({super.key});

  @override
  State<PendingDeviceLessOrders> createState() => _PendingDeviceLessOrdersState();
}

class _PendingDeviceLessOrdersState extends State<PendingDeviceLessOrders> {
  final OrderAcceptanceService _acceptanceService = OrderAcceptanceService();
  final OrderRejectionService _rejectionService = OrderRejectionService();
  final RestaurantSettingsService _settingsService = RestaurantSettingsService();
  final Set<String> _processing = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _acceptOrder(BuildContext context, String orderId) async {
    setState(() => _processing.add(orderId));
    try {
      final preparationTime = await showOrderPreparationDialog(
        context,
        _acceptanceService.getPreparationTimeOptions(),
      );
      if (!_acceptanceService.isValidPreparationTime(preparationTime)) {
        if (context.mounted) _acceptanceService.showWarningMessage(context);
        return;
      }
      await _acceptanceService.acceptOrder(
        orderId: orderId,
        preparationTime: preparationTime!,
      );
      if (!context.mounted) return;
      _acceptanceService.showSuccessMessage(context, preparationTime);
    } catch (e, st) {
      debugPrint('[PendingDeviceLess] Accept error: $e\n$st');
      if (context.mounted) {
        _acceptanceService.showErrorMessage(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _processing.remove(orderId));
    }
  }

  Future<void> _rejectOrder(BuildContext context, String orderId) async {
    setState(() => _processing.add(orderId));
    try {
      final reason = await showOrderRejectionDialog(
        context,
        _rejectionService.getRejectionReasonOptions(),
      );
      if (!_rejectionService.isValidRejectionReason(reason)) {
        if (context.mounted) _rejectionService.showWarningMessage(context);
        return;
      }
      await _rejectionService.rejectOrder(
        orderId: orderId,
        rejectionReason: reason!,
      );
      if (!context.mounted) return;
      _rejectionService.showSuccessMessage(context, reason);
    } catch (e, st) {
      debugPrint('[PendingDeviceLess] Reject error: $e\n$st');
      if (context.mounted) {
        _rejectionService.showErrorMessage(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _processing.remove(orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('status', isEqualTo: 'Order Placed')
        .where('restaurantHasNoDevice', isEqualTo: true)
        .orderBy('smsSentAt', descending: false);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Error: ${snap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.phone_android, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Pending Orders (No Device)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${docs.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final doc = docs[i];
                final id = doc.id;
                final data = doc.data();
                return _PendingOrderCard(
                  orderId: id,
                  data: data,
                  isProcessing: _processing.contains(id),
                  onAccept: () => _acceptOrder(context, id),
                  onReject: () => _rejectOrder(context, id),
                  settingsService: _settingsService,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _PendingOrderCard extends StatelessWidget {
  const _PendingOrderCard({
    required this.orderId,
    required this.data,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
    required this.settingsService,
  });

  final String orderId;
  final Map<String, dynamic> data;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final RestaurantSettingsService settingsService;

  Timestamp? _asTimestamp(dynamic v) {
    if (v is Timestamp) return v;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vendor = (data['vendor'] ?? {}) as Map<String, dynamic>;
    final vendorName = (vendor['title'] ?? vendor['authorName'] ?? '')
        .toString()
        .trim();
    final total = data['vendorTotal'] ?? data['total'] ?? data['amount'] ?? 0;
    final totalNum = (total is num) ? total.toDouble() : double.tryParse(total.toString()) ?? 0.0;
    final smsSentAt = _asTimestamp(data['smsSentAt']);
    final vendorId = vendor['id'] ?? data['vendorID'] ?? data['vendorId'] ?? '';

    return FutureBuilder<int>(
      future: vendorId.isNotEmpty
          ? settingsService.getSettings(vendorId).then((s) => s.smsTimeoutMinutes)
          : Future.value(5),
      builder: (context, settingsSnap) {
        final timeoutMin = settingsSnap.data ?? 5;
        final now = DateTime.now();
        final elapsed = smsSentAt != null
            ? now.difference(smsSentAt.toDate())
            : Duration.zero;
        final remaining = Duration(minutes: timeoutMin) - elapsed;
        final isNearTimeout = remaining.inSeconds <= 60 && remaining.inSeconds > 0;
        final isOverdue = remaining.isNegative;

        return Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isOverdue
                  ? Colors.red
                  : isNearTimeout
                      ? Colors.orange
                      : Colors.orange.shade200,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.orange.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long,
                      size: 18,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${orderId.length > 8 ? orderId.substring(0, 8) : orderId}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (vendorName.isNotEmpty)
                            Text(
                              vendorName,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _TimerChip(
                      remaining: remaining,
                      isNearTimeout: isNearTimeout,
                      isOverdue: isOverdue,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OrderInfoSection(data: data, status: 'Order Placed'),
                    const SizedBox(height: 8),
                    Text(
                      'Total: ₱${totalNum.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isProcessing ? null : onAccept,
                            icon: isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.check_circle),
                            label: const Text('ACCEPT'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isProcessing ? null : onReject,
                            icon: const Icon(Icons.cancel),
                            label: const Text('REJECT'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TimerChip extends StatelessWidget {
  const _TimerChip({
    required this.remaining,
    required this.isNearTimeout,
    required this.isOverdue,
  });

  final Duration remaining;
  final bool isNearTimeout;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    Color color = Colors.green;
    String text;
    if (isOverdue) {
      color = Colors.red;
      text = 'Overdue';
    } else if (remaining.inMinutes > 0) {
      text = '${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
      if (isNearTimeout) color = Colors.orange;
    } else {
      text = '${remaining.inSeconds}s';
      color = isNearTimeout ? Colors.orange : Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
