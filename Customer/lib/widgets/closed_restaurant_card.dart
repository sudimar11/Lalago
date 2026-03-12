import 'package:flutter/material.dart';

import 'package:foodie_customer/constants.dart';

/// Card shown when user tries to add items from a closed restaurant.
class ClosedRestaurantCard extends StatelessWidget {
  const ClosedRestaurantCard({
    super.key,
    required this.data,
  });

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final vendorName =
        (data['vendorName'] ?? 'Restaurant').toString();
    final todayHours = (data['todayHours'] ?? 'Closed').toString();
    final currentTime = (data['currentTime'] ?? '').toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.orange.shade900.withValues(alpha: 0.2)
            : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.orange.shade700 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.access_time,
                color: Color(COLOR_PRIMARY),
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$vendorName is currently closed',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? Colors.orange.shade200
                        : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "Today's hours: $todayHours",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (currentTime.isNotEmpty)
            Text(
              'Current time: $currentTime',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Please try again during operating hours.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
