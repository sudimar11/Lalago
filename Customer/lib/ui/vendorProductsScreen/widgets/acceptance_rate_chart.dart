import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:intl/intl.dart';

/// Mini line chart of acceptance rate over last 30 days.
class AcceptanceRateChart extends StatefulWidget {
  final VendorModel vendorModel;

  const AcceptanceRateChart({
    super.key,
    required this.vendorModel,
  });

  @override
  State<AcceptanceRateChart> createState() => _AcceptanceRateChartState();
}

class _AcceptanceRateChartState extends State<AcceptanceRateChart> {
  late final Future<Map<String, double>> _future;

  @override
  void initState() {
    super.initState();
    _future = FireStoreUtils.getVendorDailyAcceptanceRates(
      widget.vendorModel.id,
      lastDays: 30,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, double>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snap.data ?? {};
        if (data.isEmpty) {
          return const SizedBox.shrink();
        }

        final sortedDates = data.keys.toList()..sort();
        final spots = <FlSpot>[];
        for (var i = 0; i < sortedDates.length; i++) {
          spots.add(FlSpot(i.toDouble(), data[sortedDates[i]]!));
        }
        final maxY = data.values.fold(100.0, (a, b) => a > b ? a : b);
        final minY = data.values.fold(0.0, (a, b) => a < b ? a : b);
        final isDark = isDarkMode(context);
        final lineColor = Color(COLOR_PRIMARY);
        final gridColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

        return Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey.shade800.withOpacity(0.5)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Acceptance Rate (Last 30 Days)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppinsm',
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 20,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color: gridColor,
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}%',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: (sortedDates.length / 5).ceilToDouble(),
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i >= 0 && i < sortedDates.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  sortedDates[i].substring(5),
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                    fontSize: 9,
                                  ),
                                ),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: gridColor),
                    ),
                    minX: 0,
                    maxX: (sortedDates.length - 1).toDouble(),
                    minY: (minY - 5).clamp(0.0, 100.0),
                    maxY: (maxY + 5).clamp(0.0, 100.0),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final i = spot.x.toInt();
                            final dateStr = i >= 0 && i < sortedDates.length
                                ? sortedDates[i]
                                : '';
                            final rate = spot.y;
                            return LineTooltipItem(
                              '$dateStr\n${rate.toStringAsFixed(1)}%',
                              TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: lineColor,
                        barWidth: 2.5,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: lineColor.withOpacity(0.15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
