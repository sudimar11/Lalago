import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/AddressModel.dart';
import 'package:foodie_customer/model/CurrencyModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/timezone_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/services/version_service.dart';
import 'package:foodie_customer/services/cart_state_notifier.dart';
import 'package:foodie_customer/services/cart_sync_service.dart';
import 'package:foodie_customer/services/device_capability.dart';
import 'package:foodie_customer/services/image_cache_config.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:foodie_customer/services/chat_read_service.dart';
import 'package:foodie_customer/services/app_configuration_service.dart';
import 'package:foodie_customer/utils/performance_logger.dart';
import 'package:foodie_customer/widgets/performance_debug_overlay.dart';

import 'package:foodie_customer/ui/chat_screen/inbox_driver_screen.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/signUp/SignUpScreen.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/ui/home/HomeScreen.dart';
import 'package:foodie_customer/ui/onBoarding/OnBoardingScreen.dart';

import 'package:foodie_customer/ui/profile/ProfileScreen.dart';
import 'package:foodie_customer/ui/searchScreen/SearchScreen.dart';
import 'package:foodie_customer/screens/ai_chat_screen.dart';
import 'package:foodie_customer/widgets/ash_avatar.dart';

import 'package:foodie_customer/utils/DarkThemeProvider.dart';
import 'package:foodie_customer/utils/notification_service.dart';
import 'package:foodie_customer/services/analytics_service.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:provider/provider.dart';

enum BottomNavSelection { Home, Search, Cart, Profile }

class ContainerScreen extends StatefulWidget {
  final User? user;

  final Widget? currentWidget;

  final String? appBarTitle;

  const ContainerScreen(
      {super.key, this.user, this.currentWidget, this.appBarTitle});

  @override
  _ContainerScreen createState() {
    return _ContainerScreen();
  }
}

