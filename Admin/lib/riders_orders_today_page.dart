import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class RidersOrdersTodayPage extends StatefulWidget {
  const RidersOrdersTodayPage({super.key});

  @override
  State<RidersOrdersTodayPage> createState() => _RidersOrdersTodayPageState();
}

class _RidersOrdersTodayPageState extends State<RidersOrdersTodayPage> {
  @override
  Widget build(BuildContext context) {
    // Get today's date range
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

    // Query all riders
    final Query ridersQuery = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER)
        .orderBy('firstName');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riders Orders Today'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ridersQuery.snapshots(),
        builder: (context, ridersSnapshot) {
          if (ridersSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (ridersSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load riders'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final riders = ridersSnapshot.data?.docs ?? [];

          if (riders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.drive_eta,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No riders found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
              await Future.delayed(const Duration(milliseconds: 300));
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: riders.length,
              itemBuilder: (context, index) {
                final riderDoc = riders[index];
                final riderData = riderDoc.data() as Map<String, dynamic>;
                final riderId = riderDoc.id;

                return _RiderOrdersCard(
                  riderId: riderId,
                  riderData: riderData,
                  startOfDay: startOfDay,
                  endOfDay: endOfDay,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RiderOrdersCard extends StatelessWidget {
  final String riderId;
  final Map<String, dynamic> riderData;
  final DateTime startOfDay;
  final DateTime endOfDay;

  const _RiderOrdersCard({
    required this.riderId,
    required this.riderData,
    required this.startOfDay,
    required this.endOfDay,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = riderData['firstName'] ?? '';
    final lastName = riderData['lastName'] ?? '';
    final phoneNumber = riderData['phoneNumber'] ?? '';
    final isActive = riderData['isActive'] == true;
    final riderName = '$firstName $lastName'.trim();

    // Query completed orders for this rider today
    final Query ordersQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('driverID', isEqualTo: riderId)
        .where('status', isEqualTo: 'Order Completed')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: ordersQuery.snapshots(),
      builder: (context, ordersSnapshot) {
        final orders = ordersSnapshot.data?.docs ?? [];
        final orderCount = orders.length;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: false,
              leading: CircleAvatar(
                backgroundColor: isActive ? Colors.green : Colors.grey,
                child: const Icon(Icons.drive_eta, color: Colors.white),
              ),
              title: Text(
                riderName.isEmpty ? 'Rider $riderId' : riderName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              subtitle: Text(
                phoneNumber.isEmpty ? 'No phone' : phoneNumber,
                style: const TextStyle(fontSize: 13),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: orderCount > 0
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 14,
                          color: orderCount > 0 ? Colors.orange : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$orderCount',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: orderCount > 0 ? Colors.orange : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.expand_more),
                ],
              ),
              children: [
                if (ordersSnapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (ordersSnapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Error loading orders',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  )
                else if (orders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'No completed orders today',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  Column(
                    children: orders.map((orderDoc) {
                      final orderData = orderDoc.data() as Map<String, dynamic>;
                      return _OrderListItem(
                        orderId: orderDoc.id,
                        orderData: orderData,
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OrderListItem extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> orderData;

  const _OrderListItem({
    required this.orderId,
    required this.orderData,
  });

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      final DateTime dateTime = timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.parse(timestamp.toString());
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatCurrency(dynamic amount) {
    if (amount == null) return '₱0.00';
    try {
      final double value = amount is double
          ? amount
          : amount is int
              ? amount.toDouble()
              : double.tryParse(amount.toString()) ?? 0.0;
      return '₱${value.toStringAsFixed(2)}';
    } catch (e) {
      return '₱0.00';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = orderData['vendor'] as Map<String, dynamic>?;
    final author = orderData['author'] as Map<String, dynamic>?;
    final products = orderData['products'] as List<dynamic>? ?? [];

    final restaurantName = vendor?['title'] ??
        vendor?['authorName'] ??
        vendor?['name'] ??
        'Unknown Restaurant';

    final customerName = author?['firstName'] != null
        ? '${author!['firstName']} ${author['lastName'] ?? ''}'.trim()
        : 'Unknown Customer';

    final orderTotal =
        orderData['vendorTotal'] ?? orderData['total'] ?? orderData['amount'];

    final completedAt = orderData['completedAt'] ??
        orderData['updatedAt'] ??
        orderData['createdAt'];

    // Calculate total items count
    int totalItems = 0;
    for (final product in products) {
      if (product is! Map<String, dynamic>) continue;
      final quantity = product['quantity'];
      if (quantity != null) {
        if (quantity is num) {
          totalItems += quantity.toInt();
        } else if (quantity is String) {
          totalItems += int.tryParse(quantity) ?? 1;
        }
      } else {
        totalItems += 1;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Order #${orderId.substring(0, 8)}...',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                _formatCurrency(orderTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.restaurant, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  restaurantName,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.person, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  customerName,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.shopping_bag, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Items: $totalItems',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          if (products.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order Items:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...products.map((product) {
                    if (product is! Map<String, dynamic>) {
                      return const SizedBox.shrink();
                    }
                    final name = product['name'] as String? ?? 'Unknown';
                    final qty = product['quantity'] ?? 1;
                    final price = product['price'] as String? ?? '0';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${qty}x',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '₱$price',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'Completed: ${_formatTime(completedAt)}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
