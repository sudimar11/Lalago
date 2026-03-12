import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/working_hours_model.dart';

class VendorService {
  static const _vendors = 'vendors';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Updates the working hours for a vendor.
  Future<void> updateVendorSchedule(
    String vendorId,
    List<WorkingHoursModel> workingHours,
  ) async {
    final serialized = workingHours.map((e) => e.toJson()).toList();
    await _firestore.collection(_vendors).doc(vendorId).update({
      'workingHours': serialized,
    });
  }

  /// Updates the restaurant open/closed status.
  Future<void> updateVendorStatus(String vendorId, bool isOpen) async {
    await _firestore.collection(_vendors).doc(vendorId).update({
      'reststatus': isOpen,
    });
  }

  /// Soft-deletes a restaurant (sets isDeleted: true). Preserves data for
  /// order history. Filter isDeleted vendors when displaying the list.
  Future<void> deleteVendor(String vendorId) async {
    await _firestore.collection(_vendors).doc(vendorId).update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }
}
