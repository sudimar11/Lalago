import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/CurrencyModel.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/model/VendorModel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/services/notification_service.dart';

import 'package:foodie_restaurant/ui/add_story_screen.dart';
import 'package:foodie_restaurant/ui/auth/AuthScreen.dart';
import 'package:foodie_restaurant/ui/chat_screen/chat_screen.dart';
import 'package:foodie_restaurant/ui/chat_screen/inbox_screen.dart';
import 'package:foodie_restaurant/ui/communication/order_communication_screen.dart';
import 'package:foodie_restaurant/ui/container/message.dart';
import 'package:foodie_restaurant/ui/manageProductsScreen/ManageProductsScreen.dart';
import 'package:foodie_restaurant/ui/order_acceptance_screen.dart';
import 'package:foodie_restaurant/ui/ordersScreen/UnifiedOrdersScreen.dart';
import 'package:foodie_restaurant/ui/pause_screen.dart';
import 'package:foodie_restaurant/ui/insights_screen/InsightsScreen.dart';
import 'package:foodie_restaurant/ui/profile/ProfileScreen.dart';
import 'package:foodie_restaurant/ui/reviews/ReviewsScreen.dart';
import 'package:foodie_restaurant/ui/termsAndCondition/terms_and_codition.dart';
import 'package:foodie_restaurant/screens/ai_chat_screen.dart';
import 'package:foodie_restaurant/ui/loyalty/loyalty_program_screen.dart';
import 'package:foodie_restaurant/ui/locations/locations_screen.dart';

enum BottomNavTab { orders, menu, reviews, insights, profile }

enum DrawerSelection {
  Orders,
  CompletedOrders,
  ManageProducts,
  createTable,
  addStory,
  SpecialOffer,
  inbox,
  LoyaltyProgram,
  Locations,
  Profile,
  Wallet,
  BankInfo,
  termsCondition,
  privacyPolicy,
  Logout
}

// ignore: must_be_immutable
class ContainerScreen extends StatefulWidget {
  final User? user;

  final Widget currentWidget;
  final String appBarTitle;
  final DrawerSelection drawerSelection;
  String? userId = "";

  bool isExit = false;

  ContainerScreen(
      {Key? key,
      this.user,
      this.userId,
      appBarTitle,
      currentWidget,
      this.drawerSelection = DrawerSelection.Orders})
      : this.appBarTitle = appBarTitle ?? 'Orders',
        this.currentWidget = currentWidget ?? UnifiedOrdersScreen(),
        super(key: key);

  @override
  _ContainerScreen createState() {
    return _ContainerScreen();
  }
}

class _ContainerScreen extends State<ContainerScreen> {
  User? user;
  late String _appBarTitle;
  final fireStoreUtils = FireStoreUtils();

  // Bottom nav tab state (for Phase 3)
  int _selectedIndex = 0;
  BottomNavTab _currentTab = BottomNavTab.orders;
  Widget? _ordersScreen;
  Widget? _menuScreen;
  Widget? _reviewsScreen;
  Widget? _insightsScreen;
  Widget? _profileScreen;
  int _lowStockCount = 0;
  final _menuScreenKey = GlobalKey<ManageProductsScreenState>();
  final _unifiedOrdersKey = GlobalKey<UnifiedOrdersScreenState>();

  // Drawer overlay: when non-null, shows a drawer-only screen
  Widget? _drawerOverlayWidget;
  DrawerSelection _drawerSelection = DrawerSelection.Orders;
  int unreadMessages = 0;
  List<Map<String, String>> _chainLocations = [];

  // String _keyHash = 'Unknown';
  VendorModel? vendorModel;

  // Platform messages are asynchronous, so we initialize in an async method.
  // Future<void> getKeyHash() async {
  //   String keyHash;
  //   // Platform messages may fail, so we use a try/catch PlatformException.
  //   // We also handle the message potentially returning null.
  //   try {
  //     keyHash = await FlutterFacebookKeyhash.getFaceBookKeyHash ??
  //         'Unknown platform KeyHash';
  //   } on PlatformException {
  //     keyHash = 'Failed to get Kay Hash.';
  //   }

  //   // If the widget was removed from the tree while the asynchronous platform
  //   // message was in flight, we want to discard the reply rather than calling
  //   // setState to update our non-existent appearance.
  //   if (!mounted) return;

