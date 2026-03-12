import 'dart:async';
import 'dart:developer' as dev;

/// Wraps a Future with a timeout. Throws [TimeoutException] if not completed in time.
Future<T> withTimeout<T>(
  Future<T> future, {
  Duration timeout = const Duration(seconds: 10),
}) {
  return future.timeout(timeout, onTimeout: () {
    dev.log('[TIMEOUT] Operation timed out after ${timeout.inSeconds}s');
    throw TimeoutException('Operation timed out');
  });
}
