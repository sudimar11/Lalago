import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OrdersThisWeekPage extends StatelessWidget {
  const OrdersThisWeekPage({super.key});

  Map<String, DateTime> _getWeekDateRange() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final daysToMonday = weekday - 1;
    final mondayDate = now.subtract(Duration(days: daysToMonday));
    final String mondayDateStr = mondayDate.toIso8601String().split('T')[0];
    final DateTime startOfWeek =
        DateTime.parse('$mondayDateStr 00:00:00Z').toUtc();

    DateTime endOfWeek;
    if (weekday == 1) {
      endOfWeek = now.toUtc();
    } else {
      final daysToSunday = 7 - weekday;
      final sundayDate = now.add(Duration(days: daysToSunday));
      final String sundayDateStr = sundayDate.toIso8601String().split('T')[0];
      endOfWeek = DateTime.parse('$sundayDateStr 23:59:59Z').toUtc();
    }

    return {
      'start': startOfWeek,
      'end': endOfWeek,
    };
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
    final weekRange = _getWeekDateRange();
    final DateTime startOfWeek = weekRange['start']!;
    final DateTime endOfWeek = weekRange['end']!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders This Week'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
            .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
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

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.orange[50],
                child: Row(
                  children: [
                    const Icon(Icons.calendar_view_week,
                        color: Colors.orange, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Orders This Week',
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
                          if (rejectedOrders > 0)
                            Text(
                              'Rejected: $rejectedOrders',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
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
                          'No orders this week',
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
                          final total = data['total'] ?? 0.0;

                          final customerName = author != null
                              ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'
                                  .trim()
                              : 'Unknown';
                          final restaurantName =
                              vendor?['title']?.toString() ?? 'Unknown';

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getStatusColor(status),
                                child: const Icon(Icons.receipt_long,
                                    color: Colors.white, size: 20),
                              ),
                              title: Text(
                                restaurantName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Customer: $customerName'),
                                  if (createdAt != null)
                                    Text(
                                      _formatDate(createdAt.toDate()),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₱${total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
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

