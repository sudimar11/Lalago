// ignore_for_file: avoid_print
/// Generates lib/firebase_options.dart from android/app/google-services.json.
/// Run from Admin package root: dart run tool/generate_firebase_options.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

const _packageName = 'com.example.brgy';
const _iosBundleId = 'com.lalago.admin';

void main() {
  final scriptDir = path.dirname(Platform.script.toFilePath());
  final packageRoot = path.dirname(scriptDir);
  final jsonPath = path.join(
    packageRoot,
    'android',
    'app',
    'google-services.json',
  );
  final jsonFile = File(jsonPath);
  if (!jsonFile.existsSync()) {
    print('Error: $jsonPath not found.');
    exit(1);
  }

  final map = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
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
    print('Error: no client for $_packageName in google-services.json');
    exit(1);
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

  final content = '''
// File generated from android/app/google-services.json.
// Run: dart run tool/generate_firebase_options.dart
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] from current google-services.json.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '$apiKey',
    authDomain: '$authDomain',
    projectId: '$projectId',
    storageBucket: '$storageBucket',
    messagingSenderId: '$projectNumber',
    appId: '$webAppId',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '$apiKey',
    authDomain: '$authDomain',
    projectId: '$projectId',
    storageBucket: '$storageBucket',
    messagingSenderId: '$projectNumber',
    appId: '$appId',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: '$apiKey',
    authDomain: '$authDomain',
    projectId: '$projectId',
    storageBucket: '$storageBucket',
    messagingSenderId: '$projectNumber',
    appId: '$appId',
    iosBundleId: '$_iosBundleId',
  );
}
''';

  final outPath = path.join(packageRoot, 'lib', 'firebase_options.dart');
  File(outPath).writeAsStringSync(content);
  print('Generated $outPath from $jsonPath');
}
