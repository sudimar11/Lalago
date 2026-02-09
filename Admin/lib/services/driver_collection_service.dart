import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:uuid/uuid.dart';
import 'package:brgy/services/collection_lock_service.dart';

class DriverCollectionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CollectionLockService _lockService = CollectionLockService();
  static const _uuid = Uuid();

  /// Perform collection from driver with Firestore transaction
  Future<void> collectFromDriver({
    required String driverId,
    required String driverName,
    required double amount,
    required String reason,
    required String collectedBy,
    required String collectedByName,
  }) async {
    // Enhanced validation: amount must be positive
    if (amount <= 0) {
      throw Exception('Collection amount must be greater than zero');
    }

    // Enhanced validation: amount must be reasonable (not exceeding typical limits)
    if (amount > 1000000) {
      throw Exception('Collection amount exceeds maximum limit');
    }

    if (reason.trim().isEmpty) {
      throw Exception('Reason is required for collection');
    }

    // Acquire lock to prevent concurrent operations
    final lockAcquired = await _lockService.acquireLock(driverId);
    if (!lockAcquired) {
      throw Exception('Collection already in progress. Please wait.');
    }

    try {
      final userRef = _firestore.collection(USERS).doc(driverId);
      final collectionId = _uuid.v4();
      final now = Timestamp.now();

      // Capture wallet balance before transaction
      double walletBalanceBefore = 0.0;
      double walletBalanceAfter = 0.0;

      await _firestore.runTransaction((transaction) async {
        // Read driver document
        final driverSnap = await transaction.get(userRef);
        if (!driverSnap.exists) {
          throw Exception('Driver not found');
        }

        final driverData = driverSnap.data() as Map<String, dynamic>;

        // Check lock within transaction
        if (driverData['collectionInProgress'] != true) {
          throw Exception('Collection lock was released during transaction');
        }

        final currentWalletAmount =
            (driverData['wallet_amount'] as num?)?.toDouble() ?? 0.0;

        // Enhanced validation: ensure balance is non-negative before collection
        if (currentWalletAmount < 0) {
          throw Exception(
            'Invalid wallet state: balance is negative. Current: ₱${currentWalletAmount.toStringAsFixed(2)}',
          );
        }

        // Store wallet balance before collection
        walletBalanceBefore = currentWalletAmount;

        // Enhanced validation: double-check balance during transaction
        if (currentWalletAmount < amount) {
          throw Exception(
            'Insufficient wallet balance. Available: ₱${currentWalletAmount.toStringAsFixed(2)}, Required: ₱${amount.toStringAsFixed(2)}',
          );
        }

        // Calculate new wallet amount
        final newWalletAmount = currentWalletAmount - amount;

        // Enhanced validation: prevent negative balance
        if (newWalletAmount < 0) {
          throw Exception(
            'Invalid wallet balance calculation. Current: ₱${currentWalletAmount.toStringAsFixed(2)}, Collection: ₱${amount.toStringAsFixed(2)}',
          );
        }

        // Store wallet balance after collection
        walletBalanceAfter = newWalletAmount;

        // Get existing collectionRequests array or create new one
        final collectionRequests =
            (driverData['collectionRequests'] as List<dynamic>?) ?? [];

        // Create collection entry for driver's collectionRequests array
        final collectionEntry = {
          'id': collectionId,
          'amount': amount,
          'reason': reason.trim(),
          'collectedBy': collectedBy,
          'collectedByName': collectedByName,
          'createdAt': now,
          'status': 'completed',
          'collectionType': 'manual',
          'isAutoCollection': false,
        };

        // Add new collection to array
        final updatedCollectionRequests = [...collectionRequests, collectionEntry];

        // Update driver document with new wallet amount, updated array, and release lock
        transaction.update(userRef, {
          'wallet_amount': newWalletAmount,
          'collectionRequests': updatedCollectionRequests,
          'collectionInProgress': false,
          'collectionLockTimestamp': null,
          'lastCollectionCompletedAt': now,
        });
      });

      // Create document in driver_collections collection (outside transaction for audit)
      // Records are immutable - created once, never updated
      await _firestore.collection(DRIVER_COLLECTIONS).doc(collectionId).set({
        'collectionId': collectionId,
        'driverId': driverId,
        'driverName': driverName,
        'amount': amount,
        'collectionType': 'manual',
        'isAutoCollection': false,
        'reason': reason.trim(),
        'walletBalanceBefore': walletBalanceBefore,
        'walletBalanceAfter': walletBalanceAfter,
        'collectedBy': collectedBy,
        'collectedByName': collectedByName,
        'createdAt': now,
        'status': 'completed',
        'immutable': true,
      });
    } catch (e) {
      // Release lock on error
      await _lockService.releaseLock(driverId);
      rethrow;
    }
  }

  /// Validate collection request
  Future<bool> validateCollection(String driverId, double amount) async {
    if (amount <= 0) {
      return false;
    }

    try {
      final driverDoc =
          await _firestore.collection(USERS).doc(driverId).get();

      if (!driverDoc.exists) {
        return false;
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      final walletAmount =
          (driverData['wallet_amount'] as num?)?.toDouble() ?? 0.0;

      return walletAmount >= amount;
    } catch (e) {
      return false;
    }
  }

  /// Stream of collections for a specific driver
  Stream<List<Map<String, dynamic>>> getDriverCollections(String driverId) {
    return _firestore
        .collection(DRIVER_COLLECTIONS)
        .where('driverId', isEqualTo: driverId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => doc.data())
            .toList());
  }

  /// Stream of all collections (admin view)
  Stream<QuerySnapshot> getAllCollectionsStream() {
    return _firestore
        .collection(DRIVER_COLLECTIONS)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Perform auto-collection from driver (called by Cloud Function)
  Future<void> collectFromDriverAuto({
    required String driverId,
    required String driverName,
    required double amount,
  }) async {
    // Enhanced validation: amount must be positive
    if (amount <= 0) {
      throw Exception('Collection amount must be greater than zero');
    }

    // Enhanced validation: amount must be reasonable
    if (amount > 1000000) {
      throw Exception('Collection amount exceeds maximum limit');
    }

    // Acquire lock to prevent concurrent operations
    final lockAcquired = await _lockService.acquireLock(driverId);
    if (!lockAcquired) {
      throw Exception('Collection already in progress. Auto-collect skipped.');
    }

    try {
      final userRef = _firestore.collection(USERS).doc(driverId);
      final collectionId = _uuid.v4();
      final now = Timestamp.now();
      final currentHour = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().hour.toString().padLeft(2, '0')}';

      // Capture wallet balance before transaction
      double walletBalanceBefore = 0.0;
      double walletBalanceAfter = 0.0;

      await _firestore.runTransaction((transaction) async {
        // Read driver document
        final driverSnap = await transaction.get(userRef);
        if (!driverSnap.exists) {
          throw Exception('Driver not found');
        }

        final driverData = driverSnap.data() as Map<String, dynamic>;

        // Check lock within transaction
        if (driverData['collectionInProgress'] != true) {
          throw Exception('Collection lock was released during transaction');
        }

        final currentWalletAmount =
            (driverData['wallet_amount'] as num?)?.toDouble() ?? 0.0;

        // Enhanced validation: ensure balance is non-negative before collection
        if (currentWalletAmount < 0) {
          throw Exception(
            'Invalid wallet state: balance is negative. Current: ₱${currentWalletAmount.toStringAsFixed(2)}',
          );
        }

        // Store wallet balance before collection
        walletBalanceBefore = currentWalletAmount;

        // Enhanced validation: double-check balance during transaction
        if (currentWalletAmount < amount) {
          throw Exception(
            'Insufficient wallet balance. Available: ₱${currentWalletAmount.toStringAsFixed(2)}, Required: ₱${amount.toStringAsFixed(2)}',
          );
        }

        // Calculate new wallet amount
        final newWalletAmount = currentWalletAmount - amount;

        // Enhanced validation: prevent negative balance
        if (newWalletAmount < 0) {
          throw Exception(
            'Invalid wallet balance calculation. Current: ₱${currentWalletAmount.toStringAsFixed(2)}, Collection: ₱${amount.toStringAsFixed(2)}',
          );
        }

        // Store wallet balance after collection
        walletBalanceAfter = newWalletAmount;

        // Get existing collectionRequests array or create new one
        final collectionRequests =
            (driverData['collectionRequests'] as List<dynamic>?) ?? [];

        // Create collection entry for driver's collectionRequests array
        final collectionEntry = {
          'id': collectionId,
          'amount': amount,
          'reason': 'Auto-collection',
          'collectedBy': 'system',
          'collectedByName': 'Auto-Collect System',
          'createdAt': now,
          'status': 'completed',
          'collectionType': 'auto',
          'isAutoCollection': true,
        };

        // Add new collection to array
        final updatedCollectionRequests = [...collectionRequests, collectionEntry];

        // Update driver document with new wallet amount, updated array, auto-collect settings, and release lock
        final updateData = <String, dynamic>{
          'wallet_amount': newWalletAmount,
          'collectionRequests': updatedCollectionRequests,
          'autoCollectSettings.lastCollectionAt': now,
          'autoCollectSettings.lastCollectionHour': currentHour,
          'autoCollectSettings.updatedAt': now,
          'autoCollectSettings.failedAttempts': 0, // Reset on success
          'autoCollectSettings.lastFailureReason': null,
          'collectionInProgress': false,
          'collectionLockTimestamp': null,
          'lastCollectionCompletedAt': now,
        };

        transaction.update(userRef, updateData);
      });

      // Create document in driver_collections collection (outside transaction for audit)
      // Records are immutable - created once, never updated
      await _firestore.collection(DRIVER_COLLECTIONS).doc(collectionId).set({
        'collectionId': collectionId,
        'driverId': driverId,
        'driverName': driverName,
        'amount': amount,
        'collectionType': 'auto',
        'isAutoCollection': true,
        'reason': 'Auto-collection',
        'walletBalanceBefore': walletBalanceBefore,
        'walletBalanceAfter': walletBalanceAfter,
        'collectedBy': 'system',
        'collectedByName': 'Auto-Collect System',
        'createdAt': now,
        'status': 'completed',
        'immutable': true,
      });
    } catch (e) {
      // Release lock on error
      await _lockService.releaseLock(driverId);
      rethrow;
    }
  }
}