  //   setState(() {
  //     _keyHash = keyHash;
  //     print("::::KEYHASH::::");
  //     print(_keyHash);
  //   });
  // }

  final audioPlayer = AudioPlayer(playerId: "playerId");

  @override
  void initState() {
    super.initState();
    NotificationService.onPrepTimeReminder = _showPrepTimeReminderDialog;
    NotificationService.onNewOrder = _openOrderAcceptanceScreen;
    NotificationService.onDeclineOrder = _openOrderAcceptanceScreen;
    NotificationService.onOpenOrderCommunication = _openOrderCommunication;
    setCurrency();

    // Initialize user from widget.user if available, otherwise from MyAppState
    if (widget.user != null) {
      user = widget.user;
      MyAppState.currentUser = widget.user;
    }

    // Initialize bottom nav tab screens (for Phase 3)
    _ordersScreen = UnifiedOrdersScreen(key: _unifiedOrdersKey);
    _menuScreen = ManageProductsScreen(
      key: _menuScreenKey,
      onLowStockCountChanged: (n) {
        if (mounted && _lowStockCount != n) {
          setState(() => _lowStockCount = n);
        }
      },
    );
    _reviewsScreen = ReviewsScreen();
    _insightsScreen = InsightsScreen();
    if (user != null) {
      _profileScreen = ProfileScreen(user: user!);
    }

    listenForUnreadMessages();
    if (user?.role == USER_ROLE_CHAIN_ADMIN && (user?.chainId ?? '').isNotEmpty) {
      _loadChainLocations();
    }

    // Get user data if not already available
    if (user == null) {
      FireStoreUtils.getCurrentUser(MyAppState.currentUser == null
              ? widget.userId!
              : MyAppState.currentUser!.userID)
          .then((value) {
        setState(() {
          final u = value!;
          user = u;
          MyAppState.currentUser = u;
          _profileScreen ??= ProfileScreen(user: u);
        });
      });
    }

    // Check vendor ID and get vendor data
    String? vendorId = user?.vendorID ?? MyAppState.currentUser?.vendorID;
    if (vendorId != null && vendorId.isNotEmpty) {
      FireStoreUtils.getVendor(vendorId).then((value) {
        if (value != null) {
          vendorModel = value;
          setState(() {});
        }
      });
    }

    getSpecialDiscount();

    //getKeyHash();
    _appBarTitle = 'Orders';
    fireStoreUtils.getplaceholderimage();
    // print(MyAppState.currentUser!.vendorID);

    /// On iOS, we request notification permissions, Does nothing and returns null on Android
    FireStoreUtils.firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          NotificationService.showEnableNotificationsDialogIfNeeded(context);
        }
      });
    });
  }

  @override
  void dispose() {
    NotificationService.onPrepTimeReminder = null;
    NotificationService.onNewOrder = null;
    NotificationService.onDeclineOrder = null;
    NotificationService.onOpenOrderCommunication = null;
    super.dispose();
  }

  void _openOrderAcceptanceScreen(String orderId) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderAcceptanceScreen(orderId: orderId),
      ),
    );
  }

  void _showPrepTimeReminderDialog(String orderId, String minutes) {
    if (!mounted) return;
    final shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order Almost Ready'),
        content: Text(
          'Order #$shortId will be ready in $minutes minutes.\n\n'
          'Please mark it as ready to notify the rider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('DISMISS'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _drawerSelection = DrawerSelection.Orders;
                _drawerOverlayWidget = null;
                _selectedIndex = 0;
                _currentTab = BottomNavTab.orders;
                _appBarTitle = 'Orders';
              });
            },
            child: const Text('VIEW ORDER'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOrderCommunication(String orderId) async {
    if (!mounted) return;
    final orderSnap = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .doc(orderId)
        .get();
    if (!mounted || !orderSnap.exists) return;
    final data = orderSnap.data() ?? {};
    final riderId = (data['driverID'] ?? data['driverId'] ?? '').toString();
    final vendorId = (data['vendorID'] ?? '').toString();
    final customerId = (data['authorID'] ?? data['authorId'] ?? '').toString();
    if (riderId.isEmpty || vendorId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderCommunicationScreen(
          orderId: orderId,
          riderId: riderId,
          vendorId: vendorId,
          customerId: customerId,
        ),
      ),
    );
  }

  void listenForUnreadMessages() {
    // Make sure user is logged in
    String? vendorId = user?.vendorID ?? MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) return;

    // Listen for changes in "chat_restaurant" where restaurantId == vendorId
    FirebaseFirestore.instance
        .collection("chat_restaurant")
        .where("restaurantId", isEqualTo: vendorId)
        .snapshots()
        .listen((chatSnapshot) async {
      int newUnreadCount = 0;

      // For each chat doc that belongs to this vendor:
      for (var chatDoc in chatSnapshot.docs) {
        String chatDocId = chatDoc.id;

        // Query the subcollection "thread" for messages
        // where receiverId == vendorId AND isRead == false
        QuerySnapshot threadSnapshot = await FirebaseFirestore.instance
            .collection("chat_restaurant")
            .doc(chatDocId)
            .collection("thread")
            .where("receiverId", isEqualTo: vendorId)
            .where("isRead", isEqualTo: false)
            .get();

        // Count how many unread messages we have
        newUnreadCount += threadSnapshot.docs.length;
      }

      // Update your state
      setState(() {
        unreadMessages = newUnreadCount;
      });

      print("✅ Total Unread Messages: $unreadMessages");
    });
  }

  void openChat(
    String orderId,
    String customerId,
    String customerName,
    String restaurantId,
    String restaurantName,
    String customerProfileImage,
    String restaurantProfileImage,
    String token,
  ) async {
    print("📌 Opening chat for Order ID: $orderId");

    // Fetch unread messages (where isRead == false) for this order
    var unreadMessagesSnapshot = await FirebaseFirestore.instance
        .collection("chat_restaurant")
        .doc(orderId)
        .collection("thread")
        .where("receiverId", isEqualTo: restaurantId)
        .where("isRead", isEqualTo: false)
        .get();

    print("🔹 Unread messages found: ${unreadMessagesSnapshot.docs.length}");

    // Decrement our unread counter in the UI
    setState(() {
      unreadMessages -= unreadMessagesSnapshot.docs.length;
    });

    // Mark all unread messages as read
    for (var doc in unreadMessagesSnapshot.docs) {
      await doc.reference.update({"isRead": true});
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreens(
          orderId: orderId,
          customerId: customerId,
          customerName: customerName,
          restaurantId: restaurantId,
          restaurantName: restaurantName,
          customerProfileImage: customerProfileImage,
          restaurantProfileImage: restaurantProfileImage,
          token: token,
        ),
      ),
    );
    // In your main code or anywhere you need to navigate:
  }

  setCurrency() async {
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
  }

  bool specialDiscountEnable = false;
  bool storyEnable = false;

  getSpecialDiscount() async {
    await FirebaseFirestore.instance
        .collection(Setting)
        .doc('specialDiscountOffer')
        .get()
        .then((value) {
      specialDiscountEnable = value.data()!['isEnable'];
    });
    await FirebaseFirestore.instance
        .collection(Setting)
        .doc('story')
        .get()
        .then((value) {
      storyEnable = value.data()!['isEnabled'];
    });
    setState(() {});
  }

  DateTime preBackpress = DateTime.now();

  Future<void> _loadChainLocations() async {
    final chainId = user?.chainId ?? MyAppState.currentUser?.chainId;
    if (chainId == null || chainId.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(VENDORS)
          .where('chainId', isEqualTo: chainId)
          .get();
      if (!mounted) return;
      setState(() {
        _chainLocations = snap.docs.map((d) {
          final data = d.data();
          return {
            'id': d.id,
            'title': (data['title'] ?? '').toString(),
          };
        }).toList();
      });
    } catch (_) {}
  }

  void setExit(bool value) {
    setState(() {
      widget.isExit = value;
    });
  }

  void _onTabTapped(int index) {
    setState(() {
      _drawerOverlayWidget = null;
      _selectedIndex = index;
      _currentTab = BottomNavTab.values[index];
      switch (_currentTab) {
        case BottomNavTab.orders:
          _appBarTitle = 'Orders';
          break;
        case BottomNavTab.menu:
          _appBarTitle = 'Your Products';
          break;
        case BottomNavTab.reviews:
          _appBarTitle = 'Reviews';
          break;
        case BottomNavTab.insights:
          _appBarTitle = 'Insights';
          break;
        case BottomNavTab.profile:
          _appBarTitle = 'Profile';
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_drawerOverlayWidget != null) {
          setState(() {
            _drawerOverlayWidget = null;
            _selectedIndex = 0;
            _currentTab = BottomNavTab.orders;
            _appBarTitle = 'Orders';
          });
          return;
        }
        if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
            _currentTab = BottomNavTab.orders;
            _appBarTitle = 'Orders';
          });
          return;
        }
        final timeGap = DateTime.now().difference(preBackpress);
        final shouldExit = timeGap >= const Duration(seconds: 2);
        preBackpress = DateTime.now();
        if (!shouldExit) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Press Back button again to Exit'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.black,
            ),
          );
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar:
            _drawerSelection == DrawerSelection.Wallet ? true : false,
        backgroundColor: isDarkMode(context) ? Color(COLOR_DARK) : null,
        drawer: Drawer(
          child: Container(
        color: isDarkMode(context) ? Color(COLOR_DARK) : null,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            user == null
                ? Container()
                : SizedBox(
                    height: 210, // Limit the height to prevent overflow
                    child: DrawerHeader(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          displayCircleImage(
                              user!.profilePictureURL, 75, false),
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              user!.fullName(),
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              user!.email,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      decoration: BoxDecoration(
                        color: Color(COLOR_PRIMARY),
                      ),
                    ),
                  ),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.CompletedOrders,
                title: Text('Completed Orders'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _drawerSelection = DrawerSelection.CompletedOrders;
                    _appBarTitle = 'Completed Orders';
                    _drawerOverlayWidget = null;
                    _selectedIndex = 0;
                    _currentTab = BottomNavTab.orders;
                    _unifiedOrdersKey.currentState?.switchToTab(OrdersTab.completed);
                  });
                },
                leading: Icon(Icons.check_circle),
              ),
            ),

            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.createTable,
            //    title: Text('Create Table'),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(
            //        () {
            //          _drawerSelection = DrawerSelection.createTable;
            //          _appBarTitle = 'Create Table';
            //          _currentWidget = const CreateTable();
            //        },
            //      );
            //    },
            //    leading: const Icon(CupertinoIcons.table_badge_more),
            //  ),
            //),
            Visibility(
              visible: storyEnable == true ? true : false,
              child: ListTileTheme(
                style: ListTileStyle.drawer,
                selectedColor: Color(COLOR_PRIMARY),
                child: ListTile(
                  selected: _drawerSelection == DrawerSelection.addStory,
                  leading: Icon(Icons.ad_units),
                  title: Text('Add Story'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      String? vendorId =
                          user?.vendorID ?? MyAppState.currentUser?.vendorID;
                      if (vendorId != null && vendorId.isNotEmpty) {
                        _drawerSelection = DrawerSelection.addStory;
                        _appBarTitle = 'Add Story';
                        _drawerOverlayWidget = AddStoryScreen();
                      } else {
                        final snackBar = SnackBar(
                          content: const Text('Please add restaurant first.'),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(snackBar);
                      }
                    });
                  },
                ),
              ),
            ),
            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.SpecialOffer,
            //    leading: Icon(Icons.local_offer_outlined),
            //    title: Text('special_discount'),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(() {
            //        if (specialDiscountEnable) {
            //          _drawerSelection = DrawerSelection.SpecialOffer;
            //          _appBarTitle = 'special_discount';
            //          _currentWidget = SpecialOfferScreen();
            //        } else {
            //          final snackBar = SnackBar(
            //            content:
            //                const Text('This feature is not enable by admin.'),
            //          );
            //          ScaffoldMessenger.of(context).showSnackBar(snackBar);
            //        }
            //      });
            //    },
            //  ),
            //),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.inbox,
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(CupertinoIcons.chat_bubble_2_fill, size: 30),
                    if (unreadMessages >
                        0) // ✅ Show badge only if there are unread messages
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Center(
                            child: Text(
                              unreadMessages
                                  .toString(), // ✅ Correct unread count
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text('Inbox'),
                onTap: () {
                  if (MyAppState.currentUser == null) {
                    Navigator.pop(context);
                    push(context, AuthScreen());
                  } else {
                    Navigator.pop(context);
                    setState(() {
                      _drawerSelection = DrawerSelection.inbox;
                      _appBarTitle = 'My Inbox';
                      _drawerOverlayWidget = InboxScreen();
                    });
                  }
                },
              ),
            ),

            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.Wallet,
            //    leading: Icon(Icons.account_balance_wallet_sharp),
            //    title: Text('Wallet'),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(() {
            //        _drawerSelection = DrawerSelection.Wallet;
            //        _appBarTitle = 'Wallet';
            //        _currentWidget = WalletScreen();
            //      });
            //    },
            //  ),
            //),
            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.BankInfo,
            //    leading: Icon(Icons.account_balance),
            //    title: Text('Bank Details'),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(() {
            //        _drawerSelection = DrawerSelection.BankInfo;
            //        _appBarTitle = 'Bank Info';
            //        _currentWidget = BankDetailsScreen();
            //      });
            //    },
            //  ),
            //),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.LoyaltyProgram,
                leading: const Icon(Icons.card_giftcard),
                title: const Text('Loyalty Program'),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _drawerSelection = DrawerSelection.LoyaltyProgram;
                    _appBarTitle = 'Loyalty Program';
                    _drawerOverlayWidget =
                        const LoyaltyProgramScreen();
                  });
                },
              ),
            ),
            if (user?.role == USER_ROLE_CHAIN_ADMIN)
              ListTileTheme(
                style: ListTileStyle.drawer,
                selectedColor: Color(COLOR_PRIMARY),
                child: ListTile(
                  selected: _drawerSelection == DrawerSelection.Locations,
                  leading: const Icon(Icons.store),
                  title: const Text('Locations'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _drawerSelection = DrawerSelection.Locations;
                      _appBarTitle = 'Locations';
                      _drawerOverlayWidget =
                          const LocationsScreen();
                    });
                  },
                ),
              ),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.termsCondition,
                leading: const Icon(Icons.policy),
                title: const Text('Terms and Condition'),
                onTap: () async {
                  push(context, const TermsAndCondition());
                },
              ),
            ),
            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.privacyPolicy,
            //    leading: const Icon(Icons.privacy_tip),
            //    title: const Text('Privacy policy'),
            //    onTap: () async {
            //      push(context, const PrivacyPolicyScreen());
            //    },
            //  ),
            //),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.Logout,
                leading: Icon(Icons.logout),
                title: Text('Log out'),
                onTap: () async {
                  audioPlayer.stop();
                  Navigator.pop(context);
                  //user.active = false;
                  user!.lastOnlineTimestamp = Timestamp.now();
                  if (user!.fcmToken.isNotEmpty) {
                    unawaited(FireStoreUtils.removeFcmToken(
                      user!.userID,
                      user!.fcmToken,
                      vendorId:
                          user!.vendorID.isEmpty ? null : user!.vendorID,
                    ));
                  }
                  await FireStoreUtils.firestore
                      .collection(USERS)
                      .doc(user!.userID)
                      .update({"fcmToken": ""});
                  if (user!.vendorID.isNotEmpty) {
                    await FireStoreUtils.firestore
                        .collection(VENDORS)
                        .doc(user!.vendorID)
                        .update({"fcmToken": ""});
                  }
                  // await FireStoreUtils.updateCurrentUser(user);
                  await auth.FirebaseAuth.instance.signOut();
                  await FacebookAuth.instance.logOut();
                  MyAppState.currentUser = null;
                  pushAndRemoveUntil(context, AuthScreen(), false);
                },
              ),
            ),
          ],
        ),
      )),
      appBar: AppBar(
        iconTheme: IconThemeData(
          color: _drawerSelection == DrawerSelection.Wallet
              ? Colors.white
              : isDarkMode(context)
                  ? Colors.white
                  : Colors.black,
        ),
        centerTitle: _drawerSelection == DrawerSelection.Wallet ? true : false,
        backgroundColor: _drawerSelection == DrawerSelection.Wallet
            ? Colors.transparent
            : isDarkMode(context)
                ? Color(DARK_VIEWBG_COLOR)
                : Colors.white,
        actions: [
          if (user?.role == USER_ROLE_CHAIN_ADMIN && _chainLocations.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.store,
                color: _drawerSelection == DrawerSelection.Wallet
                    ? Colors.white
                    : (isDarkMode(context) ? Colors.white : Colors.black),
              ),
              onSelected: (id) {
                MyAppState.selectedLocationId =
                    id.isEmpty ? null : id;
                setState(() {});
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: '',
                  child: Row(
                    children: [
                      Icon(Icons.all_inclusive, size: 20),
                      SizedBox(width: 12),
                      Text('All Locations'),
                    ],
                  ),
                ),
                ..._chainLocations.map((loc) => PopupMenuItem(
                      value: loc['id'] ?? '',
                      child: Row(
                        children: [
                          const Icon(Icons.store, size: 20),
                          const SizedBox(width: 12),
                          Expanded(child: Text(loc['title'] ?? '')),
                        ],
                      ),
                    )),
              ],
            ),
          if (_currentTab == BottomNavTab.orders) ...[
            IconButton(
              icon: Icon(Icons.upload_file),
              onPressed: () =>
                  _unifiedOrdersKey.currentState?.showExportSheet(),
            ),
            IconButton(
              icon: Icon(Icons.filter_list),
              onPressed: () =>
                  _unifiedOrdersKey.currentState?.showFilterSheet(),
            ),
          ],
          if (_currentTab == BottomNavTab.menu)
            IconButton(
              icon: Icon(Icons.checklist),
              onPressed: () =>
                  _menuScreenKey.currentState?.toggleSelectionMode(),
            ),
          // if (_currentWidget is ManageProductsScreen)
          // IconButton(
          //   icon: Icon(
          //     CupertinoIcons.add_circled,
          //     color: Color(COLOR_PRIMARY),
          //   ),
          //   onPressed: () => push(
          //     context,
          //     AddOrUpdateProductScreen(product: null),
          //   ),
          // ),
        ],
        title: Text(
          _appBarTitle,
          style: TextStyle(
            fontSize: 20,
            color: _drawerSelection == DrawerSelection.Wallet
                ? Colors.white
                : isDarkMode(context)
                    ? Colors.white
                    : Colors.black,
          ),
        ),
      ),
        body: _buildBody(),
        floatingActionButton: _currentTab == BottomNavTab.menu
            ? null
            : Tooltip(
                message: 'Ask Ash',
                child: FloatingActionButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AiChatScreen(),
                    ),
                  ),
                  backgroundColor: Color(COLOR_PRIMARY),
                  child: const Icon(Icons.assistant, color: Colors.white),
                ),
              ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onTabTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor:
              isDarkMode(context) ? Color(COLOR_DARK) : Colors.white,
          selectedItemColor: Color(COLOR_PRIMARY),
          unselectedItemColor:
              isDarkMode(context) ? Colors.grey[400] : Colors.grey[600],
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.restaurant_menu),
                  if (_lowStockCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Text(
                          '$_lowStockCount',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              label: 'Menu',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.star),
              label: 'Reviews',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.insights),
              label: 'Insights',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final bodyChild = _drawerOverlayWidget ??
        IndexedStack(
          index: _selectedIndex,
          children: [
            _ordersScreen ?? UnifiedOrdersScreen(),
            _menuScreen ?? ManageProductsScreen(),
            _reviewsScreen ?? ReviewsScreen(),
            _insightsScreen ?? InsightsScreen(),
            _profileScreen ??
                (user != null
                    ? ProfileScreen(user: user!)
                    : Center(child: CircularProgressIndicator())),
          ],
        );

    final vendorId = user?.vendorID ?? MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) {
      return bodyChild;
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FireStoreUtils.firestore
          .collection(VENDORS)
          .doc(vendorId)
          .snapshots(),
      builder: (context, snapshot) {
        final autoPause =
            (snapshot.data?.data() as Map<String, dynamic>? ?? {})['autoPause']
                as Map<String, dynamic>? ??
            {};
        final isPaused = autoPause['isPaused'] == true;

        if (isPaused) {
          return PauseScreen(vendorId: vendorId);
        }

        return bodyChild;
      },
    );
  }
}
