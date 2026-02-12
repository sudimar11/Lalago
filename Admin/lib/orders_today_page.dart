import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrdersTodayPage extends StatelessWidget {
  const OrdersTodayPage({super.key});

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  double _computeFallbackTotal(Map<String, dynamic> data) {
    final products = data['products'] as List<dynamic>? ?? const [];
    double itemsTotal = 0.0;
    for (final product in products) {
      if (product is! Map<String, dynamic>) continue;
      final qtyRaw = product['quantity'];
      final qty = qtyRaw is num
          ? qtyRaw.toInt()
          : int.tryParse(qtyRaw?.toString() ?? '') ?? 1;
      final price = _parseAmount(product['price']);
      final extras = _parseAmount(product['extras_price']);
      itemsTotal += qty * (price + extras);
    }

    final discount = _parseAmount(data['discount']);
    final specialDiscount = _parseAmount(
      (data['specialDiscount'] as Map<String, dynamic>?)?['special_discount'],
    );
    final deliveryCharge = _parseAmount(data['deliveryCharge']);
    final tip = _parseAmount(data['tip_amount']);

    final total =
        itemsTotal + deliveryCharge + tip - discount - specialDiscount;
    return total < 0 ? 0.0 : total;
  }

  Color _getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('completed') || lowerStatus.contains('delivered')) {
      return Colors.green;
    } else if (lowerStatus.contains('rejected') ||
        lowerStatus.contains('cancelled')) {
      return Colors.red;
    } else if (lowerStatus.contains('pending') ||
        lowerStatus.contains('preparing')) {
      return Colors.orange;
    }
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay = DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders Today'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load orders'),
                ],
              ),
            );
          }

          final orders = snapshot.data?.docs ?? [];
          final rejectedOrders = orders.where((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final status = data['status']?.toString().toLowerCase() ?? '';
              return status == 'order rejected' || status == 'driver rejected';
            } catch (e) {
              return false;
            }
          }).length;

          final completedOrders = orders.where((doc) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final status = data['status']?.toString().toLowerCase() ?? '';
              return status == 'order completed' || status == 'completed';
            } catch (e) {
              return false;
            }
          }).length;

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.orange[50],
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.orange, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Orders Today',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            '${orders.length}',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          if (rejectedOrders > 0 || completedOrders > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  if (completedOrders > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Completed: $completedOrders',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.green,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (completedOrders > 0 && rejectedOrders > 0)
                                    const SizedBox(width: 8),
                                  if (rejectedOrders > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Rejected: $rejectedOrders',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.red,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: orders.isEmpty
                    ? const Center(
                        child: Text(
                          'No orders today',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final doc = orders[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final status = data['status']?.toString() ?? 'Unknown';
                          final createdAt = data['createdAt'] as Timestamp?;
                          final author = data['author'] as Map<String, dynamic>?;
                          final vendor = data['vendor'] as Map<String, dynamic>?;
                          final products = data['products'] as List<dynamic>? ?? [];
                          final driverID = data['driverID'] as String?;

                          final storedTotalRaw = data['totalAmount'] ??
                              data['grand_total'] ??
                              data['vendorTotal'] ??
                              data['amount'] ??
                              data['total'];

                          double total = _parseAmount(storedTotalRaw);
                          if (storedTotalRaw == null) {
                            total = _computeFallbackTotal(data);
                            FirebaseFirestore.instance
                                .collection('restaurant_orders')
                                .doc(doc.id)
                                .update({
                              'totalAmount': total,
                              'total': total,
                            });
                          }

                          final customerName = author != null
                              ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'
                                  .trim()
                              : 'Unknown';
                          final restaurantName =
                              vendor?['title']?.toString() ?? 'Unknown';

                          // Calculate total items
                          int totalItems = 0;
                          for (final product in products) {
                            if (product is! Map<String, dynamic>) continue;
                            final qty = product['quantity'];
                            if (qty != null) {
                              if (qty is num) {
                                totalItems += qty.toInt();
                              } else if (qty is String) {
                                totalItems += int.tryParse(qty) ?? 1;
                              } else {
                                totalItems += 1;
                              }
                            } else {
                              totalItems += 1;
                            }
                          }

                          double itemsSubtotal = 0.0;
                          for (final product in products) {
                            if (product is! Map<String, dynamic>) continue;
                            final qtyRaw = product['quantity'];
                            final quantity = qtyRaw is num
                                ? qtyRaw.toInt()
                                : int.tryParse(qtyRaw?.toString() ?? '') ?? 1;
                            final price = _parseAmount(product['price']);
                            final extras = _parseAmount(product['extras_price']);
                            itemsSubtotal += quantity * (price + extras);
                          }

                          final deliveryFee = _parseAmount(data['deliveryCharge']);
                          final tipAmount = _parseAmount(data['tip_amount']);
                          final discountAmount = _parseAmount(data['discount']);
                          final specialDiscountAmount = _parseAmount(
                            (data['specialDiscount']
                                as Map<String, dynamic>?)?['special_discount'],
                          );

                          String currency(double value) =>
                              '₱${value.toStringAsFixed(2)}';

                          Widget summaryRow(
                            String label,
                            String value, {
                            bool isEmphasis = false,
                          }) {
                            final style = TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isEmphasis ? FontWeight.w700 : FontWeight.w500,
                              color: isEmphasis ? Colors.black : Colors.grey[800],
                            );
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(child: Text(label, style: style)),
                                  Text(value, style: style),
                                ],
                              ),
                            );
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(status),
                                child: const Icon(Icons.receipt_long,
                                    color: Colors.white, size: 20),
                              ),
                              title: Text(
                                restaurantName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                createdAt == null
                                    ? 'Customer: $customerName'
                                    : 'Customer: $customerName • ${_formatDate(createdAt.toDate())}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: SizedBox(
                                height: kMinInteractiveDimension,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _getStatusColor(status)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          status,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          softWrap: false,
                                          style: TextStyle(
                                            color: _getStatusColor(status),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₱${total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (driverID != null && driverID.isNotEmpty)
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.drive_eta,
                                              size: 14,
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: FutureBuilder<DocumentSnapshot>(
                                                future: FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(driverID)
                                                    .get(),
                                                builder: (context, driverSnapshot) {
                                                  if (driverSnapshot.connectionState ==
                                                      ConnectionState.waiting) {
                                                    return const Text(
                                                      'Loading driver...',
                                                      style: TextStyle(fontSize: 12),
                                                    );
                                                  }
                                                  if (driverSnapshot.hasError ||
                                                      !driverSnapshot.hasData) {
                                                    return Text(
                                                      'Driver ID: ${driverID.substring(0, 8)}...',
                                                      style: const TextStyle(fontSize: 12),
                                                    );
                                                  }
                                                  final driverData = driverSnapshot.data
                                                      ?.data() as Map<String, dynamic>?;
                                                  final driverFirstName =
                                                      driverData?['firstName'] ?? '';
                                                  final driverLastName =
                                                      driverData?['lastName'] ?? '';
                                                  final driverName =
                                                      '$driverFirstName $driverLastName'
                                                          .trim();
                                                  return Text(
                                                    driverName.isEmpty
                                                        ? 'Driver ID: ${driverID.substring(0, 8)}...'
                                                        : 'Driver: $driverName',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontSize: 12),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        const Row(
                                          children: [
                                            Icon(
                                              Icons.drive_eta,
                                              size: 14,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'No driver assigned',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border:
                                              Border.all(color: Colors.grey[300]!),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Order Summary',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            summaryRow(
                                              'Items subtotal',
                                              currency(itemsSubtotal),
                                            ),
                                            summaryRow(
                                              'Delivery fee',
                                              currency(deliveryFee),
                                            ),
                                            summaryRow(
                                              'Tip',
                                              currency(tipAmount),
                                            ),
                                            summaryRow(
                                              'Discount',
                                              discountAmount <= 0
                                                  ? currency(0)
                                                  : '-${currency(discountAmount)}',
                                            ),
                                            summaryRow(
                                              'Special discount',
                                              specialDiscountAmount <= 0
                                                  ? currency(0)
                                                  : '-${currency(specialDiscountAmount)}',
                                            ),
                                            const Divider(height: 16),
                                            summaryRow(
                                              'Grand total',
                                              currency(total),
                                              isEmphasis: true,
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Payment: ${data['payment_method'] ?? '-'}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          const Icon(Icons.shopping_cart,
                                              size: 16, color: Colors.orange),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Items ($totalItems):',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (products.isEmpty)
                                        const Text(
                                          'No items',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        )
                                      else
                                        ...products.map((product) {
                                          if (product is! Map<String, dynamic>) {
                                            return const SizedBox.shrink();
                                          }
                                          final name =
                                              product['name']?.toString() ?? 'Unknown';
                                          final qty = product['quantity'];
                                          int quantity = 1;
                                          if (qty != null) {
                                            if (qty is num) {
                                              quantity = qty.toInt();
                                            } else if (qty is String) {
                                              quantity = int.tryParse(qty) ?? 1;
                                            }
                                          }
                                          final price =
                                              product['price']?.toString() ?? '0.00';

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.orange[100],
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '${quantity}x',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.orange,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: const TextStyle(fontSize: 13),
                                                  ),
                                                ),
                                                Text(
                                                  '₱$price',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      const Divider(height: 24),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Total:',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '₱${total.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange,
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
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

