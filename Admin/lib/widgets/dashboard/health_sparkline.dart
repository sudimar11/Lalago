import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class HealthSparkline extends StatelessWidget {
  const HealthSparkline({
    super.key,
    required this.history,
    this.height = 48,
    this.days = 7,
  });

  final List<Map<String, dynamic>> history;
  final double height;
  final int days;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough data yet.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
      );
    }

    final spots = history.asMap().entries.map((e) {
      final score = (e.value['overallScore'] as num?)?.toDouble() ?? 0.0;
      return FlSpot(e.key.toDouble(), score);
    }).toList();

    if (spots.isEmpty) return SizedBox(height: height);

    final maxY = 100.0;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          lineTouchData: const LineTouchData(enabled: false),
          gridData: FlGridData(
            show: true,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: Colors.grey[300]!, strokeWidth: 0.5),
          ),
          titlesData: const FlTitlesData(
            show: false,
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.green,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.green.withOpacity(0.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
