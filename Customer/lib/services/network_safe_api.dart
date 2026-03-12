/// Network-aware wrapper for critical operations.
///
/// Checks connectivity before operations, throws [NetworkUnavailableException]
/// when offline, and can trigger a recheck on socket/network errors.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:foodie_customer/utils/connection_tester.dart' show isConnected;

void _log(String message) {
  debugPrint('[CONNECTIVITY] $message');
}

/// Thrown when the device has no connectivity.
class NetworkUnavailableException implements Exception {
  NetworkUnavailableException([this.message]);
  final String? message;
  @override
  String toString() =>
      'NetworkUnavailableException: ${message ?? 'No network connection'}';
}

/// Network-aware API wrapper.
class NetworkSafeAPI {
  NetworkSafeAPI._();

  /// Callback registered via [init] to request connectivity recheck.
  static void Function()? onRecheckRequested;

  /// Initialize with optional callback. Call from main.dart initState:
  /// NetworkSafeAPI.init(onRecheck: _verifyConnectivity)
  static void init({void Function()? onRecheck}) {
    onRecheckRequested = onRecheck;
  }

  /// Runs [operation] with connectivity check. Throws [NetworkUnavailableException]
  /// if offline. On [SocketException] or [TimeoutException], calls
  /// [onRecheckRequested] and rethrows.
  static Future<T> runWithNetworkCheck<T>(
    Future<T> Function() operation, {
    void Function()? onOffline,
    void Function()? onSocketError,
  }) async {
    final connected = await isConnected();
    if (!connected) {
      _log('NetworkSafeAPI: offline, rejecting operation');
      onOffline?.call();
      throw NetworkUnavailableException(
        'No network. Please check your connection.',
      );
    }
    try {
      return await operation();
    } on SocketException catch (_) {
      _log('NetworkSafeAPI: SocketException, triggering recheck');
      onSocketError?.call();
      NetworkSafeAPI.onRecheckRequested?.call();
      rethrow;
    } on TimeoutException catch (_) {
      _log('NetworkSafeAPI: TimeoutException, triggering recheck');
      onSocketError?.call();
      NetworkSafeAPI.onRecheckRequested?.call();
      rethrow;
    } on OSError catch (e) {
      if (e.message.contains('Network is unreachable') ||
          e.message.contains('Connection refused')) {
        _log('NetworkSafeAPI: OSError (${e.message}), triggering recheck');
        onSocketError?.call();
        NetworkSafeAPI.onRecheckRequested?.call();
      }
      rethrow;
    }
  }
}
