import 'package:cloud_firestore/cloud_firestore.dart';

/// Fetches demand health data from Firestore.
class DemandHealthService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'demand_health';

  /// Stream of latest health score document.
  static Stream<DocumentSnapshot<Map<String, dynamic>>?> streamLatestHealth() {
    return _db
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty ? s.docs.first : null);
  }

  /// Fetch latest health score.
  static Future<Map<String, dynamic>?> getLatestHealth() async {
    final snap = await _db
        .collection(_collection)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data();
  }

  /// Fetch health history for last N days.
  static Future<List<Map<String, dynamic>>> getHealthHistory(int days) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final snap = await _db
        .collection(_collection)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .orderBy('timestamp', descending: false)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }
}
