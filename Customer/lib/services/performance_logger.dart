import 'package:flutter/foundation.dart';

/// Logs duration of cart-related operations in debug mode.
class PerformanceLogger {
  static const _thresholdMs = 100;

  static void logAddToCart(Duration duration) {
    if (kDebugMode && duration.inMilliseconds > _thresholdMs) {
      debugPrint('PERF addToCart: ${duration.inMilliseconds}ms');
    }
  }

  static void logUpdateQuantity(Duration duration) {
    if (kDebugMode && duration.inMilliseconds > _thresholdMs) {
      debugPrint('PERF updateQuantity: ${duration.inMilliseconds}ms');
    }
  }

  static void logRemoveFromCart(Duration duration) {
    if (kDebugMode && duration.inMilliseconds > _thresholdMs) {
      debugPrint('PERF removeFromCart: ${duration.inMilliseconds}ms');
    }
  }

  static void logCartSync(Duration duration) {
    if (kDebugMode && duration.inMilliseconds > _thresholdMs) {
      debugPrint('PERF cartSync: ${duration.inMilliseconds}ms');
    }
  }

  static void logDeliveryCalculation(Duration duration) {
    if (kDebugMode && duration.inMilliseconds > _thresholdMs) {
      debugPrint('PERF deliveryCalculation: ${duration.inMilliseconds}ms');
    }
  }
}
