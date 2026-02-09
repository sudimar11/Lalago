import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class AnalyticsWeeklyPage extends StatefulWidget {
  const AnalyticsWeeklyPage({super.key});

  @override
  State<AnalyticsWeeklyPage> createState() => _AnalyticsWeeklyPageState();
}

class _AnalyticsWeeklyPageState extends State<AnalyticsWeeklyPage> {
  LineChartData _buildDailyChartData(
      Map<int, int> ordersByHour, int maxOrders) {
    final spots = List.generate(24, (index) {
      final count = ordersByHour[index] ?? 0;
      return FlSpot(index.toDouble(), count.toDouble());
    });

    final maxYValue = maxOrders > 0 ? maxOrders.toDouble() + 1 : 5.0;
    final yInterval = maxOrders > 0 ? (maxOrders / 5).ceil().toDouble() : 1.0;

    return LineChartData(
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
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: const Text(
            'Hour of Day (24h)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          axisNameSize: 25,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 2,
            getTitlesWidget: (value, meta) {
              final hour = value.toInt();
              if (hour % 2 == 0) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    hour.toString().padLeft(2, '0'),
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
        leftTitles: AxisTitles(
          axisNameWidget: const Text(
            'Orders',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          axisNameSize: 25,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: yInterval,
            getTitlesWidget: (value, meta) {
              if (value == 0 || value.toInt() > maxOrders) {
                return const Text('');
              }
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
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey[300]!),
      ),
      minX: 0,
      maxX: 23,
      minY: 0,
      maxY: maxYValue,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: Colors.orange,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.orange.withOpacity(0.1),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (LineBarSpot touchedSpot) =>
              Colors.orange.withOpacity(0.8),
          getTooltipItems: (List<LineBarSpot> touchedSpots) {
            return touchedSpots.map((LineBarSpot touchedSpot) {
              final hour = touchedSpot.x.toInt();
              final count = touchedSpot.y.toInt();
              return LineTooltipItem(
                '$count orders\n${hour.toString().padLeft(2, '0')}:00',
                const TextStyle(color: Colors.white),
              );
            }).toList();
          },
        ),
      ),
    );
  }

  BarChartData _buildWeeklyChartData(
      Map<int, int> ordersByDay, int maxOrders, DateTime startOfRange) {
    final barGroups = List.generate(7, (index) {
      final count = ordersByDay[index] ?? 0;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: count.toDouble(),
            color: Colors.orange,
            borderRadius: BorderRadius.circular(4),
            width: 18,
          ),
        ],
      );
    });

    final maxYValue = maxOrders > 0 ? maxOrders.toDouble() + 1 : 5.0;
    final yInterval = maxOrders > 0 ? (maxOrders / 5).ceil().toDouble() : 1.0;

    return BarChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: yInterval,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey[300]!,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: const Text(
            'Last 7 Days',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          axisNameSize: 24,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index > 6) return const SizedBox.shrink();
              final date = startOfRange.add(Duration(days: index));
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  DateFormat('MM/dd').format(date),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          axisNameWidget: const Text(
            'Orders',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          axisNameSize: 24,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 36,
            interval: yInterval,
            getTitlesWidget: (value, meta) {
              if (value == 0 || value.toInt() > maxOrders) {
                return const SizedBox.shrink();
              }
              return Text(
                value.toInt().toString(),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey[300]!),
      ),
      barGroups: barGroups,
      maxY: maxYValue,
      minY: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 6));
    final DateTime startOfRange =
        DateTime(sevenDaysAgo.year, sevenDaysAgo.month, sevenDaysAgo.day);
    final DateTime endOfRange =
        DateTime(now.year, now.month, now.day, 23, 59, 59);

    final Query weeklyOrdersQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfRange))
        .where('createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfRange));

    final rangeLabel =
        '${DateFormat('MMM dd').format(startOfRange)} - ${DateFormat('MMM dd, yyyy').format(now)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics - Last 7 Days'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: weeklyOrdersQuery.snapshots(),
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
                  const Text('Failed to load weekly analytics'),
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

          // Group by day (0..6), where 0 = oldest day in the range
          final Map<int, int> ordersByDay = {};
          for (int i = 0; i < 7; i++) {
            ordersByDay[i] = 0;
          }

          for (var doc in orders) {
            final data = doc.data() as Map<String, dynamic>;
            final createdAt = data['createdAt'] as Timestamp?;
            if (createdAt != null) {
              final orderTime = createdAt.toDate().toLocal();
              final dayIndex = orderTime
                  .difference(startOfRange)
                  .inDays; // 0..6 within range
              if (dayIndex >= 0 && dayIndex < 7) {
                ordersByDay[dayIndex] = (ordersByDay[dayIndex] ?? 0) + 1;
              }
            }
          }

          final totalOrders = orders.length;
          final maxOrders = ordersByDay.values.isEmpty
              ? 1
              : ordersByDay.values.reduce((a, b) => a > b ? a : b);

          final peakDayEntries = ordersByDay.entries
              .where((entry) => entry.value == maxOrders)
              .toList();

          String peakDayDisplay;
          if (totalOrders == 0 || maxOrders == 0) {
            peakDayDisplay = 'N/A';
          } else {
            final labels = peakDayEntries.map((entry) {
              final date = startOfRange.add(Duration(days: entry.key));
              return DateFormat('EEE, MMM dd').format(date);
            }).toList();
            peakDayDisplay = labels.join(' | ');
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary cards
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                'Total Orders (7 days)',
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
                                'Peak Day Orders',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Peak Day(s):',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          peakDayDisplay,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Orders Timeline (Last 7 Days)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  rangeLabel,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    child: SizedBox(
                      height: 300,
                      child: BarChart(
                        _buildWeeklyChartData(
                          ordersByDay,
                          maxOrders,
                          startOfRange,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Daily Breakdown',
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
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: List.generate(7, (index) {
                        final date = startOfRange.add(Duration(days: index));
                        final count = ordersByDay[index] ?? 0;
                        final isPeak = count == maxOrders && maxOrders > 0;
                        final label = DateFormat('EEE, MMM dd').format(date);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  label,
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
                                flex: 4,
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
                                width: 40,
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
                  'Analytics Per Day',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Column(
                  children: List.generate(7, (index) {
                    final dayDate = startOfRange.add(Duration(days: index));
                    final dayLabel =
                        DateFormat('EEEE, MMM dd, yyyy').format(dayDate);

                    // Build hourly data for this specific day
                    final Map<int, int> ordersByHour = {
                      for (int h = 0; h < 24; h++) h: 0
                    };
                    int totalDayOrders = 0;

                    for (var doc in orders) {
                      final data = doc.data() as Map<String, dynamic>;
                      final createdAt = data['createdAt'] as Timestamp?;
                      if (createdAt != null) {
                        final orderTime = createdAt.toDate().toLocal();
                        if (orderTime.year == dayDate.year &&
                            orderTime.month == dayDate.month &&
                            orderTime.day == dayDate.day) {
                          final hour = orderTime.hour;
                          ordersByHour[hour] = (ordersByHour[hour] ?? 0) + 1;
                          totalDayOrders++;
                        }
                      }
                    }

                    final dayMaxOrders = ordersByHour.values.isEmpty
                        ? 1
                        : ordersByHour.values
                            .reduce((a, b) => a > b ? a : b);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dayLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Total Orders: $totalDayOrders',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 220,
                              child: LineChart(
                                _buildDailyChartData(
                                  ordersByHour,
                                  dayMaxOrders,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


