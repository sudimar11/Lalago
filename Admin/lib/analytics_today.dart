import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/customers_page.dart';
import 'package:brgy/active_buyers_this_week_page.dart';
import 'package:brgy/foods_page.dart';
import 'package:brgy/active_buyers_today_page.dart';
import 'package:brgy/inactive_customers_page.dart';
import 'package:brgy/riders_orders_today_page.dart';
import 'package:brgy/restaurants_page.dart';
import 'package:brgy/order_dispatcher.dart';

class AnalyticsTodayPage extends StatefulWidget {
  const AnalyticsTodayPage({super.key});

  @override
  State<AnalyticsTodayPage> createState() => _AnalyticsTodayPageState();
}

class _AnalyticsTodayPageState extends State<AnalyticsTodayPage> {
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

  Map<String, DateTime> _getTodayUtcRange() {
    final String todayDate = DateTime.now().toIso8601String().split('T')[0];
    final DateTime startOfDay =
        DateTime.parse('$todayDate 00:00:00Z').toUtc();
    final DateTime endOfDay =
        DateTime.parse('$todayDate 23:59:59Z').toUtc();
    return {
      'start': startOfDay,
      'end': endOfDay,
    };
  }

  bool _isFoodPublished(Map<String, dynamic> data) {
    const keys = [
      'isPublished',
      'published',
      'publish',
      'is_public',
      'isVisible',
      'visible',
    ];
    for (final key in keys) {
      if (!data.containsKey(key)) continue;
      final value = data[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        return value.toLowerCase() == 'true' || value == '1';
      }
    }
    return false;
  }

