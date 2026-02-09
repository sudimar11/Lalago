import 'package:flutter/material.dart';

/// Simple button card widget for dashboard navigation.
/// No data loading - just a clickable card that navigates to detail pages.
class DashboardButtonCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const DashboardButtonCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// Compact card size for dashboard sections.
  static const double cardPadding = 3;
  static const double iconSize = 14;
  static const double labelFontSize = 7;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(cardPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize, color: Colors.orange),
              const SizedBox(height: 1),
              Text(
                label,
                style: const TextStyle(
                  fontSize: labelFontSize,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

