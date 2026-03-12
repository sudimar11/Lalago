import 'package:flutter/foundation.dart';

/// Performance logging utility for debug/profile builds.
/// Measures operation duration, item counts, and payload sizes.
class PerformanceLogger {
  PerformanceLogger._();

  static final Map<String, Stopwatch> _timers = {};
  static int? _appStartMs;

  /// Call at app start or ContainerScreen init to compute time-to-X.
  static void markAppStart() {
    if (!kDebugMode) return;
    _appStartMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Elapsed ms since markAppStart, or null if not set.
  static int? get elapsedSinceAppStart =>
      _appStartMs == null ? null : DateTime.now().millisecondsSinceEpoch - _appStartMs!;

  /// Log a phase with duration and optional extra data. Guarded by kDebugMode.
  static void logPhase(String phase, int elapsedMs,
      {Map<String, dynamic>? extra}) {
    if (!kDebugMode) return;
    debugPrint('[PERF] $phase: ${elapsedMs}ms');
    if (extra != null && extra.isNotEmpty) {
      for (final e in extra.entries) {
        debugPrint('  ${e.key}: ${e.value}');
      }
    }
  }

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
      debugPrint('[PERF] $operation: ${timer.elapsedMilliseconds}ms');
      if (itemCount != null) debugPrint('  Items: $itemCount');
      if (payloadSize != null) debugPrint('  Size: ${payloadSize ~/ 1024}KB');
    }
  }

  /// Log scroll frame rate. Guarded by kDebugMode.
  static void logScrollFrameRate(double fps) {
    if (!kDebugMode) return;
    debugPrint('[PERF] scroll_fps: ${fps.toStringAsFixed(1)}');
  }

  /// Log memory usage. Use DevTools or profile build for actual RSS.
  /// Guarded by kDebugMode.
  static void logMemoryUsage() {
    if (!kDebugMode) return;
    debugPrint('[PERF] memory: use DevTools/Profile for RSS');
  }

  /// Run async function and log duration. Guarded by kDebugMode.
  static Future<T> trace<T>(
    String name,
    Future<T> Function() fn,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final result = await fn();
      if (kDebugMode) {
        sw.stop();
        debugPrint('[PERF] $name: ${sw.elapsedMilliseconds}ms');
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        sw.stop();
        debugPrint('[PERF] $name: ${sw.elapsedMilliseconds}ms (error: $e)');
      }
      rethrow;
    }
  }

  /// Show debug overlay. Set to true in debug to display FPS overlay.
  static bool showOverlay = false;
}
