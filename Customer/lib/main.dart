// IMPORTANT:
// Do NOT add Riverpod, Provider, Bloc, or any new state management.
// This file is intentionally using StatefulWidget + setState.
// Only safe refactors (widget extraction, const, rebuild reduction) are allowed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/firebase_options.dart';
import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/mail_setting.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/userPrefrence.dart';
import 'package:foodie_customer/utils/DarkThemeProvider.dart';
import 'package:foodie_customer/utils/session_manager.dart';
import 'package:foodie_customer/utils/Styles.dart';
import 'package:foodie_customer/utils/notification_service.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'model/User.dart';

const String _debugLogPath =
    '/Users/sudimard/Documents/flutter_projects/LalaGo-Customer/.cursor/debug.log';
const String _debugFallbackFileName = 'cursor-debug.log';
const List<String> _debugLogEndpoints = <String>[
  'http://127.0.0.1:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://localhost:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
  'http://100.101.3.145:7242/ingest/9b9a1649-663c-43ba-aa17-deb0eb91410a',
];
const String _cursorDebugLogEndpoint =
    'http://127.0.0.1:7244/ingest/'
    'c9ab929b-94d3-40bd-8785-7deb40c047f7';
const String _cursorDebugLogEndpointEmulator =
    'http://10.0.2.2:7244/ingest/'
    'c9ab929b-94d3-40bd-8785-7deb40c047f7';

