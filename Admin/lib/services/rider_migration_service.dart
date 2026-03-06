import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

/// One-time migration to fix rider status fields for dispatch precheck consistency.
class RiderMigrationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fix rider documents: ensure riderAvailability, add to zones if preset set.
  static Future<int> fixAllRiderStatuses() async {
    final snap = await _db
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER)
        .get();

    int updated = 0;
    for (final rider in snap.docs) {
      final data = rider.data();
      final updates = <String, dynamic>{};

      // Set riderAvailability if missing
      if (!data.containsKey('riderAvailability') ||
          data['riderAvailability'] == null) {
        final isOnline = data['isOnline'] == true;
        final checkedOut = data['checkedOutToday'] == true;
        updates['riderAvailability'] =
            (isOnline && !checkedOut) ? 'available' : 'offline';
      }

      // Set default maxOrders if missing (for capacity logic)
      if (!data.containsKey('maxOrders') || data['maxOrders'] == null) {
        updates['maxOrders'] = 3;
      }

      if (updates.isNotEmpty) {
        await rider.reference.update(updates);
        updated++;
      }

      // Add rider to zone based on selectedPresetLocationId
      final presetId = data['selectedPresetLocationId'] as String?;
      if (presetId != null && presetId.trim().isNotEmpty) {
        await _addRiderToZone(rider.id, presetId);
      }
    }
    return updated;
  }

  static Future<void> _addRiderToZone(String riderId, String presetId) async {
    try {
      final zoneRef =
          _db.collection('service_areas').doc(presetId);
      final zoneSnap = await zoneRef.get();
      if (!zoneSnap.exists) return;
      await zoneRef.update({
        'assignedDriverIds': FieldValue.arrayUnion([riderId]),
      });
    } catch (_) {}
  }
}
