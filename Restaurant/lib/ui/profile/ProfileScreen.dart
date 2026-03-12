import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/model/VendorModel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/accountDetails/AccountDetailsScreen.dart';
import 'package:foodie_restaurant/ui/add_resturant/add_resturant.dart';
import 'package:foodie_restaurant/ui/auth/AuthScreen.dart';
import 'package:foodie_restaurant/ui/offer/offers.dart';
import 'package:foodie_restaurant/ui/settings/SettingsScreen.dart';
import 'package:foodie_restaurant/ui/working_hour/working_hours_screen.dart';
import 'package:image_picker/image_picker.dart';

import '../reauthScreen/reauth_user_screen.dart';

class ProfileScreen extends StatefulWidget {
  final User user;

  ProfileScreen({Key? key, required this.user}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  late User user;
  VendorModel? vendor;
  bool? isLoader = false;
  Stream? userStream;

  @override
  void initState() {
    //user = widget.user;
    FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID).then((value) {
      setState(() {
        user = value!;
        MyAppState.currentUser = value;
        isLoader = true;
      });
    });
    userStream = FireStoreUtils.getCurrentUserStream(MyAppState.currentUser!.userID);

    userStream!.listen((event) {
      setState(() {
        user = event;
        MyAppState.currentUser = event;
        print("===123+");
        print(user.firstName);
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: !isLoader!
          ? Center(
              child: CircularProgressIndicator(color: Color(COLOR_PRIMARY)),
            )
          : SingleChildScrollView(
              child: Column(children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 32.0, left: 32, right: 32),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      Center(child: displayCircleImage(user.profilePictureURL, 130, false)),
                      Positioned.directional(
                        textDirection: Directionality.of(context),
                        start: 80,
                        end: 0,
                        child: FloatingActionButton(
                            backgroundColor: Color(COLOR_ACCENT),
                            child: Icon(
                              Icons.camera_alt,
                              color: isDarkMode(context) ? Colors.black : Colors.white,
                            ),
                            mini: true,
                            onPressed: _onCameraClick),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, right: 32, left: 32),
                  child: Text(
                    user.fullName(),
                    style: TextStyle(color: isDarkMode(context) ? Colors.white : Colors.black, fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        onTap: () async {
                          if (MyAppState.currentUser!.vendorID.isNotEmpty) {
                            vendor = (await FireStoreUtils.getVendor(
                                MyAppState.currentUser!.vendorID))!;
                          }
                          Navigator.of(context)
                              .push(MaterialPageRoute(
                                  builder: (context) =>
                                      AccountDetailsScreen(vendor: vendor)))
                              .then((value) {
                            if (value != null) {
                              setState(() {
                                FireStoreUtils.getCurrentUser(
                                        MyAppState.currentUser!.userID)
                                    .then((value) {
                                  setState(() {
                                    user = value!;
                                    MyAppState.currentUser = value;
                                  });
                                });
                              });
                            }
                          });
                        },
                        title: Text(
                          'Account Details',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        leading: Icon(
                          CupertinoIcons.person_alt,
                          color: Colors.blue,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 16, right: 16, top: 24, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'RESTAURANT MANAGEMENT',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode(context)
                                  ? Colors.white54
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                      ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddRestaurantScreen(),
                            ),
                          );
                        },
                        title: Text(
                          'Restaurant Information',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        leading: Icon(
                          Icons.restaurant_outlined,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                      ListTile(
                        onTap: () => _navigateIfVendorExists(() {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => WorkingHoursScreen(),
                            ),
                          );
                        }),
                        title: Text(
                          'Working Hours',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        leading: Icon(
                          Icons.access_time_sharp,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                      ListTile(
                        onTap: () => _navigateIfVendorExists(() {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OffersScreen(),
                            ),
                          );
                        }),
                        title: Text(
                          'Promo Offers',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        leading: Icon(
                          Icons.local_offer_outlined,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 16, right: 16, top: 24, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'SETTINGS',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode(context)
                                  ? Colors.white54
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                      ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SettingsScreen(),
                            ),
                          );
                        },
                        title: Text(
                          'App Settings',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        leading: Icon(
                          CupertinoIcons.settings,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                      Divider(
                        color: isDarkMode(context)
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                      ),
                      ListTile(
                        onTap: () async {
                          AuthProviders? authProvider;
                          List<auth.UserInfo> userInfoList = auth.FirebaseAuth.instance.currentUser?.providerData ?? [];
                          await Future.forEach(userInfoList, (auth.UserInfo info) {
                            switch (info.providerId) {
                              case 'password':
                                authProvider = AuthProviders.PASSWORD;
                                break;
                              case 'phone':
                                authProvider = AuthProviders.PHONE;
                                break;
                              case 'facebook.com':
                                authProvider = AuthProviders.FACEBOOK;
                                break;
                              case 'apple.com':
                                authProvider = AuthProviders.APPLE;
                                break;
                            }
                          });
                          bool? result = await showDialog(
                            context: context,
                            builder: (context) => ReAuthUserScreen(
                              provider: authProvider!,
                              email: auth.FirebaseAuth.instance.currentUser!.email,
                              phoneNumber: auth.FirebaseAuth.instance.currentUser!.phoneNumber,
                              deleteUser: true,
                            ),
                          );
                          if (result != null && result) {
                            await showProgress(context, "DeletingAccount", false);
                            await FireStoreUtils.deleteUser();
                            await hideProgress();
                            MyAppState.currentUser = null;
                            pushAndRemoveUntil(context, AuthScreen(), false);
                          }
                        },
                        title: Text(
                          'Delete Account',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        leading: Icon(
                          CupertinoIcons.delete,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: double.infinity),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        padding: EdgeInsets.only(top: 12, bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0), side: BorderSide(color: isDarkMode(context) ? Colors.grey.shade700 : Colors.grey.shade200)),
                      ),
                      child: Text(
                        'Logout',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDarkMode(context) ? Colors.white : Colors.black),
                      ),
                      onPressed: () async {
                        user.fcmToken = "";
                        user.lastOnlineTimestamp = Timestamp.now();
                        await FireStoreUtils.updateCurrentUser(user);
                        await auth.FirebaseAuth.instance.signOut();
                        MyAppState.currentUser = null;
                        pushAndRemoveUntil(context, AuthScreen(), false);
                      },
                    ),
                  ),
                ),
              ]),
            ),
    );
  }

  void _navigateIfVendorExists(VoidCallback onNavigate) {
    if (user.vendorID.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please add restaurant first.')),
      );
      return;
    }
    onNavigate();
  }

