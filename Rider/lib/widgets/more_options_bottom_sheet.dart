import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/attendance_service.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/ui/auth/AuthScreen.dart';
import 'package:foodie_driver/ui/privacy_policy/privacy_policy.dart';
import 'package:foodie_driver/ui/termsAndCondition/terms_and_codition.dart';
import 'package:provider/provider.dart';

class MoreOptionsBottomSheet extends StatelessWidget {
  final VoidCallback onDriverRankingTap;
  final VoidCallback onInboxTap;
  final VoidCallback onLocationUpdate;

  const MoreOptionsBottomSheet({
    Key? key,
    required this.onDriverRankingTap,
    required this.onInboxTap,
    required this.onLocationUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Consumer<User>(
        builder: (context, user, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  displayCircleImage(user.profilePictureURL, 50, false),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: Text(
                "Online",
                style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
              value: user.isActive,
              onChanged: (value) async {
                final latestUser =
                    await AttendanceService.fetchLatestUser(user.userID);
                if (latestUser != null) {
                  MyAppState.currentUser = latestUser;
                }

                final current = latestUser ?? user;
                final isSuspended = current.suspended == true ||
                    (current.attendanceStatus?.toLowerCase() == 'suspended');
                if (isSuspended) {
                  _showSuspendedDialog(context);
                  return;
                }

                await AttendanceService.touchLastActiveDate(current);

                user.isActive = value;
                user.inProgressOrderID =
                    MyAppState.currentUser!.inProgressOrderID;
                user.orderRequestData =
                    MyAppState.currentUser!.orderRequestData;
                if (user.isActive == true) {
                  onLocationUpdate();
                }
                FireStoreUtils.updateCurrentUser(user);
              },
            ),
            SwitchListTile(
              title: Text(
                "Multiple Orders",
                style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
              value: user.multipleOrders,
              onChanged: (value) {
                user.multipleOrders = value;
                FireStoreUtils.updateCurrentUser(user);
              },
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.emoji_events),
              title: Text('Driver Ranking'),
              onTap: () {
                Navigator.pop(context);
                onDriverRankingTap();
              },
            ),
            ListTile(
              leading: Icon(CupertinoIcons.chat_bubble_2_fill),
              title: Text('Inbox'),
              onTap: () {
                Navigator.pop(context);
                if (MyAppState.currentUser == null) {
                  push(context, AuthScreen());
                } else {
                  onInboxTap();
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.policy),
              title: Text('Terms and Condition'),
              onTap: () {
                Navigator.pop(context);
                push(context, const TermsAndCondition());
              },
            ),
            ListTile(
              leading: Icon(Icons.privacy_tip),
              title: Text('Privacy policy'),
              onTap: () {
                Navigator.pop(context);
                push(context, const PrivacyPolicyScreen());
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red),
              title: Text('Log out', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                user.lastOnlineTimestamp = Timestamp.now();
                await FireStoreUtils.updateCurrentUser(user);
                await auth.FirebaseAuth.instance.signOut();
                MyAppState.currentUser = null;
                pushAndRemoveUntil(context, AuthScreen(), false);
              },
            ),
          ],
        ),
      ),
    );
  }

  static void show(
    BuildContext context, {
    required VoidCallback onDriverRankingTap,
    required VoidCallback onInboxTap,
    required VoidCallback onLocationUpdate,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => MoreOptionsBottomSheet(
        onDriverRankingTap: onDriverRankingTap,
        onInboxTap: onInboxTap,
        onLocationUpdate: onLocationUpdate,
      ),
    );
  }

  void _showSuspendedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Account Suspended'),
        content: SelectableText.rich(
          TextSpan(
            text:
                'Your account is currently suspended. Please contact the '
                'administrator to restore access.',
            style: const TextStyle(color: Colors.red),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
