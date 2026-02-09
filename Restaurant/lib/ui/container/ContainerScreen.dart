import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
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

import 'package:foodie_restaurant/ui/add_resturant/add_resturant.dart';
import 'package:foodie_restaurant/ui/add_story_screen.dart';
import 'package:foodie_restaurant/ui/auth/AuthScreen.dart';
import 'package:foodie_restaurant/ui/chat_screen/chat_screen.dart';
import 'package:foodie_restaurant/ui/chat_screen/inbox_screen.dart';
import 'package:foodie_restaurant/ui/container/message.dart';
import 'package:foodie_restaurant/ui/manageProductsScreen/ManageProductsScreen.dart';
import 'package:foodie_restaurant/ui/offer/offers.dart';
import 'package:foodie_restaurant/ui/ordersScreen/OrdersScreen.dart';
import 'package:foodie_restaurant/ui/ordersScreen/CompletedOrdersScreen.dart';
import 'package:foodie_restaurant/ui/profile/ProfileScreen.dart';
import 'package:foodie_restaurant/ui/termsAndCondition/terms_and_codition.dart';
import 'package:foodie_restaurant/ui/working_hour/working_hours_screen.dart';

enum DrawerSelection {
  Orders,
  CompletedOrders,
  DineIn,
  ManageProducts,
  createTable,
  addStory,
  Offers,
  SpecialOffer,
  inbox,
  WorkingHours,
  Profile,
  Wallet,
  BankInfo,
  termsCondition,
  privacyPolicy,
  chooseLanguage,
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
      : this.appBarTitle = appBarTitle ?? 'Orders'.tr(),
        this.currentWidget = currentWidget ?? OrdersScreen(),
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
  Widget _currentWidget = OrdersScreen();
  DrawerSelection _drawerSelection = DrawerSelection.Orders;
  int unreadMessages = 0;

  // String _keyHash = 'Unknown';
  VendorModel? vendorModel;

  // Platform messages are asynchronous, so we initialize in an async method.
  // Future<void> getKeyHash() async {
  //   String keyHash;
  //   // Platform messages may fail, so we use a try/catch PlatformException.
  //   // We also handle the message potentially returning null.
  //   try {
  //     keyHash = await FlutterFacebookKeyhash.getFaceBookKeyHash ??
  //         'Unknown platform KeyHash'.tr();
  //   } on PlatformException {
  //     keyHash = 'Failed to get Kay Hash.'.tr();
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
    setCurrency();

    // Initialize user from widget.user if available, otherwise from MyAppState
    if (widget.user != null) {
      user = widget.user;
      MyAppState.currentUser = widget.user;
    }

    listenForUnreadMessages();

