import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';

/// Badge types for restaurant performance.
enum PerformanceBadgeType {
  fast,
  reliable,
  slow,
  newRestaurant,
}

/// Reusable performance badge for restaurant cards and details.
class PerformanceBadge extends StatelessWidget {
  final VendorModel? vendorModel;
  final PerformanceBadgeType? badgeType;
  final bool compact;

  const PerformanceBadge({
    super.key,
    this.vendorModel,
    this.badgeType,
    this.compact = false,
  }) : assert(vendorModel != null || badgeType != null);

  PerformanceBadgeType? get _effectiveType {
    if (badgeType != null) return badgeType;
    final badge = vendorModel?.performanceBadge?.toLowerCase();
    if (badge == null || badge.isEmpty) return null;
    switch (badge) {
      case 'fast':
        return PerformanceBadgeType.fast;
      case 'reliable':
        return PerformanceBadgeType.reliable;
      case 'slow':
        return PerformanceBadgeType.slow;
      case 'new':
        return PerformanceBadgeType.newRestaurant;
      default:
        return null;
    }
  }

  static (Color color, IconData icon, String label) _config(
    PerformanceBadgeType type,
  ) {
    switch (type) {
      case PerformanceBadgeType.fast:
        return (
          const Color(0xFF4CAF50),
          Icons.bolt,
          'Fast Responder',
        );
      case PerformanceBadgeType.reliable:
        return (
          const Color(0xFF2196F3),
          Icons.check_circle,
          'Reliable',
        );
      case PerformanceBadgeType.slow:
        return (
          const Color(0xFFFFC107),
          Icons.schedule,
          'Slow to Confirm',
        );
      case PerformanceBadgeType.newRestaurant:
        return (
          Colors.grey,
          Icons.fiber_new,
          'New Restaurant',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = _effectiveType;
    if (type == null) return const SizedBox.shrink();

    final (color, icon, label) = _config(type);
    final isDark = isDarkMode(context);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.25 : 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withOpacity(0.5),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppinsm',
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppinsm',
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
