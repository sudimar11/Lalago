import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';

class TierBadge extends StatelessWidget {
  final String tier;
  final String label;
  final double size;

  const TierBadge({
    Key? key,
    required this.tier,
    this.label = 'Current Tier',
    this.size = 80,
  }) : super(key: key);

  Color _getTierColor(String t) {
    switch (t.toLowerCase()) {
      case 'bronze':
        return Colors.brown;
      case 'silver':
        return const Color(0xFF9CA3AF);
      case 'gold':
        return Colors.amber;
      case 'diamond':
        return Colors.cyan;
      default:
        return Color(COLOR_PRIMARY);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tierDisplay = tier.isEmpty
        ? 'Bronze'
        : tier[0].toUpperCase() + tier.substring(1).toLowerCase();
    final color = _getTierColor(tier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [color, color.withValues(alpha: 0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            Icons.emoji_events,
            color: Colors.white,
            size: size * 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tierDisplay,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