  // --- Chart Data Builder Method ---
  LineChartData _buildChartData(Map<int, int> ordersByHour, int maxOrders) {
    // 1. Create FlSpot data for the chart
    final spots = List.generate(24, (index) {
      final count = ordersByHour[index] ?? 0;
      return FlSpot(index.toDouble(), count.toDouble());
    });

    // Determine Y-axis max value, adding a buffer for better visualization
    final maxYValue = maxOrders > 0 ? maxOrders.toDouble() + 1 : 5.0;
    // Determine Y-axis interval for ticks, rounding up to a sensible number
    final yInterval = maxOrders > 0 ? (maxOrders / 5).ceil().toDouble() : 1.0;

    return LineChartData(
      // --- Grid Setup ---
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 1,
          );
        },
      ),

      // --- Titles (Axis Labels) Setup ---
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        // X-axis (Hours)
        bottomTitles: AxisTitles(
          axisNameWidget: Text('Hour of Day (24h)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          axisNameSize: 25,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 2, // Show a label every 2 hours
            getTitlesWidget: (value, meta) {
              final hour = value.toInt();
              if (hour % 2 == 0) {
                // Only show titles on the interval
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                );
              }
              return const Text('');
            },
          ),
        ),
        // Y-axis (Order Count)
        leftTitles: AxisTitles(
          axisNameWidget:
              Text('Orders', style: TextStyle(fontWeight: FontWeight.bold)),
          axisNameSize: 25,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: yInterval,
            getTitlesWidget: (value, meta) {
              if (value == 0 || value.toInt() > maxOrders)
                return const Text('');
              return Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
      ),

      // --- Border & Axis Limits ---
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey[300]!),
      ),
      minX: 0,
      maxX: 23, // 24 hours (0 to 23)
      minY: 0,
      maxY: maxYValue, // Dynamic max Y value

      // --- Line Data ---
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.orange,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true, // Show dots for each hour
          ),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.orange.withOpacity(0.1),
          ),
        ),
      ],
      // Optional: Add touch behavior for tooltips
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (LineBarSpot touchedSpot) =>
              Colors.orange.withOpacity(0.8),
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((LineBarSpot touchedSpot) {
              final hour = touchedSpot.x.toInt();
              final count = touchedSpot.y.toInt();
              return LineTooltipItem(
                '${count} orders\n${hour.toString().padLeft(2, '0')}:00',
                const TextStyle(color: Colors.white),
              );
            }).toList();
          },
        ),
      ),
    );
  }
  // --- End Chart Data Builder Method ---

  @override
  Widget build(BuildContext context) {
    // Use the current local time for calculating start/end of the day
    final now = DateTime.now();
    // Get the start of the current day in local time
    final DateTime startOfDayLocal = DateTime(now.year, now.month, now.day);
    // Get the end of the current day in local time (just before midnight)
    final DateTime endOfDayLocal =
        DateTime(now.year, now.month, now.day, 23, 59, 59);

    // Orders query filters data created today (inclusive)
    final Query ordersTodayQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDayLocal))
        .where('createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDayLocal));
    final Query customersQuery = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER);
    final Query foodsQuery =
        FirebaseFirestore.instance.collection('vendor_products');
    final Query foodsTodayQuery = foodsQuery
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDayLocal))
        .where('createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDayLocal));
    final Query restaurantsQuery =
        FirebaseFirestore.instance.collection('vendors');
    final Query ridersQuery = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER);
    final DateTime startOfLast30Days = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    const double smallCardHeight = 64;
    const double smallCardTitleFontSize = 7;
    const double smallCardValueFontSize = 14;
    final Query ordersLast30DaysQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfLast30Days))
        .where('createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDayLocal));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics Today'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: ordersTodayQuery.snapshots(), // This makes the data LIVE
        builder: (context, snapshot) {
          // 1. Connection/Error Handling
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
                  const Text('Failed to load analytics'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final orders = snapshot.data?.docs ?? [];

          // 2. Data Processing (Group orders by hour)
          final Map<int, int> ordersByHour = {};
          for (int i = 0; i < 24; i++) {
            ordersByHour[i] = 0; // Initialize all 24 hours to 0
          }

          for (var doc in orders) {
            final data = doc.data() as Map<String, dynamic>;
            final createdAt = data['createdAt'] as Timestamp?;
            if (createdAt != null) {
              // Convert to local time to correctly map to the local hour
              final orderTime = createdAt.toDate().toLocal();
              final hour = orderTime.hour;
              ordersByHour[hour] = (ordersByHour[hour] ?? 0) + 1;
            }
          }
          final uniqueBuyers = <String>{};
          // 3. Calculate Statistics
          final totalOrders = orders.length;
          // Calculate max orders safely, defaulting to 1 if no orders
          final maxOrders = ordersByHour.values.isEmpty
              ? 1
              : ordersByHour.values.reduce((a, b) => a > b ? a : b);

          // Find peak hour(s)
          final peakHourEntry = ordersByHour.entries
              .where((entry) => entry.value == maxOrders)
              .toList();

          String peakHourDisplay;
          if (maxOrders == 0) {
            peakHourDisplay = 'N/A';
          } else if (peakHourEntry.length == 1) {
            peakHourDisplay =
                '${peakHourEntry.first.key.toString().padLeft(2, '0')}:00';
          } else {
            // Handle multiple peak hours (e.g., 12:00, 19:00)
            final hours = peakHourEntry
                .map((e) => '${e.key.toString().padLeft(2, '0')}:00')
                .toList();
            // Show the first one but indicate there are more
            peakHourDisplay = hours.join(', ');
          }

          // 4. Build UI
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                'Total Orders',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$totalOrders',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                'Peak Order Count',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                // Use maxOrders for the value
                                '$maxOrders',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(context).copyWith(
                    cardTheme: CardTheme(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide.none,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: customersQuery.get(),
                          builder: (context, customersSnapshot) {
                            final isLoadingCustomers =
                                customersSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int newCustomersToday = 0;
                            if (customersSnapshot.hasData) {
                              for (final doc in customersSnapshot.data!.docs) {
                                final data =
                                    doc.data() as Map<String, dynamic>?;
                                if (data == null) continue;
                                final ts = data['createdAt'] ??
                                    data['created_at'] as dynamic?;
                                if (ts == null || ts is! Timestamp) continue;
                                final dt = ts.toDate().toLocal();
                                if (dt.year == now.year &&
                                    dt.month == now.month &&
                                    dt.day == now.day) {
                                  newCustomersToday++;
                                }
                              }
                            }
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    Text(
                                      'New Customers Today',
                                      style: TextStyle(
                                        fontSize: smallCardTitleFontSize,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isLoadingCustomers
                                          ? '...'
                                          : '$newCustomersToday',
                                      style: const TextStyle(
                                        fontSize: smallCardValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: (() {
                            final todayRange = _getTodayUtcRange();
                            final startOfDay = todayRange['start']!;
                            final endOfDay = todayRange['end']!;
                            return FirebaseFirestore.instance
                                .collection('restaurant_orders')
                                .where('createdAt',
                                    isGreaterThanOrEqualTo:
                                        Timestamp.fromDate(startOfDay))
                                .where('createdAt',
                                    isLessThanOrEqualTo:
                                        Timestamp.fromDate(endOfDay))
                                .get();
                          })(),
                          builder: (context, snapshot) {
                            final isLoading =
                                snapshot.connectionState ==
                                    ConnectionState.waiting;
                            final orders = snapshot.data?.docs ?? [];
                            final uniqueCustomers = <String>{};
                            for (final orderDoc in orders) {
                              try {
                                final data =
                                    orderDoc.data() as Map<String, dynamic>;
                                final author =
                                    data['author'] as Map<String, dynamic>?;
                                if (author == null) continue;
                                final customerId = author['id'] as String?;
                                if (customerId != null &&
                                    customerId.isNotEmpty) {
                                  uniqueCustomers.add(customerId);
                                }
                              } catch (_) {}
                            }
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ActiveBuyersTodayPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Buyers Today',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoading
                                            ? '...'
                                            : '${uniqueCustomers.length}',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: (() {
                            final weekRange = _getWeekDateRange();
                            final startOfWeek = weekRange['start']!;
                            final endOfWeek = weekRange['end']!;
                            return FirebaseFirestore.instance
                                .collection('restaurant_orders')
                                .where('createdAt',
                                    isGreaterThanOrEqualTo:
                                        Timestamp.fromDate(startOfWeek))
                                .where('createdAt',
                                    isLessThanOrEqualTo:
                                        Timestamp.fromDate(endOfWeek))
                                .get();
                          })(),
                          builder: (context, snapshot) {
                            final isLoading =
                                snapshot.connectionState ==
                                    ConnectionState.waiting;
                            final ordersThisWeek =
                                snapshot.data?.docs.length ?? 0;
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    Text(
                                      'Orders This Week',
                                      style: TextStyle(
                                        fontSize: smallCardTitleFontSize,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isLoading ? '...' : '$ordersThisWeek',
                                      style: const TextStyle(
                                        fontSize: smallCardValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: (() {
                            final weekRange = _getWeekDateRange();
                            final startOfWeek = weekRange['start']!;
                            final endOfWeek = weekRange['end']!;
                            return FirebaseFirestore.instance
                                .collection('restaurant_orders')
                                .where('createdAt',
                                    isGreaterThanOrEqualTo:
                                        Timestamp.fromDate(startOfWeek))
                                .where('createdAt',
                                    isLessThanOrEqualTo:
                                        Timestamp.fromDate(endOfWeek))
                                .get();
                          })(),
                          builder: (context, snapshot) {
                            final isLoading =
                                snapshot.connectionState ==
                                    ConnectionState.waiting;
                            final orders = snapshot.data?.docs ?? [];
                            final uniqueCustomers = <String>{};
                            for (final orderDoc in orders) {
                              try {
                                final data =
                                    orderDoc.data() as Map<String, dynamic>;
                                final author =
                                    data['author'] as Map<String, dynamic>?;
                                if (author == null) continue;
                                final customerId = author['id'] as String?;
                                if (customerId != null &&
                                    customerId.isNotEmpty) {
                                  uniqueCustomers.add(customerId);
                                }
                              } catch (_) {}
                            }
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ActiveBuyersThisWeekPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Buyers This Week',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoading
                                            ? '...'
                                            : '${uniqueCustomers.length}',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: foodsQuery.get(),
                          builder: (context, foodsSnapshot) {
                            final isLoadingFoods =
                                foodsSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            final totalFoods =
                                foodsSnapshot.data?.docs.length ?? 0;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const FoodsPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Total Foods',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingFoods ? '...' : '$totalFoods',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: foodsQuery.get(),
                          builder: (context, foodsSnapshot) {
                            final isLoadingFoods =
                                foodsSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int unpublishedFoods = 0;
                            if (foodsSnapshot.hasData) {
                              for (final foodDoc
                                  in foodsSnapshot.data!.docs) {
                                final data =
                                    foodDoc.data() as Map<String, dynamic>?;
                                if (data == null) continue;
                                if (!_isFoodPublished(data)) {
                                  unpublishedFoods++;
                                }
                              }
                            }
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const FoodsPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Unpublished Foods',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingFoods
                                            ? '...'
                                            : '$unpublishedFoods',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: foodsTodayQuery.get(),
                          builder: (context, foodsSnapshot) {
                            final isLoadingFoods =
                                foodsSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            final foodsToday =
                                foodsSnapshot.data?.docs.length ?? 0;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const FoodsPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Foods Added Today',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingFoods ? '...' : '$foodsToday',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: restaurantsQuery.get(),
                          builder: (context, restaurantsSnapshot) {
                            final isLoadingRestaurants =
                                restaurantsSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            final totalRestaurants =
                                restaurantsSnapshot.data?.docs.length ?? 0;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const RestaurantsPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Total Restaurants',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingRestaurants
                                            ? '...'
                                            : '$totalRestaurants',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: ridersQuery.get(),
                          builder: (context, ridersSnapshot) {
                            final isLoadingRiders =
                                ridersSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            final totalRiders =
                                ridersSnapshot.data?.docs.length ?? 0;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const RidersOrdersTodayPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Total Riders',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingRiders ? '...' : '$totalRiders',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: ridersQuery.get(),
                          builder: (context, ridersSnapshot) {
                            final isLoadingRiders =
                                ridersSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int activeRiders = 0;
                            if (ridersSnapshot.hasData) {
                              for (final riderDoc
                                  in ridersSnapshot.data!.docs) {
                                final data =
                                    riderDoc.data() as Map<String, dynamic>?;
                                if (data == null) continue;
                                final isActive =
                                    data['checkedOutToday'] != true;
                                if (isActive) activeRiders++;
                              }
                            }
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    Text(
                                      'Active Riders Today',
                                      style: TextStyle(
                                        fontSize: smallCardTitleFontSize,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isLoadingRiders ? '...' : '$activeRiders',
                                      style: const TextStyle(
                                        fontSize: smallCardValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<List<QuerySnapshot>>(
                          future: Future.wait([
                            customersQuery.get(),
                            ordersLast30DaysQuery.get(),
                          ]),
                          builder: (context, dataSnapshot) {
                            final isLoadingInactive =
                                dataSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int inactiveCount = 0;
                            if (dataSnapshot.hasData) {
                              final customers = dataSnapshot.data![0].docs;
                              final orders = dataSnapshot.data![1].docs;
                              final allCustomerIds = <String>{};
                              final activeCustomerIds = <String>{};

                              for (final customerDoc in customers) {
                                final customerId = customerDoc.id;
                                if (customerId.isNotEmpty) {
                                  allCustomerIds.add(customerId);
                                }
                              }
                              for (final orderDoc in orders) {
                                final data =
                                    orderDoc.data()
                                        as Map<String, dynamic>?;
                                if (data == null) continue;
                                final author = data['author'];
                                if (author is Map<String, dynamic>) {
                                  final customerId = author['id'] as String?;
                                  if (customerId != null &&
                                      customerId.isNotEmpty) {
                                    activeCustomerIds.add(customerId);
                                  }
                                }
                              }
                              inactiveCount = allCustomerIds.length -
                                  activeCustomerIds.length;
                            }
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const InactiveCustomersPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Inactive Customers',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingInactive
                                            ? '...'
                                            : '$inactiveCount',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<List<QuerySnapshot>>(
                          future: Future.wait([
                            customersQuery.get(),
                            ordersLast30DaysQuery.get(),
                          ]),
                          builder: (context, dataSnapshot) {
                            final isLoadingActive =
                                dataSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int activeCount = 0;
                            if (dataSnapshot.hasData) {
                              final orders = dataSnapshot.data![1].docs;
                              final activeCustomerIds = <String>{};

                              for (final orderDoc in orders) {
                                final data =
                                    orderDoc.data()
                                        as Map<String, dynamic>?;
                                if (data == null) continue;
                                final author = data['author'];
                                if (author is Map<String, dynamic>) {
                                  final customerId = author['id'] as String?;
                                  if (customerId != null &&
                                      customerId.isNotEmpty) {
                                    activeCustomerIds.add(customerId);
                                  }
                                }
                              }
                              activeCount = activeCustomerIds.length;
                            }
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    Text(
                                      'Active Customers',
                                      style: TextStyle(
                                        fontSize: smallCardTitleFontSize,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isLoadingActive ? '...' : '$activeCount',
                                      style: const TextStyle(
                                        fontSize: smallCardValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
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
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(context).copyWith(
                    cardTheme: CardTheme(
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide.none,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: customersQuery.get(),
                          builder: (context, customersSnapshot) {
                            final isLoadingCustomers =
                                customersSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            final totalCustomers =
                                customersSnapshot.data?.docs.length ?? 0;
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const CustomersPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Total Customers',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingCustomers
                                            ? '...'
                                            : '$totalCustomers',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: ordersTodayQuery.get(),
                          builder: (context, ordersSnapshot) {
                            final isLoadingRejected =
                                ordersSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int rejectedCount = 0;
                            if (ordersSnapshot.hasData) {
                              for (final doc in ordersSnapshot.data!.docs) {
                                try {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final status =
                                      data['status']?.toString().toLowerCase() ??
                                          '';
                                  if (status == 'order rejected' ||
                                      status == 'driver rejected') {
                                    rejectedCount++;
                                  }
                                } catch (_) {}
                              }
                            }
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const OrderDispatcherPage(),
                                  ),
                                );
                              },
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Rejected Orders',
                                        style: TextStyle(
                                          fontSize: smallCardTitleFontSize,
                                          color: Colors.black,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        isLoadingRejected
                                            ? '...'
                                            : '$rejectedCount',
                                        style: const TextStyle(
                                          fontSize: smallCardValueFontSize,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: ordersTodayQuery.get(),
                          builder: (context, ordersSnapshot) {
                            final isLoadingCompleted =
                                ordersSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int completedCount = 0;
                            if (ordersSnapshot.hasData) {
                              for (final doc in ordersSnapshot.data!.docs) {
                                try {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final status =
                                      data['status']?.toString().toLowerCase() ??
                                          '';
                                  if (status == 'order completed' ||
                                      status == 'completed') {
                                    completedCount++;
                                  }
                                } catch (_) {}
                              }
                            }
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    Text(
                                      'Completed Orders',
                                      style: TextStyle(
                                        fontSize: smallCardTitleFontSize,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isLoadingCompleted
                                          ? '...'
                                          : '$completedCount',
                                      style: const TextStyle(
                                        fontSize: smallCardValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 110,
                        height: smallCardHeight,
                        child: FutureBuilder<QuerySnapshot>(
                          future: ordersTodayQuery.get(),
                          builder: (context, ordersSnapshot) {
                            final isLoadingPending =
                                ordersSnapshot.connectionState ==
                                    ConnectionState.waiting;
                            int pendingCount = 0;
                            if (ordersSnapshot.hasData) {
                              for (final doc in ordersSnapshot.data!.docs) {
                                try {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  final status =
                                      data['status']?.toString().toLowerCase() ??
                                          '';
                                  if (status != 'order completed' &&
                                      status != 'completed' &&
                                      status != 'order rejected' &&
                                      status != 'driver rejected') {
                                    pendingCount++;
                                  }
                                } catch (_) {}
                              }
                            }
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  children: [
                                    Text(
                                      'Pending Orders',
                                      style: TextStyle(
                                        fontSize: smallCardTitleFontSize,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isLoadingPending
                                          ? '...'
                                          : '$pendingCount',
                                      style: const TextStyle(
                                        fontSize: smallCardValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
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
                  ),
                ),
                const SizedBox(height: 12),
                // Peak Hour Card - Added for more detail
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Peak Hour(s): ',
                          style:
                              TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                        Text(
                          peakHourDisplay,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Chart Title
                const Text(
                  'Orders Timeline (Today)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('EEEE, MMMM dd, yyyy').format(now),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),

                // Timeline Chart
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    child: SizedBox(
                      height: 300,
                      child: LineChart(
                        _buildChartData(ordersByHour,
                            maxOrders), // Use the implemented method
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Hourly Breakdown
                const Text(
                  'Hourly Breakdown',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: List.generate(24, (index) {
                        final hour = index;
                        final count = ordersByHour[hour] ?? 0;
                        final isPeak = count == maxOrders && maxOrders > 0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 50,
                                child: Text(
                                  '${hour.toString().padLeft(2, '0')}:00',
                                  style: TextStyle(
                                    fontWeight: isPeak
                                        ? FontWeight.w900
                                        : FontWeight.w600,
                                    color: isPeak
                                        ? Colors.deepOrange
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8.0),
                                  child: LinearProgressIndicator(
                                    value:
                                        maxOrders > 0 ? count / maxOrders : 0,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isPeak
                                          ? Colors.deepOrange
                                          : Colors.orange.shade300,
                                    ),
                                    minHeight: 12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 30,
                                child: Text(
                                  '$count',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontWeight: isPeak
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isPeak
                                        ? Colors.deepOrange
                                        : Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Riders Who Delivered Today',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FutureBuilder<QuerySnapshot>(
                    future: ridersQuery.get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Failed to load riders: ${snapshot.error}',
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        );
                      }
                      final docs = snapshot.data?.docs ?? [];
                      final deliveredCountByDriver = <String, int>{};
                      for (final orderDoc in orders) {
                        final data =
                            orderDoc.data() as Map<String, dynamic>?;
                        if (data == null) continue;
                        final status =
                            data['status']?.toString().toLowerCase() ?? '';
                        if (status != 'order completed' && status != 'completed') {
                          continue;
                        }
                        final driverIdRaw =
                            data['driverID'] ?? data['driver_id'];
                        final driverId = driverIdRaw?.toString();
                        if (driverId != null && driverId.isNotEmpty) {
                          deliveredCountByDriver[driverId] =
                              (deliveredCountByDriver[driverId] ?? 0) + 1;
                        }
                      }
                      final ridersWhoDelivered = <Map<String, dynamic>>[];
                      for (final doc in docs) {
                        final data = doc.data() as Map<String, dynamic>?;
                        if (data == null) continue;
                        final deliveredCount = deliveredCountByDriver[doc.id] ?? 0;
                        if (deliveredCount == 0) continue;
                        final name =
                            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                .trim();
                        final creditWallet = ((data['wallet_credit'] ?? 0.0)
                            as num).toDouble();
                        final walletBalance = ((data['wallet_amount'] ?? 0.0)
                            as num).toDouble();
                        final total = creditWallet - walletBalance;
                        final orderCount =
                            deliveredCountByDriver[doc.id] ?? 0;
                        ridersWhoDelivered.add({
                          'name': name.isEmpty ? 'Unknown' : name,
                          'orderCount': orderCount,
                          'creditWallet': creditWallet,
                          'walletBalance': walletBalance,
                          'total': total,
                        });
                      }
                      if (ridersWhoDelivered.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                              child: Text('No riders delivered today.')),
                        );
                      }
                      double sumCredit = 0;
                      double sumBalance = 0;
                      double sumTotal = 0;
                      int sumOrders = 0;
                      for (final r in ridersWhoDelivered) {
                        sumCredit += r['creditWallet'] as double;
                        sumBalance += r['walletBalance'] as double;
                        sumTotal += r['total'] as double;
                        sumOrders += r['orderCount'] as int;
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Table(
                            defaultColumnWidth: const IntrinsicColumnWidth(),
                            border: TableBorder.all(color: Colors.grey[300]!),
                            children: [
                              TableRow(
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                ),
                                children: [
                                  _tableCell('Name', isHeader: true),
                                  _tableCell('No. of Orders', isHeader: true),
                                  _tableCell('Credit Wallet', isHeader: true),
                                  _tableCell('Wallet Balance', isHeader: true),
                                  _tableCell('Total', isHeader: true),
                                ],
                              ),
                              ...ridersWhoDelivered.map(
                                (r) => TableRow(
                                  children: [
                                    _tableCell(r['name'] as String),
                                    _tableCell('${r['orderCount'] as int}'),
                                    _tableCell(
                                        '₱${(r['creditWallet'] as double).toStringAsFixed(2)}'),
                                    _tableCell(
                                        '₱${(r['walletBalance'] as double).toStringAsFixed(2)}'),
                                    _tableCell(
                                        '₱${(r['total'] as double).toStringAsFixed(2)}'),
                                  ],
                                ),
                              ),
                              TableRow(
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                ),
                                children: [
                                  _tableCell('Overall Total', isHeader: true),
                                  _tableCell('$sumOrders', isHeader: true),
                                  _tableCell(
                                      '₱${sumCredit.toStringAsFixed(2)}',
                                      isHeader: true),
                                  _tableCell(
                                      '₱${sumBalance.toStringAsFixed(2)}',
                                      isHeader: true),
                                  _tableCell(
                                      '₱${sumTotal.toStringAsFixed(2)}',
                                      isHeader: true),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tableCell(String text, {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 14 : 13,
        ),
      ),
    );
  }
}