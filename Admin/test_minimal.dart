import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:brgy/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = await getFirebaseOptions();
  await Firebase.initializeApp(options: options);
  runApp(const MaterialApp(
    home: Scaffold(
      body: Center(child: Text('Firebase OK')),
    ),
  ));
}
