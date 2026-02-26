import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/acceptance_metrics_service.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/utils/order_ready_time_helper.dart';
import 'package:foodie_restaurant/widgets/order_acceptance_timer_widget.dart';

const _prepTimeOptions = [
  '0:5', '0:10', '0:20', '0:30', '0:40', '0:50',
  '1:00', '1:30', '2:00',
];

/// Full-screen order card for accepting or rejecting a new order.
class OrderAcceptanceScreen extends StatelessWidget {
  final OrderModel? orderModel;
  final String? orderId;

  const OrderAcceptanceScreen({
    Key? key,
    this.orderModel,
    this.orderId,
  })  : assert(orderModel != null || orderId != null),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    if (orderModel != null) {
      return _OrderAcceptanceContent(orderModel: orderModel!);
    }
    return FutureBuilder<OrderModel?>(
      future: FireStoreUtils.getOrderById(orderId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: isDarkMode(context)
                ? Color(DARK_VIEWBG_COLOR)
                : Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final order = snapshot.data;
        if (order == null || order.status != ORDER_STATUS_PLACED) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
          return Scaffold(
            backgroundColor: isDarkMode(context)
                ? Color(DARK_VIEWBG_COLOR)
                : Colors.white,
            body: Center(
              child: Text('Order not found or already processed'),
            ),
          );
        }
        return _OrderAcceptanceContent(orderModel: order);
      },
    );
  }
}

class _OrderAcceptanceContent extends StatefulWidget {
  final OrderModel orderModel;

  const _OrderAcceptanceContent({required this.orderModel});

  @override
  State<_OrderAcceptanceContent> createState() => _OrderAcceptanceContentState();
}

class _OrderAcceptanceContentState extends State<_OrderAcceptanceContent> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(widget.orderModel.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final status = data?['status'] as String? ?? '';
          if (status != ORDER_STATUS_PLACED) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.of(context).pop();
            });
          }
        }

        return Scaffold(
          backgroundColor:
              isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
          appBar: AppBar(
            title: Text(
              'New Order',
              style: TextStyle(
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
          ),
          body: _isProcessing
              ? Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(widget.orderModel),
                      const SizedBox(height: 16),
                      _buildItemsList(widget.orderModel),
                      const SizedBox(height: 16),
                      _buildTotalAndNotes(widget.orderModel),
                      const SizedBox(height: 24),
                      _buildTimer(snapshot),
                      const SizedBox(height: 24),
                      _buildButtons(),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildHeader(OrderModel order) {
    final shortId =
        order.id.length > 8 ? order.id.substring(0, 8) : order.id;
    final customerName =
        '${order.author.firstName} ${order.author.lastName}'.trim();
    final time = DateFormat('MMM d, HH:mm').format(
      order.createdAt.toDate(),
    );

    return Card(
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order #$shortId',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              customerName,
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList(OrderModel order) {
    return Card(
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Items',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            ...order.products.map((p) {
              final price = double.tryParse(p.price) ?? 0;
              final total = price * p.quantity;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${p.name} x ${p.quantity}',
                        style: TextStyle(
                          color: isDarkMode(context)
                              ? Colors.white70
                              : Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      amountShow(amount: total.toString()),
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Color(COLOR_PRIMARY),
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
  }

  Widget _buildTotalAndNotes(OrderModel order) {
    return Card(
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order Total',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  amountShow(amount: order.totalAmount.toString()),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
              ],
            ),
            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Notes: ${order.notes}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _getTotalSeconds(AsyncSnapshot<DocumentSnapshot> snapshot) {
    if (snapshot.hasData && snapshot.data!.exists) {
      final data = snapshot.data!.data() as Map<String, dynamic>?;
      final expiresAt = data?['expiresAt'] as Timestamp?;
      if (expiresAt != null) {
        final diff = expiresAt.toDate().difference(DateTime.now());
        final secs = diff.inSeconds;
        return secs > 0 ? secs : 0;
      }
      final timerSecs = data?['acceptanceTimerSeconds'] as int?;
      if (timerSecs != null && timerSecs > 0) return timerSecs;
    }
    return 180;
  }

  Widget _buildTimer(AsyncSnapshot<DocumentSnapshot> snapshot) {
    final totalSeconds = _getTotalSeconds(snapshot);
    return OrderAcceptanceTimerWidget(
      totalSeconds: 180,
      initialSeconds: totalSeconds > 0 ? totalSeconds : 0,
      onTimeout: () {
        if (mounted && !_isProcessing) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isProcessing
                ? null
                : () => _handleAccept(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('ACCEPT'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isProcessing
                ? null
                : () => _handleReject(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('REJECT'),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAccept() async {
    final preparationTime = await showDialog<String>(
      context: context,
      builder: (ctx) => _PrepTimeDialog(options: _prepTimeOptions),
    );
    if (preparationTime == null || preparationTime.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final prepMinutes =
          OrderReadyTimeHelper.parsePreparationMinutes(preparationTime);
      final now = DateTime.now();
      final readyAt = now.add(Duration(minutes: prepMinutes));

      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(widget.orderModel.id)
          .update({
        'status': ORDER_STATUS_ACCEPTED,
        'estimatedTimeToPrepare': preparationTime,
        'acceptedAt': FieldValue.serverTimestamp(),
        'readyAt': Timestamp.fromDate(readyAt),
        'prepMinutes': prepMinutes,
      });

      final vendorId = MyAppState.currentUser?.vendorID;
      if (vendorId != null) {
        await AcceptanceMetricsService.resetConsecutiveMisses(vendorId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order accepted! Tap "Find Nearest Driver" next.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleReject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Order'),
        content: const Text(
          'Are you sure you want to reject this order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('REJECT'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(widget.orderModel.id)
          .update({
        'status': ORDER_STATUS_REJECTED,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectionReason': 'restaurant_rejected',
      });

      final vendorId = MyAppState.currentUser?.vendorID;
      if (vendorId != null) {
        await AcceptanceMetricsService.incrementConsecutiveMisses(vendorId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order rejected'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error rejecting order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _PrepTimeDialog extends StatefulWidget {
  final List<String> options;

  const _PrepTimeDialog({required this.options});

  @override
  State<_PrepTimeDialog> createState() => _PrepTimeDialogState();
}

class _PrepTimeDialogState extends State<_PrepTimeDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Preparation Time'),
      content: DropdownButton<String>(
        value: _selected,
        hint: const Text('Choose time'),
        isExpanded: true,
        items: widget.options.map((t) {
          return DropdownMenuItem(value: t, child: Text(t));
        }).toList(),
        onChanged: (v) => setState(() => _selected = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (_selected != null) Navigator.pop(context, _selected);
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
