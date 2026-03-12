import 'package:flutter/material.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/utils/today_performance_service.dart';

/// Card showing today's performance: avg preparation time and customer rating.
/// Shows an informative placeholder when there is no data.
class TodayPerformanceCard extends StatelessWidget {
  const TodayPerformanceCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TodayPerformanceResult>(
      future: TodayPerformanceService.fetchForCurrentVendor(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final result = snapshot.data!;
        return _buildCard(context, result);
      },
    );
  }

  Widget _buildCard(BuildContext context, TodayPerformanceResult result) {
    final isDark = isDarkMode(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Today\'s Performance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              Icon(Icons.analytics, color: Color(COLOR_PRIMARY), size: 24),
            ],
          ),
          const SizedBox(height: 12),
          if (!result.hasData)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Complete an order to see today\'s metrics',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Average Preparation Time',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${result.avgMinutes.toStringAsFixed(1)} minutes',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                      Text(
                        'Based on ${result.totalOrders} orders today',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rating',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (result.ratingCount > 0 && result.avgRating != null) ...[
                      Row(
                        children: List.generate(
                          5,
                          (i) {
                            final r = result.avgRating!;
                            final filled = r >= i + 1;
                            final half =
                                r >= i + 0.5 && r < i + 1;
                            return Icon(
                              filled
                                  ? Icons.star
                                  : half
                                      ? Icons.star_half
                                      : Icons.star_border,
                              color: filled || half
                                  ? Colors.amber
                                  : Colors.grey,
                              size: 20,
                            );
                          },
                        ),
                      ),
                      Text(
                        '${result.avgRating!.toStringAsFixed(1)} ★',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                        ),
                      ),
                    ] else
                      Text(
                        'No Ratings Yet',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}
