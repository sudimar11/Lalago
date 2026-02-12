import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:foodie_driver/constants.dart';

class PerformanceBarChart extends StatelessWidget {
  final Map<String, double> dailyScores;
  final double currentPerformance;
  final bool isDarkMode;

  const PerformanceBarChart({
    Key? key,
    required this.dailyScores,
    required this.currentPerformance,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Prepare data for the chart
    final barGroups = <BarChartGroupData>[];
    final dayLabels = <String>[];
    
    // Get Monday of current week
    final now = DateTime.now();
    final weekday = now.weekday;
    final daysToMonday = weekday - 1;
    final monday = now.subtract(Duration(days: daysToMonday));
    
    // Create bars for each day (Mon-Sun)
    for (int i = 0; i < 7; i++) {
      final date = monday.add(Duration(days: i));
      final dateString = DateFormat('yyyy-MM-dd').format(date);
      final score = dailyScores[dateString] ?? 0.0;
      
      // Day labels (M, T, W, T, F, S, S)
      final dayAbbrev = DateFormat('E').format(date).substring(0, 1);
      dayLabels.add(dayAbbrev);
      
      // Determine color based on score
      Color barColor;
      if (score > 0) {
        barColor = Colors.green;
      } else if (score < 0) {
        barColor = Colors.red;
      } else {
        barColor = isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400;
      }
      
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: score,
              color: barColor,
              width: 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 2.5,
          minY: -3.5,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => isDarkMode
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.white,
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.all(8),
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final date = monday.add(Duration(days: group.x.toInt()));
                final dateString = DateFormat('MMM d').format(date);
                final score = rod.toY;
                String label;
                if (score > 0) {
                  label = '+${score.toStringAsFixed(1)}';
                } else if (score < 0) {
                  label = score.toStringAsFixed(1);
                } else {
                  label = '0.0';
                }
                return BarTooltipItem(
                  '$dateString\n$label points',
                  TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() >= 0 && value.toInt() < dayLabels.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        dayLabels[value.toInt()],
                        style: TextStyle(
                          color: isDarkMode
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return const Text('');
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) {
                    return const Text('');
                  }
                  String label;
                  if (value > 0) {
                    label = '+${value.toStringAsFixed(1)}';
                  } else if (value < 0) {
                    label = value.toStringAsFixed(1);
                  } else {
                    label = '0';
                  }
                  return Text(
                    label,
                    style: TextStyle(
                      color: isDarkMode
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: isDarkMode
                    ? Colors.grey.shade800
                    : Colors.grey.shade300,
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(
                color: isDarkMode
                    ? Colors.grey.shade800
                    : Colors.grey.shade300,
                width: 1,
              ),
              left: BorderSide(
                color: isDarkMode
                    ? Colors.grey.shade800
                    : Colors.grey.shade300,
                width: 1,
              ),
            ),
          ),
          barGroups: barGroups,
        ),
      ),
    );
  }
}

