import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:intl/intl.dart';
import 'package:foodie_customer/ui/accountDetails/AccountDetailsScreen.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/contactUs/ContactUsScreen.dart';
import 'package:foodie_customer/ui/feedback/FeedbackScreen.dart';
import 'package:foodie_customer/ui/reauthScreen/reauth_user_screen.dart';
import 'package:foodie_customer/ui/referral_screen/referral_screen_new.dart';
import 'package:foodie_customer/ui/ordersScreen/OrdersScreen.dart';
import 'package:foodie_customer/ui/home/favourite_restaurant.dart';
import 'package:foodie_customer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';
import 'package:foodie_customer/services/referral_reward_service.dart';
import 'package:foodie_customer/constants.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ProfileScreen extends StatefulWidget {
  final User user;

  ProfileScreen({Key? key, required this.user}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  late User user;

  @override
  void initState() {
    user = widget.user;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? Color(DARK_COLOR) : null,
      body: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/bg.jpg"), // Set background image
            fit: BoxFit.cover,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 32.0, left: 32, right: 32),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  Center(
                      child: displayCircleImage(
                          user.profilePictureURL, 160, false)),
                  Positioned.directional(
                    textDirection: Directionality.of(context),
                    start: 80,
                    end: 0,
                    child: FloatingActionButton(
                        backgroundColor: Color(COLOR_ACCENT),
                        child: Icon(
                          Icons.camera_alt,
                          color:
                              isDarkMode(context) ? Colors.black : Colors.white,
                        ),
                        mini: true,
                        onPressed: _onCameraClick),
                  )
                ],
              ),
            ),
            SizedBox(
              height: 20,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16.0, right: 32, left: 32),
              child: Text(
                user.fullName(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              height: 80,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: <Widget>[
                  // Cards Row - Orders, Favorites, Addresses
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // Orders Card
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              push(context, OrdersScreen());
                            },
                            child: Container(
                              padding: EdgeInsets.all(16),
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.shopping_bag_outlined,
                                      color: Color(COLOR_PRIMARY),
                                      size: 28,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Orders",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "History",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        // Favorites Card
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              push(context, FavouriteRestaurantScreen());
                            },
                            child: Container(
                              padding: EdgeInsets.all(16),
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.favorite_outline,
                                      color: Color(COLOR_PRIMARY),
                                      size: 28,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Favorites",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "Saved items",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        // Addresses Card
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              push(context, DeliveryAddressScreen());
                            },
                            child: Container(
                              padding: EdgeInsets.all(16),
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      color: Color(COLOR_PRIMARY),
                                      size: 28,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "Addresses",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    "Manage",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    onTap: () {
                      push(context, AccountDetailsScreen(user: user));
                    },
                    title: Text(
                      "Account Details",
                      style: TextStyle(fontSize: 16),
                    ),
                    leading: Icon(
                      CupertinoIcons.person_alt,
                      color: Colors.blue,
                    ),
                  ),
                  // Referral Wallet Balance Display
                  if (user.referralWalletAmount > 0)
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet,
                                  color: Colors.green.shade700, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Referral Wallet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Balance: ${amountShow(amount: user.referralWalletAmount.toStringAsFixed(2))}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'For order use only. Cannot be withdrawn or transferred.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Referral Section
                  ListTile(
                    onTap: () {
                      push(context, ReferralScreen());
                    },
                    title: Text(
                      "Referral Program",
                      style: TextStyle(fontSize: 16),
                    ),
                    leading: Icon(
                      CupertinoIcons.share,
                      color: user.isReferralPath
                          ? Color(COLOR_PRIMARY)
                          : Colors.grey,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show referral status indicators
                        if (user.isReferralPath) ...[
                          // Show referral path active indicator
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "Active",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                        ],
                        if (user.isPromoDisabled) ...[
                          // Show promo disabled indicator
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "Promo OFF",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 4),
                        ],
                        if (user.referralCode != null &&
                            user.referralCode!.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Color(COLOR_PRIMARY).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user.referralCode!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(COLOR_PRIMARY),
                              ),
                            ),
                          ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ],
                    ),
                  ),
                  // ListTile(
                  //   onTap: () {
                  //     push(context, SettingsScreen(user: user));
                  //   },
                  //   title: Text(
                  //     "settings",
                  //     style: TextStyle(fontSize: 16),
                  //   ),
                  //   leading: Icon(
                  //     CupertinoIcons.settings,
                  //     color: Colors.grey,
                  //   ),
                  // ),
                  ListTile(
                    onTap: () {
                      push(context, ContactUsScreen());
                    },
                    title: Text(
                      "Contact Us",
                      style: TextStyle(fontSize: 16),
                    ),
                    leading: Hero(
                      tag: "Contact Us",
                      child: Icon(
                        CupertinoIcons.phone_solid,
                        color: Colors.green,
                      ),
                    ),
                  ),
                  ListTile(
                    onTap: () {
                      push(context, FeedbackScreen());
                    },
                    title: Text(
                      "Feedback & Suggestions",
                      style: TextStyle(fontSize: 16),
                    ),
                    leading: Icon(
                      CupertinoIcons.chat_bubble_text,
                      color: Colors.blue,
                    ),
                  ),
                  ListTile(
                    onTap: () async {
                      AuthProviders? authProvider;
                      List<auth.UserInfo> userInfoList = auth.FirebaseAuth
                              .instance.currentUser?.providerData ??
                          [];
                      await Future.forEach(userInfoList, (auth.UserInfo info) {
                        switch (info.providerId) {
                          case 'password':
                            authProvider = AuthProviders.PASSWORD;
                            break;
                          case 'phone':
                            authProvider = AuthProviders.PHONE;
                            break;
                          case 'apple.com':
                            authProvider = AuthProviders.APPLE;
                            break;
                        }
                      });
                      if (authProvider == null) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Delete account is not available for this '
                                'sign-in method.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      bool? result = await showDialog(
                        context: context,
                        builder: (context) => ReAuthUserScreen(
                          provider: authProvider!,
                          email: auth.FirebaseAuth.instance.currentUser!.email,
                          phoneNumber: auth
                              .FirebaseAuth.instance.currentUser!.phoneNumber,
                          deleteUser: true,
                        ),
                      );
                      if (result != null && result) {
                        await showProgress(
                            context, "Deleting account...", false);
                        await FireStoreUtils.deleteUser();
                        await hideProgress();
                        MyAppState.currentUser = null;
                        pushAndRemoveUntil(context, LoginScreen(), false);
                      }
                    },
                    title: Text(
                      'Delete Account',
                      style: TextStyle(fontSize: 16),
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
                child: TextButton.icon(
                  icon: Icon(
                    Icons.logout,
                    color: Colors.white,
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Color(COLOR_PRIMARY),
                    padding: EdgeInsets.only(top: 12, bottom: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        side: BorderSide(
                            color: isDarkMode(context)
                                ? Colors.grey.shade700
                                : Colors.grey.shade200)),
                  ),
                  label: Text(
                    'Log Out',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  onPressed: () async {
                    //user.active = false;
                    user.lastOnlineTimestamp = Timestamp.now();
                    await FireStoreUtils.updateCurrentUser(user);
                    await auth.FirebaseAuth.instance.signOut();
                    MyAppState.currentUser = null;
                    pushAndRemoveUntil(context, LoginScreen(), false);
                  },
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  _onCameraClick() {
    print('🔄 DEBUG: Camera button clicked');
    final action = CupertinoActionSheet(
      message: Text(
        "Add profile picture",
        style: TextStyle(fontSize: 15.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: Text("Remove Picture"),
          isDestructiveAction: true,
          onPressed: () async {
            Navigator.pop(context);
            showProgress(context, "Removing picture...", false);
            user.profilePictureURL = '';
            await FireStoreUtils.updateCurrentUser(user);
            MyAppState.currentUser = user;
            hideProgress();
            setState(() {});
          },
        ),
        CupertinoActionSheetAction(
          child: Text("Choose from gallery"),
          onPressed: () async {
            print('🔄 DEBUG: Gallery option selected');
            Navigator.pop(context);
            await Future.delayed(const Duration(milliseconds: 300));
            if (!mounted) return;
            try {
              XFile? image =
                  await _imagePicker.pickImage(source: ImageSource.gallery);
              if (!mounted) return;
              if (image != null) {
                print('🔄 DEBUG: Image selected from gallery: ${image.path}');
                await _imagePicked(File(image.path));
              } else {
                print('❌ DEBUG: No image selected from gallery');
              }
              if (!mounted) return;
              setState(() {});
            } catch (e, s) {
              print('ProfileScreen gallery picker: $e $s');
            }
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
    print('🔄 DEBUG: Starting image upload process...');
    print('🔄 DEBUG: Image path: ${image.path}');
    print('🔄 DEBUG: Image exists: ${await image.exists()}');

    try {
      print('🔄 DEBUG: Showing progress dialog...');
      showProgress(context, "Uploading image...", false);

      print('🔄 DEBUG: Starting image compression...');
      File? compressedImage = await FireStoreUtils.compressImage(image);
      print('🔄 DEBUG: Compression completed. Original: ${image.path}');
      print('🔄 DEBUG: Compressed: ${compressedImage?.path ?? 'null'}');

      final bytes = compressedImage?.readAsBytesSync().lengthInBytes;
      final kb = bytes ?? 0 / 1024;
      final mb = kb / 1024;

      print('🔄 DEBUG: File size - Bytes: $bytes, KB: $kb, MB: $mb');
      print(
          '🔄 DEBUG: File size limit removed - proceeding with upload regardless of size');

      print('🔄 DEBUG: Starting Firebase upload...');
      print('🔄 DEBUG: User ID: ${user.userID}');

      // Add timeout to prevent hanging
      user.profilePictureURL =
          await FireStoreUtils.uploadUserImageToFireStorage(
                  compressedImage ?? image, user.userID)
              .timeout(Duration(seconds: 30), onTimeout: () {
        print('❌ DEBUG: Upload timeout after 30 seconds');
        throw TimeoutException('Upload timeout', Duration(seconds: 30));
      });

      print('✅ DEBUG: Firebase upload completed successfully');
      print('✅ DEBUG: New profile URL: ${user.profilePictureURL}');

      print('🔄 DEBUG: Updating user in Firestore...');
      await FireStoreUtils.updateCurrentUser(user);
      print('✅ DEBUG: User updated in Firestore successfully');

      print('🔄 DEBUG: Updating current user in app state...');
      MyAppState.currentUser = user;
      print('✅ DEBUG: App state updated successfully');

      print('🔄 DEBUG: Hiding progress dialog...');
      hideProgress();
      print('✅ DEBUG: Progress dialog hidden successfully');

      print('🔄 DEBUG: Refreshing UI...');
      setState(() {});
      print('✅ DEBUG: UI refreshed successfully');

      print('✅ DEBUG: Image upload process completed successfully!');
    } catch (e, stackTrace) {
      print('❌ DEBUG: Error occurred during image upload: $e');
      print('❌ DEBUG: Stack trace: $stackTrace');

      print('🔄 DEBUG: Attempting to hide progress dialog...');
      try {
        hideProgress();
        print('✅ DEBUG: Progress dialog hidden after error');
      } catch (hideError) {
        print('❌ DEBUG: Failed to hide progress dialog: $hideError');
      }

      print('🔄 DEBUG: Showing error dialog to user...');
      showAlertDialog(context, "Error",
          "Failed to upload image: ${e.toString()}", true);
      print('✅ DEBUG: Error dialog shown to user');
    }
  }
}
