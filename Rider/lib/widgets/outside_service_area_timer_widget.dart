import 'dart:async';

import 'package:flutter/material.dart';
import 'package:foodie_driver/services/helper.dart';

/// Shows elapsed time outside service area and countdown until penalty.
class OutsideServiceAreaTimerWidget extends StatefulWidget {
  final DateTime firstOutsideAt;
  final int penaltyThresholdMinutes;

  const OutsideServiceAreaTimerWidget({
    Key? key,
    required this.firstOutsideAt,
    this.penaltyThresholdMinutes = 30,
  }) : super(key: key);

  @override
  State<OutsideServiceAreaTimerWidget> createState() =>
      _OutsideServiceAreaTimerWidgetState();
}

class _OutsideServiceAreaTimerWidgetState
    extends State<OutsideServiceAreaTimerWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final elapsed = now.difference(widget.firstOutsideAt);
    final threshold =
        Duration(minutes: widget.penaltyThresholdMinutes);
    final remaining = threshold - elapsed;
    final showCountdown = !remaining.isNegative;

    final textColor =
        isDarkMode(context) ? Colors.white : Colors.black;
    const warnColor = Colors.orange;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 8,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: warnColor,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            'Outside ${_formatDuration(elapsed)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (showCountdown) ...[
            const SizedBox(width: 6),
            Text(
              '(${_formatDuration(remaining)} left)',
              style: const TextStyle(
                fontSize: 10,
                color: warnColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
