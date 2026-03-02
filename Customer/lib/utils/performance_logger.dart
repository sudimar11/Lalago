import 'package:flutter/foundation.dart';

/// Performance logging utility for debug/profile builds.
/// Measures operation duration, item counts, and payload sizes.
class PerformanceLogger {
  PerformanceLogger._();

  static final Map<String, Stopwatch> _timers = {};

  /// Start timing an operation.
  static void start(String operation) {
    if (!kDebugMode) return;
    _timers[operation] = Stopwatch()..start();
  }

  /// End timing and optionally log item count and payload size.
  static void end(String operation, {int? itemCount, int? payloadSize}) {
    if (!kDebugMode) return;
    final timer = _timers.remove(operation);
    if (timer != null) {
      timer.stop();
      debugPrint('$operation: ${timer.elapsedMilliseconds}ms');
      if (itemCount != null) debugPrint('  Items: $itemCount');
      if (payloadSize != null) debugPrint('  Size: ${payloadSize ~/ 1024}KB');
    }
  }
}
