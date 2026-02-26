import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/widgets/performance_badge.dart';
import 'acceptance_rate_chart.dart';

/// Performance metrics section for restaurant details page.
class RestaurantPerformanceSection extends StatelessWidget {
  final VendorModel vendorModel;

  const RestaurantPerformanceSection({
    super.key,
    required this.vendorModel,
  });

  @override
  Widget build(BuildContext context) {
    final pm = vendorModel.publicMetrics;
    final badge = vendorModel.performanceBadge?.toLowerCase();
    final isNew = badge == 'new' || pm == null;

    if (isNew) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode(context)
                ? Colors.grey.shade800.withOpacity(0.5)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDarkMode(context)
                  ? Colors.grey.shade700
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: isDarkMode(context)
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This restaurant just joined Lalago. '
                  'Check back soon for performance data.',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppinsr',
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final acceptanceRate = vendorModel.acceptanceRate;
    final avgTime = vendorModel.avgAcceptanceTimeSeconds;
    final orderCount = vendorModel.orderCountLast30Days;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDarkMode(context)
              ? Colors.grey.shade800.withOpacity(0.5)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDarkMode(context)
                ? Colors.grey.shade700
                : Colors.grey.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Performance',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppinsm',
                    color: isDarkMode(context)
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                PerformanceBadge(
                  vendorModel: vendorModel,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                if (acceptanceRate != null)
                  _MetricChip(
                    icon: Icons.check_circle_outline,
                    label: '${acceptanceRate.toStringAsFixed(1)}% acceptance',
                    isDark: isDarkMode(context),
                  ),
                if (avgTime != null && avgTime > 0)
                  _MetricChip(
                    icon: Icons.schedule,
                    label: _formatAvgTime(avgTime),
                    isDark: isDarkMode(context),
                  ),
                if (orderCount != null && orderCount > 0)
                  _MetricChip(
                    icon: Icons.receipt_long,
                    label: '$orderCount orders (30 days)',
                    isDark: isDarkMode(context),
                  ),
              ],
            ),
            AcceptanceRateChart(vendorModel: vendorModel),
          ],
        ),
      ),
    );
  }

  String _formatAvgTime(double seconds) {
    if (seconds < 60) {
      return 'Usually confirms in ${seconds.round()} sec';
    }
    final mins = (seconds / 60).round();
    return mins == 1
        ? 'Usually confirms in 1 min'
        : 'Usually confirms in $mins mins';
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'Poppinsr',
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}
