import 'package:brgy/dashboard.dart';
import 'package:brgy/login.dart';
import 'package:brgy/model/User.dart';
import 'package:brgy/services/FirebaseHelper.dart';
import 'package:brgy/constants.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:brgy/services/sms_background_service.dart';
import 'package:brgy/services/sms_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final options = await getFirebaseOptions();
  DefaultFirebaseOptions.setCurrentPlatform(options);
  await Firebase.initializeApp(options: options);

  // Initialize SMS services only on non-web platforms
  if (!kIsWeb) {
    // Initialize SMS Background Service
    await SMSBackgroundService().initialize();

    // Initialize SMS Service permissions
    final smsService = SMSService();
    await smsService.initialize();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const brandYellow = Color(0xFFFFC107);
    const bgColor = Color(0xFFF6F7F9);
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);

    return MaterialApp(
      title: 'LalaGO',
      theme: ThemeData(
        primarySwatch: Colors.amber,
        primaryColor: brandYellow,
        colorScheme: const ColorScheme.light(
          primary: brandYellow,
          onPrimary: textPrimary,
          surface: Colors.white,
          onSurface: textPrimary,
        ),
        scaffoldBackgroundColor: bgColor,
        appBarTheme: AppBarTheme(
          backgroundColor: brandYellow,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: brandYellow,
            foregroundColor: textPrimary,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: brandYellow, width: 2),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: brandYellow,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 2,
        ),
      ),
      home: const AuthCheck(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyAppState {
  static User? currentUser;
}

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<auth.User?>(
      stream: auth.FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.connectionState == ConnectionState.none) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user == null) {
            return const LoginScreen();
          } else {
            // If we have a Firebase Auth user but no current user in MyAppState,
            // we need to fetch the user data from Firestore
            if (MyAppState.currentUser == null) {
              return FutureBuilder<User?>(
                future: FireStoreUtils.getCurrentUser(user.uid),
                builder: (context, userSnapshot) {
                  if (userSnapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (userSnapshot.hasData && userSnapshot.data != null) {
                    final firestoreUser = userSnapshot.data!;
                    // Allow customer or admin role for Admin app
                    final allowedRole = firestoreUser.role == USER_ROLE_CUSTOMER ||
                        firestoreUser.role == USER_ROLE_ADMIN;
                    if (firestoreUser.active && allowedRole) {
                      MyAppState.currentUser = firestoreUser;
                      return DashboardScreen();
                    } else {
                      // User is not active or doesn't have allowed role
                      auth.FirebaseAuth.instance.signOut();
                      return const LoginScreen();
                    }
                  } else {
                    // User not found in Firestore
                    auth.FirebaseAuth.instance.signOut();
                    return const LoginScreen();
                  }
                },
              );
            } else {
              return DashboardScreen();
            }
          }
        }

        return const Scaffold(
          body: Center(child: Text('Initializing...')),
        );
      },
    );
  }
}
