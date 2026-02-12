import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/constants.dart';

class RidersOrdersWeeklyPage extends StatefulWidget {
  const RidersOrdersWeeklyPage({super.key});

  @override
  State<RidersOrdersWeeklyPage> createState() =>
      _RidersOrdersWeeklyPageState();
}

class _RidersOrdersWeeklyPageState extends State<RidersOrdersWeeklyPage> {
  Future<void> _onRefresh() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  // Helper to calculate start of week (Monday) and end of week (Sunday)
  Map<String, DateTime> _getWeekDateRange() {
    final now = DateTime.now();
    final weekday = now.weekday; // 1 = Monday, 7 = Sunday
    final daysToMonday = weekday - 1;

    final mondayDate = now.subtract(Duration(days: daysToMonday));
    final mondayDateStr = mondayDate.toIso8601String().split('T')[0];
    final startOfWeek =
        DateTime.parse('$mondayDateStr 00:00:00Z').toUtc();

    final daysToSunday = 7 - weekday;
    final sundayDate = now.add(Duration(days: daysToSunday));
    final sundayDateStr = sundayDate.toIso8601String().split('T')[0];
    final endOfWeek =
        DateTime.parse('$sundayDateStr 23:59:59Z').toUtc();

    return {
      'start': startOfWeek,
      'end': endOfWeek,
    };
  }

  // Process all orders and group by rider and day (Mon-Sun)
  Map<String, List<int>> _processOrders(
    List<QueryDocumentSnapshot> orders,
    Map<String, String> riderNames,
  ) {
    final Map<String, List<int>> riderCounts = {};

    // Initialize all riders with zero counts
    for (final key in riderNames.keys) {
      riderCounts[key] = [0, 0, 0, 0, 0, 0, 0];
    }

    for (final orderDoc in orders) {
      try {
        final data = orderDoc.data() as Map<String, dynamic>;

        // Only count completed orders
        final status =
            (data['status'] ?? '').toString().toLowerCase();
        if (status != 'order completed') {
          continue;
        }

        final driverIdRaw = data['driverID'] ?? data['driverId'];
        if (driverIdRaw == null) continue;
        final riderKey = driverIdRaw.toString();

        final createdAt = data['createdAt'] as Timestamp?;
        if (createdAt == null) continue;

        final orderDate = createdAt.toDate().toLocal();
        final dayOfWeek = orderDate.weekday; // 1=Mon, 7=Sun

        if (dayOfWeek < 1 || dayOfWeek > 7) continue;

        riderCounts.putIfAbsent(
          riderKey,
          () => [0, 0, 0, 0, 0, 0, 0],
        );
        riderCounts[riderKey]![dayOfWeek - 1]++;
      } catch (_) {
        continue;
      }
    }

    return riderCounts;
  }

  @override
  Widget build(BuildContext context) {
    final weekRange = _getWeekDateRange();
    final startOfWeek = weekRange['start']!;
    final endOfWeek = weekRange['end']!;

    final Query ridersQuery = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER)
        .orderBy('firstName');

    final Query ordersQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
        )
        .where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Orders (This Week)'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: StreamBuilder<QuerySnapshot>(
          stream: ridersQuery.snapshots(),
          builder: (context, ridersSnapshot) {
            if (ridersSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (ridersSnapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error,
                      size: 64,
                      color: Colors.red,
                    ),
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
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.drive_eta,
                      size: 64,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No riders found',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }

            final Map<String, String> riderNames = {};
            for (final riderDoc in riders) {
              final data =
                  riderDoc.data() as Map<String, dynamic>? ?? {};
              final firstName = data['firstName'] ?? '';
              final lastName = data['lastName'] ?? '';
              final fullName = '$firstName $lastName'.trim();
              riderNames[riderDoc.id] =
                  fullName.isEmpty ? 'Rider ${riderDoc.id}' : fullName;
            }

            return StreamBuilder<QuerySnapshot>(
              stream: ordersQuery.snapshots(),
              builder: (context, ordersSnapshot) {
                if (ordersSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final orders = ordersSnapshot.data?.docs ?? [];
                final riderCounts =
                    _processOrders(orders, riderNames);

                if (orders.isEmpty) {
                  // Show table with zeros so all riders appear
                  for (final key in riderNames.keys) {
                    riderCounts.putIfAbsent(
                      key,
                      () => [0, 0, 0, 0, 0, 0, 0],
                    );
                  }
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(
                        Colors.orange[50],
                      ),
                      columns: const [
                        DataColumn(
                          label: Text(
                            'Rider',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Text(
                            'Mon',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Tue',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Wed',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Thu',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Fri',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Sat',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Sun',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text(
                            'Total',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          numeric: true,
                        ),
                      ],
                      rows: riders.map((riderDoc) {
                        final riderId = riderDoc.id;
                        final name =
                            riderNames[riderId] ?? 'Rider $riderId';
                        final counts =
                            riderCounts[riderId] ??
                            [0, 0, 0, 0, 0, 0, 0];
                        final total = counts.fold<int>(
                          0,
                          (sum, c) => sum + c,
                        );

                        return DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 150,
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            ...List.generate(7, (index) {
                              final count = index < counts.length
                                  ? counts[index]
                                  : 0;
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


