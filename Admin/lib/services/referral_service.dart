import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/ReferralConfig.dart';
import 'package:brgy/constants.dart';

class ReferralService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static const String settingsDocId = 'REFERRAL_SYSTEM';
  static const String settingsCollection = 'settings';
  static const String referralsCollection = 'referrals';
  static const String adjustmentsCollection = 'referral_wallet_adjustments';
  static const String ordersCollection = 'restaurant_orders';

  // Get referral configuration stream
  static Stream<ReferralConfig> getReferralConfigStream() {
    return firestore
        .collection(settingsCollection)
        .doc(settingsDocId)
        .snapshots()
        .map((docSnapshot) {
      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return _getDefaultConfig();
      }

      final data = docSnapshot.data()!;
      return ReferralConfig.fromJson(data);
    });
  }

  // Get referral configuration (one-time)
  static Future<ReferralConfig> getReferralConfig() async {
    try {
      final docSnapshot = await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return _getDefaultConfig();
      }

      final data = docSnapshot.data()!;
      return ReferralConfig.fromJson(data);
    } catch (e) {
      print('Error getting referral config: $e');
      return _getDefaultConfig();
    }
  }

  // Update referral configuration
  static Future<void> updateReferralConfig(ReferralConfig config) async {
    try {
      if (!config.isValid()) {
        throw Exception('Invalid referral configuration');
      }

      config.updatedAt = Timestamp.now();

      await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .set(config.toJson(), SetOptions(merge: true));
    } catch (e) {
      print('Error updating referral config: $e');
      throw Exception('Failed to update referral configuration: $e');
    }
  }

  // Update master toggle
  static Future<void> updateMasterToggle(bool enabled) async {
    try {
      await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .set({'enabled': enabled}, SetOptions(merge: true));
    } catch (e) {
      print('Error updating master toggle: $e');
      throw Exception('Failed to update master toggle: $e');
    }
  }

  // Get referral relationships
  static Future<List<ReferralRelationship>> getReferralRelationships({
    String? referrerId,
    String? referredUserId,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          firestore.collection(referralsCollection);

      if (referrerId != null) {
        query = query.where('referrerId', isEqualTo: referrerId);
      }
      if (referredUserId != null) {
        query = query.where('referredUserId', isEqualTo: referredUserId);
      }

      final snapshot = await query.orderBy('createdAt', descending: true).get();

      return snapshot.docs
          .map((doc) => ReferralRelationship.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error getting referral relationships: $e');
      return [];
    }
  }

  // Get stream of all referral relationships
  static Stream<List<ReferralRelationship>> getReferralRelationshipsStream() {
    return firestore
        .collection(referralsCollection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ReferralRelationship.fromFirestore(doc))
          .toList();
    });
  }

  // Get user referral statistics
  static Future<UserReferralStats> getUserReferralStats(String userId) async {
    try {
      // Get user document
      final userDoc = await firestore.collection(USERS).doc(userId).get();
      final userData = userDoc.data() ?? {};

      final referralWalletBalance =
          (userData['referral_wallet_balance'] as num?)?.toDouble() ?? 0.0;
      final totalEarned =
          (userData['referral_wallet_total_earned'] as num?)?.toDouble() ?? 0.0;
      final totalUsed =
          (userData['referral_wallet_total_used'] as num?)?.toDouble() ?? 0.0;

      // Get referrals as referrer
      final referrerRelationships =
          await getReferralRelationships(referrerId: userId);

      // Get referrals as referred user
      final referredRelationships =
          await getReferralRelationships(referredUserId: userId);

      return UserReferralStats(
        userId: userId,
        referralWalletBalance: referralWalletBalance,
        totalEarned: totalEarned,
        totalUsed: totalUsed,
        referrerRelationships: referrerRelationships,
        referredRelationships: referredRelationships,
      );
    } catch (e) {
      print('Error getting user referral stats: $e');
      return UserReferralStats(
        userId: userId,
        referralWalletBalance: 0.0,
        totalEarned: 0.0,
        totalUsed: 0.0,
        referrerRelationships: [],
        referredRelationships: [],
      );
    }
  }

  // Adjust referral wallet
  static Future<void> adjustReferralWallet(
    String userId,
    String type, // "add" | "deduct"
    double amount,
    String reason,
    String adminId,
    String adminName,
  ) async {
    try {
      if (type != 'add' && type != 'deduct') {
        throw Exception('Invalid adjustment type');
      }
      if (amount <= 0) {
        throw Exception('Amount must be greater than 0');
      }
      if (reason.trim().isEmpty) {
        throw Exception('Reason is required');
      }

      // Get current user data
      final userRef = firestore.collection(USERS).doc(userId);
      final userDoc = await userRef.get();

      if (!userDoc.exists) {
        throw Exception('User not found');
      }

      final userData = userDoc.data() ?? {};
      final currentBalance =
          (userData['referral_wallet_balance'] as num?)?.toDouble() ?? 0.0;
      final previousTotalEarned =
          (userData['referral_wallet_total_earned'] as num?)?.toDouble() ?? 0.0;

      // Calculate new balance
      double newBalance;
      double newTotalEarned = previousTotalEarned;

      if (type == 'add') {
        newBalance = currentBalance + amount;
        newTotalEarned = previousTotalEarned + amount;
      } else {
        newBalance = currentBalance - amount;
        if (newBalance < 0) {
          throw Exception('Insufficient balance for deduction');
        }
      }

      // Update user document
      await userRef.update({
        'referral_wallet_balance': newBalance,
        if (type == 'add') 'referral_wallet_total_earned': newTotalEarned,
      });

      // Create adjustment log
      final adjustmentId = firestore.collection(adjustmentsCollection).doc().id;
      await firestore.collection(adjustmentsCollection).doc(adjustmentId).set({
        'id': adjustmentId,
        'userId': userId,
        'adjustmentType': type,
        'amount': amount,
        'reason': reason,
        'adminId': adminId,
        'adminName': adminName,
        'createdAt': Timestamp.now(),
        'previousBalance': currentBalance,
        'newBalance': newBalance,
      });
    } catch (e) {
      print('Error adjusting referral wallet: $e');
      throw Exception('Failed to adjust referral wallet: $e');
    }
  }

  // Get wallet adjustments for a user
  static Future<List<WalletAdjustment>> getWalletAdjustments(
      String userId) async {
    try {
      final snapshot = await firestore
          .collection(adjustmentsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => WalletAdjustment.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error getting wallet adjustments: $e');
      return [];
    }
  }

  // Get all users with referral wallet balances
  static Future<List<UserReferralWallet>> getUsersWithReferralWallets() async {
    try {
      final snapshot = await firestore
          .collection(USERS)
          .where('referral_wallet_balance', isGreaterThan: 0)
          .get();

      final users = <UserReferralWallet>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final balance =
            (data['referral_wallet_balance'] as num?)?.toDouble() ?? 0.0;
        final totalEarned =
            (data['referral_wallet_total_earned'] as num?)?.toDouble() ?? 0.0;
        final totalUsed =
            (data['referral_wallet_total_used'] as num?)?.toDouble() ?? 0.0;

        if (balance > 0) {
          users.add(UserReferralWallet(
            userId: doc.id,
            userName: '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                .trim(),
            email: data['email'] ?? '',
            phoneNumber: data['phoneNumber'] ?? '',
            currentBalance: balance,
            totalEarned: totalEarned,
            totalUsed: totalUsed,
          ));
        }
      }

      // Sort by balance descending
      users.sort((a, b) => b.currentBalance.compareTo(a.currentBalance));

      return users;
    } catch (e) {
      print('Error getting users with referral wallets: $e');
      return [];
    }
  }

  // Get stream of users with referral wallet balances
  static Stream<List<UserReferralWallet>> getUsersWithReferralWalletsStream() {
    return firestore
        .collection(USERS)
        .where('referral_wallet_balance', isGreaterThan: 0)
        .snapshots()
        .asyncMap((snapshot) async {
      final users = <UserReferralWallet>[];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final balance =
            (data['referral_wallet_balance'] as num?)?.toDouble() ?? 0.0;
        final totalEarned =
            (data['referral_wallet_total_earned'] as num?)?.toDouble() ?? 0.0;
        final totalUsed =
            (data['referral_wallet_total_used'] as num?)?.toDouble() ?? 0.0;

        if (balance > 0) {
          users.add(UserReferralWallet(
            userId: doc.id,
            userName: '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                .trim(),
            email: data['email'] ?? '',
            phoneNumber: data['phoneNumber'] ?? '',
            currentBalance: balance,
            totalEarned: totalEarned,
            totalUsed: totalUsed,
          ));
        }
      }

      users.sort((a, b) => b.currentBalance.compareTo(a.currentBalance));

      return users;
    });
  }

  // Helper to get default configuration
  static ReferralConfig _getDefaultConfig() {
    return ReferralConfig(
      enabled: false,
      rewardAmount: 0.0,
      minOrderAmount: 0.0,
    );
  }
}