    // Get user data if not already available
    if (user == null) {
      FireStoreUtils.getCurrentUser(MyAppState.currentUser == null
              ? widget.userId!
              : MyAppState.currentUser!.userID)
          .then((value) {
        setState(() {
          user = value!;
          MyAppState.currentUser = value;
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
    _appBarTitle = 'Orders'.tr();
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
        // where receiverId == vendorId AND isread == false
        QuerySnapshot threadSnapshot = await FirebaseFirestore.instance
            .collection("chat_restaurant")
            .doc(chatDocId)
            .collection("thread")
            .where("receiverId", isEqualTo: vendorId)
            .where("isread", isEqualTo: false) // <-- use "isread"
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

    // Fetch unread messages (where isread == false) for this order
    var unreadMessagesSnapshot = await FirebaseFirestore.instance
        .collection("chat_restaurant")
        .doc(orderId)
        .collection("thread")
        .where("receiverId", isEqualTo: restaurantId)
        .where("isread", isEqualTo: false) // <-- use "isread"
        .get();

    print("🔹 Unread messages found: ${unreadMessagesSnapshot.docs.length}");

    // Decrement our unread counter in the UI
    setState(() {
      unreadMessages -= unreadMessagesSnapshot.docs.length;
    });

    // Mark all unread messages as read
    for (var doc in unreadMessagesSnapshot.docs) {
      await doc.reference.update({"isread": true}); // <-- use "isread"
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

  void setExit(bool value) {
    setState(() {
      widget.isExit = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                selected: _drawerSelection == DrawerSelection.Orders,
                title: Text('Orders').tr(),
                onTap: () {
                  Navigator.pop(context);
                  setState(
                    () {
                      _drawerSelection = DrawerSelection.Orders;
                      _appBarTitle = 'Orders'.tr();
                      _currentWidget = OrdersScreen();
                    },
                  );
                },
                leading: Image.asset(
                  'assets/images/app_logo.png',
                  color: _drawerSelection == DrawerSelection.Orders
                      ? Color(COLOR_PRIMARY)
                      : isDarkMode(context)
                          ? Colors.grey.shade200
                          : Colors.grey.shade600,
                  width: 24,
                  height: 24,
                ),
              ),
            ),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.CompletedOrders,
                title: Text('Completed Orders').tr(),
                onTap: () {
                  Navigator.pop(context);
                  setState(
                    () {
                      _drawerSelection = DrawerSelection.CompletedOrders;
                      _appBarTitle = 'Completed Orders'.tr();
                      _currentWidget = CompletedOrdersScreen();
                    },
                  );
                },
                leading: Icon(Icons.check_circle),
              ),
            ),

            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.DineIn,
                leading: Icon(Icons.restaurant_outlined),
                title: Text('Restaurant Information').tr(),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _drawerSelection = DrawerSelection.DineIn;
                    _appBarTitle = 'Restaurant Information'.tr();
                    _currentWidget = AddRestaurantScreen();
                  });
                  //Navigator.push(
                  //  context,
                  //  MaterialPageRoute(
                  //    builder: (_) => MessageBadgePage(
                  //      vendorId:
                  //          vendorModel?.id ?? MyAppState.currentUser!.vendorID,
                  //    ),
                  //  ),
                  //);
                },
              ),
            ),

            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.ManageProducts,
                leading: FaIcon(FontAwesomeIcons.pizzaSlice),
                title: Text('Manage Products').tr(),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _drawerSelection = DrawerSelection.ManageProducts;
                    _appBarTitle = 'Your Products'.tr();
                    _currentWidget = ManageProductsScreen();
                  });
                },
              ),
            ),
            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.createTable,
            //    title: Text('Create Table'.tr()),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(
            //        () {
            //          _drawerSelection = DrawerSelection.createTable;
            //          _appBarTitle = 'Create Table'.tr();
            //          _currentWidget = const CreateTable();
            //        },
            //      );
            //    },
            //    leading: const Icon(CupertinoIcons.table_badge_more),
            //  ),
            //),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.Offers,
                leading: Icon(Icons.local_offer_outlined),
                title: Text('Promo Offers').tr(),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _drawerSelection = DrawerSelection.Offers;
                    _appBarTitle = 'Offers'.tr();
                    _currentWidget = OffersScreen();
                  });
                },
              ),
            ),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.WorkingHours,
                leading: Icon(Icons.access_time_sharp),
                title: Text('Working Hours').tr(),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    String? vendorId =
                        user?.vendorID ?? MyAppState.currentUser?.vendorID;
                    if (vendorId != null && vendorId.isNotEmpty) {
                      _drawerSelection = DrawerSelection.WorkingHours;
                      _appBarTitle = 'Working Hours'.tr();
                      _currentWidget = WorkingHoursScreen();
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
            Visibility(
              visible: storyEnable == true ? true : false,
              child: ListTileTheme(
                style: ListTileStyle.drawer,
                selectedColor: Color(COLOR_PRIMARY),
                child: ListTile(
                  selected: _drawerSelection == DrawerSelection.addStory,
                  leading: Icon(Icons.ad_units),
                  title: Text('Add Story').tr(),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      String? vendorId =
                          user?.vendorID ?? MyAppState.currentUser?.vendorID;
                      if (vendorId != null && vendorId.isNotEmpty) {
                        _drawerSelection = DrawerSelection.addStory;
                        _appBarTitle = 'Add Story'.tr();
                        _currentWidget = AddStoryScreen();
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
            //    title: Text('special_discount').tr(),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(() {
            //        if (specialDiscountEnable) {
            //          _drawerSelection = DrawerSelection.SpecialOffer;
            //          _appBarTitle = 'special_discount'.tr();
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
                title: Text('Inbox').tr(),
                onTap: () {
                  if (MyAppState.currentUser == null) {
                    Navigator.pop(context);
                    push(context, AuthScreen());
                  } else {
                    Navigator.pop(context);
                    setState(() {
                      _drawerSelection = DrawerSelection.inbox;
                      _appBarTitle = 'My Inbox'.tr();
                      _currentWidget = InboxScreen();
                    });
                  }
                },
              ),
            ),

            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.Profile,
                leading: Icon(CupertinoIcons.person),
                title: Text('Profile').tr(),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _drawerSelection = DrawerSelection.Profile;
                    _appBarTitle = 'Profile'.tr();
                    _currentWidget = ProfileScreen(
                      user: user!,
                    );
                  });
                },
              ),
            ),
            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.Wallet,
            //    leading: Icon(Icons.account_balance_wallet_sharp),
            //    title: Text('Wallet').tr(),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(() {
            //        _drawerSelection = DrawerSelection.Wallet;
            //        _appBarTitle = 'Wallet'.tr();
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
            //    title: Text('Bank Details').tr(),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(() {
            //        _drawerSelection = DrawerSelection.BankInfo;
            //        _appBarTitle = 'Bank Info'.tr();
            //        _currentWidget = BankDetailsScreen();
            //      });
            //    },
            //  ),
            //),
            //ListTileTheme(
            //  style: ListTileStyle.drawer,
            //  selectedColor: Color(COLOR_PRIMARY),
            //  child: ListTile(
            //    selected: _drawerSelection == DrawerSelection.chooseLanguage,
            //    leading: Icon(
            //      Icons.language,
            //      color: _drawerSelection == DrawerSelection.chooseLanguage
            //          ? Color(COLOR_PRIMARY)
            //          : isDarkMode(context)
            //              ? Colors.grey.shade200
            //              : Colors.grey.shade600,
            //    ),
            //    title: const Text('Language').tr(),
            //    onTap: () {
            //      Navigator.pop(context);
            //      setState(() {
            //        _drawerSelection = DrawerSelection.chooseLanguage;
            //        _appBarTitle = 'Language'.tr();
            //        _currentWidget = LanguageChooseScreen(
            //          isContainer: true,
            //        );
            //      });
            //    },
            //  ),
            //),
            ListTileTheme(
              style: ListTileStyle.drawer,
              selectedColor: Color(COLOR_PRIMARY),
              child: ListTile(
                selected: _drawerSelection == DrawerSelection.termsCondition,
                leading: const Icon(Icons.policy),
                title: const Text('Terms and Condition').tr(),
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
            //    title: const Text('Privacy policy').tr(),
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
                title: Text('Log out').tr(),
                onTap: () async {
                  audioPlayer.stop();
                  Navigator.pop(context);
                  //user.active = false;
                  user!.lastOnlineTimestamp = Timestamp.now();
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
      body: PopScope(
          onPopInvokedWithResult: (cantExit, dynamic) async {
            final timeGap = DateTime.now().difference(preBackpress);
            final cantExit = timeGap >= Duration(seconds: 2);
            preBackpress = DateTime.now();
            if (cantExit) {
              //show snackbar
              final snack = SnackBar(
                content: Text(
                  'Press Back button again to Exit',
                  style: TextStyle(color: Colors.white),
                ),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.black,
              );
              ScaffoldMessenger.of(context).showSnackBar(snack);
              return setExit(false); // false will do nothing when back press
            } else {
              return setExit(true); // true will exit the app
            }
          },
          child: _currentWidget),
    );
  }
}
