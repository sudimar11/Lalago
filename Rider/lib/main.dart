import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/model/mail_setting.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/notification_service.dart'
    show NotificationService, firebaseMessageBackgroundHandle;
import 'package:foodie_driver/services/enhanced_notification_manager.dart';
import 'package:foodie_driver/services/session_service.dart';
import 'package:foodie_driver/services/timezone_service.dart';
import 'package:foodie_driver/services/time_tracking_service.dart';
import 'package:foodie_driver/services/driver_performance_service.dart';
import 'package:foodie_driver/services/attendance_service.dart';
import 'package:foodie_driver/services/order_service.dart';
import 'package:foodie_driver/ui/auth/AuthScreen.dart';
import 'package:foodie_driver/ui/container/ContainerScreen.dart';
import 'package:foodie_driver/ui/onBoarding/OnBoardingScreen.dart';
import 'package:foodie_driver/userPrefrence.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:foodie_driver/utils/shared_preferences_helper.dart';

import 'package:foodie_driver/resources/debug_log.dart';

import 'package:provider/provider.dart';
import 'package:foodie_driver/services/connectivity_service.dart';
import 'package:foodie_driver/services/offline_transaction_service.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';
import 'package:foodie_driver/services/background_sync_service.dart';
import 'package:foodie_driver/services/heat_zone_service.dart';

import 'model/User.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase first (doesn't depend on SharedPreferences)
    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(firebaseMessageBackgroundHandle);

    // Enable Firestore persistence
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    final offlineService = OfflineTransactionService();
    // All plugin init deferred to after first frame so engine/channels are ready.

    runApp(MyApp(offlineService: offlineService));
  }, (error, stack) {
    elog(error, stack, 'Zone');
  });
}

class MyApp extends StatefulWidget {
  final OfflineTransactionService offlineService;