class _ContainerScreen extends State<ContainerScreen>
    with WidgetsBindingObserver {
  late CartDatabase cartDatabase;

  User? user;

  final fireStoreUtils = FireStoreUtils();
  final GlobalKey<SearchScreenState> _searchScreenKey =
      GlobalKey<SearchScreenState>();

  // Persistent tab screen widgets (initialized once)
  Widget? _homeScreen;
  Widget? _searchScreen;
  Widget? _cartScreen;
  Widget? _profileScreen;

  BottomNavSelection _currentBottomNav = BottomNavSelection.Home;

  int cartCount = 0;

  bool? isWalletEnable;

  bool _isInitializing = true;
  String? _initializationError;

  int _loadingMessageIndex = 0;
  int _pulseKey = 0;
  Timer? _loadingMessageTimer;
  Timer? _loadingPulseTimer;

  static const List<String> _loadingMessages = [
    'Setting up your experience...',
    'Finding restaurants near you...',
    'Almost ready...',
    'Getting your favorites ready...',
  ];
  static const List<String> _loadingTips = [
    'Discover new restaurants nearby',
    'Order from your favorite spots in minutes',
    'Earn rewards with every order',
  ];

  void _cycleLoadingMessage(Timer _) {
    if (mounted && _isInitializing) {
      setState(() {
        _loadingMessageIndex =
            (_loadingMessageIndex + 1) % _loadingMessages.length;
      });
    }
  }

  void _cyclePulse(Timer _) {
    if (mounted && _isInitializing) {
      setState(() => _pulseKey++);
    }
  }

  void _cancelLoadingTimers() {
    _loadingMessageTimer?.cancel();
    _loadingMessageTimer = null;
    _loadingPulseTimer?.cancel();
    _loadingPulseTimer = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PerformanceLogger.markAppStart();
    ImageCacheConfig.ensureInitialized();

    if (widget.user != null) {
      user = widget.user!;
      _isInitializing = false;
      _initializeAfterUserSet();
    } else {
      _performInitialization();
      _loadingMessageTimer =
          Timer.periodic(const Duration(milliseconds: 2500), _cycleLoadingMessage);
      _loadingPulseTimer =
          Timer.periodic(const Duration(milliseconds: 1500), _cyclePulse);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelLoadingTimers();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final userId = user?.userID ?? MyAppState.currentUser?.userID;
    if (userId != null && userId.isNotEmpty) {
      if (state == AppLifecycleState.resumed) {
        AnalyticsService.trackUserEngagement(userId, 'app_open');
      } else if (state == AppLifecycleState.paused) {
        AnalyticsService.trackUserEngagement(userId, 'app_background');
      }
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _maybeClearImageCacheOnBackground();
    }
  }

  void _maybeClearImageCacheOnBackground() async {
    try {
      final lowEnd = await DeviceCapability.isLowEndDevice();
      if (lowEnd) {
        await DefaultCacheManager().emptyCache();
      }
    } catch (_) {}
  }

  Future<void> _performInitialization() async {
    try {
      setState(() {
        _isInitializing = true;
        _initializationError = null;
      });

      // 1) Check onboarding completion
      final prefs = await SharedPreferences.getInstance();
      final finishedOnBoarding = prefs.getBool(FINISHED_ON_BOARDING) ?? false;

      if (!finishedOnBoarding) {
        await prefs.setBool(FINISHED_ON_BOARDING, true);
        if (mounted) {
          pushReplacement(context, OnBoardingScreen());
        }
        return;
      }

      // 2) Wait for Firebase Auth to restore session from local storage
      debugPrint('[AUTH_INIT] Waiting for Firebase Auth session restoration...');
      auth.User? fbUser;
      try {
        fbUser = await auth.FirebaseAuth.instance.authStateChanges().first
            .timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint(
                '[AUTH_INIT] Auth restoration timeout, using currentUser');
            return auth.FirebaseAuth.instance.currentUser;
          },
        );
      } catch (e) {
        debugPrint('[AUTH_INIT] Error during auth restoration: $e');
        fbUser = auth.FirebaseAuth.instance.currentUser;
      }
      debugPrint(
          '[AUTH_INIT] Auth restoration complete. User: ${fbUser?.uid ?? "null"}');

      if (fbUser == null) {
        MyAppState.currentUser = null;
        user = null;
        final loc = MyAppState.selectedPosition.location;
        final hasValidGuestLocation = loc != null &&
            !(loc.latitude == 0 && loc.longitude == 0);
        if (!hasValidGuestLocation) {
          debugPrint(
              '[AUTH_INIT] Guest mode, setting default Jolo, Sulu location');
          MyAppState.selectedPosition = AddressModel.defaultJoloLocation();
        }
        debugPrint('[AUTH_INIT] Guest mode with valid location');
        await _initializeAfterUserSet();
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }
        return;
      }
      debugPrint('[AUTH_INIT] Proceeding with uid=${fbUser.uid}');

      // 3) Fetch Firestore user record
      final fetchedUser = await FireStoreUtils.getCurrentUser(fbUser.uid);
      if (fetchedUser == null || fetchedUser.role != USER_ROLE_CUSTOMER) {
        await CartSyncService.onLogout();
        await auth.FirebaseAuth.instance.signOut();
        MyAppState.currentUser = null;
        user = null;
        if (mounted) {
          setState(() {
            _cancelLoadingTimers();
            _isInitializing = false;
          });
          pushReplacement(context, LoginScreen(isInitialScreen: true));
        }
        return;
      }

      // 4) Handle inactive customer - auto-reactivate
      fetchedUser.active = true;
      fetchedUser.lastOnlineTimestamp = Timestamp.now();
      await FireStoreUtils.updateCurrentUser(fetchedUser);
      MyAppState.currentUser = fetchedUser;
      user = fetchedUser;

      unawaited(TimezoneService.updateUserTimezone());

      // 5) Check for app updates
      if (mounted) {
        Future.delayed(Duration(seconds: 1), () {
          if (mounted) {
            VersionService.checkForUpdate(context);
          }
        });
      }

      // 6) Validate shipping address
      final addrs = fetchedUser.shippingAddress;
      if (mounted) {
        if (addrs != null && addrs.isNotEmpty) {
          final defaultAddr = addrs.firstWhere(
            (a) => a.isDefault == true,
            orElse: () => addrs.first,
          );
          MyAppState.selectedPosition = defaultAddr;
        } else {
          debugPrint(
              '[AUTH_INIT] User has no shipping address; using default Jolo');
          MyAppState.selectedPosition = AddressModel.defaultJoloLocation();
        }
      }

      // 7) Initialize currency and other settings
      await _initializeAfterUserSet();

      // 8) Mark initialization as complete
      if (mounted) {
        setState(() {
          _cancelLoadingTimers();
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        setState(() {
          _cancelLoadingTimers();
          _isInitializing = false;
          _initializationError = e.toString();
        });
      }
    }
  }

  Future<void> _initializeAfterUserSet() async {
    if (FireStoreUtils.isMessagingEnabled && MyAppState.currentUser != null) {
      unawaited(FireStoreUtils.refreshFcmTokenForUser(MyAppState.currentUser!));
      Future.delayed(const Duration(seconds: 3), () {
        if (MyAppState.currentUser != null) {
          FireStoreUtils.refreshFcmTokenForUser(MyAppState.currentUser!);
        }
      });
      Future.delayed(const Duration(seconds: 8), () {
        if (MyAppState.currentUser != null) {
          FireStoreUtils.refreshFcmTokenForUser(MyAppState.currentUser!);
        }
      });
    }
    // Load placeholder image (fire-and-forget)
    FireStoreUtils.getplaceholderimage().then((value) {
      AppGlobal.placeHolderImage = value;
    });

    // Start cart sync for logged-in users
    if (MyAppState.currentUser != null && mounted) {
      try {
        final cartDb = Provider.of<CartDatabase>(context, listen: false);
        CartSyncService.startCartSync(cartDb);
      } catch (_) {}
    }

    // Build main scaffold immediately; defer currency/settings to background
    if (mounted) {
      setState(() {
        _homeScreen = widget.currentWidget is HomeScreen
            ? widget.currentWidget
            : HomeScreen(user: MyAppState.currentUser);
        _searchScreen = SearchScreen(
          key: _searchScreenKey,
          shouldAutoFocus: widget.currentWidget is SearchScreen,
          onBackPressed: () => _onBottomNavTapped(BottomNavSelection.Home),
        );
        _cartScreen = widget.currentWidget is CartScreen
            ? widget.currentWidget
            : CartScreen(fromContainer: true);
        _profileScreen = widget.currentWidget is ProfileScreen
            ? widget.currentWidget
            : MyAppState.currentUser != null
                ? ProfileScreen(user: MyAppState.currentUser!)
                : null; // Will show guest placeholder

        // Set initial bottom nav selection based on currentWidget
        if (widget.currentWidget is CartScreen) {
          _currentBottomNav = BottomNavSelection.Cart;
        } else if (widget.currentWidget is SearchScreen) {
          _currentBottomNav = BottomNavSelection.Search;
        } else if (widget.currentWidget is ProfileScreen) {
          _currentBottomNav = BottomNavSelection.Profile;
        } else {
          _currentBottomNav = BottomNavSelection.Home;
        }
      });
      if (FireStoreUtils.isMessagingEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            NotificationService.showEnableNotificationsDialogIfNeeded(context);
          }
        });
      }
      // Defer non-critical config so main UI appears first
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAppConfigurationInBackground();
      });
      // Log time to first paint once main scaffold is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final elapsed = PerformanceLogger.elapsedSinceAppStart;
          if (elapsed != null) {
            PerformanceLogger.logPhase('time_to_first_paint', elapsed);
          }
        }
      });
    }
  }

  /// Loads theme, currency, tax, payment config in background; updates UI when done.
  Future<void> _loadAppConfigurationInBackground() async {
    try {
      await AppConfigurationService.loadAsync();
    } catch (e) {
      debugPrint('[ContainerScreen] App config load error: $e');
    }
    if (mounted) {
      setState(() {
        // Refresh bottom nav selection from currentWidget when config is ready
        if (widget.currentWidget is CartScreen) {
          _currentBottomNav = BottomNavSelection.Cart;
        } else if (widget.currentWidget is SearchScreen) {
          _currentBottomNav = BottomNavSelection.Search;
        } else if (widget.currentWidget is ProfileScreen) {
          _currentBottomNav = BottomNavSelection.Profile;
        } else {
          _currentBottomNav = BottomNavSelection.Home;
        }
      });
    }
  }

  Future<void> _testGemini() async {
    try {
      final model = FirebaseAI.googleAI().generativeModel(
        model: 'gemini-2.5-flash-lite',
      );
      final response = await model.generateContent([
        Content.text('Say hello in one word'),
      ]);
      debugPrint('Gemini says: ${response.text}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Response: ${response.text}')),
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onBottomNavTapped(BottomNavSelection selection) {
    setState(() {
      _currentBottomNav = selection;
      if (selection == BottomNavSelection.Search) {
        _searchScreen = SearchScreen(
          key: _searchScreenKey,
          shouldAutoFocus: true,
          onBackPressed: () => _onBottomNavTapped(BottomNavSelection.Home),
        );
      } else if (_searchScreen != null) {
        _searchScreen = SearchScreen(
          key: _searchScreenKey,
          shouldAutoFocus: false,
          onBackPressed: () => _onBottomNavTapped(BottomNavSelection.Home),
        );
      }
    });
  }

  setCurrency() async {
    await FirebaseFirestore.instance
        .collection(Setting)
        .doc("home_page_theme")
        .get()
        .then((value) {
      if (mounted) {
        setState(() {
          // Use default if doc doesn't exist or field is missing
          homePageThem = value.data()?["theme"] ?? "theme_1";

          // Set the appropriate bottom nav selection based on currentWidget
          if (widget.currentWidget is CartScreen) {
            _currentBottomNav = BottomNavSelection.Cart;
          } else if (widget.currentWidget is SearchScreen) {
            _currentBottomNav = BottomNavSelection.Search;
          } else if (widget.currentWidget is ProfileScreen) {
            _currentBottomNav = BottomNavSelection.Profile;
          } else {
            _currentBottomNav = BottomNavSelection.Home;
          }
        });
      }
    });

    await FireStoreUtils().getCurrency().then((value) {
      if (value != null) {
        currencyModel = value;
      } else {
        currencyModel = CurrencyModel(
            id: "",
            code: "USD",
            decimal: 2,
            isactive: true,
            name: "US Dollar",
            symbol: "\$",
            symbolatright: false);
      }
    });

    // Only get country if location is available
    if (MyAppState.selectedPosition.location != null) {
      try {
        List<Placemark> placeMarks = await placemarkFromCoordinates(
            MyAppState.selectedPosition.location!.latitude,
            MyAppState.selectedPosition.location!.longitude);

        if (placeMarks.isNotEmpty) {
          country = placeMarks.first.country;
        }
      } catch (e) {
        debugPrint('Error getting country from coordinates: $e');
      }
    }

    await FireStoreUtils().getTaxList().then((value) {
      if (value != null) {
        taxList = value;
      }
    });

    await FireStoreUtils.getPaypalSettingData();

    //await FireStoreUtils.getFlutterWaveSettingData();

    await FireStoreUtils.getPaytmSettingData();

    await FireStoreUtils.getWalletSettingData();

    await FireStoreUtils.getReferralAmount();
  }

// returns true if we have any network
  Future<bool> hasNetwork() async {
    final status = await Connectivity().checkConnectivity();
    return status != ConnectivityResult.none;
  }

// wrapper you call instead of directly calling Firestore
  void performWrite(Future<void> Function() firestoreOp) async {
    if (!await hasNetwork()) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("No Internet"),
          content: Text("Please turn on Wi-Fi or mobile data to continue."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK"),
            ),
          ],
        ),
      );
      return;
    }
    // if we're online, actually do the Firestore operation
    await firestoreOp();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    cartDatabase = Provider.of<CartDatabase>(context);
  }

  DateTime preBackpress = DateTime.now();

  Widget _buildLoadingIndicator() {
    final currentMessage =
        _loadingMessages[_loadingMessageIndex % _loadingMessages.length];
    final currentTip =
        _loadingTips[_loadingMessageIndex % _loadingTips.length];
    final pulseBegin = _pulseKey.isEven ? 0.95 : 1.05;
    final pulseEnd = _pulseKey.isEven ? 1.05 : 0.95;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                    strokeWidth: 3,
                    backgroundColor: Colors.grey[200],
                  ),
                ),
                TweenAnimationBuilder<double>(
                  key: ValueKey(_pulseKey),
                  tween: Tween(begin: pulseBegin, end: pulseEnd),
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.easeInOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/app_logo.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Text(
              currentMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontFamily: 'Poppinsm',
                color: Color(COLOR_PRIMARY),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This usually takes just a few seconds',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                currentTip,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageFloatingButton() {
    final userId = MyAppState.currentUser?.userID ?? '';
    return FloatingActionButton(
      onPressed: () {
        if (MyAppState.currentUser != null) {
          push(context, const InboxDriverScreen());
        } else {
          push(context, LoginScreen());
        }
      },
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: StreamBuilder<int>(
        stream: ChatReadService.getTotalUnreadCountStream(userId),
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          return Semantics(
            button: true,
            label:
                'Messages, ${count > 0 ? '$count unread' : 'no unread messages'}',
            child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.orange.shade400,
                          Colors.orange.shade600,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
                      size: 29,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              SizedBox(height: 16),
              Text(
                'Initialization Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              SizedBox(height: 8),
              Text(
                _initializationError ?? 'Unknown error occurred',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  _performInitialization();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<DarkThemeProvider>(context);

    // Show loading indicator during initialization
    if (_isInitializing) {
      return _buildLoadingIndicator();
    }

    // Show error state if initialization failed
    if (_initializationError != null) {
      return _buildErrorState();
    }

    // Show main UI (allow guest mode with null user)
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_currentBottomNav != BottomNavSelection.Home) {
          setState(() {
            _currentBottomNav = BottomNavSelection.Home;
          });
        } else {
          final timeGap = DateTime.now().difference(preBackpress);
          final canExit = timeGap < const Duration(seconds: 2);

          preBackpress = DateTime.now();

          if (canExit) {
            SystemNavigator.pop();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Press Back button again to Exit',
                  style: const TextStyle(color: Colors.white),
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.black,
              ),
            );
          }
        }
      },
      child: user != null
          ? ChangeNotifierProvider.value(
              value: user!,
              child: Consumer<User>(
                builder: (context, user, _) {
                  return _buildMainScaffold(context);
                },
              ),
            )
          : _buildMainScaffold(context),
    );
  }

  Widget _buildMainScaffold(BuildContext context) {
    return Scaffold(
        body: PerformanceDebugOverlay(
          child: Column(
          children: [
            // Guest mode banner - only show on Home screen
            if (MyAppState.currentUser == null && _currentBottomNav == BottomNavSelection.Home)
              Container(
                color: Colors.amber[100],
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Browsing as guest. Login to place orders.'),
                    ),
                    TextButton(
                      onPressed: () => push(context, LoginScreen()),
                      child: Text('Login'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(
                index: _currentBottomNav.index,
                children: [
                  _homeScreen ?? const SizedBox.shrink(),
                  _searchScreen ?? const SizedBox.shrink(),
                  _cartScreen ?? const SizedBox.shrink(),
                  _profileScreen ?? _buildGuestProfilePlaceholder(),
                ],
              ),
            ),
          ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
                  currentIndex: _currentBottomNav.index,
                  onTap: (index) =>
                      _onBottomNavTapped(BottomNavSelection.values[index]),
                  type: BottomNavigationBarType.fixed,
                  backgroundColor:
                      isDarkMode(context) ? Color(DARK_COLOR) : Colors.white,
                  selectedItemColor: Color(COLOR_PRIMARY),
                  unselectedItemColor: Colors.black,
                  items: [
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.home),
                      label: 'Home',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.search),
                      label: 'Search',
                    ),
                    BottomNavigationBarItem(
                      icon: Selector<CartStateNotifier, int>(
                        selector: (_, notifier) => notifier.itemCount,
                        builder: (context, totalQuantity, _) {
                          return Stack(
                            children: [
                              Icon(CupertinoIcons.cart),
                              if (totalQuantity > 0)
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Container(
                                    padding: EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    constraints: BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      totalQuantity > 99
                                          ? '99+'
                                          : totalQuantity.toString(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      label: 'Cart',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(CupertinoIcons.person),
                      label: 'Profile',
                    ),
                  ],
                ),
                floatingActionButton: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                    );
                  },
                  child: _currentBottomNav == BottomNavSelection.Home
                      ? Column(
                          key: const ValueKey('fab_column'),
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildMessageFloatingButton(),
                            const SizedBox(height: 8),
                            FloatingActionButton(
                              key: const ValueKey('ai_fab'),
                              onPressed: () => push(context, AiChatScreen()),
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              child: AshAvatar(radius: 24, showGlow: true),
                            ),
                          ],
                        )
                      : const SizedBox(key: ValueKey('ai_fab_empty')),
                ),
                appBar: null);
  }

  Widget _buildGuestProfilePlaceholder() {
    final dark = isDarkMode(context);
    final textColor = dark ? Colors.white70 : const Color(0xFF424242);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Color(COLOR_PRIMARY).withOpacity(0.08),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(COLOR_PRIMARY).withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 48,
                color: Color(COLOR_PRIMARY),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Sign in to view your profile',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: textColor,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Create an account or sign in to access your orders and preferences',
              style: TextStyle(
                fontSize: 14,
                color: dark ? Colors.white54 : const Color(0xFF757575),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => push(context, LoginScreen()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Login'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => push(context, SignUpScreen()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Color(COLOR_PRIMARY),
                  side: BorderSide(color: Color(COLOR_PRIMARY)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Register'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
