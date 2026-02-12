import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

/// Service for managing collection locks to prevent concurrent operations
class CollectionLockService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Acquire lock for collection operation
  /// Returns true if lock was acquired, false if already locked
  Future<bool> acquireLock(String driverId) async {
    try {
      final result = await _firestore.runTransaction((transaction) async {
        final driverRef = _firestore.collection(USERS).doc(driverId);
        final driverSnap = await transaction.get(driverRef);

        if (!driverSnap.exists) {
          throw Exception('Driver not found');
        }

        final data = driverSnap.data()!;
        final isLocked = data['collectionInProgress'] == true;
        final lockTimestamp = data['collectionLockTimestamp'] as Timestamp?;

        // Check if lock is stale (older than 5 minutes)
        if (isLocked && lockTimestamp != null) {
          final now = DateTime.now();
          final lockAge = now.difference(lockTimestamp.toDate());

          if (lockAge.inMinutes > 5) {
            // Release stale lock
            transaction.update(driverRef, {
              'collectionInProgress': false,
              'collectionLockTimestamp': null,
              'collectionLockReleasedReason': 'timeout',
              'collectionLockReleasedAt': FieldValue.serverTimestamp(),
            });
            // Now acquire the lock
            transaction.update(driverRef, {
              'collectionInProgress': true,
              'collectionLockTimestamp': FieldValue.serverTimestamp(),
            });
            return true;
          }

          return false; // Lock is active and not stale
        }

        // Acquire lock
        transaction.update(driverRef, {
          'collectionInProgress': true,
          'collectionLockTimestamp': FieldValue.serverTimestamp(),
        });

        return true;
      });

      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Release lock after collection
  Future<void> releaseLock(String driverId) async {
    try {
      await _firestore.collection(USERS).doc(driverId).update({
        'collectionInProgress': false,
        'collectionLockTimestamp': null,
        'lastCollectionCompletedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Log error but don't throw - lock release should be best effort
      print('[CollectionLock] Error releasing lock: $e');
    }
  }

  /// Check if collection is currently in progress
  Future<bool> isLocked(String driverId) async {
    try {
      final driverDoc =
          await _firestore.collection(USERS).doc(driverId).get();

      if (!driverDoc.exists) {
        return false;
      }

      final data = driverDoc.data()!;
      final isLocked = data['collectionInProgress'] == true;

      if (!isLocked) {
        return false;
      }

      // Check if lock is stale
      final lockTimestamp = data['collectionLockTimestamp'] as Timestamp?;
      if (lockTimestamp != null) {
        final now = DateTime.now();
        final lockAge = now.difference(lockTimestamp.toDate());

        if (lockAge.inMinutes > 5) {
          // Auto-release stale lock
          await releaseLock(driverId);
          return false;
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}