// Referral Relationship model
class ReferralRelationship {
  final String id;
  final String referrerId;
  final String referredUserId;
  final String referralCode;
  final String status; // "pending" | "completed" | "cancelled"
  final String? triggeringOrderId;
  final double creditedAmount;
  final Timestamp? creditedAt;
  final Timestamp createdAt;
  final Timestamp updatedAt;

  ReferralRelationship({
    required this.id,
    required this.referrerId,
    required this.referredUserId,
    required this.referralCode,
    required this.status,
    this.triggeringOrderId,
    required this.creditedAmount,
    this.creditedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReferralRelationship.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    Timestamp? creditedAt;
    if (data['creditedAt'] != null) {
      if (data['creditedAt'] is Timestamp) {
        creditedAt = data['creditedAt'] as Timestamp;
      } else if (data['creditedAt'] is Map) {
        creditedAt = Timestamp(
          data['creditedAt']['_seconds'] ?? 0,
          data['creditedAt']['_nanoseconds'] ?? 0,
        );
      }
    }

    Timestamp createdAt;
    if (data['createdAt'] != null) {
      if (data['createdAt'] is Timestamp) {
        createdAt = data['createdAt'] as Timestamp;
      } else if (data['createdAt'] is Map) {
        createdAt = Timestamp(
          data['createdAt']['_seconds'] ?? 0,
          data['createdAt']['_nanoseconds'] ?? 0,
        );
      } else {
        createdAt = Timestamp.now();
      }
    } else {
      createdAt = Timestamp.now();
    }

    Timestamp updatedAt;
    if (data['updatedAt'] != null) {
      if (data['updatedAt'] is Timestamp) {
        updatedAt = data['updatedAt'] as Timestamp;
      } else if (data['updatedAt'] is Map) {
        updatedAt = Timestamp(
          data['updatedAt']['_seconds'] ?? 0,
          data['updatedAt']['_nanoseconds'] ?? 0,
        );
      } else {
        updatedAt = Timestamp.now();
      }
    } else {
      updatedAt = Timestamp.now();
    }

    return ReferralRelationship(
      id: doc.id,
      referrerId: data['referrerId'] ?? '',
      referredUserId: data['referredUserId'] ?? '',
      referralCode: data['referralCode'] ?? '',
      status: data['status'] ?? 'pending',
      triggeringOrderId: data['triggeringOrderId'],
      creditedAmount: (data['creditedAmount'] is num)
          ? (data['creditedAmount'] as num).toDouble()
          : 0.0,
      creditedAt: creditedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

// Wallet Adjustment model
class WalletAdjustment {
  final String id;
  final String userId;
  final String adjustmentType; // "add" | "deduct"
  final double amount;
  final String reason;
  final String adminId;
  final String adminName;
  final Timestamp createdAt;
  final double previousBalance;
  final double newBalance;

  WalletAdjustment({
    required this.id,
    required this.userId,
    required this.adjustmentType,
    required this.amount,
    required this.reason,
    required this.adminId,
    required this.adminName,
    required this.createdAt,
    required this.previousBalance,
    required this.newBalance,
  });

  factory WalletAdjustment.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    Timestamp createdAt;
    if (data['createdAt'] != null) {
      if (data['createdAt'] is Timestamp) {
        createdAt = data['createdAt'] as Timestamp;
      } else if (data['createdAt'] is Map) {
        createdAt = Timestamp(
          data['createdAt']['_seconds'] ?? 0,
          data['createdAt']['_nanoseconds'] ?? 0,
        );
      } else {
        createdAt = Timestamp.now();
      }
    } else {
      createdAt = Timestamp.now();
    }

    return WalletAdjustment(
      id: doc.id,
      userId: data['userId'] ?? '',
      adjustmentType: data['adjustmentType'] ?? '',
      amount: (data['amount'] is num)
          ? (data['amount'] as num).toDouble()
          : 0.0,
      reason: data['reason'] ?? '',
      adminId: data['adminId'] ?? '',
      adminName: data['adminName'] ?? '',
      createdAt: createdAt,
      previousBalance: (data['previousBalance'] is num)
          ? (data['previousBalance'] as num).toDouble()
          : 0.0,
      newBalance: (data['newBalance'] is num)
          ? (data['newBalance'] as num).toDouble()
          : 0.0,
    );
  }
}

// User Referral Stats model
class UserReferralStats {
  final String userId;
  final double referralWalletBalance;
  final double totalEarned;
  final double totalUsed;
  final List<ReferralRelationship> referrerRelationships;
  final List<ReferralRelationship> referredRelationships;

  UserReferralStats({
    required this.userId,
    required this.referralWalletBalance,
    required this.totalEarned,
    required this.totalUsed,
    required this.referrerRelationships,
    required this.referredRelationships,
  });
}

// User Referral Wallet model
class UserReferralWallet {
  final String userId;
  final String userName;
  final String email;
  final String phoneNumber;
  final double currentBalance;
  final double totalEarned;
  final double totalUsed;

  UserReferralWallet({
    required this.userId,
    required this.userName,
    required this.email,
    required this.phoneNumber,
    required this.currentBalance,
    required this.totalEarned,
    required this.totalUsed,
  });
}

