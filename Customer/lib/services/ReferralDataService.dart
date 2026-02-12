import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/referral_model.dart';

/// Model for referral statistics
class ReferralStats {
  final String referralCode;
  final int totalReferrals;
  final int pendingReferrals;
  final int completedReferrals;
  final double totalEarnings;
  final List<Map<String, dynamic>> recentReferrals;
  final List<Map<String, dynamic>> referralHistory;

  ReferralStats({
    required this.referralCode,
    required this.totalReferrals,
    required this.pendingReferrals,
    required this.completedReferrals,
    required this.totalEarnings,
    required this.recentReferrals,
    required this.referralHistory,
  });
}

/// Service to handle referral data loading from Firebase
class ReferralDataService {
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Loads comprehensive referral data for the current user
  static Future<ReferralStats?> loadUserReferralData(String userId) async {
    try {
      print('🔍 Loading referral data for user: $userId');

      // Get user's referral code from referral collection
      final referralDoc =
          await firestore.collection(REFERRAL).doc(userId).get();

      String? referralCode;
      if (referralDoc.exists && referralDoc.data() != null) {
        final referralModel = ReferralModel.fromJson(referralDoc.data()!);
        referralCode = referralModel.referralCode;
        print('✅ Found referral code: $referralCode');
      } else {
        // Fallback to user's referralCode field
        referralCode = MyAppState.currentUser?.referralCode;
        print('ℹ️ Using referral code from user object: $referralCode');
      }

      if (referralCode == null || referralCode.isEmpty) {
        print('⚠️ No referral code found for user');
        return null;
      }

      // Load referral statistics in parallel
      final futures = await Future.wait([
        _loadReferralsByCode(referralCode),
        _loadPendingReferrals(userId),
        _loadReferralCredits(userId),
        _loadReferralHistory(userId),
      ]);

      final referralsByCode = futures[0];
      final pendingReferrals = futures[1];
      final referralCredits = futures[2];
      final referralHistory = futures[3];

      // Calculate statistics
      final totalReferrals = referralsByCode.length;
      final pendingCount = pendingReferrals.length;
      final completedCount = totalReferrals - pendingCount;

      double totalEarnings = 0.0;
      for (var credit in referralCredits) {
        totalEarnings += (credit['amount'] as num?)?.toDouble() ?? 0.0;
      }

      print(
          '📊 Referral Stats - Total: $totalReferrals, Pending: $pendingCount, Completed: $completedCount, Earnings: \$${totalEarnings.toStringAsFixed(2)}');

      return ReferralStats(
        referralCode: referralCode,
        totalReferrals: totalReferrals,
        pendingReferrals: pendingCount,
        completedReferrals: completedCount,
        totalEarnings: totalEarnings,
        recentReferrals: referralsByCode.take(5).toList(),
        referralHistory: referralHistory,
      );
    } catch (e) {
      print('❌ Error loading referral data: $e');
      return null;
    }
  }

  /// Loads all referrals made using a specific referral code
  static Future<List<Map<String, dynamic>>> _loadReferralsByCode(
      String referralCode) async {
    try {
      print('🔍 Loading referrals by code: $referralCode');

      final querySnapshot = await firestore
          .collection(REFERRAL)
          .where('referralBy', isEqualTo: referralCode)
          .get();

      final referrals = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id; // Add document ID
        return data;
      }).toList();

      print('✅ Found ${referrals.length} referrals by code');
      return referrals;
    } catch (e) {
      print('❌ Error loading referrals by code: $e');
      return [];
    }
  }

  /// Loads pending referrals for a user
  static Future<List<Map<String, dynamic>>> _loadPendingReferrals(
      String userId) async {
    try {
      print('🔍 Loading pending referrals for user: $userId');

      final querySnapshot = await firestore
          .collection(PENDING_REFERRALS)
          .where('referrerId', isEqualTo: userId)
          .where('isProcessed', isEqualTo: false)
          .get();

      final pendingReferrals = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();

      print('✅ Found ${pendingReferrals.length} pending referrals');
      return pendingReferrals;
    } catch (e) {
      print('❌ Error loading pending referrals: $e');
      return [];
    }
  }

  /// Loads referral credits earned by a user
  static Future<List<Map<String, dynamic>>> _loadReferralCredits(
      String userId) async {
    try {
      print('🔍 Loading referral credits for user: $userId');

      final querySnapshot = await firestore
          .collection('referral_credits')
          .where('referrerId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      final credits = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();

      print('✅ Found ${credits.length} referral credits');
      return credits;
    } catch (e) {
      print('❌ Error loading referral credits: $e');
      return [];
    }
  }

  /// Loads referral transaction history
  static Future<List<Map<String, dynamic>>> _loadReferralHistory(
      String userId) async {
    try {
      print('🔍 Loading referral history for user: $userId');

      final querySnapshot = await firestore
          .collection('referral_transactions')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(20) // Limit to recent 20 transactions
          .get();

      final history = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();

      print('✅ Found ${history.length} referral history records');
      return history;
    } catch (e) {
      print('❌ Error loading referral history: $e');
      return [];
    }
  }

  /// Gets all users who used a specific referral code
  static Future<List<Map<String, dynamic>>> getUsersByReferralCode(
      String referralCode) async {
    try {
      print('🔍 Getting users by referral code: $referralCode');

      final querySnapshot = await firestore
          .collection(REFERRAL)
          .where('referralBy', isEqualTo: referralCode)
          .get();

      List<Map<String, dynamic>> users = [];

      for (var doc in querySnapshot.docs) {
        final referralData = doc.data();
        final userId = referralData['id'];

        if (userId != null) {
          // Get user details
          try {
            final userDoc =
                await firestore.collection('users').doc(userId).get();

            if (userDoc.exists) {
              final userData = userDoc.data()!;
              users.add({
                'userId': userId,
                'email': userData['email'],
                'firstName': userData['firstName'],
                'lastName': userData['lastName'],
                'referralCode': referralData['referralCode'],
                'joinedDate': userData['createdAt'],
              });
            }
          } catch (e) {
            print('⚠️ Could not load user details for $userId: $e');
          }
        }
      }

      print('✅ Found ${users.length} users who used referral code');
      return users;
    } catch (e) {
      print('❌ Error getting users by referral code: $e');
      return [];
    }
  }

  /// Refreshes referral data by clearing cache and reloading
  static Future<ReferralStats?> refreshReferralData(String userId) async {
    print('🔄 Refreshing referral data for user: $userId');
    // Simply reload - Firebase handles caching internally
    return await loadUserReferralData(userId);
  }

  /// Gets referral settings from Firebase
  static Future<Map<String, dynamic>?> getReferralSettings() async {
    try {
      final doc =
          await firestore.collection('settings').doc('referral_amount').get();

      if (doc.exists) {
        return doc.data();
      }
    } catch (e) {
      print('❌ Error loading referral settings: $e');
    }
    return null;
  }
}
