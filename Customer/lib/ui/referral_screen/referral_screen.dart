import 'package:clipboard/clipboard.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/main.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({Key? key}) : super(key: key);

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _debugFirebaseState();
    _ensureReferralCode();
  }

  /// Debug helper to show Firebase configuration state
  void _debugFirebaseState() {
    print('🔍 === FIREBASE STATE DEBUG ===');

    // Check Firebase Auth
    final firebaseUser = auth.FirebaseAuth.instance.currentUser;
    print('🔍 Firebase Auth user: ${firebaseUser?.uid ?? "null"}');
    print('🔍 Firebase Auth email: ${firebaseUser?.email ?? "null"}');
    print('🔍 Firebase Auth verified: ${firebaseUser?.emailVerified ?? false}');

    // Check MyAppState user
    final currentUser = MyAppState.currentUser;
    print('🔍 MyAppState user: ${currentUser?.userID ?? "null"}');
    print('🔍 MyAppState email: ${currentUser?.email ?? "null"}');
    print(
        '🔍 MyAppState referral code: ${currentUser?.referralCode ?? "null"}');

    // Check Firebase Functions
    try {
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      print('🔍 Firebase Functions instance: OK');
    } catch (e) {
      print('🔍 Firebase Functions error: $e');
    }

    print('🔍 === FIREBASE STATE DEBUG END ===');
  }

  /// Ensures the current user has a referral code via Firebase callable
  Future<void> _ensureReferralCode() async {
    final currentUser = MyAppState.currentUser;
    if (currentUser == null) return;

    // Start loading state (non-blocking)
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔥 === FIREBASE CALLABLE DEBUG START ===');
      print(
          '🔥 Calling Firebase createReferralCode function for user: ${currentUser.userID}');
      print('🔥 User email: ${currentUser.email}');
      print('🔥 Current referral code: ${currentUser.referralCode ?? "null"}');

      // Call Firebase callable function
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('createReferralCode');

      print('🔥 Making callable request...');
      final result = await callable.call({
        'userId': currentUser.userID,
      });

      print('🔥 Callable completed successfully');
      print('🔥 Raw result data: ${result.data}');
      print('🔥 Result data type: ${result.data.runtimeType}');

      // Extract code from simple {code} response
      final String? newReferralCode = result.data['code'];

      print('🔥 Extracted referral code: $newReferralCode');

      if (newReferralCode != null) {
        print('✅ Firebase callable returned referral code: $newReferralCode');

        // Only update user if the code actually changed
        if (currentUser.referralCode != newReferralCode) {
          print(
              '🔄 Referral code changed, updating user: ${currentUser.referralCode} → $newReferralCode');

          // Update local user object immediately
          currentUser.referralCode = newReferralCode;
          print('🔥 Local user object updated');

          // Update Firebase (non-blocking - happens in background)
          FireStoreUtils.updateCurrentUser(currentUser).then((_) {
            print('✅ User updated in Firebase with new referral code');
          }).catchError((error) {
            print(
                '❌ Failed to update user in Firebase: $error (continuing anyway)');
          });

          // Trigger UI update immediately (don't wait for Firebase update)
          if (mounted) {
            print('🔥 Triggering UI update');
            setState(() {});
          } else {
            print('⚠️ Widget not mounted, skipping UI update');
          }
        } else {
          print('ℹ️ Referral code unchanged: $newReferralCode');
        }
      } else {
        print('ℹ️ Firebase callable returned null code');
        print('🔥 Full result data: ${result.data}');
        if (result.data.containsKey('disabled')) {
          print('ℹ️ Reason: Generation disabled = ${result.data['disabled']}');
        }
      }

      print('🔥 === FIREBASE CALLABLE DEBUG END ===');
    } catch (e) {
      print('❌ === FIREBASE CALLABLE ERROR DEBUG START ===');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Error message: $e');
      print('❌ Error string: ${e.toString()}');

      // Enhanced error debugging for Firebase Functions
      if (e.toString().contains('FirebaseFunctionsException')) {
        print('❌ This is a FirebaseFunctionsException');
        final errorParts = e.toString().split(',');
        for (String part in errorParts) {
          print('❌ Error detail: ${part.trim()}');
        }
      }

      // Check for specific Firebase error types
      if (e.toString().contains('unauthenticated')) {
        print('❌ SPECIFIC ERROR: User not authenticated with Firebase');
        print('❌ SOLUTION: Ensure user is logged in to Firebase Auth');
      } else if (e.toString().contains('permission-denied')) {
        print('❌ SPECIFIC ERROR: Permission denied');
        print('❌ SOLUTION: Check Firebase security rules or user permissions');
      } else if (e.toString().contains('not-found')) {
        print('❌ SPECIFIC ERROR: Function or resource not found');
        print('❌ SOLUTION: Ensure Firebase function is deployed');
      } else if (e.toString().contains('internal')) {
        print('❌ SPECIFIC ERROR: Internal server error');
        print('❌ SOLUTION: Check Firebase function logs');
      } else if (e.toString().contains('invalid-argument')) {
        print('❌ SPECIFIC ERROR: Invalid argument passed to function');
        print('❌ SOLUTION: Check function parameters');
      } else if (e.toString().contains('network')) {
        print('❌ SPECIFIC ERROR: Network connectivity issue');
        print('❌ SOLUTION: Check internet connection');
      } else {
        print('❌ UNKNOWN ERROR TYPE: $e');
        print('❌ SOLUTION: Check Firebase console and function logs');
      }

      // Show debug information in development
      print('❌ User ID: ${currentUser.userID}');
      print('❌ User email: ${currentUser.email}');
      print('❌ Current referral code: ${currentUser.referralCode ?? "null"}');
      print('❌ User active: ${currentUser.active}');
      print('❌ User role: ${currentUser.role}');

      // Check Firebase Auth state
      try {
        final firebaseUser = auth.FirebaseAuth.instance.currentUser;
        if (firebaseUser != null) {
          print('❌ Firebase Auth user: ${firebaseUser.uid}');
          print('❌ Firebase Auth email: ${firebaseUser.email}');
          print('❌ Firebase Auth verified: ${firebaseUser.emailVerified}');
        } else {
          print('❌ NO FIREBASE AUTH USER - This is likely the problem!');
        }
      } catch (authError) {
        print('❌ Error checking Firebase Auth: $authError');
      }

      // Check Firebase Functions configuration
      try {
        FirebaseFunctions.instanceFor(region: 'asia-southeast1');
        print('❌ Firebase Functions instance: Available');
      } catch (functionsError) {
        print('❌ Error with Firebase Functions: $functionsError');
      }

      print('❌ Stack trace: ${StackTrace.current}');
      print('❌ === FIREBASE CALLABLE ERROR DEBUG END ===');
      print('⚠️ Continuing with existing state (soft failure)');

      // Optional: Show debug info to user in debug mode
      // if (kDebugMode) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(
      //       content: Text('Debug: Firebase callable error - $e'),
      //       backgroundColor: Colors.orange,
      //       duration: Duration(seconds: 3),
      //     ),
      //   );
      // }
    } finally {
      // Always stop loading state
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Color(0xFFFF662E),
          elevation: 0,
          leading: InkWell(
              onTap: () {
                Navigator.pop(context);
              },
              child: Icon(
                Icons.arrow_back,
                color: Colors.white,
              ))),
      body: Consumer<User?>(
        builder: (context, userObj, _) {
          final User? user = userObj;
          // Show loading indicator while backend check is in progress or user is null
          if (_isLoading || user == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(COLOR_PRIMARY)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    user == null
                        ? 'Loading user data...'
                        : 'Setting up your referral code...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          // Display referral information based on backend flags only
          return Column(
            children: [
              Container(
                width: MediaQuery.of(context).size.width,
                decoration: BoxDecoration(
                    image: DecorationImage(
                        image: AssetImage(
                            'assets/images/background_image_referral.png'),
                        fit: BoxFit.cover)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/earn_icon.png',
                        width: 160,
                      ),
                      SizedBox(
                        height: 40,
                      ),
                      Text(
                        "Refer your friends and",
                        style:
                            TextStyle(color: Colors.white, letterSpacing: 1.5),
                      ),
                      SizedBox(
                        height: 8,
                      ),
                      Text(
                        "Earn" +
                            " ${(user.referralRewardAmount ?? referralAmount.toString()).isNotEmpty ? amountShow(amount: user.referralRewardAmount ?? referralAmount.toString()) : amountShow(amount: referralAmount.toString())} " +
                            "each",
                        style: TextStyle(
                            fontSize: 22,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5),
                      ),
                      SizedBox(
                        height: 10,
                      ),
                      // Referral Active Banner - only show if backend says promo is disabled
                      if (user.isPromoDisabled)
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Text(
                            "Referral active → ₱20 promo disabled (mutually exclusive)",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      SizedBox(
                        height: 10,
                      ),
                      // Text(
                      //   referralModel!.referralCode.toString(),
                      //   style: TextStyle(fontSize: 20, color: Colors.black),
                      // ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 50,
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Invite Friend & Businesses",
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.0,
                        fontSize: 18),
                  ),
                  SizedBox(
                    height: 20,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      "Invite Foodie to sign up using your code and you'll get"
                               +
                          " ${amountShow(amount: user.referralRewardAmount ?? referralAmount.toString())}" +
                          "after successfully order complete.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0XFF666666),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.0),
                    ),
                  ),
                  SizedBox(
                    height: 30,
                  ),
                  // Your Referral Code Section
                  Text(
                    "Your Referral Code",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 15),
                  // Referral Code Display with Copy/Share
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final referralCode = user.referralCode;
                            if (referralCode != null &&
                                referralCode.isNotEmpty &&
                                referralCode != "Loading...") {
                              FlutterClipboard.copy(referralCode).then((value) {
                                SnackBar snackBar = SnackBar(
                                  content: Text(
                                    "Referral code copied",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: Colors.green,
                                );
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(snackBar);
                              });
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text("Referral code not ready yet"),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                          child: DottedBorder(
                            borderType: BorderType.RRect,
                            radius: const Radius.circular(8),
                            padding: const EdgeInsets.all(16),
                            color: const Color(COUPON_DASH_COLOR),
                            strokeWidth: 2,
                            dashPattern: const [5],
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: const Color(COUPON_BG_COLOR),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    user.referralCode ?? "Loading...",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: "Poppinsb",
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      letterSpacing: 1.0,
                                      color: Color(COLOR_PRIMARY),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "Tap to copy",
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
                      ),
                    ],
                  ),
                ],
              )
            ],
          );
        },
      ),
    );
  }

}
