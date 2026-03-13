import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';

class ProgressBarWithIndicator extends StatelessWidget {
  final double progress;
  final int tokensCurrent;
  final int tokensForNextTier;
  final String? nextTierName;
  final int tokensNeeded;

  const ProgressBarWithIndicator({
    Key? key,
    required this.progress,
    required this.tokensCurrent,
    required this.tokensForNextTier,
    this.nextTierName,
    required this.tokensNeeded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nextDisplay = nextTierName != null
        ? nextTierName![0].toUpperCase() + nextTierName!.substring(1)
        : 'next tier';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$tokensCurrent / $tokensForNextTier tokens',
              style: theme.textTheme.titleMedium,
            ),
            if (nextTierName != null)
              Text(
                'Next: $nextDisplay',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 12,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.brightness == Brightness.dark
                  ? theme.colorScheme.primary
                  : Color(COLOR_PRIMARY),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tokensNeeded > 0
              ? '$tokensNeeded more order${tokensNeeded > 1 ? 's' : ''} to reach $nextDisplay!'
              : 'You have reached the highest tier!',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }
}
