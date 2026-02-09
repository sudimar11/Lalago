import 'package:clipboard/clipboard.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/BackendService.dart';
import 'package:foodie_customer/services/ReferralDataService.dart';
import 'package:foodie_customer/main.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({Key? key}) : super(key: key);

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _isLoading = false;
  ReferralStats? _referralStats;

  @override
  void initState() {
    super.initState();
    _debugFirebaseState();
    _loadExistingReferralCode();
  }

  /// Debug Firebase state for troubleshooting
  void _debugFirebaseState() {
    print('🔍 === REFERRAL SCREEN DEBUG INFO ===');

    // Check current user
    final currentUser = MyAppState.currentUser;
    if (currentUser != null) {
      print('🔍 Current user ID: ${currentUser.userID}');
      print('🔍 Current user email: ${currentUser.email}');
      print(
          '🔍 Current user referral code: ${currentUser.referralCode ?? "null"}');
    } else {
      print('🔍 No current user found');
    }

    // Check Firebase Auth
    try {
      final firebaseUser = auth.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        print('🔍 Firebase Auth user: ${firebaseUser.uid}');
        print('🔍 Firebase Auth email: ${firebaseUser.email}');
      } else {
        print('🔍 No Firebase Auth user');
      }
    } catch (e) {
      print('🔍 Firebase Auth error: $e');
    }

    print('🔍 === END DEBUG INFO ===');
  }

  /// Loads existing referral code from Firestore
  Future<void> _loadExistingReferralCode() async {
    final currentUser = MyAppState.currentUser;
    if (currentUser == null) {
      return;
    }

    // Start loading state (non-blocking)
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔥 === FIRESTORE LOAD DEBUG START ===');
      print(
          '🔥 Loading referral code from Firestore for user: ${currentUser.userID}');
      print('🔥 User email: ${currentUser.email}');
      print('🔥 Current referral code: ${currentUser.referralCode ?? "null"}');

      // Read from Firestore referral collection
      final doc = await FirebaseFirestore.instance
          .collection('referral')
          .doc(currentUser.userID)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final referralCode = data['referralCode'] as String?;

        print('🔥 Firestore document exists');
        print('🔥 Referral code from Firestore: $referralCode');

        if (referralCode != null && referralCode.isNotEmpty) {
          print('✅ Found referral code in Firestore: $referralCode');

          // Update local user object if code is different
          if (currentUser.referralCode != referralCode) {
            print(
                '🔄 Referral code changed, updating user: ${currentUser.referralCode} → $referralCode');

            currentUser.referralCode = referralCode;
            print('🔥 Local user object updated');

            // Update Firebase user document (non-blocking - happens in background)
            FireStoreUtils.updateCurrentUser(currentUser).then((_) {
              print(
                  '✅ User updated in Firebase with referral code from Firestore');
            }).catchError((error) {
              print(
                  '❌ Failed to update user in Firebase: $error (continuing anyway)');
            });
          } else {
            print('ℹ️ Referral code unchanged: $referralCode');
          }

          // Load referral statistics after getting the referral code
          await _loadReferralStatistics(referralCode);

          // Trigger UI update immediately
          if (mounted) {
            print('🔥 Triggering UI update');
            setState(() {});
          } else {
            print('⚠️ Widget not mounted, skipping UI update');
          }
        } else {
          print('ℹ️ No referral code found in Firestore document');
        }
      } else {
        print('ℹ️ No Firestore document found for user');
      }

      print('🔥 === FIRESTORE LOAD DEBUG END ===');
    } catch (e) {
      print('❌ === FIRESTORE LOAD ERROR DEBUG START ===');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Error message: $e');
      print('❌ Error string: ${e.toString()}');
      print('❌ User ID: ${currentUser.userID}');
      print('❌ User email: ${currentUser.email}');
      print('❌ Current referral code: ${currentUser.referralCode ?? "null"}');
      print('❌ Stack trace: ${StackTrace.current}');
      print('❌ === FIRESTORE LOAD ERROR DEBUG END ===');
      print('⚠️ Continuing with existing state (soft failure)');
    } finally {
      // Stop loading state
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Ensures the current user has a referral code via Backend HTTP API
  /// This function is kept for future use but not called
  // ignore: unused_element
  Future<void> _ensureReferralCode() async {
    final currentUser = MyAppState.currentUser;
    if (currentUser == null) {
      return;
    }

    // Start loading state (non-blocking)
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      print('🔥 === BACKEND API DEBUG START ===');
      print(
          '🔥 Calling Backend ensureReferralCodeForScreen for user: ${currentUser.userID}');
      print('🔥 User email: ${currentUser.email}');
      print('🔥 Current referral code: ${currentUser.referralCode ?? "null"}');

      // Call Backend HTTP API instead of Firebase Functions
      final String? newReferralCode =
          await BackendService.ensureReferralCodeForScreen(currentUser.userID);

      print('🔥 Backend API completed');
      print('🔥 Returned referral code: $newReferralCode');

      if (newReferralCode != null) {
        print('✅ Backend API returned referral code: $newReferralCode');

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
        print(
            'ℹ️ Backend API returned null code (referral system may be disabled)');
      }

      print('🔥 === BACKEND API DEBUG END ===');
    } catch (e) {
      print('❌ === BACKEND API ERROR DEBUG START ===');
      print('❌ Error type: ${e.runtimeType}');
      print('❌ Error message: $e');
      print('❌ Error string: ${e.toString()}');

      // Check for common HTTP/network errors
      if (e.toString().contains('SocketException')) {
        print('❌ SPECIFIC ERROR: Network connectivity issue');
        print('❌ SOLUTION: Check internet connection or backend server status');
      } else if (e.toString().contains('TimeoutException')) {
        print('❌ SPECIFIC ERROR: Request timeout');
        print('❌ SOLUTION: Check backend server response time');
      } else if (e.toString().contains('401')) {
        print('❌ SPECIFIC ERROR: Authentication failed');
        print('❌ SOLUTION: User needs to re-authenticate');
      } else if (e.toString().contains('403')) {
        print('❌ SPECIFIC ERROR: Permission denied');
        print('❌ SOLUTION: Check user permissions or backend authorization');
      } else if (e.toString().contains('404')) {
        print('❌ SPECIFIC ERROR: Backend endpoint not found');
        print('❌ SOLUTION: Check backend server and API endpoints');
      } else if (e.toString().contains('500')) {
        print('❌ SPECIFIC ERROR: Backend server error');
        print('❌ SOLUTION: Check backend server logs');
      } else {
        print('❌ UNKNOWN ERROR TYPE: $e');
        print('❌ SOLUTION: Check backend server status and logs');
      }

      // Show debug information in development
      print('❌ User ID: ${currentUser.userID}');
      print('❌ User email: ${currentUser.email}');
      print('❌ Current referral code: ${currentUser.referralCode ?? "null"}');
      print('❌ User active: ${currentUser.active}');
      print('❌ User role: ${currentUser.role}');

      // Check Firebase Auth state for backend authentication
      try {
        final firebaseUser = auth.FirebaseAuth.instance.currentUser;
        if (firebaseUser != null) {
          print('❌ Firebase Auth user: ${firebaseUser.uid}');
          print('❌ Firebase Auth email: ${firebaseUser.email}');
          print('❌ Firebase Auth verified: ${firebaseUser.emailVerified}');
        } else {
          print('❌ NO FIREBASE AUTH USER - Backend needs Firebase Auth token!');
        }
      } catch (authError) {
        print('❌ Error checking Firebase Auth: $authError');
      }

      print('❌ Stack trace: ${StackTrace.current}');
      print('❌ === BACKEND API ERROR DEBUG END ===');
      print('⚠️ Continuing with existing state (soft failure)');
    } finally {
      // Stop loading state
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Loads referral statistics from Firebase
  Future<void> _loadReferralStatistics(String referralCode) async {
    try {
      final currentUser = MyAppState.currentUser;
      if (currentUser == null) return;

      print('📊 Loading referral statistics...');
      final referralStats =
          await ReferralDataService.loadUserReferralData(currentUser.userID);

      if (mounted) {
        setState(() {
          _referralStats = referralStats;
        });
      }

      if (referralStats != null) {
        print(
            '✅ Loaded referral stats: ${referralStats.totalReferrals} referrals, \$${referralStats.totalEarnings.toStringAsFixed(2)} earned');
      } else {
        print('⚠️ No referral statistics found');
      }
    } catch (e) {
      print('❌ Error loading referral statistics: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? const Color(DARK_BG_COLOR) : null,
      appBar: AppBar(
        backgroundColor:
            isDarkMode(context) ? const Color(DARK_BG_COLOR) : null,
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.white : Colors.black),
        title: Text(
          'Referrals',
          style: TextStyle(
            color: isDarkMode(context) ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildReferralContent(),
    );
  }

  Widget _buildReferralContent() {
    final currentUser = MyAppState.currentUser;
    if (currentUser == null) {
      return const Center(
        child: Text('Please log in to view referrals'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(COLOR_PRIMARY),
                  Color(COLOR_PRIMARY).withOpacity(0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.card_giftcard,
                  size: 60,
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Text(
                  'Invite Friends & Earn',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Share your referral code with friends and earn rewards when they make their first order!'
                      ,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Referral Code Section
          if (currentUser.referralCode != null &&
              currentUser.referralCode!.isNotEmpty)
            _buildReferralCodeSection(currentUser.referralCode!)
          else
            _buildNoReferralCodeSection(),

          const SizedBox(height: 24),

          // Statistics Section
          if (_referralStats != null) _buildStatisticsSection(_referralStats!),

          const SizedBox(height: 24),

          // Recent Referrals Section
          if (_referralStats != null &&
              _referralStats!.recentReferrals.isNotEmpty)
            _buildRecentReferralsSection(_referralStats!.recentReferrals),

          const SizedBox(height: 24),

          // How it works section
          _buildHowItWorksSection(),
        ],
      ),
    );
  }

  Widget _buildReferralCodeSection(String referralCode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Referral Code',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          DottedBorder(
            color: Color(COLOR_PRIMARY),
            strokeWidth: 2,
            dashPattern: const [8, 4],
            borderType: BorderType.RRect,
            radius: const Radius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    referralCode,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(COLOR_PRIMARY),
                      letterSpacing: 2,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _copyToClipboard(referralCode),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(COLOR_PRIMARY),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.copy,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _copyToClipboard(referralCode),
                  icon: const Icon(Icons.copy),
                  label: Text('Copy Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(COLOR_PRIMARY),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _shareReferralCode(referralCode),
                  icon: const Icon(Icons.share),
                  label: Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoReferralCodeSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 60,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Generating Your Referral Code',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your unique referral code is being generated. Please wait a moment or refresh the page.'
                ,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode(context) ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _loadExistingReferralCode(),
            icon: const Icon(Icons.refresh),
            label: Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(COLOR_PRIMARY),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How It Works',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildHowItWorksStep(
            1,
            'Share Your Code',
            'Send your referral code to friends and family',
            Icons.share,
          ),
          const SizedBox(height: 12),
          _buildHowItWorksStep(
            2,
            'Friends Sign Up',
            'They use your code when creating their account',
            Icons.person_add,
          ),
          const SizedBox(height: 12),
          _buildHowItWorksStep(
            3,
            'Earn Rewards',
            'Get rewards when they complete their first order',
            Icons.card_giftcard,
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksStep(
      int step, String title, String description, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color(COLOR_PRIMARY),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: Color(COLOR_PRIMARY),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color:
                          isDarkMode(context) ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode(context) ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _copyToClipboard(String referralCode) {
    FlutterClipboard.copy(referralCode).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Referral code copied to clipboard!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }).catchError((error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy referral code'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  void _shareReferralCode(String referralCode) {
    final shareText =
        'Join me on our food delivery app using my referral code: $referralCode and get special offers on your first order!'
            ;

    Share.share(
      shareText,
      subject: 'Join me on our food delivery app!',
    );
  }

  Widget _buildStatisticsSection(ReferralStats stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Referral Stats',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode(context) ? Colors.white : Colors.black87,
                ),
              ),
              GestureDetector(
                onTap: () => _loadExistingReferralCode(),
                child: Icon(
                  Icons.refresh,
                  color: Color(COLOR_PRIMARY),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total Referrals',
                  stats.totalReferrals.toString(),
                  Icons.people,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Completed',
                  stats.completedReferrals.toString(),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Pending',
                  stats.pendingReferrals.toString(),
                  Icons.hourglass_empty,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Total Earned',
                  '\$${stats.totalEarnings.toStringAsFixed(2)}',
                  Icons.monetization_on,
                  Colors.purple,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode(context) ? Colors.white70 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReferralsSection(
      List<Map<String, dynamic>> recentReferrals) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Referrals',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          ...recentReferrals
              .map((referral) => _buildReferralItem(referral))
              .toList(),
          if (recentReferrals.length >= 5)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: TextButton(
                  onPressed: () {
                    // Navigate to full referrals list
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Full referral history coming soon!'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                  child: Text(
                    'View All Referrals',
                    style: TextStyle(color: Color(COLOR_PRIMARY)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReferralItem(Map<String, dynamic> referral) {
    final referralCode = referral['referralCode'] ?? 'Unknown';
    final userId = referral['id'] ?? 'Unknown';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color(COLOR_PRIMARY).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              color: Color(COLOR_PRIMARY),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User: ${userId.length > 10 ? userId.substring(0, 10) + '...' : userId}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDarkMode(context) ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  'Code: $referralCode',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        isDarkMode(context) ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 16,
          ),
        ],
      ),
    );
  }
}
