import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AlertItem extends StatelessWidget {
  const AlertItem({
    super.key,
    required this.alertId,
    required this.data,
    this.compact = false,
    this.showViewButton = false,
    this.onTap,
  });

  final String alertId;
  final Map<String, dynamic> data;
  final bool compact;
  final bool showViewButton;
  final VoidCallback? onTap;

  Color _severityColor() {
    switch ((data['severity'] ?? '').toString().toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _timeSince(DateTime? dt) {
    if (dt == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final severity = (data['severity'] ?? 'info').toString();
    final type = (data['type'] ?? 'overall_drop').toString();
    final expected = (data['expected'] as num?)?.toInt() ?? 0;
    final actual = (data['actual'] as num?)?.toInt() ?? 0;
    final detectedAt = (data['detectedAt'] as Timestamp?)?.toDate();
    final color = _severityColor();

    final content = Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Row(
        children: [
          Container(
            width: compact ? 36 : 48,
            height: compact ? 36 : 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              severity == 'critical' ? Icons.warning : Icons.info_outline,
              color: color,
              size: compact ? 20 : 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${severity.toUpperCase()}: $type',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 12 : 14,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Expected: $expected | Actual: $actual',
                  style: TextStyle(
                    fontSize: compact ? 11 : 12,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  _timeSince(detectedAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (showViewButton)
            TextButton(
              onPressed: onTap,
              child: const Text('View'),
            ),
        ],
      ),
    );

    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: content,
    );
    if (onTap != null && !showViewButton) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }
    return card;
  }
}
