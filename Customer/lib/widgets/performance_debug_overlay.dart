import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:foodie_customer/utils/performance_logger.dart';

/// Debug overlay showing FPS and basic performance metrics.
/// Only visible when PerformanceLogger.showOverlay is true and kDebugMode.
class PerformanceDebugOverlay extends StatefulWidget {
  final Widget child;

  const PerformanceDebugOverlay({
    super.key,
    required this.child,
  });

  @override
  State<PerformanceDebugOverlay> createState() => _PerformanceDebugOverlayState();
}

class _PerformanceDebugOverlayState extends State<PerformanceDebugOverlay> {
  double _fps = 0;
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      SchedulerBinding.instance.addTimingsCallback(_onFrameTiming);
    }
  }

  void _onFrameTiming(List<FrameTiming> timings) {
    if (!mounted) return;
    for (final timing in timings) {
      _frameCount++;
      final totalUs = timing.totalSpan.inMicroseconds;
      if (totalUs > 0) {
        final frameFps = 1e6 / totalUs;
        setState(() {
          _fps = _fps * 0.8 + frameFps * 0.2;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.child;

    return Stack(
      children: [
        widget.child,
        Builder(
          builder: (context) {
            if (!PerformanceLogger.showOverlay) return const SizedBox.shrink();
            return Positioned(
              top: 48,
              right: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'FPS: ${_fps.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        'Frames: $_frameCount',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
