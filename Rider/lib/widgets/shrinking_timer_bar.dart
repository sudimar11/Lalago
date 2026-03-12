import 'dart:async';

import 'package:flutter/material.dart';

/// Shows a shrinking progress bar for rider accept deadline countdown.
class ShrinkingTimerBar extends StatefulWidget {
  final int totalSeconds;
  final int initialRemainingSeconds;
  final String orderId;
  final VoidCallback? onTimeout;

  const ShrinkingTimerBar({
    Key? key,
    required this.totalSeconds,
    required this.initialRemainingSeconds,
    required this.orderId,
    this.onTimeout,
  }) : super(key: key);

  @override
  State<ShrinkingTimerBar> createState() => _ShrinkingTimerBarState();
}

class _ShrinkingTimerBarState extends State<ShrinkingTimerBar> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialRemainingSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining--;
        if (_remaining <= 0) {
          _timer?.cancel();
          widget.onTimeout?.call();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remaining <= 0 ? 0.0 : _remaining / widget.totalSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade300,
          valueColor: AlwaysStoppedAnimation<Color>(
            _remaining <= 10 ? Colors.red : Colors.orange,
          ),
          minHeight: 6,
        ),
        const SizedBox(height: 4),
        Text(
          '$_remaining s to accept',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
