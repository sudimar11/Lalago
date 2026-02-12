import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RestaurantOrdersWeeklyPage extends StatefulWidget {
  const RestaurantOrdersWeeklyPage({super.key});

  @override
  State<RestaurantOrdersWeeklyPage> createState() =>
      _RestaurantOrdersWeeklyPageState();
}

class _RestaurantOrdersWeeklyPageState
    extends State<RestaurantOrdersWeeklyPage> {
  Future<void> _onRefresh() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  // Helper function to calculate start of week (Monday) and end of week (Sunday)
  Map<String, DateTime> _getWeekDateRange() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final daysToMonday = weekday - 1;

    final mondayDate = now.subtract(Duration(days: daysToMonday));
    final String mondayDateStr = mondayDate.toIso8601String().split('T')[0];
    final DateTime startOfWeek =
        DateTime.parse('$mondayDateStr 00:00:00Z').toUtc();

    final daysToSunday = 7 - weekday;
    final sundayDate = now.add(Duration(days: daysToSunday));
    final String sundayDateStr = sundayDate.toIso8601String().split('T')[0];
    final DateTime endOfWeek =
        DateTime.parse('$sundayDateStr 23:59:59Z').toUtc();

    return {
      'start': startOfWeek,
      'end': endOfWeek,
    };
  }

  // Get restaurant key from order vendor data
  String? _getRestaurantKey(Map<String, dynamic> vendor) {
    final vendorId = vendor['id'] as String? ?? vendor['vendorId'] as String?;
    final vendorTitle = vendor['title'] as String? ?? vendor['authorName'] as String?;
    
    if (vendorId != null && vendorId.isNotEmpty) {
      return vendorId;
    }
    if (vendorTitle != null && vendorTitle.isNotEmpty) {
      return vendorTitle;
    }
    return null;
  }

  // Process all orders and group by restaurant and day
  Map<String, List<int>> _processOrders(
    List<QueryDocumentSnapshot> orders,
    Map<String, String> restaurantNames,
  ) {
    final Map<String, List<int>> restaurantCounts = {};

    // Initialize all restaurants with zero counts
    for (final key in restaurantNames.keys) {
      restaurantCounts[key] = [0, 0, 0, 0, 0, 0, 0]; // Mon-Sun
    }

    // Process each order
    for (final orderDoc in orders) {
      try {
        final data = orderDoc.data() as Map<String, dynamic>;
        final vendor = data['vendor'];
        if (vendor == null || vendor is! Map<String, dynamic>) continue;

        final restaurantKey = _getRestaurantKey(vendor);
        if (restaurantKey == null) continue;

        final createdAt = data['createdAt'] as Timestamp?;
        if (createdAt == null) continue;

        final orderDate = createdAt.toDate().toLocal();
        final dayOfWeek = orderDate.weekday; // 1=Monday, 7=Sunday

        if (dayOfWeek >= 1 && dayOfWeek <= 7) {
          // Initialize if not exists
          if (!restaurantCounts.containsKey(restaurantKey)) {
            restaurantCounts[restaurantKey] = [0, 0, 0, 0, 0, 0, 0];
          }
          // Increment count for the day (dayOfWeek - 1 because array is 0-indexed)
          restaurantCounts[restaurantKey]![dayOfWeek - 1]++;
        }
      } catch (e) {
        continue;
      }
    }

    return restaurantCounts;
  }

  @override
  Widget build(BuildContext context) {
    final weekRange = _getWeekDateRange();
    final DateTime startOfWeek = weekRange['start']!;
    final DateTime endOfWeek = weekRange['end']!;

    final Query vendorsQuery =
        FirebaseFirestore.instance.collection('vendors').orderBy('title');
    final Query ordersQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Orders (This Week)'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: StreamBuilder<QuerySnapshot>(
          stream: vendorsQuery.snapshots(),
          builder: (context, vendorsSnapshot) {
            if (vendorsSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (vendorsSnapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Failed to load restaurants'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final vendors = vendorsSnapshot.data?.docs ?? [];
            if (vendors.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No restaurants found',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            // Build restaurant names map
            final Map<String, String> restaurantNames = {};
            for (final vendorDoc in vendors) {
              final vendorData = vendorDoc.data() as Map<String, dynamic>;
              final vendorId = vendorDoc.id;
              final vendorTitle =
                  (vendorData['title'] ?? vendorData['authorName'] ?? '').toString();
              restaurantNames[vendorId] = vendorTitle;
              if (vendorTitle.isNotEmpty) {
                restaurantNames[vendorTitle] = vendorTitle;
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: ordersQuery.snapshots(),
              builder: (context, ordersSnapshot) {
                if (ordersSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final orders = ordersSnapshot.data?.docs ?? [];
                final restaurantCounts = _processOrders(orders, restaurantNames);

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor:
                          MaterialStateProperty.all(Colors.orange[50]),
                      columns: const [
                        DataColumn(
                          label: Text(
                            'Restaurant',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Mon',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Tue',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Wed',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Thu',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Fri',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Sat',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Sun',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Total',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          numeric: true,
                        ),
                      ],
                      rows: vendors.map((vendorDoc) {
                        final vendorData =
                            vendorDoc.data() as Map<String, dynamic>;
                        final vendorId = vendorDoc.id;
                        final vendorTitle = (vendorData['title'] ??
                                vendorData['authorName'] ??
                                '')
                            .toString();

                        // Try to get counts by ID first, then by title
                        final counts = restaurantCounts[vendorId] ??
                            restaurantCounts[vendorTitle] ??
                            [0, 0, 0, 0, 0, 0, 0];
                        final total =
                            counts.fold<int>(0, (sum, count) => sum + count);

                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 150,
                                child: Text(
                                  vendorTitle,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            ...List.generate(7, (index) {
                              final count =
                                  index < counts.length ? counts[index] : 0;
                              return DataCell(
                                Text(
                                  '$count',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }),
                            DataCell(
                              Text(
                                '$total',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
