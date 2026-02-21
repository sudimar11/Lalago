import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/main.dart';

/// Min/max bounds matching Rider DriverPerformanceService
const double _minPerformance = 50.0;
const double _maxPerformance = 100.0;

class RiderPerformanceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Update rider performance with audit log.
  /// [newValue] is clamped to 50-100.
  static Future<void> updateRiderPerformance(
    String riderId,
    double newValue,
    String reason,
  ) async {
    final clamped = newValue.clamp(_minPerformance, _maxPerformance);
    final riderRef = _firestore.collection(USERS).doc(riderId);
    final doc = await riderRef.get();

    if (!doc.exists) {
      throw Exception('Rider not found');
    }

    final previousValue =
        (doc.data()?['driver_performance'] as num?)?.toDouble() ?? 100.0;

    await riderRef.update({'driver_performance': clamped});

    final adminId = MyAppState.currentUser?.userID ?? '';
    final adminName = MyAppState.currentUser?.fullName() ?? 'Admin';

    await riderRef.collection('performance_audit').add({
      'adminId': adminId.isEmpty ? adminName : adminId,
      'adminName': adminName,
      'previousValue': previousValue,
      'newValue': clamped,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
