import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/model/PautosOrderModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/ui/chat_screen/chat_screen.dart';
import 'package:foodie_customer/ui/pautos/pautos_substitutions_screen.dart';
import 'package:foodie_customer/ui/pautos/pautos_tracking_page.dart';
import 'package:foodie_customer/ui/fullScreenImageViewer/FullScreenImageViewer.dart';

class PautosOrderDetailScreen extends StatefulWidget {
  final String orderId;

  const PautosOrderDetailScreen({Key? key, required this.orderId})
      : super(key: key);

  @override
  State<PautosOrderDetailScreen> createState() => _PautosOrderDetailScreenState();
}

class _PautosOrderDetailScreenState extends State<PautosOrderDetailScreen> {
  final _fireStoreUtils = FireStoreUtils();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PAUTOS Order',
          style: TextStyle(fontFamily: 'Poppinsm'),
        ),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
        actions: [
          StreamBuilder<PautosOrderModel?>(
            stream: _fireStoreUtils.getPautosOrderStream(widget.orderId),
            builder: (context, snap) {
              final order = snap.data;
              final showChat = order != null &&
                  order.driverID != null &&
                  order.driverID!.isNotEmpty &&
                  order.status != 'Request Posted';
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
                        customerName:
                            '${MyAppState.currentUser?.firstName ?? ''} '
                            '${MyAppState.currentUser?.lastName ?? ''}'
                                .trim(),
                        restaurantId: order.driverID,
                        restaurantName: order.driverName ?? 'Rider',
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
        stream: _fireStoreUtils.getPautosOrderStream(widget.orderId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
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
            return const Center(
              child: Text('Order not found'),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(order),
                const SizedBox(height: 16),
                _buildSection(
                  'Shopping List',
                  order.shoppingList,
                  Icons.shopping_cart_outlined,
                ),
                const SizedBox(height: 16),
                _buildSection(
                  'Max Budget',
                  '${currencyModel?.symbol ?? '₱'} '
                  '${order.maxBudget.toStringAsFixed(currencyModel?.decimal ?? 0)}',
                  Icons.account_balance_wallet_outlined,
                ),
                if (order.preferredStore != null &&
                    order.preferredStore!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildSection(
                    'Preferred Store',
                    order.preferredStore!,
                    Icons.store_outlined,
                  ),
                ],
                const SizedBox(height: 16),
                _buildSection(
                  'Delivery Address',
                  order.address.getFullAddress(),
                  Icons.location_on_outlined,
                ),
                const SizedBox(height: 16),
                _buildDriverSection(order),
                if (order.actualItemCost != null) ...[
                  const SizedBox(height: 16),
                  _buildBillSection(order),
                ],
                if (order.totalAmount != null) ...[
                  const SizedBox(height: 16),
                  _buildBillSection(order),
                ],
                if (order.receiptPhotoUrl != null &&
                    order.receiptPhotoUrl!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildReceiptSection(context, order),
                ],
                if (order.status == 'Substitution Pending') ...[
                  const SizedBox(height: 16),
                  _buildReviewSubstitutionsButton(context),
                ],
                if (_canTrack(order)) ...[
                  const SizedBox(height: 16),
                  _buildTrackButton(context, order),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(PautosOrderModel order) {
    final isProgress = order.status == 'Driver Accepted' ||
        order.status == 'Shopping' ||
        order.status == 'Substitution Pending' ||
        order.status == 'Delivering' ||
        order.status == 'Delivered' ||
        order.status == 'Completed';
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
                    fontFamily: 'Poppinsm',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Created ${DateFormat('MMM d, yyyy • h:mm a').format(order.createdAt.toDate())}',
                  style: TextStyle(
                    fontFamily: 'Poppinsr',
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

  Widget _buildSection(String title, String content, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
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
                  fontFamily: 'Poppinsm',
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
              fontFamily: 'Poppinsr',
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

  Widget _buildBillSection(PautosOrderModel order) {
    final symbol = currencyModel?.symbol ?? '₱';
    final decimals = currencyModel?.decimal ?? 0;
    final fmt = (double v) => v.toStringAsFixed(decimals);

    final lines = <String>[
      'Item cost: $symbol ${fmt(order.actualItemCost!)}',
    ];
    if (order.deliveryFee != null && order.deliveryFee! > 0) {
      lines.add('Delivery: $symbol ${fmt(order.deliveryFee!)}');
    }
    if (order.serviceFee != null && order.serviceFee! > 0) {
      lines.add('Service fee: $symbol ${fmt(order.serviceFee!)}');
    }
    if (order.totalAmount != null) {
      lines.add('');
      lines.add('Total: $symbol ${fmt(order.totalAmount!)}');
    }
    if (order.paymentMethod != null && order.paymentMethod!.isNotEmpty) {
      lines.add(order.paymentMethod == 'Wallet' ? 'Payment: Wallet' : 'Payment: Cash on Delivery');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
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
              Icon(Icons.receipt_long, size: 20, color: Color(COLOR_PRIMARY)),
              const SizedBox(width: 8),
              Text(
                'Bill',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
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
            lines.join('\n'),
            style: TextStyle(
              fontFamily: 'Poppinsr',
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

  Widget _buildReceiptSection(BuildContext context, PautosOrderModel order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
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
              Icon(Icons.receipt_long, size: 20, color: Color(COLOR_PRIMARY)),
              const SizedBox(width: 8),
              Text(
                'Receipt',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
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
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImageViewer(
                    imageUrl: order.receiptPhotoUrl!,
                  ),
                ),
              );
            },
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    order.receiptPhotoUrl!,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Tap to view receipt',
                  style: TextStyle(
                    fontFamily: 'Poppinsr',
                    fontSize: 14,
                    color: Color(COLOR_PRIMARY),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _canTrack(PautosOrderModel order) {
    return order.driverID != null &&
        order.driverID!.isNotEmpty &&
        order.status != 'Request Posted' &&
        (order.status == 'Driver Accepted' ||
            order.status == 'Shopping' ||
            order.status == 'Substitution Pending' ||
            order.status == 'Delivering' ||
            order.status == 'Delivered' ||
            order.status == 'Completed');
  }

  Widget _buildReviewSubstitutionsButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PautosSubstitutionsScreen(orderId: widget.orderId),
            ),
          );
        },
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Review substitutions'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTrackButton(BuildContext context, PautosOrderModel order) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PautosTrackingPage(orderId: order.id),
            ),
          );
        },
        icon: const Icon(Icons.map_outlined),
        label: const Text('Track on map'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(COLOR_PRIMARY),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildDriverSection(PautosOrderModel order) {
    final hasDriver =
        order.driverID != null && order.driverID!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
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
              Icon(
                Icons.person_outline,
                size: 20,
                color: Color(COLOR_PRIMARY),
              ),
              const SizedBox(width: 8),
              Text(
                'Driver',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
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
            hasDriver ? (order.driverName ?? '—') : '—',
            style: TextStyle(
              fontFamily: 'Poppinsr',
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
}
