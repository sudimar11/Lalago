import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesHelper {
  // Static cache to prevent concurrent initialization attempts
  static Future<SharedPreferences?>? _initializationFuture;

  /// Safely get SharedPreferences instance with retry logic
  /// Returns null if unavailable after all retries (non-fatal).
  /// Multiple concurrent calls will share the same initialization attempt.
  static Future<SharedPreferences?> getInstanceSafe({
    int? maxRetries,
    Duration? initialDelay,
  }) async {
    // If already initializing, return the same future
    if (_initializationFuture != null) {
      return _initializationFuture;
    }

    // Start initialization and cache the future
    _initializationFuture = _doGetInstanceSafe(
      maxRetries: maxRetries,
      initialDelay: initialDelay,
    );

    try {
      return await _initializationFuture;
    } finally {
      // Clear cache after completion (success or failure)
      // This allows retry on next app start if needed
      _initializationFuture = null;
    }
  }

  static Future<SharedPreferences?> _doGetInstanceSafe({
    int? maxRetries,
    Duration? initialDelay,
  }) async {
    int retries = 0;

    // In release use more retries with longer spacing so channel can become ready
    final bool isReleaseMode = kReleaseMode;
    final int effectiveMaxRetries = maxRetries ?? (isReleaseMode ? 12 : 15);
    final Duration effectiveInitialDelay = initialDelay ??
        (isReleaseMode
            ? const Duration(milliseconds: 500)
            : const Duration(milliseconds: 200));

    // Wait in release so platform channel is ready (bootstrap already delayed 8s).
    final Duration initialWait = isReleaseMode
        ? const Duration(milliseconds: 1500)
        : const Duration(milliseconds: 300);
    await Future.delayed(initialWait);

    while (retries < effectiveMaxRetries) {
      try {
        // Exponential backoff; in release use longer delays between attempts
        if (retries > 0) {
          final double multiplier = isReleaseMode ? 2.0 : 1.0;
          final Duration delay = Duration(
              milliseconds: (effectiveInitialDelay.inMilliseconds *
                      (1 << (retries - 1).clamp(0, 4)) *
                      multiplier)
                  .round());
          await Future.delayed(delay);
        }

        final prefs = await SharedPreferences.getInstance();
        if (retries > 0) {
          print("✅ SharedPreferences obtained on retry attempt ${retries + 1}");
        }
        return prefs;
      } catch (e) {
        retries++;
        if (retries <= 5) {
          print("⚠️ SharedPreferences attempt $retries failed: $e");
        }

        if (retries >= effectiveMaxRetries) {
          print(
              "❌ SharedPreferences not available after $effectiveMaxRetries attempts; continuing without it");
          print(
              "⚠️ App will continue without SharedPreferences - some features may be limited");
          return null; // non-fatal
        }
      }
    }

    print("⚠️ SharedPreferences not available; continuing without it");
    return null;
  }
}