  const MyApp({Key? key, required this.offlineService}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// this key is used to navigate to the appropriate screen when the
  /// notification is clicked from the system tray
  static User? currentUser;

  /// Bootstrap completes after first frame + plugin init (SharedPreferences,
  /// Hive, Notifications, Workmanager). OnBoarding awaits this before using
  /// any plugin so channels are ready in release.
  static final Completer<void> _bootstrapCompleter = Completer<void>();
  static Future<void> get bootstrapFuture => _bootstrapCompleter.future;

  NotificationService notificationService = NotificationService();
  EnhancedNotificationManager? enhancedNotificationManager;

  /// Perform automatic checkout when closing time passes
  static Future<void> performAutomaticCheckout() async {
    if (currentUser == null) return;

    // Don't checkout if already checked out today
    if (currentUser!.checkedOutToday == true) {
      print('✅ User already checked out today, skipping automatic checkout');
      return;
    }

    // Don't checkout if driver has active orders
    if (currentUser!.inProgressOrderID != null &&
        (currentUser!.inProgressOrderID as List).isNotEmpty) {
      print('⚠️ Driver has active orders, skipping automatic checkout');
      return;
    }

    // Don't checkout if not checked in today
    if (currentUser!.todayCheckInTime == null ||
        currentUser!.todayCheckInTime!.isEmpty) {
      print('⚠️ Driver not checked in today, skipping automatic checkout');
      return;
    }

    try {
      print('🔄 Performing automatic checkout due to closing time...');

      // Get current time
      final timeString = TimeTrackingService.getCurrentTimeString();

      // Calculate work duration
      final workDuration = TimeTrackingService.calculateTodayWorkDuration(
          currentUser!.todayCheckInTime!);

      // Update user object with check-out data
      currentUser!.checkedOutToday = true;
      currentUser!.todayCheckOutTime = timeString;
      currentUser!.isOnline = false;

      print(
          '📝 Updated user - checkedOutToday: ${currentUser!.checkedOutToday}, todayCheckOutTime: ${currentUser!.todayCheckOutTime}');

      // Apply performance adjustments for check-out
      if (currentUser!.todayCheckInTime != null &&
          currentUser!.todayCheckInTime!.isNotEmpty) {
        try {
          final newPerformance =
              await DriverPerformanceService.applyCheckOutAdjustments(
                      currentUser!.userID,
                      scheduledCheckInTime: currentUser!.checkInTime,
                      actualCheckInTime: currentUser!.todayCheckInTime!,
                      scheduledCheckOutTime: currentUser!.checkOutTime,
                      actualCheckOutTime: timeString)
                  .timeout(Duration(seconds: 10));
          currentUser!.driverPerformance = newPerformance;
          print(
              '📊 Performance updated to $newPerformance% after automatic checkout');
        } catch (e) {
          print('❌ Error updating performance during checkout: $e');
        }
      }

      // Save to Firebase
      try {
        await FireStoreUtils.updateCurrentUser(currentUser!)
            .timeout(Duration(seconds: 10));
        await OrderService.updateRiderStatus();
        print(
            '✅ Automatic checkout completed successfully at $timeString. Work duration: ${TimeTrackingService.formatDuration(workDuration)}');
      } catch (e) {
        print('❌ Error saving checkout to Firestore: $e');
      }
    } catch (e) {
      print('❌ Error during automatic checkout: $e');
    }
  }

  // Helper method to preserve check-in data during user updates
  // IMPORTANT: Only preserves SCHEDULED times (checkInTime, checkOutTime),
  // NOT today's actual check-in status. Today's status should come from backend.
  static void _preserveAndRestoreCheckInData(User freshUser) {
    if (MyAppState.currentUser != null) {
      // Only preserve SCHEDULED check-in/check-out times
      // Today's actual status (checkedInToday, todayCheckInTime, etc.)
      // should come from the backend, not local state
      String? preservedCheckInTime = MyAppState.currentUser!.checkInTime;
      String? preservedCheckOutTime = MyAppState.currentUser!.checkOutTime;

      print(
          '🔄 DEBUG: Preserving scheduled check-in times during user update:');
      print('📝 checkInTime: $preservedCheckInTime');
      print('📝 checkOutTime: $preservedCheckOutTime');
      print('ℹ️ Today\'s check-in status will come from backend');

      // Restore only scheduled times if they were lost during the fetch
      if (preservedCheckInTime != null && preservedCheckInTime.isNotEmpty) {
        freshUser.checkInTime = preservedCheckInTime;
        print('🔄 DEBUG: Restored checkInTime: $preservedCheckInTime');
      }
      if (preservedCheckOutTime != null && preservedCheckOutTime.isNotEmpty) {
        freshUser.checkOutTime = preservedCheckOutTime;
        print('🔄 DEBUG: Restored checkOutTime: $preservedCheckOutTime');
      }
      // NOTE: We intentionally do NOT restore today's status here
      // The backend data is the source of truth for today's check-in
    }
  }

  Future<void> _loadGlobalSettings() async {
    try {
      print('🌐 Trying to fetch global settings from Firestore...');
      final snapshot = await FirebaseFirestore.instance
          .collection(Setting)
          .doc("globalSettings")
          .get()
          .timeout(Duration(seconds: 10));

      if (!snapshot.exists) {
        print('⚠️ globalSettings document does not exist.');
        return;
      }

      if (snapshot.data() != null &&
          snapshot.data()!.containsKey("website_color")) {
        COLOR_PRIMARY = int.parse(
            snapshot.data()!["website_color"].replaceFirst("#", "0xff"));
        print(
            '✅ Global settings fetched successfully - Website color: ${snapshot.data()!["website_color"]}');
      } else {
        print('⚠️ No website_color found in global settings document.');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        print(
            '❌ Firestore unavailable – likely no internet or blocked Google services.');
      } else {
        print(
            '❌ FirebaseException while fetching global settings: ${e.code} – ${e.message}');
      }
    } on TimeoutException catch (e) {
      print('⏰ Timeout while fetching global settings: $e');
      print('⚠️ App may be offline or connection is slow');
    } catch (e) {
      print('❌ Unknown error fetching global settings: $e');
    }
  }

  Future<void> _loadGoogleMapsKey() async {
    try {
      print('🗺️ Trying to fetch Google Maps API key from Firestore...');
      final snapshot = await FirebaseFirestore.instance
          .collection(Setting)
          .doc("googleMapKey")
          .get()
          .timeout(Duration(seconds: 10));

      if (!snapshot.exists) {
        print('⚠️ googleMapKey document does not exist.');
        return;
      }

      if (snapshot.data() != null && snapshot.data()!.containsKey('key')) {
        GOOGLE_API_KEY = snapshot.data()!['key'].toString();
        print('✅ Google Maps API key fetched successfully');
      } else {
        print('⚠️ No "key" field found in googleMapKey document.');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        print(
            '❌ Firestore unavailable – likely no internet or blocked Google services.');
      } else {
        print(
            '❌ FirebaseException while fetching Google Maps key: ${e.code} – ${e.message}');
      }
    } on TimeoutException catch (e) {
      print('⏰ Timeout while fetching Google Maps key: $e');
      print('⚠️ App may be offline or connection is slow');
    } catch (e) {
      print('❌ Unknown error fetching Google Maps key: $e');
    }
  }

  Future<void> _loadEmailSettings() async {
    try {
      print('📧 Trying to fetch email settings from Firestore...');
      final snapshot = await FirebaseFirestore.instance
          .collection(Setting)
          .doc("emailSetting")
          .get()
          .timeout(Duration(seconds: 10));

      if (!snapshot.exists) {
        print('⚠️ emailSetting document does not exist.');
        return;
      }

      if (snapshot.data() != null) {
        mailSettings = MailSettings.fromJson(snapshot.data()!);
        print('✅ Email settings fetched successfully');
      } else {
        print('⚠️ emailSetting document exists but has no data.');
      }
    } on FirebaseException catch (e) {
      if (e.code == 'unavailable') {
        print(
            '❌ Firestore unavailable – likely no internet or blocked Google services.');
      } else {
        print(
            '❌ FirebaseException while fetching email settings: ${e.code} – ${e.message}');
      }
    } on TimeoutException catch (e) {
      print('⏰ Timeout while fetching email settings: $e');
      print('⚠️ App may be offline or connection is slow');
    } catch (e) {
      print('❌ Unknown error fetching email settings: $e');
    }
  }

  Future<void> initializeFlutterFire() async {
    try {
      print('🔧 Starting Firebase configuration initialization...');

      await _loadGlobalSettings();
      await _loadGoogleMapsKey();
      await _loadEmailSettings();

      // Initialize heat zones for Hotspots feature (non-blocking)
      HeatZoneService.initializeHeatZones();

      print('✅ Firebase configuration initialization completed');
    } catch (e, stackTrace) {
      print('❌ ERROR in initializeFlutterFire(): $e');
      print('📍 Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => ConnectivityService(),
        ),
        ChangeNotifierProvider<OfflineTransactionService>.value(
          value: widget.offlineService,
        ),
        ChangeNotifierProvider<RemittanceEnforcementService>(
          create: (_) => RemittanceEnforcementService(),
        ),
      ],
      child: MaterialApp(
          title: 'Flutter Uber Eats Driver',
          theme: ThemeData(
              useMaterial3: false,
              appBarTheme: AppBarTheme(
                centerTitle: true,
                color: Colors.transparent,
                elevation: 0,
                actionsIconTheme: IconThemeData(color: Color(COLOR_PRIMARY)),
                iconTheme: IconThemeData(color: Color(COLOR_PRIMARY)),
              ),
              bottomSheetTheme:
                  BottomSheetThemeData(backgroundColor: Colors.white),
              primaryColor: Color(COLOR_PRIMARY),
              textTheme: TextTheme(
                  titleLarge: TextStyle(
                      color: Colors.black,
                      fontSize: 17.0,
                      letterSpacing: 0,
                      fontWeight: FontWeight.w700)),
              brightness: Brightness.light),
          debugShowCheckedModeBanner: false,
          color: Color(COLOR_PRIMARY),
          home: OnBoarding()),
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Wait for first frame so Flutter engine has registered platform plugins.
        await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
        if (kReleaseMode) {
          await Future<void>.delayed(const Duration(milliseconds: 3000));
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (!mounted) return;

        await initializeFlutterFire();
        if (!mounted) return;

        // Complete bootstrap now so OnBoarding can proceed. Plugin init runs
        // in background - app continues even if SharedPreferences/Hive fail.
      } finally {
        if (!_bootstrapCompleter.isCompleted) {
          _bootstrapCompleter.complete();
        }
      }

      // Run plugin-dependent init in background (non-blocking).
      Future<void> _runPluginInit() async {
        const gap = Duration(milliseconds: 500);
        await Future<void>.delayed(gap);
        if (!mounted) return;
        await _initializePreferences();
        await Future<void>.delayed(gap);
        if (!mounted) return;
        await widget.offlineService.initialize();
        await Future<void>.delayed(gap);
        if (!mounted) return;
        await _initializeNotifications();
        await Future<void>.delayed(gap);
        if (!mounted) return;
        try {
          await BackgroundSyncService.initialize();
        } catch (_) {}
      }
      _runPluginInit();
    });
    print('🔧 Firebase configuration will run after first frame.');
    print('👁️ Adding lifecycle observer...');
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _initializeNotifications() async {
    try {
      print('🔔 Initializing notification service...');
      await notificationService.initInfo();

      // Request permission early so getToken() can succeed on iOS
      await notificationService.requestPermissionIfNeeded();

      // Initialize enhanced notification manager
      enhancedNotificationManager =
          EnhancedNotificationManager(notificationService);

      // Start listeners if user is already logged in. FCM token refresh
      // runs once in OnBoarding after currentUser is set to avoid duplicate
      // refresh on app start.
      if (auth.FirebaseAuth.instance.currentUser != null) {
        print('👤 User already logged in, starting notification listeners...');
        await enhancedNotificationManager!.initialize();
      }

      // Update Firestore whenever FCM token changes (e.g. reinstall, new device)
      FirebaseMessaging.instance.onTokenRefresh.listen((String newToken) {
        print('🔑 FCM token refreshed by Firebase');
        FireStoreUtils.saveFcmTokenForCurrentUser(newToken).then((ok) {
          if (ok) {
            print('✅ FCM token refresh saved to users/{riderId}.fcmToken');
          }
        });
      });

      print('✅ Notification system initialized');
    } catch (e) {
      print('❌ Error initializing notifications: $e');
    }
  }

