import 'package:flutter/foundation.dart';

/// Lightweight debug logger. No-ops in release builds.
void dlog(String message) {
  if (kDebugMode) {
    // Use print for maximum compatibility with Flutter DevTools log view
    // and Android Studio/VSCode consoles.
    // Keep it simple and fast.
    // Prefix kept short to reduce noise.
    // ignore: avoid_print
    print(message);
  }
}

/// Convenience error logger for try/catch blocks.
void elog(Object error, [StackTrace? stackTrace, String prefix = '']) {
  if (kDebugMode) {
    final p = prefix.isNotEmpty ? '$prefix ' : '';
    // ignore: avoid_print
    print('${p}ERROR: $error');
    if (stackTrace != null) {
      // ignore: avoid_print
      print(stackTrace);
    }
  }
}
