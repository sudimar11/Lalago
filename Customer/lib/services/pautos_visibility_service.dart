import 'package:cloud_firestore/cloud_firestore.dart';

class PautosVisibilityService {
  static const String _collection = 'settings';
  static const String _document = 'PAUTOS_SETTINGS';

  /// Stream that emits `true` when PAUTOS is enabled (default), `false` when
  /// disabled.
  static Stream<bool> getPautosEnabledStream() {
    return FirebaseFirestore.instance
        .collection(_collection)
        .doc(_document)
        .snapshots()
        .map((snapshot) {
      // If document or field missing, default to true.
      return snapshot.data()?['enabled'] != false;
    });
  }
}
