import 'dart:async';
import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/model/mail_setting.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/services/notification_service.dart';
import 'package:foodie_restaurant/ui/auth/AuthScreen.dart';
import 'package:foodie_restaurant/ui/container/ContainerScreen.dart';
import 'package:foodie_restaurant/ui/onBoarding/OnBoardingScreen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase core
  await Firebase.initializeApp();

  // Activate App Check (using debug provider for now)
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
  );

  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final AudioPlayer audioPlayer = AudioPlayer(playerId: "playerId");
  static User? currentUser;
  /// When chain_admin: null = chain-wide, else vendorID of selected location.
  static String? selectedLocationId;
  final NotificationService notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationInit();
    _initializeFlutterFire(); // fire-and-forget config loading
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      await audioPlayer.dispose();
    }
  }

  /// Load Firestore-backed settings.
  Future<void> _initializeFlutterFire() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(Setting)
          .doc('globalSettings')
          .get();
      final data = snap.data();
      if (data != null && data.containsKey('website_color')) {
        COLOR_PRIMARY = int.parse(
          data['website_color'].toString().replaceFirst('#', '0xff'),
        );
        log('🔹 COLOR_PRIMARY set');
      }
    } catch (e) {
      log('❗ globalSettings load error: $e');
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection(Setting)
          .doc('DineinForRestaurant')
          .get();
      isDineInEnable = snap.data()?['isEnabled'] as bool? ?? false;
      log('🔹 isDineInEnable = $isDineInEnable');
    } catch (e) {
      log('❗ DineinForRestaurant load error: $e');
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection(Setting)
          .doc('googleMapKey')
          .get();
      final key = snap.data()?['key']?.toString();
      if (key != null) {
        GOOGLE_API_KEY = key;
        log('🔹 GOOGLE_API_KEY loaded');
      }
    } catch (e) {
      log('❗ googleMapKey load error: $e');
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection(Setting)
          .doc('emailSetting')
          .get();
      final data = snap.data();
      if (data != null) {
        mailSettings = MailSettings.fromJson(data);
        log('🔹 mailSettings initialized');
      }
    } catch (e) {
      log('❗ emailSetting load error: $e');
    }
  }

  /// Initialize local notifications (no FCM token handling).
  void _notificationInit() {
    notificationService.initInfo();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Restaurant Dashboard',
      theme: ThemeData(
        useMaterial3: false,
        primaryColor: Color(COLOR_PRIMARY),
        brightness: Brightness.light,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          color: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(COLOR_PRIMARY)),
          actionsIconTheme: IconThemeData(color: Color(COLOR_PRIMARY)),
        ),
        bottomSheetTheme: BottomSheetThemeData(backgroundColor: Colors.white),
      ),
      darkTheme: ThemeData(
        primaryColor: Color(COLOR_PRIMARY),
        brightness: Brightness.dark,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          color: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Color(COLOR_PRIMARY)),
          actionsIconTheme: IconThemeData(color: Color(COLOR_PRIMARY)),
        ),
        bottomSheetTheme:
            BottomSheetThemeData(backgroundColor: Colors.grey.shade900),
      ),
      debugShowCheckedModeBanner: false,
      builder: EasyLoading.init(),
      home: OnBoarding(),
    );
  }
}

class OnBoarding extends StatefulWidget {
  @override
  _OnBoardingState createState() => _OnBoardingState();
}

class _OnBoardingState extends State<OnBoarding> {
  @override
  void initState() {
    super.initState();
    _checkOnBoarding();
  }

  Future<void> _checkOnBoarding() async {
    final prefs = await SharedPreferences.getInstance();
    final finished = prefs.getBool(FINISHED_ON_BOARDING) ?? false;

    if (!finished) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => OnBoardingScreen()),
      );
      return;
    }

    final fbUser = auth.FirebaseAuth.instance.currentUser;
    if (fbUser == null) {
      _goTo(AuthScreen());
      return;
    }

    final user = await FireStoreUtils.getCurrentUser(fbUser.uid);
    if (user == null || user.role != USER_ROLE_VENDOR) {
      _goTo(AuthScreen());
      return;
    }

    if (user.active) {
      MyAppState.currentUser = user;
      _goTo(ContainerScreen(user: user));
    } else {
      await auth.FirebaseAuth.instance.signOut();
      await FacebookAuth.instance.logOut();
      MyAppState.currentUser = null;
      _goTo(AuthScreen());
    }
  }

  void _goTo(Widget screen) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
}
