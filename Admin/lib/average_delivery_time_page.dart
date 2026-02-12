import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AverageDeliveryTimePage extends StatelessWidget {
  const AverageDeliveryTimePage({super.key});

  String _formatDuration(int totalMinutes) {
    if (totalMinutes < 60) {
      return '$totalMinutes mins';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}mins';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final DateTime thirtyDaysAgo =
        DateTime.now().subtract(const Duration(days: 30)).toUtc();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Average Delivery Time'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
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

          // Filter completed orders and calculate delivery times
          final List<Map<String, dynamic>> deliveryData = [];
          for (final orderDoc in orders) {
            try {
              final data = orderDoc.data() as Map<String, dynamic>;
              final status = (data['status'] ?? '').toString().toLowerCase();

              // Only process completed orders
              if (status == 'order completed' || status == 'completed') {
                final createdAt = data['createdAt'];
                final deliveredAt = data['deliveredAt'];

                if (createdAt != null &&
                    deliveredAt != null &&
                    createdAt is Timestamp &&
                    deliveredAt is Timestamp) {
                  final created = createdAt.toDate();
                  final delivered = deliveredAt.toDate();
                  final duration = delivered.difference(created);
                  final minutes = duration.inMinutes;

                  // Only include positive delivery times
                  if (minutes > 0) {
                    final author = data['author'] as Map<String, dynamic>?;
                    final vendor = data['vendor'] as Map<String, dynamic>?;
                    deliveryData.add({
                      'minutes': minutes,
                      'createdAt': created,
                      'deliveredAt': delivered,
                      'customerName': author != null
                          ? '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'
                              .trim()
                          : 'Unknown',
                      'restaurantName': vendor?['title']?.toString() ?? 'Unknown',
                    });
                  }
                }
              }
            } catch (e) {
              continue;
            }
          }

          // Split by time window: last 7 days vs last 30 days
          final sevenDaysAgo =
              DateTime.now().subtract(const Duration(days: 7));
          final deliveryDataLast7Days = deliveryData
              .where(
                (d) => !(d['createdAt'] as DateTime).isBefore(sevenDaysAgo),
              )
              .toList();

          // Calculate statistics
          String averageTime = 'N/A';
          String averageTime7Days = 'N/A';
          String fastestTime = 'N/A';
          String slowestTime = 'N/A';
          String medianTime = 'N/A';

          if (deliveryDataLast7Days.isNotEmpty) {
            final times7 =
                deliveryDataLast7Days.map((d) => d['minutes'] as int).toList();
            final total7 = times7.reduce((a, b) => a + b);
            averageTime7Days = _formatDuration(
              (total7 / times7.length).round(),
            );
          }

          if (deliveryData.isNotEmpty) {
            final times = deliveryData.map((d) => d['minutes'] as int).toList()
              ..sort();
            final totalMinutes = times.reduce((a, b) => a + b);
            final avgMinutes = (totalMinutes / times.length).round();
            averageTime = _formatDuration(avgMinutes);
            fastestTime = _formatDuration(times.first);
            slowestTime = _formatDuration(times.last);

            // Calculate median
            if (times.length % 2 == 0) {
              final mid = times.length ~/ 2;
              final median = (times[mid - 1] + times[mid]) ~/ 2;
              medianTime = _formatDuration(median);
            } else {
              medianTime = _formatDuration(times[times.length ~/ 2]);
            }
          }

          // Sort by delivery time (fastest first)
          deliveryData.sort((a, b) => (a['minutes'] as int).compareTo(b['minutes'] as int));

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.orange[50],
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _AvgDeliveryCard(
                            value: averageTime7Days,
                            period: 'Last 7 days',
                            orderCount: deliveryDataLast7Days.length,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _AvgDeliveryCard(
                            value: averageTime,
                            period: 'Last 30 days',
                            orderCount: deliveryData.length,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Fastest',
                            value: fastestTime,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Slowest',
                            value: slowestTime,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            label: 'Median',
                            value: medianTime,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Based on ${deliveryDataLast7Days.length} orders (7d) • '
                      '${deliveryData.length} orders (30d)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: deliveryData.isEmpty
                    ? const Center(
                        child: Text(
                          'No completed orders in last 30 days',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: deliveryData.length,
                        itemBuilder: (context, index) {
                          final item = deliveryData[index];
                          final minutes = item['minutes'] as int;
                          final createdAt = item['createdAt'] as DateTime;
                          final deliveredAt = item['deliveredAt'] as DateTime;

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: minutes < 30
                                    ? Colors.green
                                    : minutes < 60
                                        ? Colors.orange
                                        : Colors.red,
                                child: Text(
                                  '${minutes}m',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                item['restaurantName'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Customer: ${item['customerName']}'),
                                  Text(
                                    'Created: ${_formatDate(createdAt)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'Delivered: ${_formatDate(deliveredAt)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: Text(
                                _formatDuration(minutes),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: minutes < 30
                                      ? Colors.green
                                      : minutes < 60
                                          ? Colors.orange
                                          : Colors.red,
                                ),
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

class _AvgDeliveryCard extends StatelessWidget {
  final String value;
  final String period;
  final int orderCount;

  const _AvgDeliveryCard({
    required this.value,
    required this.period,
    required this.orderCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.access_time, color: Colors.grey[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Avg delivery',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            period,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          if (orderCount > 0)
            Text(
              '$orderCount orders',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