  Future<void> _initializePreferences() async {
    try {
      print("💾 Initializing SharedPreferences AFTER first frame...");
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await UserPreference.init(prefs);
        print("✅ SharedPreferences fully initialized");
      } else {
        print(
            "⚠️ SharedPreferences unavailable - app will continue without it");
        print("ℹ️ Login state uses Firebase Auth persistence");
      }
    } catch (e) {
      print("⚠️ SharedPreferences initialization failed (non-critical): $e");
      print(
          "ℹ️ App will continue to function - login state uses Firebase Auth persistence");
      // Don't crash the app, but log the error
      // The app can function without SharedPreferences since we check Firebase Auth first
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    enhancedNotificationManager?.dispose();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (auth.FirebaseAuth.instance.currentUser != null && currentUser != null) {
      User? value;
      try {
        value =
            await FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID)
                .timeout(Duration(seconds: 10));
      } catch (e) {
        print('❌ Error fetching user in lifecycle: $e');
        return; // Exit early if we can't get user data
      }

      if (value != null) {
        // Preserve and restore check-in data
        MyAppState._preserveAndRestoreCheckInData(value);
        MyAppState.currentUser = value;
      }

      if (state == AppLifecycleState.paused) {
        if (MyAppState.currentUser != null) {
          MyAppState.currentUser!.lastOnlineTimestamp = Timestamp.now();
          try {
            await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!)
                .timeout(Duration(seconds: 10));
          } catch (e) {
            print('❌ Error updating user on pause: $e');
          }
        }
      } else if (state == AppLifecycleState.resumed) {
        bool hasPassedClosing = false;
        try {
          hasPassedClosing = await SessionService.hasPassedClosingTime()
              .timeout(Duration(seconds: 10));
        } catch (e) {
          print('❌ Error checking closing time on resume: $e');
        }

        if (hasPassedClosing) {
          print(
              '⏰ App resumed after closing time, performing automatic checkout...');
          try {
            await MyAppState.performAutomaticCheckout()
                .timeout(Duration(seconds: 15));
          } catch (e) {
            print('❌ Error during automatic checkout on resume: $e');
          }
        }

        if (MyAppState.currentUser != null) {
          MyAppState.currentUser!.lastOnlineTimestamp = Timestamp.now();
          try {
            await AttendanceService.touchLastActiveDate(
              MyAppState.currentUser!,
            );
          } catch (_) {}
          try {
            await FireStoreUtils.touchLastActivity(
              MyAppState.currentUser!.userID,
            );
          } catch (e) {
            print('Error updating activity on resume: $e');
          }
        }
      }
    }
  }
}

