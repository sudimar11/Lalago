// Web implementation: no dart:io Socket; use connectivity + http
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

void _log(String message) {
  final ts = DateTime.now().toIso8601String();
  debugPrint('[$ts] [CONNECTIVITY] $message');
}

Future<bool> isConnectedImpl() async {
  // 1. Quick: connectivity check
  final result = await Connectivity().checkConnectivity();
  if (result == ConnectivityResult.none) {
    _log('ConnectionTester: quick check failed (none)');
    return false;
  }
  _log('ConnectionTester: quick check passed');

  // 2. Medium: http HEAD to reliable endpoint (web has no Socket)
  try {
    final response = await http
        .head(Uri.parse('https://www.gstatic.com/generate_204'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode >= 200 && response.statusCode < 400) {
      _log('ConnectionTester: http check passed');
      return true;
    }
  } catch (e) {
    _log('ConnectionTester: http check failed: $e');
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
