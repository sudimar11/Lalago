import 'dart:async';
import 'package:flutter/material.dart';
import 'package:foodie_restaurant/services/helper.dart';

/// Reusable countdown timer for order acceptance.
/// Color phases: Normal (2:00-3:00) blue/gray, Warning (1:30-2:00) orange,
/// Critical (0:00-1:30) red with blinking.
class OrderAcceptanceTimerWidget extends StatefulWidget {
  final int totalSeconds;
  final VoidCallback onTimeout;
  final void Function(int remainingSeconds)? onTick;
  final int? initialSeconds;

  const OrderAcceptanceTimerWidget({
    Key? key,
    this.totalSeconds = 180,
    required this.onTimeout,
    this.onTick,
    this.initialSeconds,
  }) : super(key: key);

  @override
  State<OrderAcceptanceTimerWidget> createState() =>
      _OrderAcceptanceTimerWidgetState();
}

class _OrderAcceptanceTimerWidgetState extends State<OrderAcceptanceTimerWidget>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  late int _remainingSeconds;
  bool _hasTimedOut = false;
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _remainingSeconds =
        widget.initialSeconds ?? widget.totalSeconds;
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds <= 0) {
          _timer?.cancel();
          if (!_hasTimedOut) {
            _hasTimedOut = true;
            widget.onTimeout();
          }
          return;
        }
        _remainingSeconds--;
        widget.onTick?.call(_remainingSeconds);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  String _formatRemaining() {
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color _getTimerColor() {
    if (_remainingSeconds <= 90) return Colors.red;
    if (_remainingSeconds <= 120) return Colors.orange;
    return isDarkMode(context) ? Colors.grey : Colors.blue.shade700;
  }

  bool get _isCritical => _remainingSeconds <= 90 && _remainingSeconds > 0;
  bool get _isWarning =>
      _remainingSeconds > 90 && _remainingSeconds <= 120;

  @override
  Widget build(BuildContext context) {
    final color = _getTimerColor();
    final isCritical = _isCritical;

    final timerContent = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isCritical
              ? Icons.error
              : (_isWarning ? Icons.warning : Icons.timer),
          color: color,
          size: 28,
        ),
        const SizedBox(width: 12),
        Text(
          _formatRemaining(),
          style: TextStyle(
            color: color,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          isCritical
              ? FadeTransition(
                  opacity: _blinkController,
                  child: timerContent,
                )
              : timerContent,
          const SizedBox(height: 4),
          Text(
            'Time remaining to accept',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