class OnBoarding extends StatefulWidget {
  @override
  State createState() {
    return OnBoardingState();
  }
}

class OnBoardingState extends State<OnBoarding> {
  bool _isChecking = false;
  SharedPreferences? prefs;

  Future hasFinishedOnBoarding() async {
    // Prevent multiple simultaneous checks
    if (_isChecking) {
      print('⚠️ Onboarding check already in progress, skipping...');
      return;
    }

    _isChecking = true;
    final stopwatch = Stopwatch()..start();
    try {
      print('🔍 Checking onboarding status...');
      print('⏱️ Timer started for onboarding check');

      // CRITICAL: Check Firebase Auth FIRST (doesn't need SharedPreferences)
      // Firebase Auth persists login state automatically
      print('🔐 Getting current Firebase user...');
      auth.User? firebaseUser = auth.FirebaseAuth.instance.currentUser;
      print('👤 Firebase user: ${firebaseUser?.uid ?? "null"}');

      // If user is logged in, skip SharedPreferences check and go straight to app
      if (firebaseUser != null) {
        print('✅ Firebase user found, checking user data...');
        print('🔄 Fetching user data from Firestore...');
        print('⏱️ Time elapsed so far: ${stopwatch.elapsedMilliseconds}ms');

        // Retry logic for Firestore user fetch (2 retries with 1s delay)
        User? user;
        int retryCount = 0;
        const maxRetries = 2;

        while (retryCount <= maxRetries) {
          try {
            user = await FireStoreUtils.getCurrentUser(firebaseUser.uid)
                .timeout(Duration(seconds: 15));
            if (user != null) {
              break; // Success
            }
          } catch (e) {
            if (retryCount < maxRetries) {
              print(
                  'Firestore user fetch failed → retry attempt ${retryCount + 1}/$maxRetries');
              await Future.delayed(Duration(seconds: 1));
              retryCount++;
            } else {
              print('Firestore user fetch failed after $maxRetries retries');
              user = null;
              break;
            }
          }
        }

        print('📊 User data received: ${user?.userID ?? "null"}');
        print('🎭 User role: ${user?.role ?? "null"}');
        print('🚗 Expected role: $USER_ROLE_DRIVER');

        // Only proceed with navigation if user was successfully fetched
        if (user != null) {
          // Check role only after successful fetch
          if (user.role == USER_ROLE_DRIVER) {
            print('✅ User is a valid driver');
            print('🟢 User active status: ${user.active}');

            // Check if closing_time has passed - perform checkout if passed
            // Add timeout to prevent hanging
            bool hasPassedClosing = false;
            try {
              hasPassedClosing =
                  await SessionService.hasPassedClosingTime().timeout(
                Duration(seconds: 10),
                onTimeout: () {
                  print('⏰ Timeout checking closing time');
                  return false;
                },
              );
            } catch (e) {
              print('❌ Error checking closing time: $e');
              hasPassedClosing = false;
            }

            if (hasPassedClosing) {
              print(
                  '⏰ Closing time has passed, performing automatic checkout...');

              // Preserve check-in data before modifying user object
              if (MyAppState.currentUser != null) {
                print(
                    '🔄 DEBUG: Preserving check-in data during closing time checkout...');
                MyAppState._preserveAndRestoreCheckInData(user);
              }

              MyAppState.currentUser = user;

              // Add timeout to checkout
              try {
                await MyAppState.performAutomaticCheckout()
                    .timeout(Duration(seconds: 15));
              } catch (e) {
                print('❌ Error during automatic checkout: $e');
              }

              // Refresh user data after checkout (with timeout)
              try {
                final updatedUser =
                    await FireStoreUtils.getCurrentUser(user.userID)
                        .timeout(Duration(seconds: 10));
                if (updatedUser != null) {
                  MyAppState.currentUser = updatedUser;
                  user = updatedUser;
                }
              } catch (e) {
                print('❌ Error refreshing user data after checkout: $e');
              }
            }

            // Allow navigation regardless of active status
            // user is guaranteed non-null here due to outer if (user != null) check
            if (user != null && !user.isReallyActive) {
              print(
                  'Inactive flag detected → NOT signing out, allowing navigation');
            }

            print('🚀 Setting up and navigating to main screen...');

            // Preserve check-in data before modifying user object
            // user is guaranteed non-null here due to outer if (user != null) check
            if (MyAppState.currentUser != null && user != null) {
              print('🔄 DEBUG: Preserving check-in data during onboarding...');
              MyAppState._preserveAndRestoreCheckInData(user);
            }

            // user is guaranteed non-null here due to outer if (user != null) check
            if (user != null) {
              // Reset check-in status when it's a new calendar day
              final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
              final lastActive = user.lastActiveDate ?? '';
              if (lastActive != today) {
                user.checkedInToday = false;
                user.checkedOutToday = false;
                user.todayCheckInTime = null;
                user.todayCheckOutTime = null;
                user.isOnline = false;
              }

              user.isActive = true;
              user.role = USER_ROLE_DRIVER;
              // Sync isOnline: if not checked in today, force isOnline false so
              // driver cannot receive orders until they check in
              if (user.checkedInToday != true && user.isOnline == true) {
                user.isOnline = false;
              }
              //user.fcmToken =
              //    await FireStoreUtils.firebaseMessaging.getToken() ?? '';

              print('💾 Updating user in Firestore...');

              // Add timeout to update
              try {
                await FireStoreUtils.updateCurrentUser(user)
                    .timeout(Duration(seconds: 10));
              } catch (e) {
                print('❌ Error updating user: $e');
              }

              try {
                await AttendanceService.evaluateAndUpdateAttendance(user);
                await AttendanceService.touchLastActiveDate(user);
              } catch (_) {}

              MyAppState.currentUser = user;

              try {
                await OrderService.updateRiderStatus();
              } catch (e) {
                print('❌ Error updating rider status on login: $e');
              }

              // Refresh FCM token on every app start when rider is already logged in
              print('🔑 Refreshing FCM token for rider on app start...');
              final tokenRefreshed =
                  await FireStoreUtils.refreshAndSaveFcmTokenIfLoggedIn();
              if (tokenRefreshed) {
                print('✅ FCM token refreshed and saved to users/{riderId}.fcmToken');
              } else {
                print(
                    '⚠️ FCM token refresh skipped or failed (iOS may retry with delay)');
              }

              unawaited(TimezoneService.updateUserTimezone());
            }

            // Start notification listeners after user is set
            // Access through the app state instance
            final appState = context.findAncestorStateOfType<MyAppState>();
            if (appState?.enhancedNotificationManager != null) {
              print('🔔 Starting notification listeners for logged-in user...');
              await appState!.enhancedNotificationManager!.restart();
            }

            print('🏠 Navigating to ContainerScreen...');
            print(
                '⏱️ Total onboarding check time: ${stopwatch.elapsedMilliseconds}ms');

            // Check if widget is still mounted before navigating
            if (mounted) {
              pushReplacement(context, ContainerScreen());
            } else {
              print('⚠️ Widget not mounted, cannot navigate');
            }
          } else {
            // Role mismatch - only after successful fetch
            print('Role mismatch confirmed → redirecting to AuthScreen');
            if (mounted) {
              pushReplacement(context, AuthScreen());
            } else {
              print('⚠️ Widget not mounted, cannot navigate');
            }
          }
        } else {
          // Firestore fetch failed after retries - stay in loading state, don't logout
          print(
              'Firestore user fetch failed after retries → staying in loading state');
          // Don't navigate, keep user in loading screen
          // Firebase Auth session remains intact
        }
        // Exit early - user was logged in, don't check SharedPreferences
        return;
      }

      // Only check SharedPreferences if no Firebase user is logged in
      print(
          '💾 No Firebase user found, checking SharedPreferences for onboarding status...');

      bool finishedOnBoarding = false;
      try {
        // Try to get SharedPreferences, but don't fail if it doesn't work
        finishedOnBoarding = (prefs?.getBool(FINISHED_ON_BOARDING) ?? false);
        print(
            '📋 Onboarding finished (from SharedPreferences): $finishedOnBoarding');
      } catch (e) {
        print('⚠️ Could not read SharedPreferences: $e');
        print(
            '📋 Assuming onboarding not finished (will show onboarding screen)');
        finishedOnBoarding = false;
      }

      if (!finishedOnBoarding) {
        print(
            '📚 User hasn\'t finished onboarding, navigating to OnBoardingScreen...');
        if (mounted) {
          pushReplacement(context, OnBoardingScreen());
        } else {
          print('⚠️ Widget not mounted, cannot navigate');
        }
      } else {
        // Onboarding was finished but no Firebase user - go to login
        print(
            '❌ Onboarding finished but no Firebase user, navigating to AuthScreen...');
        if (mounted) {
          pushReplacement(context, AuthScreen());
        } else {
          print('⚠️ Widget not mounted, cannot navigate');
        }
      }
    } catch (e, stackTrace) {
      stopwatch.stop();
      print('❌ ERROR in hasFinishedOnBoarding(): $e');
      print('📍 Stack trace: $stackTrace');
      print('⏱️ Time before error: ${stopwatch.elapsedMilliseconds}ms');
      // Don't logout on exception - attempt single retry
      print('Exception in onboarding check → attempting retry');

      // Reset checking flag to allow retry
      _isChecking = false;

      // Wait a moment before retry
      await Future.delayed(Duration(seconds: 1));

      // Attempt single retry
      try {
        await hasFinishedOnBoarding();
      } catch (retryError) {
        print('Exception retry failed → staying in loading state');
        // Stay in loading state, don't navigate or logout
        // Firebase Auth session remains intact
      }
    } finally {
      stopwatch.stop();
      _isChecking = false;
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Wait for plugin bootstrap (SharedPreferences, Hive, Notifications, Workmanager)
      // so platform channels are ready before we use SharedPreferences or navigate.
      try {
        await MyAppState.bootstrapFuture.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            print("⚠️ Bootstrap timeout (60s), proceeding with onboarding check");
          },
        );
      } catch (e) {
        print("⚠️ Bootstrap wait error: $e");
      }
      if (!mounted) return;

