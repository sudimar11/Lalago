import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:brgy/firebase_options.dart';
import 'package:brgy/pages/ash_notification_tester.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = await getFirebaseOptions();
  DefaultFirebaseOptions.setCurrentPlatform(options);
  await Firebase.initializeApp(options: options);
  runApp(MaterialApp(
    title: 'Ash Tester (Isolated)',
    debugShowCheckedModeBanner: false,
    home: const AshNotificationTesterPage(),
  ));
}
