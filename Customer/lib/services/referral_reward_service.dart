import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/referral_wallet_transaction.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';

class ReferralRewardConfig {
  final bool isEnabled;
  final double rewardAmount;
  final String rewardType; // "fixed" or "percentage"

  ReferralRewardConfig({
    required this.isEnabled,
    required this.rewardAmount,
    required this.rewardType,
  });

  factory ReferralRewardConfig.fromJson(Map<String, dynamic> json) {
    return ReferralRewardConfig(
      isEnabled: json['isEnabled'] is bool ? json['isEnabled'] : false,
      rewardAmount: (json['rewardAmount'] ?? 0.0).toDouble(),
      rewardType: json['rewardType'] ?? 'fixed',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isEnabled': this.isEnabled,
      'rewardAmount': this.rewardAmount,
      'rewardType': this.rewardType,
    };
  }

  static ReferralRewardConfig getDefault() {
    return ReferralRewardConfig(
      isEnabled: false,
      rewardAmount: 0.0,
      rewardType: 'fixed',
    );
  }
}

class ReferralRewardService {
  static const String settingsDocId = 'REFERRAL_REWARD';
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  /// Get referral reward configuration
  static Future<ReferralRewardConfig> getReferralRewardConfig() async {
    try {
      final doc = await firestore
          .collection(Setting)
          .doc(settingsDocId)
          .get();

      if (doc.exists && doc.data() != null) {
        return ReferralRewardConfig.fromJson(doc.data()!);
      } else {
        return ReferralRewardConfig.getDefault();
      }
    } catch (e) {
      print('Error getting referral reward config: $e');
      return ReferralRewardConfig.getDefault();
    }
  }

