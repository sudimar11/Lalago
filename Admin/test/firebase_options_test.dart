import 'dart:convert';
import 'dart:io';

import 'package:brgy/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

/// Asserts that getFirebaseOptions() returns options matching
/// android/app/google-services.json (read from disk).
void main() {
  late String projectId;
  late String projectNumber;
  late String apiKey;
  late String storageBucket;
  late String appId;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final packageRoot = Directory.current.path;
    final jsonPath = path.join(
      packageRoot,
      'android',
      'app',
      'google-services.json',
    );
    final jsonFile = File(jsonPath);
    if (!jsonFile.existsSync()) {
      throw Exception(
        'android/app/google-services.json not found at $jsonPath. '
        'Run tests from Admin package root.',
      );
    }
    final map = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
    final projectInfo = map['project_info'] as Map<String, dynamic>;
    final clients = map['client'] as List<dynamic>;
    const packageName = 'com.example.brgy';
    Map<String, dynamic>? found;
    for (final c in clients) {
      final info = c['client_info'] as Map<String, dynamic>?;
      final androidInfo = info?['android_client_info'] as Map<String, dynamic>?;
      if (androidInfo?['package_name'] == packageName) {
        found = c as Map<String, dynamic>;
        break;
      }
    }
    found ??= clients.isNotEmpty ? clients.first as Map<String, dynamic> : null;
    if (found == null) {
      throw Exception('No client for $packageName in google-services.json');
    }
    projectId = projectInfo['project_id'] as String;
    projectNumber = projectInfo['project_number'] as String;
    storageBucket = projectInfo['storage_bucket'] as String;
    final apiKeys = found['api_key'] as List<dynamic>;
    apiKey = apiKeys.isNotEmpty
        ? (apiKeys.first as Map<String, dynamic>)['current_key'] as String
        : '';
    appId = (found['client_info'] as Map<String, dynamic>)['mobilesdk_app_id']
        as String;
  });

  group('getFirebaseOptions', () {
    test('returns options matching current google-services.json', () async {
      final options = await getFirebaseOptions();
      expect(options.projectId, projectId);
      expect(options.messagingSenderId, projectNumber);
      expect(options.apiKey, apiKey);
      expect(options.storageBucket, storageBucket);
      expect(options.authDomain, '$projectId.firebaseapp.com');
      expect(options.appId, appId);
    });

    test('setCurrentPlatform then currentPlatform returns same options',
        () async {
      final options = await getFirebaseOptions();
      DefaultFirebaseOptions.setCurrentPlatform(options);
      expect(DefaultFirebaseOptions.currentPlatform.projectId, projectId);
      expect(DefaultFirebaseOptions.currentPlatform.appId, appId);
    });
  });
}
