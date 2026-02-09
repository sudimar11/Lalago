import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/CurrencyModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/services/version_service.dart';

import 'package:foodie_customer/ui/auth/AuthScreen.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/ui/home/HomeScreen.dart';
import 'package:foodie_customer/ui/location_permission_screen.dart';
import 'package:foodie_customer/ui/onBoarding/OnBoardingScreen.dart';

import 'package:foodie_customer/ui/profile/ProfileScreen.dart';
import 'package:foodie_customer/ui/searchScreen/SearchScreen.dart';

import 'package:foodie_customer/utils/DarkThemeProvider.dart';
import 'package:foodie_customer/utils/notification_service.dart';
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

class _ContainerScreen extends State<ContainerScreen> {
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

  @override
  void initState() {
    super.initState();

    if (widget.user != null) {
      user = widget.user!;
      _isInitializing = false;
      _initializeAfterUserSet();
    } else {
      _performInitialization();
    }
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

      // 2) Check FirebaseAuth user (wait for session restore if null)
      auth.User? fbUser = auth.FirebaseAuth.instance.currentUser;
      debugPrint('[AUTH_INIT] Initial currentUser: ${fbUser?.uid}');

      if (fbUser == null) {
        debugPrint(
            '[AUTH_INIT] currentUser is null, waiting for authStateChanges (2s timeout)...');
        try {
          fbUser = await auth.FirebaseAuth.instance
              .authStateChanges()
              .first
              .timeout(const Duration(milliseconds: 2000));
        } catch (_) {
          // Timeout or error - fbUser stays null
        }
        debugPrint('[AUTH_INIT] After wait, currentUser: ${fbUser?.uid}');
      }

      if (fbUser == null) {
        debugPrint(
            '[AUTH_INIT] User still null after wait, redirecting to AuthScreen');
        if (mounted) {
          pushReplacement(context, AuthScreen());
        }
        return;
      }
      debugPrint('[AUTH_INIT] Proceeding with uid=${fbUser.uid}');

      // 3) Fetch Firestore user record
      final fetchedUser = await FireStoreUtils.getCurrentUser(fbUser.uid);
      if (fetchedUser == null || fetchedUser.role != USER_ROLE_CUSTOMER) {
        if (mounted) {
          pushReplacement(context, AuthScreen());
        }
        return;
      }

      // 4) Handle inactive customer - auto-reactivate
      fetchedUser.active = true;
      fetchedUser.lastOnlineTimestamp = Timestamp.now();
      await FireStoreUtils.updateCurrentUser(fetchedUser);
      MyAppState.currentUser = fetchedUser;
      user = fetchedUser;

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
          MyAppState.selectedPosotion = defaultAddr;
        } else {
          pushAndRemoveUntil(context, LocationPermissionScreen(), false);
          return;
        }
      }

      // 7) Initialize currency and other settings
      await _initializeAfterUserSet();

      // 8) Mark initialization as complete
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        setState(() {
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
    // Load placeholder image
    FireStoreUtils.getplaceholderimage().then((value) {
      AppGlobal.placeHolderImage = value;
    });

    // Initialize currency and settings
    await setCurrency();

    // Initialize persistent tab screens once
    if (mounted) {
      setState(() {
        _homeScreen = widget.currentWidget is HomeScreen
            ? widget.currentWidget
            : HomeScreen(user: MyAppState.currentUser);
        _searchScreen = SearchScreen(
          key: _searchScreenKey,
          shouldAutoFocus: widget.currentWidget is SearchScreen,
        );
        _cartScreen = widget.currentWidget is CartScreen
            ? widget.currentWidget
            : CartScreen(fromContainer: true);
        _profileScreen = widget.currentWidget is ProfileScreen
            ? widget.currentWidget
            : ProfileScreen(user: MyAppState.currentUser!);

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
    }
  }

  void _onBottomNavTapped(BottomNavSelection selection) {
    setState(() {
      _currentBottomNav = selection;
      if (selection == BottomNavSelection.Search) {
        _searchScreen = SearchScreen(
          key: _searchScreenKey,
          shouldAutoFocus: true,
        );
      } else if (_searchScreen != null) {
        _searchScreen = SearchScreen(
          key: _searchScreenKey,
          shouldAutoFocus: false,
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
    if (MyAppState.selectedPosotion.location != null) {
      try {
        List<Placemark> placeMarks = await placemarkFromCoordinates(
            MyAppState.selectedPosotion.location!.latitude,
            MyAppState.selectedPosotion.location!.longitude);

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
                Container(
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
              ],
            ),
            SizedBox(height: 20),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: 22,
                fontFamily: 'Poppinsm',
                color: Color(COLOR_PRIMARY),
              ),
            ),
          ],
        ),
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

    // Show main UI if user is available
    if (user == null) {
      return _buildLoadingIndicator();
    }

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
      child: ChangeNotifierProvider.value(
        value: user!,
        child: Consumer<User>(
          builder: (context, user, _) {
            return Scaffold(
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
                      icon: StreamBuilder<List<CartProduct>>(
                        stream: cartDatabase.watchProducts,
                        builder: (context, snapshot) {
                          int totalQuantity = 0;
                          if (snapshot.hasData) {
                            totalQuantity = snapshot.data!
                                .fold(0, (sum, item) => sum + item.quantity);
                          }

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
                                      borderRadius: BorderRadius.circular(8),
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
                appBar: null,
                body: IndexedStack(
                  index: _currentBottomNav.index,
                  children: [
                    _homeScreen ?? const SizedBox.shrink(),
                    _searchScreen ?? const SizedBox.shrink(),
                    _cartScreen ?? const SizedBox.shrink(),
                    _profileScreen ?? const SizedBox.shrink(),
                  ],
                ));
          },
        ),
      ),
    );
  }
}