  /// Process referral reward when referred user completes first order
  static Future<bool> processReferralReward({
    required String refereeUserId,
    required String orderId,
  }) async {
    try {
      // Get the referred user
      final refereeUser = await FireStoreUtils.getCurrentUser(refereeUserId);
      if (refereeUser == null) {
        print('❌ Referred user not found: $refereeUserId');
        return false;
      }

      // Check if user has a referrer
      if (refereeUser.referredBy == null || refereeUser.referredBy!.isEmpty) {
        print('ℹ️ User has no referrer');
        return false;
      }

      // Check if this is the user's first completed order
      if (!refereeUser.hasCompletedFirstOrder) {
        print('ℹ️ This is not the user\'s first completed order');
        return false;
      }

      // Get referrer's user ID from referral code
      // The referredBy field contains the referral code, so we need to find the user who owns that code
      final referralDoc = await firestore
          .collection(REFERRAL)
          .where('referralCode', isEqualTo: refereeUser.referredBy)
          .limit(1)
          .get();

      String? referrerId;
      if (referralDoc.docs.isNotEmpty) {
        // Get user ID from referral document
        final referralData = referralDoc.docs.first.data();
        referrerId = referralData['id'] ?? referralDoc.docs.first.id;
      } else {
        // Fallback: try to find user by referral code directly
        final userQuery = await firestore
            .collection(USERS)
            .where('referralCode', isEqualTo: refereeUser.referredBy)
            .limit(1)
            .get();
        
        if (userQuery.docs.isNotEmpty) {
          referrerId = userQuery.docs.first.id;
        }
      }

      if (referrerId == null || referrerId.isEmpty) {
        print('❌ Referral code not found: ${refereeUser.referredBy}');
        return false;
      }

      // Check if referral reward already processed
      final existingReward = await firestore
          .collection('referral_rewards')
          .where('refereeId', isEqualTo: refereeUserId)
          .where('isProcessed', isEqualTo: true)
          .limit(1)
          .get();

      if (existingReward.docs.isNotEmpty) {
        print('ℹ️ Referral reward already processed for user: $refereeUserId');
        return false;
      }

      // Get reward configuration
      final config = await getReferralRewardConfig();
      if (!config.isEnabled || config.rewardAmount <= 0) {
        print('ℹ️ Referral rewards disabled or amount is 0');
        return false;
      }

      // Get referrer user
      final referrerUser = await FireStoreUtils.getCurrentUser(referrerId);
      if (referrerUser == null) {
        print('❌ Referrer user not found: $referrerId');
        return false;
      }

      // Credit referral wallet amount
      final newReferralWalletAmount =
          (referrerUser.referralWalletAmount + config.rewardAmount);

      // Update referrer's referral wallet amount
      await firestore.collection(USERS).doc(referrerId).update({
        'referralWalletAmount': newReferralWalletAmount,
      });

      // Create transaction record
      final transaction = ReferralWalletTransaction(
        userId: referrerId,
        type: 'credit',
        amount: config.rewardAmount,
        orderId: orderId,
        referralId: refereeUserId,
        description:
            'Referral reward for ${refereeUser.firstName} ${refereeUser.lastName}',
        createdAt: Timestamp.now(),
      );

      await firestore
          .collection('referral_wallet_transactions')
          .add(transaction.toJson());

      // Mark referral as processed
      await firestore.collection('referral_rewards').add({
        'referrerId': referrerId,
        'refereeId': refereeUserId,
        'referralCode': refereeUser.referredBy,
        'rewardAmount': config.rewardAmount,
        'orderId': orderId,
        'isProcessed': true,
        'processedAt': Timestamp.now(),
        'createdAt': Timestamp.now(),
      });

      print(
          '✅ Referral reward processed: $referrerId received ${config.rewardAmount}');
      return true;
    } catch (e, stackTrace) {
      print('❌ Error processing referral reward: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Get referral history for a user
  static Future<List<Map<String, dynamic>>> getReferralHistory(
      String userId) async {
    try {
      final querySnapshot = await firestore
          .collection('referral_rewards')
          .where('referrerId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error getting referral history: $e');
      return [];
    }
  }

  /// Get users referred by a specific referral code
  static Future<List<Map<String, dynamic>>> getReferredUsers(
      String referralCode) async {
    try {
      // Get all users who used this referral code
      final referralQuery = await firestore
          .collection(REFERRAL)
          .where('referralBy', isEqualTo: referralCode)
          .get();

      List<Map<String, dynamic>> referredUsers = [];

      for (var referralDoc in referralQuery.docs) {
        final referralData = referralDoc.data();
        final refereeId = referralData['id'] ?? referralDoc.id;

        // Get user details
        final userDoc = await firestore.collection(USERS).doc(refereeId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          final user = User.fromJson(userData);

          // Check order status
          String status = 'Registered';
          bool hasOrdered = false;
          bool hasCompleted = false;

          // Check if user has placed any order
          final ordersQuery = await firestore
              .collection(ORDERS)
              .where('authorID', isEqualTo: refereeId)
              .limit(1)
              .get();

          if (ordersQuery.docs.isNotEmpty) {
            hasOrdered = true;
            status = 'Ordered';

            // Check if user has completed first order
            if (user.hasCompletedFirstOrder) {
              hasCompleted = true;
              status = 'Completed';
            }
          }

          // Check if reward was processed
          final rewardQuery = await firestore
              .collection('referral_rewards')
              .where('refereeId', isEqualTo: refereeId)
              .where('isProcessed', isEqualTo: true)
              .limit(1)
              .get();

          final rewardState = rewardQuery.docs.isNotEmpty ? 'credited' : 'pending';
          final rewardAmount = rewardQuery.docs.isNotEmpty
              ? (rewardQuery.docs.first.data()['rewardAmount'] ?? 0.0)
              : 0.0;

          referredUsers.add({
            'userId': refereeId,
            'firstName': user.firstName,
            'lastName': user.lastName,
            'email': user.email,
            'status': status,
            'hasOrdered': hasOrdered,
            'hasCompleted': hasCompleted,
            'rewardAmount': rewardAmount,
            'rewardState': rewardState,
            'joinedDate': user.createdAt,
          });
        }
      }

      return referredUsers;
    } catch (e) {
      print('Error getting referred users: $e');
      return [];
    }
  }
}