Future<void> _appendDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, Object?> data,
  String runId = 'pre-fix',
}) async {
  final payload = <String, Object?>{
    'sessionId': 'debug-session',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  try {
    await File(_debugLogPath).writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    );
  } catch (_) {
    for (final endpoint in _debugLogEndpoints) {
      try {
        final client = HttpClient();
        final request = await client.postUrl(Uri.parse(endpoint));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
        await request.close();
        client.close();
        break;
      } catch (_) {}
    }
  }
  try {
    final fallbackFile =
        File('${Directory.systemTemp.path}/$_debugFallbackFileName');
    await fallbackFile.writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    );
  } catch (_) {}
  try {
    final tempDir = await getTemporaryDirectory();
    final fallbackFile = File('${tempDir.path}/$_debugFallbackFileName');
    await fallbackFile.writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    );
  } catch (_) {}
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final fallbackFile = File('${docsDir.path}/$_debugFallbackFileName');
    await fallbackFile.writeAsString(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

Future<void> _appendCursorDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, Object?> data,
  String runId = 'pre-fix',
}) async {
  final payload = <String, Object?>{
    'sessionId': 'debug-session',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  final endpoints = Platform.isAndroid
      ? <String>[_cursorDebugLogEndpointEmulator, _cursorDebugLogEndpoint]
      : <String>[_cursorDebugLogEndpoint];
  for (final endpoint in endpoints) {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      await request.close();
      client.close();
      break;
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('💥 [CRASH] ErrorWidget caught: ${details.exception}');
    debugPrint('💥 [STACK] ${details.stack}');
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(
              'Error: ${details.exception}\n\n${details.stack}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  };
  // #region agent log
  unawaited(_appendDebugLog(
    hypothesisId: 'H0',
    location: 'main.dart:main',
    message: 'app startup reached',
    data: <String, Object?>{
      'platform': Platform.operatingSystem,
    },
  ));
  // #endregion
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') {
        rethrow;
      }
      Firebase.app();
    }
  }
  unawaited(() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final crashlytics = FirebaseCrashlytics.instance;
      crashlytics.setCustomKey('app_version', packageInfo.version);
      crashlytics.setCustomKey('app_build_number', packageInfo.buildNumber);
      crashlytics.setCustomKey('platform', Platform.operatingSystem);
      crashlytics.setCustomKey('is_debug', kDebugMode);
    } catch (_) {}
  }());
  if (kDebugMode && Platform.isAndroid) {
    // #region agent log
    unawaited(_appendCursorDebugLog(
      hypothesisId: 'H7',
      location: 'main.dart:authSettings:entry',
      message: 'attempting to disable app verification (debug)',
      data: <String, Object?>{
        'isDebug': kDebugMode,
        'platform': Platform.operatingSystem,
      },
    ));
    // #endregion
    try {
      await auth.FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: true,
      );
      // #region agent log
      unawaited(_appendCursorDebugLog(
        hypothesisId: 'H7',
        location: 'main.dart:authSettings:success',
        message: 'app verification disabled for testing',
        data: const <String, Object?>{
          'enabled': true,
        },
      ));
      // #endregion
    } catch (e) {
      // #region agent log
      unawaited(_appendCursorDebugLog(
        hypothesisId: 'H7',
        location: 'main.dart:authSettings:error',
        message: 'failed to disable app verification',
        data: <String, Object?>{
          'error': e.toString(),
        },
      ));
      // #endregion
    }
  }

  await UserPreference.init();

  await SessionManager.initialize();

  if (FireStoreUtils.isMessagingEnabled) {
    // Initialize notification service before app can receive FCM (ensures pop-up works)
    final notificationService = NotificationService.instance;
    await notificationService.initInfo();
    unawaited(FireStoreUtils.safeInitMessaging());

    // Store FCM token when available (also updates active orders' author.fcmToken)
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      debugPrint(
          '[FCM_DEBUG] onTokenRefresh fired currentUser='
          '${MyAppState.currentUser?.userID ?? "null"}');
      if (MyAppState.currentUser != null) {
        MyAppState.currentUser!.fcmToken = token;
        await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
        unawaited(FireStoreUtils.updateActiveOrdersFcmTokenForUser(
            MyAppState.currentUser!.userID, token));
        debugPrint(
            '[FCM_CONFIRM] FCM token saved to Firestore (onTokenRefresh): '
            'users/${MyAppState.currentUser!.userID}');
      }
    }).onError((e) {
      debugPrint('[FCM_DEBUG] onTokenRefresh failed $e');
    });

    // Get initial FCM token (non-blocking, safe on iOS)
    unawaited(() async {
      final token = await FireStoreUtils.safeGetFcmToken();
      final uid = MyAppState.currentUser?.userID;
      debugPrint(
          '[FCM_DEBUG] initial token fetch token=${token != null ? "ok" : "null"} '
          'currentUser=${uid ?? "null"}');
      if (token != null && MyAppState.currentUser != null) {
        MyAppState.currentUser!.fcmToken = token;
        await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
        unawaited(FireStoreUtils.updateActiveOrdersFcmTokenForUser(
            MyAppState.currentUser!.userID, token));
        debugPrint(
            '[FCM_CONFIRM] FCM token saved to Firestore (initial): users/$uid');
      } else if (token != null && uid == null) {
        debugPrint(
            '[FCM_DEBUG] token NOT saved (user not logged in yet)');
      }
    }());
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<CartDatabase>(
          create: (_) => CartDatabase(),
        )
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static User? currentUser;
  static AddressModel selectedPosition = AddressModel();
  static const _debugLogPath =
      '/Users/sudimard/Desktop/customer/.cursor/debug.log';

  void _appendRuntimeDebugLog({
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, dynamic> data,
  }) {
    final payload = <String, dynamic>{
      'sessionId': 'debug-session',
      'runId': 'pre-fix',
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      File(_debugLogPath).writeAsStringSync(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }

  // Connectivity state
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isOffline = false;

  /// Resolves the default address from a list of shipping addresses.
  /// Returns the address with isDefault == true, or falls back to the first address if no default is found.
  static AddressModel? resolveDefaultAddress(
      List<AddressModel>? shippingAddress) {
    if (shippingAddress == null || shippingAddress.isEmpty) return null;

    // Find address with isDefault == true
    try {
      return shippingAddress.firstWhere((addr) => addr.isDefault == true);
    } catch (e) {
      // Fallback to first address if no default found
      return shippingAddress.first;
    }
  }

  /// Updates MyAppState.selectedPosition with the resolved default address from currentUser's shippingAddress.
  /// This should be called after any address update operation.
  static void updateSelectedPositionFromDefault() {
    if (currentUser != null && currentUser!.shippingAddress != null) {
      final defaultAddr = resolveDefaultAddress(currentUser!.shippingAddress);
      if (defaultAddr != null) {
        selectedPosition = defaultAddr;
      }
    }
  }

  // Define an async function to initialize FlutterFire

  void initializeFlutterFire() async {
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

      final FlutterExceptionHandler? originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails errorDetails) async {
        await FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
        originalOnError!(errorDetails);
        // Forward to original handler.
      };
      await FirebaseFirestore.instance
          .collection(Setting)
          .doc("globalSettings")
          .get()
          .then((dineinresult) {
        if (dineinresult.exists &&
            dineinresult.data() != null &&
            dineinresult.data()!.containsKey("website_color")) {
          COLOR_PRIMARY = int.parse(
              dineinresult.data()!["website_color"].replaceFirst("#", "0xff"));
        }
      });

      await FirebaseFirestore.instance
          .collection(Setting)
          .doc("DineinForRestaurant")
          .get()
          .then((dineinresult) {
        if (dineinresult.exists) {
          isDineInEnable = dineinresult.data()!["isEnabledForCustomer"];
        }
      });

      await FirebaseFirestore.instance
          .collection(Setting)
          .doc("emailSetting")
          .get()
          .then((value) {
        if (value.exists) {
          mailSettings = MailSettings.fromJson(value.data()!);
        }
      });

      await FirebaseFirestore.instance
          .collection(Setting)
          .doc("home_page_theme")
          .get()
          .then((value) {
        if (value.exists) {
          homePageThem = value.data()!["theme"];
        }
      });

      await FirebaseFirestore.instance
          .collection(Setting)
          .doc("Version")
          .get()
          .then((value) {
        debugPrint(value.data().toString());
        appVersion = value.data()!['app_version'].toString();
      });

      await FirebaseFirestore.instance
          .collection(Setting)
          .doc("googleMapKey")
          .get()
          .then((value) {
        GOOGLE_API_KEY = value.data()!['key'].toString();
        isGoogleApiKeyFromFirestore = true;
        // #region agent log
        _appendRuntimeDebugLog(
          hypothesisId: 'H5',
          location: 'main:loadSettings:googleMapKey',
          message: 'Loaded Google Maps key from Firestore',
          data: {
            'isIOS': Platform.isIOS,
            'keyLength': GOOGLE_API_KEY.length,
            'fromFirestore': isGoogleApiKeyFromFirestore,
          },
        );
        // #endregion
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  DarkThemeProvider themeChangeProvider = DarkThemeProvider();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        return themeChangeProvider;
      },
      child: Consumer<DarkThemeProvider>(
        builder: (context, value, child) {
          return MaterialApp(
            navigatorKey: NotificationService.navigatorKey,
            debugShowCheckedModeBanner: false,
            theme: Styles.themeData(themeChangeProvider.darkTheme, context),
            home: ContainerScreen(),
            builder: (context, child) {
              return Stack(
                children: [
                  if (child != null) child,
                  if (_isOffline)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Container(
                          color: Colors.white,
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'assets/lost.png',
                                width: 100,
                                height: 100,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Connection Lost',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  void initState() {
    initializeFlutterFire();
    WidgetsBinding.instance.addObserver(this);
    // Listen for connectivity changes and toggle offline banner
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) {
      final bool offline = result == ConnectivityResult.none;
      if (mounted && offline != _isOffline) {
        setState(() {
          _isOffline = offline;
        });
      }
    });
    // Set initial connectivity state
    Connectivity().checkConnectivity().then((result) {
      final bool offline = result == ConnectivityResult.none;
      if (mounted && offline != _isOffline) {
        setState(() {
          _isOffline = offline;
        });
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}
}
