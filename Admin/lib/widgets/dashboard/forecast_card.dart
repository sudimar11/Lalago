import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:brgy/services/main_dashboard_service.dart';

class ForecastCard extends StatelessWidget {
  const ForecastCard({
    super.key,
    required this.predicted,
    required this.actual,
    required this.lowerBound,
    required this.upperBound,
    this.source = ForecastSource.orderForecasts,
    this.sparklineSpots,
    this.onTap,
  });

  final int predicted;
  final int actual;
  final int lowerBound;
  final int upperBound;
  final ForecastSource source;
  final List<FlSpot>? sparklineSpots;
  final VoidCallback? onTap;

  String _sourceLabel() {
    switch (source) {
      case ForecastSource.orderForecasts:
        return 'Forecast (90-day model)';
      case ForecastSource.forecastAggregates:
        return 'Est. from aggregates (14-day avg)';
      case ForecastSource.restaurantOrders:
        return 'Est. from orders (14-day avg)';
    }
  }

  @override
  Widget build(BuildContext context) {
    Color statusColor = Colors.green;
    String statusLabel = 'On track';
    if (predicted > 0) {
      final ratio = actual / predicted;
      if (ratio >= 0.95) {
        statusColor = Colors.green;
        statusLabel = 'On track';
      } else if (ratio >= 0.8) {
        statusColor = Colors.orange;
        statusLabel = 'Slightly below';
      } else {
        statusColor = Colors.red;
        statusLabel = 'Underperforming';
      }
    }

    final body = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's Forecast",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _sourceLabel(),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$predicted',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              const Text('orders predicted', style: TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Actual so far: $actual orders',
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          if (lowerBound > 0)
            Text(
              '80% confidence: $lowerBound - $upperBound',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          if (sparklineSpots != null && sparklineSpots!.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 80,
              child: LineChart(
                LineChartData(
                  lineTouchData: const LineTouchData(enabled: false),
                  gridData: FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: sparklineSpots!,
                      isCurved: true,
                      color: Colors.orange,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.orange.withOpacity(0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: body,
        ),
      );
    }
    return Card(child: body);
  }
}
