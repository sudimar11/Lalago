// Minimal main to isolate _scriptUrls error.
// Run: flutter run -d chrome -t lib/main_minimal.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:brgy/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = await getFirebaseOptions();
  DefaultFirebaseOptions.setCurrentPlatform(options);
  await Firebase.initializeApp(options: options);

  // Bare MaterialApp - no theme, no auth, no dashboard
  runApp(MaterialApp(
    home: Scaffold(
      body: Center(child: Text('Test - no _scriptUrls expected')),
    ),
  ));
}
