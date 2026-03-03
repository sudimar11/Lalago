import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/ui/accountDetails/AccountDetailsScreen.dart';
import 'package:foodie_driver/ui/auth/AuthScreen.dart';
import 'package:foodie_driver/ui/contactUs/ContactUsScreen.dart';
import 'package:foodie_driver/ui/reauthScreen/reauth_user_screen.dart';
import 'package:foodie_driver/ui/ordersScreen/OrdersBlankScreen.dart';
import 'package:foodie_driver/ui/profile/zone_browser_screen.dart';
import 'package:foodie_driver/ui/wallet/wallet_detail_page.dart';
import 'package:foodie_driver/widgets/more_options_bottom_sheet.dart';
import 'package:foodie_driver/userPrefrence.dart';
import 'package:foodie_driver/widgets/attendance_card.dart';
import 'package:foodie_driver/widgets/time_input_dialog.dart';
import 'package:foodie_driver/services/time_tracking_service.dart';
import 'package:foodie_driver/services/driver_performance_service.dart';
import 'package:foodie_driver/services/performance_tier_helper.dart';
import 'package:foodie_driver/services/rider_preset_location_service.dart';
import 'package:foodie_driver/ui/profile/AttendanceHistoryScreen.dart';
import 'package:foodie_driver/widgets/shared_app_bar.dart';
import 'package:foodie_driver/services/order_service.dart';

class ProfileScreen extends StatefulWidget {
  final User user;
  final bool showNavigationBar;

  ProfileScreen({Key? key, required this.user, this.showNavigationBar = false})
      : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSavingCheckIn = false;
  bool _isSavingCheckOut = false;
  bool _isSavingCheckOutToday = false;
  RiderPresetLocationData? _currentZone;
  bool _isLoadingZone = true;

