import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/model/PautosOrderModel.dart';
import 'package:foodie_driver/services/pautos_service.dart';
import 'package:foodie_driver/ui/chat_screen/chat_screen.dart';
import 'package:foodie_driver/ui/pautos/pautos_shopping_screen.dart';

class PautosOrderDetailScreen extends StatefulWidget {
  final String orderId;

  const PautosOrderDetailScreen({Key? key, required this.orderId})
      : super(key: key);

  @override
  State<PautosOrderDetailScreen> createState() => _PautosOrderDetailScreenState();
}

class _PautosOrderDetailScreenState extends State<PautosOrderDetailScreen> {
  bool _isAccepting = false;
  bool _isRejecting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PAUTOS Order'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<PautosOrderModel?>(
            stream: PautosService.getPautosOrderStream(widget.orderId),
            builder: (context, snap) {
              final order = snap.data;
              final showChat = order != null &&
                  (order.status == 'Driver Accepted' ||
                      order.status == 'Shopping' ||
                      order.status == 'Substitution Pending' ||
                      order.status == 'Delivering');
              if (!showChat) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.chat_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreens(
                        orderId: order.id,
                        customerId: order.authorID,
                        restaurantId: order.driverID,
                        restaurantName: order.driverName ?? 'Customer',
                        chatType: 'Driver',
                        isPautos: true,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<PautosOrderModel?>(
        stream: PautosService.getPautosOrderStream(widget.orderId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          final order = snapshot.data;
          if (order == null) {
            return const Center(child: Text('Order not found'));
          }
          final currentUserId =
              FirebaseAuth.instance.currentUser?.uid ?? MyAppState.currentUser?.userID ?? '';
          final isOfferedToMe = order.status == 'Driver Assigned' &&
              order.driverID == currentUserId;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(context, order),
                const SizedBox(height: 16),
                _buildSection(
                  context,
                  'Shopping List',
                  order.shoppingList,
                  Icons.shopping_cart_outlined,
                ),
                const SizedBox(height: 16),
                _buildSection(
                  context,
                  'Max Budget',
                  amountShow(amount: order.maxBudget.toString()),
                  Icons.account_balance_wallet_outlined,
                ),
                if (order.preferredStore != null &&
                    order.preferredStore!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSection(
                    context,
                    'Preferred Store',
                    order.preferredStore!,
                    Icons.store_outlined,
                  ),
                ],
                const SizedBox(height: 16),
                _buildSection(
                  context,
                  'Delivery Address',
                  order.address.getFullAddress().trim().isEmpty
                      ? '—'
                      : order.address.getFullAddress(),
                  Icons.location_on_outlined,
                ),
                if (isOfferedToMe) ...[
                  const SizedBox(height: 24),
                  _buildAcceptRejectButtons(context),
                ],
                if (_isMyAcceptedOrder(order, currentUserId)) ...[
                  const SizedBox(height: 24),
                  _buildStatusActionButtons(context, order),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, PautosOrderModel order) {
    final isProgress = order.status == 'Driver Accepted' ||
        order.status == 'Shopping' ||
        order.status == 'Substitution Pending' ||
        order.status == 'Delivering' ||
        order.status == 'Delivered';
    final statusColor = isProgress ? Colors.green : Color(COLOR_PRIMARY);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: statusColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.status,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Created ${DateFormat('MMM d, yyyy • h:mm a').format(order.createdAt.toDate())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode(context)
                        ? Colors.white70
                        : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    String content,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? Color(DARK_CARD_BG_COLOR)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode(context)
              ? Colors.grey.shade700
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Color(COLOR_PRIMARY)),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode(context)
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode(context)
                  ? Colors.white70
                  : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  bool _isMyAcceptedOrder(PautosOrderModel order, String currentUserId) {
    return order.driverID == currentUserId &&
        (order.status == 'Driver Accepted' ||
            order.status == 'Shopping' ||
            order.status == 'Substitution Pending' ||
            order.status == 'Delivering');
  }

  Widget _buildStatusActionButtons(
      BuildContext context, PautosOrderModel order) {
    if (order.status == 'Driver Accepted') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _startShopping(context),
          icon: const Icon(Icons.shopping_cart),
          label: const Text('Start Shopping'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(COLOR_ACCENT),
            foregroundColor: Colors.white,
          ),
        ),
      );
    }
    if (order.status == 'Shopping' || order.status == 'Substitution Pending') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _openShoppingScreen(context, order),
          icon: const Icon(Icons.edit_note),
          label: Text(
            order.status == 'Substitution Pending'
                ? 'Continue Shopping (review substitutions)'
                : 'Continue Shopping',
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(COLOR_ACCENT),
            foregroundColor: Colors.white,
          ),
        ),
      );
    }
    final isDelivering = order.status == 'Delivering';
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _updateStatus(
            context, isDelivering ? 'Delivered' : 'Delivering'),
        icon: Icon(isDelivering ? Icons.check_circle : Icons.local_shipping),
        label: Text(isDelivering ? 'Mark Delivered' : 'Start Delivering'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(COLOR_ACCENT),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Future<void> _startShopping(BuildContext context) async {
    final ok = await PautosService.startShopping(widget.orderId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shopping started'),
          backgroundColor: Colors.green,
        ),
      );
      final order = await PautosService.getPautosOrderStream(widget.orderId).first;
      if (mounted && order != null) {
        _openShoppingScreen(context, order);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to start shopping'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _openShoppingScreen(BuildContext context, PautosOrderModel order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PautosShoppingScreen(
          orderId: widget.orderId,
          order: order,
        ),
      ),
    );
  }

  Future<void> _updateStatus(BuildContext context, String newStatus) async {
    if (newStatus == 'Delivered') {
      final err = await PautosService.completePautosOrder(widget.orderId);
      if (!mounted) return;
      if (err == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order completed'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        String msg = 'Failed to complete';
        if (err.contains('INSUFFICIENT_WALLET_BALANCE')) {
          msg = 'Customer has insufficient wallet balance';
        } else if (err.contains('ORDER_ALREADY_COMPLETED')) {
          msg = 'Order already completed';
        } else if (err.isNotEmpty) {
          msg = err;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    final ok = await PautosService.updatePautosStatus(widget.orderId, newStatus);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $newStatus'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update status'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildAcceptRejectButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAccepting || _isRejecting
                ? null
                : () => _acceptAssignment(context),
            icon: _isAccepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_isAccepting ? 'Accepting...' : 'Accept Assignment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_ACCENT),
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isAccepting || _isRejecting
                ? null
                : () => _rejectAssignment(context),
            icon: _isRejecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Icon(Icons.close),
            label: Text(_isRejecting ? 'Rejecting...' : 'Reject'),
          ),
        ),
      ],
    );
  }

  Future<void> _acceptAssignment(BuildContext context) async {
    setState(() => _isAccepting = true);
    final ok = await PautosService.acceptPautosAssignment(widget.orderId);
    if (!mounted) return;
    setState(() => _isAccepting = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assignment accepted!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to accept. Order may have changed.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _rejectAssignment(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject PAUTOS Assignment'),
        content: const Text(
          'Are you sure you want to reject this assignment? '
          'It will be offered to another rider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isRejecting = true);
    final ok = await PautosService.rejectPautosAssignment(widget.orderId);
    if (!mounted) return;
    setState(() => _isRejecting = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assignment rejected.'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reject. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
