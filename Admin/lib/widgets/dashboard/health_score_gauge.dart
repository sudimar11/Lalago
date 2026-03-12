import 'package:flutter/material.dart';

class HealthScoreGauge extends StatelessWidget {
  const HealthScoreGauge({
    super.key,
    required this.score,
    this.size = 100,
    this.showLabel = true,
    this.onTap,
  });

  final int score;
  final double size;
  final bool showLabel;
  final VoidCallback? onTap;

  Color _scoreColor() {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor();
    final label = score >= 80 ? 'Healthy' : score >= 60 ? 'Caution' : 'Critical';
    final fontSize = (size * 0.36).clamp(20.0, 48.0);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: (score / 100).clamp(0.0, 1.0),
                strokeWidth: (size * 0.12).clamp(8.0, 16.0),
                color: color,
                backgroundColor: Colors.grey[200],
              ),
              Text(
                '$score',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      );
    }
    return content;
  }
}