  Future<void> _loadCurrentZone() async {
    final presetId =
        MyAppState.currentUser?.selectedPresetLocationId;
    if (presetId == null || presetId.trim().isEmpty) {
      if (mounted) setState(() => _isLoadingZone = false);
      return;
    }
    try {
      final zone =
          await RiderPresetLocationService.getPresetById(presetId);
      if (mounted) {
        setState(() {
          _currentZone = zone;
          _isLoadingZone = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingZone = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentZone();

    // Initialize fields if they don't exist in global user object
    if (MyAppState.currentUser!.checkInTime == null) {
      print('🆕 DEBUG: checkInTime field does not exist, initializing...');
      MyAppState.currentUser!.checkInTime = '';
    }

    if (MyAppState.currentUser!.checkOutTime == null) {
      print('🆕 DEBUG: checkOutTime field does not exist, initializing...');
      MyAppState.currentUser!.checkOutTime = '';
    }

    if (MyAppState.currentUser!.checkedInToday == null) {
      print('🆕 DEBUG: checkedInToday field does not exist, initializing...');
      MyAppState.currentUser!.checkedInToday = false;
    }

    if (MyAppState.currentUser!.isOnline == null) {
      MyAppState.currentUser!.isOnline =
          MyAppState.currentUser!.checkedInToday ?? false;
    }

    if (MyAppState.currentUser!.todayCheckInTime == null) {
      print('🆕 DEBUG: todayCheckInTime field does not exist, initializing...');
      MyAppState.currentUser!.todayCheckInTime = '';
    }

    if (MyAppState.currentUser!.todayCheckOutTime == null) {
      print(
          '🆕 DEBUG: todayCheckOutTime field does not exist, initializing...');
      MyAppState.currentUser!.todayCheckOutTime = '';
    }

    if (MyAppState.currentUser!.checkedOutToday == null) {
      print('🆕 DEBUG: checkedOutToday field does not exist, initializing...');
      MyAppState.currentUser!.checkedOutToday = false;
    }

    // Check if we need to reset daily check-in status (new day)
    _checkAndResetDailyStatus();

    // Initialize performance score if not set
    if (MyAppState.currentUser!.driverPerformance == null) {
      DriverPerformanceService.initializePerformance(
          MyAppState.currentUser!.userID);
      MyAppState.currentUser!.driverPerformance = 75.0;
    }
  }

  @override
  void dispose() {
    // Ensure any pending changes are saved when screen closes
    _saveUserDataIfNeeded();
    super.dispose();
  }

  Future<void> _saveUserDataIfNeeded() async {
    try {
      // Check if there are any unsaved changes
      if (MyAppState.currentUser != null) {
        await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
        print('✅ DEBUG: User data saved on screen dispose');
      }
    } catch (e) {
      print('❌ DEBUG: Error saving user data on dispose: $e');
    }
  }

  Future<void> _refreshProfile() async {
    try {
      // Reload user data from Firebase
      if (MyAppState.currentUser != null) {
        // Only preserve SCHEDULED check-in/check-out times
        // Today's actual status should come from the backend
        String? preservedCheckInTime = MyAppState.currentUser!.checkInTime;
        String? preservedCheckOutTime = MyAppState.currentUser!.checkOutTime;

        final updatedUser = await FireStoreUtils.getCurrentUser(
          MyAppState.currentUser!.userID,
        );

        if (updatedUser != null) {
          // Restore only scheduled times if they were lost during the fetch
          if (preservedCheckInTime != null && preservedCheckInTime.isNotEmpty) {
            updatedUser.checkInTime = preservedCheckInTime;
          }
          if (preservedCheckOutTime != null &&
              preservedCheckOutTime.isNotEmpty) {
            updatedUser.checkOutTime = preservedCheckOutTime;
          }
          // NOTE: We intentionally do NOT restore today's status here
          // The backend data is the source of truth for today's check-in

          MyAppState.currentUser = updatedUser;
        }
      }

      // Check and reset daily status if needed
      await _checkAndResetDailyStatus();

      // Update UI
      setState(() {});
    } catch (e) {
      print('❌ Error refreshing profile: $e');
    }
  }

  Future<void> _openZoneBrowser() async {
    final result = await Navigator.push<RiderPresetLocationData>(
      context,
      MaterialPageRoute(
        builder: (_) => const ZoneBrowserScreen(),
      ),
    );
    if (result != null && mounted) {
      setState(() => _currentZone = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Work area changed to ${result.name}',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _refreshProfile,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 32.0, left: 32, right: 32),
            child: SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      Center(
                          child: displayCircleImage(
                              MyAppState.currentUser!.profilePictureURL,
                              130,
                              false)),
                      Positioned.directional(
                        textDirection: Directionality.of(context),
                        start: 80,
                        end: 0,
                        child: FloatingActionButton(
                            heroTag: 'userImage',
                            backgroundColor: Color(COLOR_ACCENT),
                            child: Icon(
                              Icons.camera_alt,
                              color: isDarkMode(context)
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            mini: true,
                            onPressed: () => _onCameraClick(true)),
                      )
                    ],
                  ),
                  Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      Center(
                          child: displayCarImage(
                              MyAppState.currentUser!.carPictureURL,
                              130,
                              false)),
                      Positioned.directional(
                        textDirection: Directionality.of(context),
                        start: 80,
                        end: 0,
                        child: FloatingActionButton(
                            heroTag: 'carImage',
                            backgroundColor: Color(COLOR_ACCENT),
                            child: Icon(
                              Icons.camera_alt,
                              color: isDarkMode(context)
                                  ? Colors.black
                                  : Colors.white,
                            ),
                            mini: true,
                            onPressed: () => _onCameraClick(false)),
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16.0, right: 32, left: 32),
            child: Text(
              MyAppState.currentUser!.fullName(),
              style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                  fontSize: 20),
              textAlign: TextAlign.center,
            ),
          ),
          // Attendance Card
          AttendanceCard(
            checkInTime: MyAppState.currentUser!.checkInTime,
            checkOutTime: MyAppState.currentUser!.checkOutTime,
            totalHours: _calculateTotalHours(),
            onCheckInTap: _updateCheckInTime,
            onCheckOutTap: _updateCheckOutTime,
            canCheckInToday: _canCheckInToday(),
            onCheckInTodayTap: _handleCheckInToday,
            checkedInToday: MyAppState.currentUser!.checkedInToday,
            todayCheckInTime: MyAppState.currentUser!.todayCheckInTime,
            canCheckOutToday: _canCheckOutToday(),
            onCheckOutTodayTap: _handleCheckOutToday,
            checkedOutToday: MyAppState.currentUser!.checkedOutToday,
            todayCheckOutTime: MyAppState.currentUser!.todayCheckOutTime,
            isLate: _checkIfLate()['isLate'],
            hoursLate: _checkIfLate()['hoursLate'],
            lateMessage: _checkIfLate()['message'],
          ),
          // Activity Overview Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Activity Overview',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDarkMode(context)
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Excuse Button Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: FutureBuilder<int>(
              future: _getRemainingExcuses(),
              builder: (context, snapshot) {
                final remainingExcuses = snapshot.data ?? 0;
                final hasCredits = remainingExcuses > 0;
                final today =
                    DateFormat('yyyy-MM-dd').format(DateTime.now());
                final isAlreadyExcused =
                    MyAppState.currentUser?.excusedDays?.contains(today) ??
                        false;

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: hasCredits && !isAlreadyExcused
                        ? () => _handleExcuse()
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isAlreadyExcused
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : (hasCredits
                                      ? Color(COLOR_ACCENT)
                                          .withValues(alpha: 0.12)
                                      : Colors.grey.withValues(alpha: 0.12)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isAlreadyExcused
                                  ? Icons.check_circle
                                  : Icons.calendar_today_outlined,
                              color: isAlreadyExcused
                                  ? Colors.green
                                  : (hasCredits
                                      ? Color(COLOR_ACCENT)
                                      : Colors.grey),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Excuse for Today',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isAlreadyExcused
                                      ? 'You\'re excused for today'
                                      : hasCredits
                                          ? 'Remaining: $remainingExcuses'
                                          : 'No credits left',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDarkMode(context)
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!isAlreadyExcused && hasCredits)
                            Text(
                              'Use',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(COLOR_ACCENT),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(MyAppState.currentUser!.userID)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data()
                  as Map<String, dynamic>? ??
                  {};
              final perf =
                  (data['driver_performance'] as num?)
                      ?.toDouble() ??
                  75.0;
              final accRate =
                  (data['acceptance_rate'] as num?)
                      ?.toDouble();
              final avgRating =
                  (data['average_rating'] as num?)
                      ?.toDouble();
              final attScore =
                  (data['attendance_score'] as num?)
                      ?.toDouble();
              final tier = PerformanceTierHelper.getTier(perf);
              final tierConfig =
                  PerformanceTierHelper.defaultConfig;

              double? nextThreshold;
              String? nextTierName;
              if (perf < tierConfig.bronzeThreshold) {
                nextThreshold = tierConfig.bronzeThreshold;
                nextTierName = 'Bronze';
              } else if (perf < tierConfig.silverThreshold) {
                nextThreshold = tierConfig.silverThreshold;
                nextTierName = 'Silver';
              } else if (perf < tierConfig.goldThreshold) {
                nextThreshold = tierConfig.goldThreshold;
                nextTierName = 'Gold';
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: tier.color
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.trending_up,
                                color: tier.color,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Performance Score',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDarkMode(context)
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .baseline,
                                    textBaseline:
                                        TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '${perf.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight:
                                              FontWeight.bold,
                                          color: tier.color,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding:
                                            const EdgeInsets
                                                .symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: tier.color
                                              .withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius:
                                              BorderRadius
                                                  .circular(8),
                                        ),
                                        child: Text(
                                          tier.name,
                                          style: TextStyle(
                                            color: tier.color,
                                            fontWeight:
                                                FontWeight.w600,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Performance Breakdown',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildMetricRow(
                              context,
                              'Acceptance Rate',
                              accRate != null
                                  ? '${accRate.toStringAsFixed(1)}%'
                                  : '--',
                              accRate ?? 0,
                              100,
                              Colors.blue,
                            ),
                            const SizedBox(height: 8),
                            _buildMetricRow(
                              context,
                              'Customer Rating',
                              avgRating != null
                                  ? '${avgRating.toStringAsFixed(1)}/5'
                                  : '--',
                              avgRating ?? 0,
                              5,
                              Colors.amber,
                            ),
                            const SizedBox(height: 8),
                            _buildMetricRow(
                              context,
                              'Attendance',
                              attScore != null
                                  ? '${attScore.toStringAsFixed(1)}%'
                                  : '--',
                              attScore ?? 0,
                              100,
                              Colors.green,
                            ),
                            if (nextTierName != null &&
                                nextThreshold != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isDarkMode(context)
                                      ? Colors.blueGrey.shade800
                                      : Colors.blue.shade50,
                                  borderRadius:
                                      BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${(nextThreshold - perf).toStringAsFixed(1)} points to $nextTierName',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode(context)
                                        ? Colors.blue.shade200
                                        : Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              'Gold: +20% per delivery  |  '
                              'Silver: +10%  |  '
                              'Bronze: base rate',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500,
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
          ),
          // Today's Bonus Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: FutureBuilder<Map<String, dynamic>>(
              future: Future.wait([
                _getTodayIncentiveSummary(),
                _getQualifiedStatus(),
                _isAlreadyClaimedToday(),
              ]).then((results) => {
                    'incentiveSummary': results[0],
                    'qualifiedStatus': results[1],
                    'alreadyClaimed': results[2],
                  }),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }

                final data = snapshot.data ??
                    {
                      'incentiveSummary': {
                        'ordersCount': 0,
                        'totalIncentive': 0.0
                      },
                      'qualifiedStatus': {
                        'isQualified': false,
                        'hoursOnline': 0.0,
                        'qualifiedTime': 5,
                        'checkedOutToday': false,
                      },
                      'alreadyClaimed': false,
                    };

                final incentiveSummary =
                    data['incentiveSummary'] as Map<String, dynamic>;
                final qualifiedStatus =
                    data['qualifiedStatus'] as Map<String, dynamic>;
                final alreadyClaimed = data['alreadyClaimed'] as bool;

                final totalIncentive =
                    (incentiveSummary['totalIncentive'] as num).toDouble();
                final isQualified = qualifiedStatus['isQualified'] as bool;
                final hoursOnline =
                    (qualifiedStatus['hoursOnline'] as num).toDouble();
                final qualifiedTime =
                    (qualifiedStatus['qualifiedTime'] as num).toInt();
                final checkedOutToday =
                    qualifiedStatus['checkedOutToday'] as bool? ?? false;

                final canClaim = totalIncentive > 0 &&
                    isQualified &&
                    !alreadyClaimed &&
                    checkedOutToday;
                final progress = qualifiedTime > 0
                    ? (hoursOnline / qualifiedTime).clamp(0.0, 1.0)
                    : 0.0;

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.card_giftcard,
                                color: Colors.orange.shade700,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Today\'s Bonus',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDarkMode(context)
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₱${totalIncentive.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 36,
                              child: ElevatedButton(
                                onPressed: canClaim
                                    ? () => _claimIncentive(
                                          totalIncentive,
                                          isQualified,
                                        )
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: canClaim
                                      ? Colors.orange
                                      : Colors.grey.shade300,
                                  foregroundColor:
                                      canClaim ? Colors.white : Colors.grey,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  alreadyClaimed
                                      ? 'Claimed'
                                      : 'Claim',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Progress bar for hours
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${hoursOnline.toStringAsFixed(1)}h / ${qualifiedTime}h online',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              isQualified ? 'Qualified ✓' : 'Not qualified',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isQualified
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isQualified
                                  ? Colors.green.shade600
                                  : Colors.orange.shade400,
                            ),
                          ),
                        ),
                        if (totalIncentive > 0 &&
                            hoursOnline >= qualifiedTime &&
                            !alreadyClaimed &&
                            !checkedOutToday) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Check out today to claim your bonus.',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: <Widget>[
                ListTile(
                  onTap: () {
                    push(context, const AttendanceHistoryScreen());
                  },
                  title: Text(
                    'Attendance History',
                    style: TextStyle(fontSize: 16),
                  ),
                  leading: Icon(
                    CupertinoIcons.calendar,
                    color: Colors.purple,
                  ),
                ),
                ListTile(
                  onTap: () {
                    push(context,
                        AccountDetailsScreen(user: MyAppState.currentUser!));
                  },
                  title: Text(
                    'Account Details',
                    style: TextStyle(fontSize: 16),
                  ),
                  leading: Icon(
                    CupertinoIcons.person_alt,
                    color: Colors.blue,
                  ),
                ),
                _WorkAreaCard(
                  currentZone: _currentZone,
                  isLoading: _isLoadingZone,
                  onBrowseZones: _openZoneBrowser,
                ),
                // ListTile(
                //   onTap: () {
                //     push(context, SettingsScreen(user: user));
                //   },
                //   title: Text(
                //     'Settings',
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
                    'Contact Us',
                    style: TextStyle(fontSize: 16),
                  ),
                  leading: Hero(
                    tag: 'contactUs',
                    child: Icon(
                      CupertinoIcons.phone_solid,
                      color: Colors.green,
                    ),
                  ),
                ),
                ListTile(
                  onTap: () async {
                    AuthProviders? authProvider;
                    List<auth.UserInfo> userInfoList =
                        auth.FirebaseAuth.instance.currentUser?.providerData ??
                            [];
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
                        phoneNumber:
                            auth.FirebaseAuth.instance.currentUser!.phoneNumber,
                        deleteUser: true,
                      ),
                    );
                    if (result != null && result) {
                      await showProgress(
                          context, 'Deleting account...', false);
                      await FireStoreUtils.deleteUser();
                      await hideProgress();
                      MyAppState.currentUser = null;
                      pushAndRemoveUntil(context, AuthScreen(), false);
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
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  padding: EdgeInsets.only(top: 12, bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    side: BorderSide(
                        color: isDarkMode(context)
                            ? Colors.grey.shade700
                            : Colors.grey.shade200),
                  ),
                ),
                child: Text(
                  'Logout',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context) ? Colors.white : Colors.black),
                ),
                onPressed: () async {
                  //user.isActive = false;
                  final u = MyAppState.currentUser!;
                  u.lastOnlineTimestamp = Timestamp.now();
                  await FireStoreUtils.updateCurrentUser(u);
                  if (u.fcmToken.isNotEmpty) {
                    unawaited(FireStoreUtils.removeFcmToken(u.userID, u.fcmToken));
                  }
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

  @override
  Widget build(BuildContext context) {
    // When embedded in ContainerScreen (showNavigationBar = false),
    // don't use Scaffold as ContainerScreen already provides it
    if (!widget.showNavigationBar) {
      return _buildBody();
    }

    // When used standalone (showNavigationBar = true), use Scaffold
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      appBar: SharedAppBar(
        title: 'My Profile',
        user: widget.user,
      ),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: 3, // Profile is index 3
        onTap: (index) {
          switch (index) {
            case 0:
              // Navigate to Home
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => OrdersBlankScreen(),
                ),
              );
              break;
            case 1:
              // Navigate to Orders
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => OrdersBlankScreen(),
                ),
              );
              break;
            case 2:
              // Navigate to Wallet
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const WalletDetailPage(
                    walletType: 'earning',
                  ),
                ),
              );
              break;
            case 3:
              // Already on Profile, do nothing
              break;
            case 4:
              // Show More options
              MoreOptionsBottomSheet.show(
                context,
                onDriverRankingTap: () {
                  // Handle driver ranking navigation if needed
                },
                onInboxTap: () {
                  // Handle inbox navigation if needed
                },
                onLocationUpdate: () {
                  // Handle location update if needed
                },
              );
              break;
          }
        },
        backgroundColor: Colors.black,
        selectedItemColor: Color(COLOR_PRIMARY),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: TextStyle(fontSize: 12),
        unselectedLabelStyle: TextStyle(fontSize: 12),
        items: [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_sharp),
            label: 'Wallet',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }

  _onCameraClick(bool isUserImage) async {
    // Check permissions first
    final permission = await Permission.photos.request();
    if (permission != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Permission denied. Please enable photo access in settings.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final action = CupertinoActionSheet(
      message: Text(
        isUserImage ? 'Add Profile Picture' : 'Add Car Picture',
        style: TextStyle(fontSize: 15.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: Text('Remove picture'),
          isDestructiveAction: true,
          onPressed: () async {
            Navigator.pop(context);
            showProgress(context, 'Removing Picture...', false);
            isUserImage
                ? MyAppState.currentUser!.profilePictureURL = ''
                : MyAppState.currentUser!.carPictureURL = '';
            await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
            hideProgress();
            setState(() {});
          },
        ),
        CupertinoActionSheetAction(
          child: Text('Choose image from gallery'),
          onPressed: () async {
            Navigator.pop(context);
            XFile? image =
                await _imagePicker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              await _imagePicked(File(image.path), isUserImage);
            }
            setState(() {});
          },
        ),
        CupertinoActionSheetAction(
          child: Text('Take a picture'),
          onPressed: () async {
            Navigator.pop(context);
            XFile? image =
                await _imagePicker.pickImage(source: ImageSource.camera);
            if (image != null) {
              await _imagePicked(File(image.path), isUserImage);
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

  Future<void> _imagePicked(File image, bool isUserImage) async {
    try {
      // Validate image file
      if (!await image.exists()) {
        throw Exception('Image file does not exist');
      }

      // Check file size (10MB limit)
      final fileSize = await image.length();
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception(
            'Image file is too large. Please choose a smaller image.');
      }

      showProgress(
          context,
          isUserImage
              ? 'Uploading image...'
              : 'Uploading car image...',
          false);

      String? imageUrl;
      if (isUserImage) {
        imageUrl = await FireStoreUtils.uploadUserImageToFireStorage(
            image, MyAppState.currentUser!.userID);
        MyAppState.currentUser!.profilePictureURL = imageUrl;
      } else {
        imageUrl = await FireStoreUtils.uploadCarImageToFireStorage(
            image, MyAppState.currentUser!.userID);
        MyAppState.currentUser!.carPictureURL = imageUrl;
      }

      // Verify upload was successful
      if (imageUrl.isNotEmpty) {
        await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image uploaded successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception('Failed to upload image - no URL returned');
      }
    } catch (e) {
      print('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      hideProgress();
    }
  }

  Future<void> _updateCheckInTime() async {
    // Check if check-in time is already set
    if (MyAppState.currentUser!.checkInTime != null &&
        MyAppState.currentUser!.checkInTime!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Check-in time has already been set and cannot be changed'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    print('🔄 DEBUG: Opening time input dialog');
    showDialog(
      context: context,
      builder: (context) => TimeInputDialog(
        currentTime: MyAppState.currentUser!.checkInTime,
        onTimeSelected: (selectedTime) async {
          print('🕐 DEBUG: Time selected: $selectedTime');
          print('🕐 DEBUG: selectedTime value: "$selectedTime"');
          print('🕐 DEBUG: selectedTime length: ${selectedTime.length}');
          print('🕐 DEBUG: selectedTime isEmpty: ${selectedTime.isEmpty}');
          print('👤 DEBUG: Current user ID: ${MyAppState.currentUser!.userID}');
          print(
              '👤 DEBUG: Current user email: ${MyAppState.currentUser!.email}');

          // Prevent multiple rapid saves
          if (_isSavingCheckIn) {
            print(
                '⚠️ DEBUG: Check-in save already in progress, ignoring duplicate request');
            return;
          }

          try {
            print('⏳ DEBUG: Starting to save check-in time...');

            // Validate time format
            if (!_isValidTimeFormat(selectedTime)) {
              print('❌ DEBUG: Invalid time format: $selectedTime');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Invalid time format. Please use format like "8:00 AM" or "08:30 PM"'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }

            // Check if this is the first time setting checkInTime
            bool isFirstTime = MyAppState.currentUser!.checkInTime == null ||
                MyAppState.currentUser!.checkInTime!.isEmpty;
            if (isFirstTime) {
              print('🆕 DEBUG: Creating checkInTime field for the first time');
            } else {
              print('🔄 DEBUG: Updating existing checkInTime field');
            }

            _isSavingCheckIn = true;
            showProgress(context, 'Saving check-in time...', false);

            // Update global user object with the selected time
            print(
                '📝 DEBUG: Before setting checkInTime: ${MyAppState.currentUser!.checkInTime}');
            MyAppState.currentUser!.checkInTime = selectedTime;
            print(
                '📝 DEBUG: After setting checkInTime: ${MyAppState.currentUser!.checkInTime}');
            print(
                '📝 DEBUG: User object keys: ${MyAppState.currentUser!.toJson().keys.toList()}');
            print(
                '📝 DEBUG: User object checkInTime field: ${MyAppState.currentUser!.toJson()['checkInTime']}');

            // Save to Firebase with enhanced debugging
            print(
                '🔥 DEBUG: About to call FireStoreUtils.updateCurrentUser...');
            print(
                '🔥 DEBUG: Full user object: ${MyAppState.currentUser!.toJson()}');

            print('🔥 DEBUG: Calling FireStoreUtils.updateCurrentUser now...');
            var result =
                await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!)
                    .timeout(
              Duration(seconds: 30),
              onTimeout: () {
                throw Exception('Save operation timed out after 30 seconds');
              },
            );
            print(
                '🔥 DEBUG: FireStoreUtils.updateCurrentUser returned: $result');
            print(
                '✅ DEBUG: FireStoreUtils.updateCurrentUser completed successfully');

            // Update UI
            setState(() {});
            print('🔄 DEBUG: setState called');

            hideProgress();
            print('✅ DEBUG: Check-in time saved successfully!');
            if (isFirstTime) {
              print(
                  '🎉 DEBUG: checkInTime field created successfully in Firebase!');
            }
            print(
                '🔄 DEBUG: Dialog will close automatically after successful save');
          } catch (e) {
            print('❌ DEBUG: Error in _updateCheckInTime: $e');
            print('❌ DEBUG: Error type: ${e.runtimeType}');
            print('❌ DEBUG: Stack trace: ${e.toString()}');
            hideProgress();

            // Show error to user
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save check-in time: $e'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          } finally {
            _isSavingCheckIn = false;
          }
        },
      ),
    );
  }

  Future<void> _updateCheckOutTime() async {
    // Check if check-out time is already set
    if (MyAppState.currentUser!.checkOutTime != null &&
        MyAppState.currentUser!.checkOutTime!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Check-out time has already been set and cannot be changed'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    print('🔄 DEBUG: Opening check-out time input dialog');
    showDialog(
      context: context,
      builder: (context) => TimeInputDialog(
        currentTime: MyAppState.currentUser!.checkOutTime,
        onTimeSelected: (selectedTime) async {
          print('🕐 DEBUG: Check-out time selected: $selectedTime');
          print('🕐 DEBUG: selectedTime value: "$selectedTime"');
          print('🕐 DEBUG: selectedTime length: ${selectedTime.length}');
          print('🕐 DEBUG: selectedTime isEmpty: ${selectedTime.isEmpty}');
          print('👤 DEBUG: Current user ID: ${MyAppState.currentUser!.userID}');
          print(
              '👤 DEBUG: Current user email: ${MyAppState.currentUser!.email}');

          // Prevent multiple rapid saves
          if (_isSavingCheckOut) {
            print(
                '⚠️ DEBUG: Check-out save already in progress, ignoring duplicate request');
            return;
          }

          try {
            print('⏳ DEBUG: Starting to save check-out time...');

            // Validate time format
            if (!_isValidTimeFormat(selectedTime)) {
              print('❌ DEBUG: Invalid time format: $selectedTime');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Invalid time format. Please use format like "5:00 PM" or "17:30 PM"'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }

            // Validate check-in time exists
            if (MyAppState.currentUser!.checkInTime == null ||
                MyAppState.currentUser!.checkInTime!.isEmpty) {
              print(
                  '❌ DEBUG: Check-in time is not set, cannot set check-out time');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Please set your check-in time first before setting check-out time'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }

            // Validate time difference (minimum 6 hours)
            if (!_isValidTimeDifference(
                MyAppState.currentUser!.checkInTime!, selectedTime)) {
              print(
                  '❌ DEBUG: Check-out time is less than 6 hours after check-in time');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Check-out time must be at least 6 hours after check-in time'),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 4),
                ),
              );
              return;
            }

            // Check if this is the first time setting checkOutTime
            bool isFirstTime = MyAppState.currentUser!.checkOutTime == null ||
                MyAppState.currentUser!.checkOutTime!.isEmpty;
            if (isFirstTime) {
              print('🆕 DEBUG: Creating checkOutTime field for the first time');
            } else {
              print('🔄 DEBUG: Updating existing checkOutTime field');
            }

            _isSavingCheckOut = true;
            showProgress(context, 'Saving check-out time...', false);

            // Update global user object with enhanced debugging
            print(
                '📝 DEBUG: Before setting checkOutTime: ${MyAppState.currentUser!.checkOutTime}');

            // Set the selected time
            MyAppState.currentUser!.checkOutTime = selectedTime;
            print(
                '📝 DEBUG: After setting checkOutTime: ${MyAppState.currentUser!.checkOutTime}');
            print(
                '📝 DEBUG: User object keys: ${MyAppState.currentUser!.toJson().keys.toList()}');
            print(
                '📝 DEBUG: User object checkOutTime field: ${MyAppState.currentUser!.toJson()['checkOutTime']}');

            // Save to Firebase with enhanced debugging
            print(
                '🔥 DEBUG: About to call FireStoreUtils.updateCurrentUser...');
            print(
                '🔥 DEBUG: Full user object: ${MyAppState.currentUser!.toJson()}');

            print('🔥 DEBUG: Calling FireStoreUtils.updateCurrentUser now...');
            var result =
                await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!)
                    .timeout(
              Duration(seconds: 30),
              onTimeout: () {
                throw Exception('Save operation timed out after 30 seconds');
              },
            );
            print(
                '🔥 DEBUG: FireStoreUtils.updateCurrentUser returned: $result');
            print(
                '✅ DEBUG: FireStoreUtils.updateCurrentUser completed successfully');

            // Update UI
            setState(() {});
            print('🔄 DEBUG: setState called');

            hideProgress();
            print('✅ DEBUG: Check-out time saved successfully!');
            if (isFirstTime) {
              print(
                  '🎉 DEBUG: checkOutTime field created successfully in Firebase!');
            }
            print(
                '🔄 DEBUG: Dialog will close automatically after successful save');
          } catch (e) {
            print('❌ DEBUG: Error in _updateCheckOutTime: $e');
            print('❌ DEBUG: Error type: ${e.runtimeType}');
            print('❌ DEBUG: Stack trace: ${e.toString()}');
            hideProgress();

            // Show error to user
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save check-out time: $e'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          } finally {
            _isSavingCheckOut = false;
          }
        },
      ),
    );
  }

  // Helper method to validate time format (h:mm a or hh:mm a)
  bool _isValidTimeFormat(String timeString) {
    try {
      final parts = timeString.split(' ');
      if (parts.length == 2) {
        final timePart = parts[0];
        final period = parts[1].toLowerCase();

        // Check period is am or pm
        if (period != 'am' && period != 'pm') {
          return false;
        }

        // Check time format (h:mm or hh:mm)
        final timeParts = timePart.split(':');
        if (timeParts.length == 2) {
          final hour = int.tryParse(timeParts[0]);
          final minute = int.tryParse(timeParts[1]);

          // Validate hour (1-12) and minute (0-59)
          if (hour != null &&
              minute != null &&
              hour >= 1 &&
              hour <= 12 &&
              minute >= 0 &&
              minute <= 59) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Helper method to parse time string to DateTime
  DateTime _parseTimeString(String timeString) {
    try {
      final parts = timeString.split(' ');
      if (parts.length == 2) {
        final timePart = parts[0];
        final period = parts[1];
        final timeParts = timePart.split(':');
        if (timeParts.length == 2) {
          int hour = int.parse(timeParts[0]);
          int minute = int.parse(timeParts[1]);

          if (period.toLowerCase() == 'pm' && hour != 12) {
            hour += 12;
          } else if (period.toLowerCase() == 'am' && hour == 12) {
            hour = 0;
          }

          // Create DateTime for today with the parsed time
          final now = DateTime.now();
          return DateTime(now.year, now.month, now.day, hour, minute);
        }
      }
    } catch (e) {
      print('❌ DEBUG: Error parsing time string: $e');
    }
    return DateTime.now();
  }

  // Helper method to validate time difference (minimum 6 hours)
  bool _isValidTimeDifference(String checkInTime, String checkOutTime) {
    try {
      final checkInDateTime = _parseTimeString(checkInTime);
      final checkOutDateTime = _parseTimeString(checkOutTime);

      // If check-out is on the next day, add 24 hours
      if (checkOutDateTime.isBefore(checkInDateTime)) {
        final nextDayCheckOut = checkOutDateTime.add(Duration(days: 1));
        final difference = nextDayCheckOut.difference(checkInDateTime);
        print(
            '🕐 DEBUG: Check-in: $checkInTime, Check-out (next day): $checkOutTime');
        print(
            '🕐 DEBUG: Time difference: ${difference.inHours} hours ${difference.inMinutes % 60} minutes');
        return difference.inHours >= 6;
      } else {
        final difference = checkOutDateTime.difference(checkInDateTime);
        print('🕐 DEBUG: Check-in: $checkInTime, Check-out: $checkOutTime');
        print(
            '🕐 DEBUG: Time difference: ${difference.inHours} hours ${difference.inMinutes % 60} minutes');
        return difference.inHours >= 6;
      }
    } catch (e) {
      print('❌ DEBUG: Error validating time difference: $e');
      return false;
    }
  }

  // Helper method to calculate total hours between check-in and check-out
  String _calculateTotalHours() {
    if (MyAppState.currentUser!.checkInTime == null ||
        MyAppState.currentUser!.checkInTime!.isEmpty ||
        MyAppState.currentUser!.checkOutTime == null ||
        MyAppState.currentUser!.checkOutTime!.isEmpty) {
      return '0h 0m';
    }

    try {
      final checkInDateTime =
          _parseTimeString(MyAppState.currentUser!.checkInTime!);
      final checkOutDateTime =
          _parseTimeString(MyAppState.currentUser!.checkOutTime!);

      Duration difference;

      // If check-out is on the next day, add 24 hours
      if (checkOutDateTime.isBefore(checkInDateTime)) {
        final nextDayCheckOut = checkOutDateTime.add(Duration(days: 1));
        difference = nextDayCheckOut.difference(checkInDateTime);
      } else {
        difference = checkOutDateTime.difference(checkInDateTime);
      }

      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;

      print('🕐 DEBUG: Calculated total hours: ${hours}h ${minutes}m');
      return '${hours}h ${minutes}m';
    } catch (e) {
      print('❌ DEBUG: Error calculating total hours: $e');
      return '0h 0m';
    }
  }

  // Helper method to check if user can check in today
  bool _canCheckInToday() {
    // User can check in if:
    // 1. They haven't checked in yet today, OR
    // 2. They have checked in but already checked out (allowing multiple check-ins per day)
    final hasNotCheckedIn = MyAppState.currentUser!.checkedInToday != true;
    final hasCheckedOut = MyAppState.currentUser!.checkedOutToday == true;
    
    if (!hasNotCheckedIn && !hasCheckedOut) {
      // User has checked in and hasn't checked out yet - can't check in again
      print('🕐 DEBUG: User is currently checked in, cannot check in again until check out');
      return false;
    }

    // Check if user has set their regular check-in and check-out times
    if (MyAppState.currentUser!.checkInTime == null ||
        MyAppState.currentUser!.checkInTime!.isEmpty ||
        MyAppState.currentUser!.checkOutTime == null ||
        MyAppState.currentUser!.checkOutTime!.isEmpty) {
      print('🕐 DEBUG: User has not set regular check-in/check-out times');
      return false;
    }

    try {
      final checkInDateTime =
          _parseTimeString(MyAppState.currentUser!.checkInTime!);
      final checkOutDateTime =
          _parseTimeString(MyAppState.currentUser!.checkOutTime!);

      Duration difference;

      // If check-out is on the next day, add 24 hours
      if (checkOutDateTime.isBefore(checkInDateTime)) {
        final nextDayCheckOut = checkOutDateTime.add(Duration(days: 1));
        difference = nextDayCheckOut.difference(checkInDateTime);
      } else {
        difference = checkOutDateTime.difference(checkInDateTime);
      }

      final totalHours = difference.inHours + (difference.inMinutes / 60.0);
      print(
          '🕐 DEBUG: Total hours for check-in eligibility: $totalHours hours');
      return totalHours > 5.0;
    } catch (e) {
      print('❌ DEBUG: Error checking check-in eligibility: $e');
      return false;
    }
  }

  // Handle Check In Today button tap
  void _handleCheckInToday() {
    print('🔄 DEBUG: Check In Today button tapped');

    // Check if user is late
    final lateStatus = _checkIfLate();
    final isLate = lateStatus['isLate'] as bool;
    final hoursLate = lateStatus['hoursLate'] as double;
    final lateMessage = lateStatus['message'] as String;

    // Show confirmation dialog with late warning if applicable
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
        title: Row(
          children: [
            Icon(
              isLate ? Icons.warning : Icons.access_time,
              color: isLate ? Colors.red : Color(COLOR_ACCENT),
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'Check In Today',
              style: TextStyle(
                color: isDarkMode(context) ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLate) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lateMessage,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              isLate
                  ? 'You are ${hoursLate.toStringAsFixed(1)} hours late. Do you still want to check in?'
                  : 'Are you sure you want to check in for today?',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performCheckIn();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isLate ? Colors.red : Color(COLOR_ACCENT),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isLate ? 'Check In Late' : 'Check In',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Check if user is late and calculate hours late
  Map<String, dynamic> _checkIfLate() {
    try {
      // If user hasn't checked in today, check against scheduled time
      if (MyAppState.currentUser!.checkedInToday != true ||
          MyAppState.currentUser!.todayCheckInTime == null ||
          MyAppState.currentUser!.todayCheckInTime!.isEmpty) {
        // Compare current time with scheduled check-in time
        if (MyAppState.currentUser!.checkInTime != null &&
            MyAppState.currentUser!.checkInTime!.isNotEmpty) {
          final now = DateTime.now();
          final scheduledTime =
              _parseTimeString(MyAppState.currentUser!.checkInTime!);

          // Create DateTime for today with scheduled time
          final todayScheduled = DateTime(now.year, now.month, now.day,
              scheduledTime.hour, scheduledTime.minute);

          // Calculate difference
          final difference = now.difference(todayScheduled);
          final hoursLate = difference.inHours + (difference.inMinutes / 60.0);

          print('🕐 DEBUG: Current time: $now');
          print('🕐 DEBUG: Scheduled time: $todayScheduled');
          print('🕐 DEBUG: Hours late: $hoursLate');

          if (hoursLate > 0) {
            return {
              'isLate': true,
              'hoursLate': hoursLate,
              'message': 'You are ${hoursLate.toStringAsFixed(1)} hours late'
            };
          } else {
            return {
              'isLate': false,
              'hoursLate': 0.0,
              'message': 'You are on time'
            };
          }
        }
      } else {
        // User has already checked in today, check their actual check-in time against scheduled time
        if (MyAppState.currentUser!.checkInTime != null &&
            MyAppState.currentUser!.checkInTime!.isNotEmpty &&
            MyAppState.currentUser!.todayCheckInTime != null &&
            MyAppState.currentUser!.todayCheckInTime!.isNotEmpty) {
          final actualCheckInTime =
              _parseTimeString(MyAppState.currentUser!.todayCheckInTime!);
          final scheduledTime =
              _parseTimeString(MyAppState.currentUser!.checkInTime!);

          // Create DateTime for today with both times
          final now = DateTime.now();
          final todayActual = DateTime(now.year, now.month, now.day,
              actualCheckInTime.hour, actualCheckInTime.minute);
          final todayScheduled = DateTime(now.year, now.month, now.day,
              scheduledTime.hour, scheduledTime.minute);

          // Calculate difference
          final difference = todayActual.difference(todayScheduled);
          final hoursLate = difference.inHours + (difference.inMinutes / 60.0);

          print('🕐 DEBUG: Actual check-in: $todayActual');
          print('🕐 DEBUG: Scheduled time: $todayScheduled');
          print('🕐 DEBUG: Hours late: $hoursLate');

          if (hoursLate > 0) {
            return {
              'isLate': true,
              'hoursLate': hoursLate,
              'message': 'You were ${hoursLate.toStringAsFixed(1)} hours late'
            };
          } else {
            return {
              'isLate': false,
              'hoursLate': 0.0,
              'message': 'You were on time'
            };
          }
        }
      }

      return {
        'isLate': false,
        'hoursLate': 0.0,
        'message': 'No scheduled time set'
      };
    } catch (e) {
      print('❌ DEBUG: Error checking if late: $e');
      return {
        'isLate': false,
        'hoursLate': 0.0,
        'message': 'Error checking time'
      };
    }
  }

  // Check and reset daily status if it's a new day
  // This method verifies backend data and syncs local state accordingly
  Future<void> _checkAndResetDailyStatus() async {
    try {
      // Get today's date as a string
      final today = DateTime.now();
      final todayString = DateFormat('yyyy-MM-dd').format(today);

      // Get the last check-in date from user preferences
      final lastCheckInDate = UserPreference.getLastCheckInDate() ?? '';

      print(
          '🕐 DEBUG: Today: $todayString, Last check-in date: $lastCheckInDate');

      // Check backend data to see if user has checked in today
      final backendHasCheckInToday = MyAppState.currentUser!.checkedInToday == true &&
          MyAppState.currentUser!.todayCheckInTime != null &&
          MyAppState.currentUser!.todayCheckInTime!.isNotEmpty;

      print(
          '🔍 DEBUG: Backend check-in status - checkedInToday: ${MyAppState.currentUser!.checkedInToday}, todayCheckInTime: ${MyAppState.currentUser!.todayCheckInTime}');

      // If backend says user is checked in today, sync local preference
      if (backendHasCheckInToday && lastCheckInDate != todayString) {
        print('🔄 DEBUG: Backend has check-in for today, syncing local preference');
        UserPreference.setLastCheckInDate(date: todayString);
        print('✅ DEBUG: Local preference synced with backend');
        return; // Don't reset, backend is correct
      }

      // If it's a new day AND backend confirms no check-in, reset the status
      if (lastCheckInDate != todayString) {
        // Double-check: if backend has no check-in for today, it's safe to reset
        if (!backendHasCheckInToday) {
          print('🔄 DEBUG: New day detected, resetting check-in status');

          MyAppState.currentUser!.checkedInToday = false;
          MyAppState.currentUser!.todayCheckInTime = '';
          MyAppState.currentUser!.checkedOutToday = false;
          MyAppState.currentUser!.todayCheckOutTime = '';
          MyAppState.currentUser!.isOnline = false;

          // Save the reset status to Firebase
          await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);

          // Update the last check-in date
          UserPreference.setLastCheckInDate(date: todayString);

          // Clean up old claimed incentives
          await _cleanupOldClaimedIncentives();

          print('✅ DEBUG: Daily check-in status reset successfully');
        } else {
          // Backend has check-in but local preference is wrong - sync it
          print('🔄 DEBUG: Backend has check-in, syncing local preference');
          UserPreference.setLastCheckInDate(date: todayString);
        }
      } else {
        // Same day - verify backend and local state are in sync
        if (backendHasCheckInToday) {
          // Backend says checked in - ensure local state matches
          if (MyAppState.currentUser!.checkedInToday != true ||
              MyAppState.currentUser!.todayCheckInTime == null ||
              MyAppState.currentUser!.todayCheckInTime!.isEmpty) {
            print('⚠️ DEBUG: Local state out of sync, refreshing from backend');
            // Refresh user data from backend
            final updatedUser = await FireStoreUtils.getCurrentUser(
              MyAppState.currentUser!.userID,
            );
            if (updatedUser != null) {
              // Preserve scheduled times
              final preservedCheckInTime = MyAppState.currentUser!.checkInTime;
              final preservedCheckOutTime = MyAppState.currentUser!.checkOutTime;
              if (preservedCheckInTime != null && preservedCheckInTime.isNotEmpty) {
                updatedUser.checkInTime = preservedCheckInTime;
              }
              if (preservedCheckOutTime != null && preservedCheckOutTime.isNotEmpty) {
                updatedUser.checkOutTime = preservedCheckOutTime;
              }
              MyAppState.currentUser = updatedUser;
              print('✅ DEBUG: Local state synced with backend');
            }
          }
        }
      }
    } catch (e) {
      print('❌ DEBUG: Error checking/resetting daily status: $e');
    }
  }

  // Perform the actual check-in
  Future<void> _performCheckIn() async {
    try {
      print('🔄 DEBUG: Performing check-in for today');
      showProgress(context, 'Checking in...', false);

      // Get current time
      final now = DateTime.now();
      final timeString = DateFormat('h:mm a').format(now);
      final todayString = DateFormat('yyyy-MM-dd').format(now);

      print('🕐 DEBUG: Current time: $timeString, Today: $todayString');

      // Update user object with check-in data
      MyAppState.currentUser!.checkedInToday = true;
      MyAppState.currentUser!.isOnline = true;
      MyAppState.currentUser!.isActive = true;
      MyAppState.currentUser!.active = true;
      MyAppState.currentUser!.todayCheckInTime = timeString;
      // Reset check-out status when checking in again
      MyAppState.currentUser!.checkedOutToday = false;
      MyAppState.currentUser!.todayCheckOutTime = '';

      print(
          '📝 DEBUG: Updated user - checkedInToday: ${MyAppState.currentUser!.checkedInToday}, todayCheckInTime: ${MyAppState.currentUser!.todayCheckInTime}, checkedOutToday: ${MyAppState.currentUser!.checkedOutToday}, isActive: ${MyAppState.currentUser!.isActive}');

      // Detect and mark missing absences before check-in
      try {
        final absentDaysMarked =
            await DriverPerformanceService.detectAndMarkMissingAbsences(
                MyAppState.currentUser!.userID);

        if (absentDaysMarked > 0 && mounted) {
          final pointsDeducted =
              absentDaysMarked * DriverPerformanceService.ADJUSTMENT_ABSENT;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$absentDaysMarked absent day(s) detected and marked. Performance deducted: ${pointsDeducted.toStringAsFixed(1)} points',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        // Handle errors gracefully - don't block check-in
        print(
            '⚠️ Error detecting missing absences during check-in (non-blocking): $e');
      }

      // Apply performance adjustment for check-in (on-time or late)
      if (MyAppState.currentUser!.checkInTime != null &&
          MyAppState.currentUser!.checkInTime!.isNotEmpty) {
        final newPerformance =
            await DriverPerformanceService.applyCheckInAdjustment(
                MyAppState.currentUser!.userID,
                MyAppState.currentUser!.checkInTime!,
                timeString);
        MyAppState.currentUser!.driverPerformance = newPerformance;
        print(
            '📊 DEBUG: Performance updated to $newPerformance% after check-in');
      }

      // Save to Firebase
      print('🔥 DEBUG: Saving check-in data to Firebase...');
      await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
      await OrderService.updateRiderStatus();
      print('✅ DEBUG: Check-in data saved to Firebase successfully');

      // Save the last check-in date
      UserPreference.setLastCheckInDate(date: todayString);
      print('📅 DEBUG: Last check-in date saved: $todayString');

      // Update UI
      setState(() {});
      print('🔄 DEBUG: setState called');

      hideProgress();

      // Check if user was late and show appropriate message
      final lateStatus = _checkIfLate();
      final wasLate = lateStatus['isLate'] as bool;
      final hoursLate = lateStatus['hoursLate'] as double;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(wasLate
              ? 'Checked in late at $timeString (${hoursLate.toStringAsFixed(1)} hours late)'
              : 'Successfully checked in for today at $timeString!'),
          backgroundColor: wasLate ? Colors.orange : Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      print('✅ DEBUG: Check-in completed successfully');
    } catch (e) {
      print('❌ DEBUG: Error during check-in: $e');
      print('❌ DEBUG: Error type: ${e.runtimeType}');
      hideProgress();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to check in: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Check if user can check out today
  bool _canCheckOutToday() {
    // User must be checked in today to check out
    if (MyAppState.currentUser!.checkedInToday != true) {
      print('🕐 DEBUG: User has not checked in today');
      return false;
    }

    // User must not have already checked out today
    if (MyAppState.currentUser!.checkedOutToday == true) {
      print('🕐 DEBUG: User has already checked out today');
      return false;
    }

    // User must have a check-in time for today
    if (MyAppState.currentUser!.todayCheckInTime == null ||
        MyAppState.currentUser!.todayCheckInTime!.isEmpty) {
      print('🕐 DEBUG: User has no check-in time for today');
      return false;
    }

    return true;
  }

  // Handle Check Out Today button tap
  void _handleCheckOutToday() async {
    print('🔄 DEBUG: Check Out Today button tapped');

    // Add comprehensive debug information
    print('🔍 DEBUG: ===== CHECKOUT DEBUG START =====');
    print('🔍 DEBUG: Current user ID: ${MyAppState.currentUser!.userID}');
    print('🔍 DEBUG: Current user email: ${MyAppState.currentUser!.email}');
    print(
        '🔍 DEBUG: Current user phone: ${MyAppState.currentUser!.phoneNumber}');
    print('🔍 DEBUG: Current user role: ${MyAppState.currentUser!.role}');
    print('🔍 DEBUG: ===== CHECKOUT DEBUG END =====');

    // Calculate work duration for display
    final workDuration = TimeTrackingService.calculateTodayWorkDuration(
        MyAppState.currentUser!.todayCheckInTime!);

    // Fetch today's incentive summary
    final incentiveSummary = await _getTodayIncentiveSummary();

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor:
            isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
        title: Row(
          children: [
            Icon(
              Icons.logout,
              color: Color(COLOR_ACCENT),
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'Check Out Today',
              style: TextStyle(
                color: isDarkMode(context) ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to check out for today?',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),

            // Work duration display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Work Duration: ${TimeTrackingService.formatDuration(workDuration)}',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Incentive summary card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.card_giftcard, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Today\'s Incentive',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Orders Completed:',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${incentiveSummary['ordersCount']}',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Column(
                    children: [
                      Text(
                        'Total Incentive:',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          '₱${(incentiveSummary['totalIncentive'] as double).toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _performCheckOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Check Out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Perform the actual check-out
  Future<void> _performCheckOut() async {
    try {
      print('🔄 DEBUG: Performing check-out for today');
      showProgress(context, 'Checking out...', false);

      // Prevent multiple rapid saves
      if (_isSavingCheckOutToday) {
        print(
            '⚠️ DEBUG: Check-out save already in progress, ignoring duplicate request');
        hideProgress();
        return;
      }

      _isSavingCheckOutToday = true;

      // Get current time
      final timeString = TimeTrackingService.getCurrentTimeString();
      final todayString = TimeTrackingService.getTodayDateString();

      print('🕐 DEBUG: Current time: $timeString, Today: $todayString');

      // Calculate work duration
      final workDuration = TimeTrackingService.calculateTodayWorkDuration(
          MyAppState.currentUser!.todayCheckInTime!);

      print(
          '💰 DEBUG: Work duration: ${TimeTrackingService.formatDuration(workDuration)}');

      // Update user object with check-out data
      // #region agent log
      http.post(Uri.parse('http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),headers:{'Content-Type':'application/json'},body:json.encode({'location':'ProfileScreen.dart:2115','message':'Before checkout update','data':{'checkedInToday':MyAppState.currentUser!.checkedInToday,'checkedOutToday':MyAppState.currentUser!.checkedOutToday,'isOnline':MyAppState.currentUser!.isOnline},'timestamp':DateTime.now().millisecondsSinceEpoch,'sessionId':'debug-session','runId':'checkout-test','hypothesisId':'A'})).catchError((_)=>http.Response('', 500));
      // #endregion
      MyAppState.currentUser!.checkedOutToday = true;
      MyAppState.currentUser!.todayCheckOutTime = timeString;
      MyAppState.currentUser!.isOnline = false;
      // ✅ Keep checkedInToday as true - user checked in AND checked out today
      // #region agent log
      http.post(Uri.parse('http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),headers:{'Content-Type':'application/json'},body:json.encode({'location':'ProfileScreen.dart:2117','message':'After checkout update - keeping checkedInToday true','data':{'checkedInToday':MyAppState.currentUser!.checkedInToday,'checkedOutToday':MyAppState.currentUser!.checkedOutToday,'isOnline':MyAppState.currentUser!.isOnline},'timestamp':DateTime.now().millisecondsSinceEpoch,'sessionId':'debug-session','runId':'checkout-test','hypothesisId':'A'})).catchError((_)=>http.Response('', 500));
      // #endregion

      print(
          '📝 DEBUG: Updated user - checkedOutToday: ${MyAppState.currentUser!.checkedOutToday}, todayCheckOutTime: ${MyAppState.currentUser!.todayCheckOutTime}');

      // Apply performance adjustments for check-out
      if (MyAppState.currentUser!.todayCheckInTime != null &&
          MyAppState.currentUser!.todayCheckInTime!.isNotEmpty) {
        final newPerformance =
            await DriverPerformanceService.applyCheckOutAdjustments(
                MyAppState.currentUser!.userID,
                scheduledCheckInTime: MyAppState.currentUser!.checkInTime,
                actualCheckInTime: MyAppState.currentUser!.todayCheckInTime!,
                scheduledCheckOutTime: MyAppState.currentUser!.checkOutTime,
                actualCheckOutTime: timeString);
        MyAppState.currentUser!.driverPerformance = newPerformance;
        print(
            '📊 DEBUG: Performance updated to $newPerformance% after check-out');
      }

      // Save to Firebase
      print('🔥 DEBUG: Saving check-out data to Firebase...');
      // #region agent log
      http.post(Uri.parse('http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),headers:{'Content-Type':'application/json'},body:json.encode({'location':'ProfileScreen.dart:2138','message':'Before Firebase save','data':{'checkedInToday':MyAppState.currentUser!.checkedInToday,'checkedOutToday':MyAppState.currentUser!.checkedOutToday,'isOnline':MyAppState.currentUser!.isOnline},'timestamp':DateTime.now().millisecondsSinceEpoch,'sessionId':'debug-session','runId':'checkout-test','hypothesisId':'E'})).catchError((_)=>http.Response('', 500));
      // #endregion
      await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
      await OrderService.updateRiderStatus();
      print('✅ DEBUG: Check-out data saved to Firebase successfully');
      // #region agent log
      http.post(Uri.parse('http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),headers:{'Content-Type':'application/json'},body:json.encode({'location':'ProfileScreen.dart:2140','message':'After Firebase save','data':{'checkedInToday':MyAppState.currentUser!.checkedInToday,'checkedOutToday':MyAppState.currentUser!.checkedOutToday,'isOnline':MyAppState.currentUser!.isOnline},'timestamp':DateTime.now().millisecondsSinceEpoch,'sessionId':'debug-session','runId':'checkout-test','hypothesisId':'E'})).catchError((_)=>http.Response('', 500));
      // #endregion

      // Update UI
      setState(() {});
      print('🔄 DEBUG: setState called');

      hideProgress();

      // Show success message
      String message;
      Color backgroundColor;

      message =
          'Successfully checked out at $timeString! Work duration: ${TimeTrackingService.formatDuration(workDuration)}';
      backgroundColor = Colors.blue;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: Duration(seconds: 4),
        ),
      );

      print('✅ DEBUG: Check-out completed successfully');
    } catch (e) {
      print('❌ DEBUG: Error during check-out: $e');
      print('❌ DEBUG: Error type: ${e.runtimeType}');
      hideProgress();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to check out: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      _isSavingCheckOutToday = false;
    }
  }

  /// Get today's incentive summary (orders count and total incentive)
  Future<Map<String, dynamic>> _getTodayIncentiveSummary() async {
    try {
      final currentUserId = MyAppState.currentUser?.userID;
      if (currentUserId == null || currentUserId.isEmpty) {
        return {'ordersCount': 0, 'totalIncentive': 0.0};
      }

      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Query today's completed orders
      final ordersSnapshot = await firestore
          .collection('restaurant_orders')
          .where('driverID', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'Order Completed')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      int ordersCount = ordersSnapshot.size;
      double totalIncentive = 0.0;

      // Sum up incentives from all completed orders
      for (var doc in ordersSnapshot.docs) {
        final data = doc.data();
        final incentive = (data['incentive'] as num?)?.toDouble() ?? 0.0;
        totalIncentive += incentive;
      }

      return {
        'ordersCount': ordersCount,
        'totalIncentive': totalIncentive,
      };
    } catch (e) {
      print('❌ Error getting today\'s incentive summary: $e');
      return {'ordersCount': 0, 'totalIncentive': 0.0};
    }
  }

  /// Fetch qualified_time from Firestore
  Future<int> _getQualifiedTime() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final doc =
          await firestore.collection(Setting).doc('driver_performance').get();

      if (doc.exists && doc.data() != null) {
        final qualifiedTime = doc.data()!['qualified_time'];
        if (qualifiedTime != null) {
          return (qualifiedTime as num).toInt();
        }
      }
      // Default to 5 if not found
      return 5;
    } catch (e) {
      print('❌ Error getting qualified_time: $e');
      // Default to 5 on error
      return 5;
    }
  }

  /// Fetch excuse limit from Firestore settings
  Future<int> _getExcuseLimit() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final doc =
          await firestore.collection(Setting).doc('driver_performance').get();

      if (doc.exists && doc.data() != null) {
        final excuse = doc.data()!['excuse'];
        if (excuse != null) {
          return (excuse as num).toInt();
        }
      }
      // Default to 0 if not found
      return 0;
    } catch (e) {
      print('❌ Error getting excuse limit: $e');
      // Default to 0 on error
      return 0;
    }
  }

  /// Calculate remaining excuse credits
  Future<int> _getRemainingExcuses() async {
    try {
      final excuseLimit = await _getExcuseLimit();
      if (excuseLimit <= 0) return 0;

      final user = MyAppState.currentUser;
      if (user == null) return 0;

      // Get used excuses count from excusedDays list
      final excusedDays = user.excusedDays ?? [];
      final usedExcuses = excusedDays.length;

      // Calculate remaining
      final remaining = excuseLimit - usedExcuses;
      return remaining > 0 ? remaining : 0;
    } catch (e) {
      print('❌ Error calculating remaining excuses: $e');
      return 0;
    }
  }

  /// Calculate hours online from todayCheckInTime
  double _calculateHoursOnline() {
    try {
      final user = MyAppState.currentUser;
      if (user == null || user.checkedInToday != true) {
        return 0.0;
      }

      // Use todayCheckInTime if available, otherwise fallback to checkInTime
      String? checkInTimeString = user.todayCheckInTime?.isNotEmpty == true
          ? user.todayCheckInTime
          : user.checkInTime;

      if (checkInTimeString == null || checkInTimeString.isEmpty) {
        return 0.0;
      }

      final now = DateTime.now();
      final checkInDateTime = _parseTimeString(checkInTimeString);
      final duration = now.difference(checkInDateTime);

      // Return hours as double (including fractional hours)
      if (duration.isNegative) {
        return 0.0;
      }

      return duration.inHours + (duration.inMinutes % 60) / 60.0;
    } catch (e) {
      print('❌ Error calculating hours online: $e');
      return 0.0;
    }
  }

  /// Get qualified status information
  Future<Map<String, dynamic>> _getQualifiedStatus() async {
    try {
      final qualifiedTime = await _getQualifiedTime();
      final hoursOnline = _calculateHoursOnline();
      final user = MyAppState.currentUser;
      final checkedOutToday =
          user?.checkedOutToday == true &&
              (user?.todayCheckOutTime != null &&
                  user!.todayCheckOutTime!.isNotEmpty);
      final isQualified = hoursOnline >= qualifiedTime && checkedOutToday;

      return {
        'isQualified': isQualified,
        'hoursOnline': hoursOnline,
        'qualifiedTime': qualifiedTime,
        'checkedOutToday': checkedOutToday,
      };
    } catch (e) {
      print('❌ Error getting qualified status: $e');
      return {
        'isQualified': false,
        'hoursOnline': 0.0,
        'qualifiedTime': 5,
        'checkedOutToday': false,
      };
    }
  }

  /// Check if incentive is already claimed today
  Future<bool> _isAlreadyClaimedToday() async {
    try {
      final user = MyAppState.currentUser;
      if (user == null) return false;

      final userId = user.userID;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      final userData = userDoc.data() ?? {};
      final claimedIncentives =
          (userData['claimedIncentives'] as List<dynamic>?) ?? [];

      return claimedIncentives.any((item) {
        final itemMap = item as Map<String, dynamic>;
        final claimDate = (itemMap['date'] as Timestamp?)?.toDate();
        if (claimDate == null) return false;
        final claimDay = DateTime(
          claimDate.year,
          claimDate.month,
          claimDate.day,
        );
        return claimDay.year == today.year &&
            claimDay.month == today.month &&
            claimDay.day == today.day;
      });
    } catch (e) {
      print('❌ Error checking if already claimed: $e');
      return false;
    }
  }

  /// Clean up old claimed incentives (older than 30 days)
  Future<void> _cleanupOldClaimedIncentives() async {
    try {
      final user = MyAppState.currentUser;
      if (user == null) return;

      final userId = user.userID;
      final now = DateTime.now();
      final cutoffDate = now.subtract(const Duration(days: 30));

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      final userData = userDoc.data() ?? {};
      final claimedIncentives =
          (userData['claimedIncentives'] as List<dynamic>?) ?? [];

      if (claimedIncentives.isEmpty) return;

      // Filter out entries older than 30 days
      final cleanedIncentives = claimedIncentives.where((item) {
        final itemMap = item as Map<String, dynamic>;
        final claimDate = (itemMap['date'] as Timestamp?)?.toDate();
        if (claimDate == null) return false;
        return claimDate.isAfter(cutoffDate);
      }).toList();

      // Only update if we removed some entries
      if (cleanedIncentives.length < claimedIncentives.length) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({'claimedIncentives': cleanedIncentives});
        print(
            '✅ DEBUG: Cleaned up ${claimedIncentives.length - cleanedIncentives.length} old claimed incentives');
      }
    } catch (e) {
      print('❌ Error cleaning up old claimed incentives: $e');
    }
  }

  /// Claim today's incentive
  Future<void> _claimIncentive(
    double amount,
    bool isQualified,
  ) async {
    try {
      // Check if user is qualified
      if (!isQualified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'You must be qualified to claim incentives',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      // Check if amount is valid
      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No incentive available to claim'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final user = MyAppState.currentUser;
      if (user == null) {
        throw Exception('User not found');
      }

      if (user.checkedOutToday != true ||
          user.todayCheckOutTime == null ||
          user.todayCheckOutTime!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You must check out today to claim today\'s bonus.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final userId = user.userID;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Check if already claimed today
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      final userData = userDoc.data() ?? {};
      final claimedIncentives =
          (userData['claimedIncentives'] as List<dynamic>?) ?? [];

      // Check if already claimed today
      final alreadyClaimedToday = claimedIncentives.any((item) {
        final itemMap = item as Map<String, dynamic>;
        final claimDate = (itemMap['date'] as Timestamp?)?.toDate();
        if (claimDate == null) return false;
        final claimDay = DateTime(
          claimDate.year,
          claimDate.month,
          claimDate.day,
        );
        return claimDay.year == today.year &&
            claimDay.month == today.month &&
            claimDay.day == today.day;
      });

      if (alreadyClaimedToday) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('You have already claimed today\'s incentive'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      // Show loading
      showProgress(context, 'Claiming incentive...', false);

      // Create incentive record
      final incentiveRecord = {
        'date': Timestamp.fromDate(now),
        'amount': amount,
        'status': 'claimed',
        'claimedAt': Timestamp.fromDate(now),
      };

      // Add to claimedIncentives array
      final updatedIncentives = [...claimedIncentives, incentiveRecord];

      // Update user document
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'claimedIncentives': updatedIncentives,
      });

      hideProgress();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully claimed ₱${amount.toStringAsFixed(0)} incentive!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Refresh the screen
      setState(() {});
    } catch (e) {
      hideProgress();
      print('❌ Error claiming incentive: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to claim incentive: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Handle excuse button tap
  Future<void> _handleExcuse() async {
    try {
      // Check remaining excuses
      final remainingExcuses = await _getRemainingExcuses();

      if (remainingExcuses <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'You have no remaining excuse credits. Please contact support if you need assistance.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      // Check if already excused today
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final user = MyAppState.currentUser;
      if (user != null && user.excusedDays != null) {
        if (user.excusedDays!.contains(today)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('You have already excused yourself for today.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor:
              isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
          title: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Color(COLOR_ACCENT),
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Excuse for Today',
                style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to excuse yourself for today?',
                style: TextStyle(
                  color: isDarkMode(context)
                      ? Colors.grey.shade300
                      : Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Remaining excuses: $remainingExcuses',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Note: Excused days will not affect your performance score.',
                style: TextStyle(
                  color: isDarkMode(context)
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDarkMode(context)
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(COLOR_ACCENT),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Excuse',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Show loading
      showProgress(context, 'Processing excuse...', false);

      // Record excused day
      final todayString = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await DriverPerformanceService.recordExcusedDay(
          MyAppState.currentUser!.userID, todayString);

      // Update user's remaining excuse count
      final excuseLimit = await _getExcuseLimit();
      final excusedDays = MyAppState.currentUser!.excusedDays ?? [];
      if (!excusedDays.contains(todayString)) {
        excusedDays.add(todayString);
      }
      final remaining = excuseLimit - excusedDays.length;

      // Update user object
      MyAppState.currentUser!.excusedDays = excusedDays;
      MyAppState.currentUser!.remainingExcuses = remaining > 0 ? remaining : 0;

      // Save to Firebase
      await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);

      hideProgress();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully excused for today. Remaining excuses: ${remaining > 0 ? remaining : 0}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      // Refresh the screen
      setState(() {});
    } catch (e) {
      hideProgress();
      print('❌ Error handling excuse: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to process excuse: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Color _getPerformanceColor(double score) {
    return PerformanceTierHelper.getTier(score).color;
  }

  String _getPerformanceLabel(double score) {
    return PerformanceTierHelper.getTier(score).name;
  }

  Widget _buildMetricRow(
    BuildContext context,
    String label,
    String valueText,
    double value,
    double maxValue,
    Color color,
  ) {
    final ratio = maxValue > 0
        ? (value / maxValue).clamp(0.0, 1.0)
        : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode(context)
                  ? Colors.grey.shade400
                  : Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: isDarkMode(context)
                  ? Colors.grey.shade800
                  : Colors.grey.shade200,
              valueColor:
                  AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDarkMode(context)
                  ? Colors.white70
                  : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

double _zoomForRadius(double radiusKm) {
  if (radiusKm <= 0) return 14.0;
  final diameter = radiusKm * 2;
  final zoom = 14.0 - (math.log(diameter) / math.ln2);
  return zoom.clamp(8.0, 17.0);
}

class _WorkAreaCard extends StatelessWidget {
  final RiderPresetLocationData? currentZone;
  final bool isLoading;
  final VoidCallback onBrowseZones;

  const _WorkAreaCard({
    required this.currentZone,
    required this.isLoading,
    required this.onBrowseZones,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'MY WORK AREA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          if (isLoading)
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: CircularProgressIndicator.adaptive(),
              ),
            )
          else if (currentZone == null)
            _buildNoZoneSelected(context)
          else
            _buildZonePreview(context),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onBrowseZones,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('BROWSE ALL ZONES'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Color(COLOR_PRIMARY),
                side: BorderSide(
                  color: Color(COLOR_PRIMARY),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoZoneSelected(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? Colors.grey.shade800
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade300,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.place_outlined,
              size: 32,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              'No work area selected',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZonePreview(BuildContext context) {
    final zone = currentZone!;
    final hasCircle = zone.hasRadius;
    final center = LatLng(zone.latitude, zone.longitude);
    final zoom = hasCircle
        ? _zoomForRadius(zone.radiusKm!)
        : 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.shade300,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: center,
                zoom: zoom,
              ),
              liteModeEnabled: Platform.isAndroid,
              zoomGesturesEnabled: false,
              scrollGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              circles: hasCircle
                  ? {
                      Circle(
                        circleId: const CircleId(
                          'zone_preview',
                        ),
                        center: center,
                        radius: zone.radiusKm! * 1000,
                        fillColor: Colors.blue
                            .withOpacity(0.1),
                        strokeColor: Colors.blue
                            .withOpacity(0.5),
                        strokeWidth: 2,
                      ),
                    }
                  : {},
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.place,
              color: Colors.blue,
              size: 20,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                zone.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