      // If user is already logged in, we don't need SharedPreferences.
      var firebaseUser = auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        print("✅ Firebase user found, skipping SharedPreferences wait");
        hasFinishedOnBoarding();
        return;
      }

      // No user yet: give Firebase Auth a short window to restore session.
      print("⏳ No Firebase user yet, waiting up to 2s for auth to restore...");
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      firebaseUser = auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        print("✅ Firebase user restored after wait, skipping SharedPrefs");
        hasFinishedOnBoarding();
        return;
      }

      // Still no Firebase user: we need SharedPreferences to know if
      // onboarding was finished. Bootstrap has already run so channel is ready.
      try {
        prefs = await SharedPreferencesHelper.getInstanceSafe()
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () {
                print("⚠️ SharedPreferences timeout, proceeding without it");
                return null;
              },
            );
        if (prefs == null) {
          print("⚠️ SharedPreferences unavailable, proceeding without it");
        }
        if (!mounted) return;
        hasFinishedOnBoarding();
      } catch (e) {
        print("❌ Failed to initialize SharedPreferences in OnBoarding: $e");
        if (!mounted) return;
        hasFinishedOnBoarding();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    print('🎨 OnBoarding build() method called - showing loading screen');
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator.adaptive(
              valueColor: AlwaysStoppedAnimation(
                Color(COLOR_PRIMARY),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Check console for debug info',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
