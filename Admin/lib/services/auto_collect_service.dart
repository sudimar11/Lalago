import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class AutoCollectService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get auto-collect settings for a driver
  Future<Map<String, dynamic>?> getAutoCollectSettings(String driverId) async {
    try {
      final driverDoc =
          await _firestore.collection(USERS).doc(driverId).get();

      if (!driverDoc.exists) {
        return null;
      }

      final driverData = driverDoc.data();
      final autoCollectSettings =
          driverData?['autoCollectSettings'] as Map<String, dynamic>?;

      return autoCollectSettings;
    } catch (e) {
      return null;
    }
  }

  /// Update auto-collect settings
  Future<void> updateAutoCollectSettings({
    required String driverId,
    required bool enabled,
    required double amount,
    required String scheduleTime,
    required String frequency,
  }) async {
    if (amount <= 0) {
      throw Exception('Collection amount must be greater than zero');
    }

    final now = Timestamp.now();
    final autoCollectSettings = {
      'enabled': enabled,
      'amount': amount,
      'scheduleTime': scheduleTime,
      'frequency': frequency,
      'updatedAt': now,
      if (enabled) 'createdAt': now,
    };

    await _firestore.collection(USERS).doc(driverId).update({
      'autoCollectSettings': autoCollectSettings,
    });
  }

  /// Disable auto-collect
  Future<void> disableAutoCollect(String driverId) async {
    final now = Timestamp.now();
    await _firestore.collection(USERS).doc(driverId).update({
      'autoCollectSettings.enabled': false,
      'autoCollectSettings.updatedAt': now,
    });
  }

  /// Check if collection should execute (duplicate prevention)
  Future<bool> shouldExecuteCollection(String driverId, DateTime now) async {
    try {
      final settings = await getAutoCollectSettings(driverId);
      if (settings == null || settings['enabled'] != true) {
        return false;
      }

      final scheduleTime = settings['scheduleTime'] as String? ?? '';
      if (scheduleTime.isEmpty) {
        return false;
      }

      // Parse schedule time (HH:mm format)
      final timeParts = scheduleTime.split(':');
      if (timeParts.length != 2) {
        return false;
      }

      final scheduleHour = int.tryParse(timeParts[0]);
      final scheduleMinute = int.tryParse(timeParts[1]);

      if (scheduleHour == null || scheduleMinute == null) {
        return false;
      }

      // Check if current time matches schedule time (within the same hour)
      if (now.hour != scheduleHour) {
        return false;
      }

      // Check duplicate prevention - same hour
      final currentHour = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}';
      final lastCollectionHour = settings['lastCollectionHour'] as String?;

      if (lastCollectionHour == currentHour) {
        return false; // Already collected this hour
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Execute auto-collection (called by Cloud Function or manually)
  Future<void> executeAutoCollection(String driverId) async {
    try {
      final settings = await getAutoCollectSettings(driverId);
      if (settings == null || settings['enabled'] != true) {
        throw Exception('Auto-collect is not enabled for this driver');
      }

      final amount = (settings['amount'] as num?)?.toDouble() ?? 0.0;
      if (amount <= 0) {
        throw Exception('Invalid collection amount');
      }

      // Get driver name
      final driverDoc = await _firestore.collection(USERS).doc(driverId).get();
      if (!driverDoc.exists) {
        throw Exception('Driver not found');
      }

      final driverData = driverDoc.data() as Map<String, dynamic>;
      final firstName = (driverData['firstName'] ?? '').toString();
      final lastName = (driverData['lastName'] ?? '').toString();
      final driverName = '$firstName $lastName'.trim();
      if (driverName.isEmpty) {
        throw Exception('Driver name not found');
      }

      // Execute collection using the collection service
      // Note: This will be called from Cloud Function, so we need to import
      // the collection service or duplicate the logic here
      // For now, we'll update the settings after collection
      final now = Timestamp.now();
      final currentHour = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}-${DateTime.now().hour.toString().padLeft(2, '0')}';

      await _firestore.collection(USERS).doc(driverId).update({
        'autoCollectSettings.lastCollectionAt': now,
        'autoCollectSettings.lastCollectionHour': currentHour,
        'autoCollectSettings.updatedAt': now,
      });
    } catch (e) {
      rethrow;
    }
  }
}

