import 'package:flutter/material.dart';

class PromoImpactCard extends StatelessWidget {
  const PromoImpactCard({
    super.key,
    required this.promoId,
    required this.data,
    this.compact = false,
    this.onTap,
  });

  final String promoId;
  final Map<String, dynamic> data;
  final bool compact;
  final VoidCallback? onTap;

  Color _roiColor() {
    final roi = (data['roi'] as num?)?.toDouble() ?? 0;
    if (roi > 0) return Colors.green;
    if (roi >= -0.1) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final incrementalOrders =
        (data['incrementalOrders'] as num?)?.toInt() ?? 0;
    final roi = (data['roi'] as num?)?.toDouble() ?? 0;
    final roiColor = _roiColor();
    final roiLabel =
        roi > 0 ? 'Positive' : roi >= -0.1 ? 'Break-even' : 'Subsidy';

    final content = Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  promoId,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 13 : null,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '+$incrementalOrders incremental orders',
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: roiColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'ROI ${(roi * 100).toStringAsFixed(1)}% ($roiLabel)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: roiColor,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ),
        ],
      ),
    );

    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: content,
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }
    return card;
  }
}
