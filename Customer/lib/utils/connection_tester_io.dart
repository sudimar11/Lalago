// Mobile/desktop implementation: uses dart:io Socket for reachability
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';

void _log(String message) {
  final ts = DateTime.now().toIso8601String();
  debugPrint('[$ts] [CONNECTIVITY] $message');
}

Future<bool> _trySocket(String host, int port) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 4),
    );
    return true;
  } catch (e) {
    _log('ConnectionTester: socket $host:$port failed: $e');
    return false;
  } finally {
    final s = socket;
    if (s != null) s.destroy();
  }
}

Future<bool> isConnectedImpl() async {
  // 1. Quick: connectivity check
  final result = await Connectivity().checkConnectivity();
  if (result == ConnectivityResult.none) {
    _log('ConnectionTester: quick check failed (none)');
    return false;
  }
  _log('ConnectionTester: quick check passed');

  // 2. Medium: Socket to Google DNS and Cloudflare DNS
  if (await _trySocket('8.8.8.8', 53)) {
    _log('ConnectionTester: socket 8.8.8.8 passed');
    return true;
  }
  if (await _trySocket('1.1.1.1', 53)) {
    _log('ConnectionTester: socket 1.1.1.1 passed');
    return true;
  }

  // 3. Heavy: Firebase test
  try {
    // ignore: deprecated_member_use
    await auth.FirebaseAuth.instance
        .fetchSignInMethodsForEmail('test@connection-check.invalid')
        .timeout(const Duration(seconds: 5));
    _log('ConnectionTester: firebase check passed');
    return true;
  } catch (e) {
    _log('ConnectionTester: firebase check failed: $e');
  }

  _log('ConnectionTester: all checks failed');
  return false;
}
