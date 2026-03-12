// Loads options from android/app/google-services.json at runtime.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;

const _packageName = 'com.example.brgy';
const _iosBundleId = 'com.lalago.admin';
const _assetPath = 'android/app/google-services.json';

/// Loads [FirebaseOptions] from android/app/google-services.json for the
/// current platform. Call once at startup before [Firebase.initializeApp].
Future<FirebaseOptions> getFirebaseOptions() async {
  final jsonString = await rootBundle.loadString(_assetPath);
  final map = jsonDecode(jsonString) as Map<String, dynamic>;
  final projectInfo = map['project_info'] as Map<String, dynamic>;
  final clients = map['client'] as List<dynamic>;

  Map<String, dynamic>? client;
  for (final c in clients) {
    final info = c['client_info'] as Map<String, dynamic>?;
    final androidInfo = info?['android_client_info'] as Map<String, dynamic>?;
    if (androidInfo?['package_name'] == _packageName) {
      client = c as Map<String, dynamic>;
      break;
    }
  }
  client ??= clients.isNotEmpty ? clients.first as Map<String, dynamic> : null;
  if (client == null) {
    throw StateError(
      'No client for $_packageName in $_assetPath',
    );
  }

  final projectId = projectInfo['project_id'] as String;
  final projectNumber = projectInfo['project_number'] as String;
  final storageBucket = projectInfo['storage_bucket'] as String;
  final clientInfo = client!['client_info'] as Map<String, dynamic>;
  final appId = clientInfo['mobilesdk_app_id'] as String;
  final apiKeys = client['api_key'] as List<dynamic>;
  final apiKey = apiKeys.isNotEmpty
      ? (apiKeys.first as Map<String, dynamic>)['current_key'] as String
      : '';

  final authDomain = '$projectId.firebaseapp.com';
  final appIdSuffix = appId.contains(':') ? appId.split(':').last : appId;
  final webAppId = '1:$projectNumber:web:$appIdSuffix';

  if (kIsWeb) {
    return FirebaseOptions(
      apiKey: apiKey,
      authDomain: authDomain,
      projectId: projectId,
      storageBucket: storageBucket,
      messagingSenderId: projectNumber,
      appId: webAppId,
    );
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return FirebaseOptions(
        apiKey: apiKey,
        authDomain: authDomain,
        projectId: projectId,
        storageBucket: storageBucket,
        messagingSenderId: projectNumber,
        appId: appId,
      );
    case TargetPlatform.iOS:
      return FirebaseOptions(
        apiKey: apiKey,
        authDomain: authDomain,
        projectId: projectId,
        storageBucket: storageBucket,
        messagingSenderId: projectNumber,
        appId: appId,
        iosBundleId: _iosBundleId,
      );
    default:
      throw UnsupportedError(
        'Firebase options for $defaultTargetPlatform are not configured. '
        'Use android/app/google-services.json (Android project).',
      );
  }
}

/// Default [FirebaseOptions] for use with your Firebase apps.
/// Requires [getFirebaseOptions] to have been called first (e.g. in main).
class DefaultFirebaseOptions {
  static FirebaseOptions? _cached;

  /// Caches result of [getFirebaseOptions]. Call [getFirebaseOptions] once
  /// before using this.
  static FirebaseOptions get currentPlatform {
    if (_cached != null) return _cached!;
    throw StateError(
      'Firebase options not loaded. Call getFirebaseOptions() in main() first.',
    );
  }

  /// Called by main() to set options from [getFirebaseOptions].
  static void setCurrentPlatform(FirebaseOptions options) {
    _cached = options;
  }
}