  _onCameraClick() {
    final action = CupertinoActionSheet(
      message: Text(
        'Add Profile Picture',
        style: TextStyle(fontSize: 15.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: Text('Remove picture'),
          isDestructiveAction: true,
          onPressed: () async {
            Navigator.pop(context);
            showProgress(context, "RemovingPicture", false);
            user.profilePictureURL = '';
            await FireStoreUtils.updateCurrentUser(user);
            MyAppState.currentUser = user;
            hideProgress();
            setState(() {});
          },
        ),
        CupertinoActionSheetAction(
          child: Text('Choose image from gallery'),
          onPressed: () async {
            Navigator.pop(context);
            XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              await _imagePicked(File(image.path));
            }
            setState(() {});
          },
        ),
        CupertinoActionSheetAction(
          child: Text('Take a picture'),
          onPressed: () async {
            Navigator.pop(context);
            XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
            if (image != null) {
              await _imagePicked(File(image.path));
            }
            setState(() {});
          },
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        child: Text('Cancel'),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
    );
    showCupertinoModalPopup(context: context, builder: (context) => action);
  }

  Future<void> _imagePicked(File image) async {
    showProgress(context, "UploadingImage", false);
    user.profilePictureURL = await FireStoreUtils.uploadUserImageToFireStorage(image, user.userID);
    await FireStoreUtils.updateCurrentUser(user);
    MyAppState.currentUser = user;
    hideProgress();
  }
}
