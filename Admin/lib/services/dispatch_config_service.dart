import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for reading and writing global dispatch settings
/// (e.g. auto-dispatch enable/disable toggle).
class DispatchConfigService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference get _settingsRef =>
      _firestore.collection('config').doc('dispatch_settings');

  /// Read auto-dispatch enabled flag. Defaults to true if document missing.
  Future<bool> getAutoDispatchEnabled() async {
    final doc = await _settingsRef.get();
    if (!doc.exists || doc.data() == null) {
      return true;
    }
    final data = doc.data()! as Map<String, dynamic>;
    return data['autoDispatchEnabled'] as bool? ?? true;
  }

  /// Stream auto-dispatch enabled for real-time UI updates.
  Stream<bool> streamAutoDispatchEnabled() {
    return _settingsRef.snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return true;
      }
      final data = snap.data()! as Map<String, dynamic>;
      return data['autoDispatchEnabled'] as bool? ?? true;
    });
  }

  /// Update auto-dispatch toggle. Writes to Firestore and logs to dispatch_events.
  Future<void> setAutoDispatchEnabled(
    bool value, {
    String? adminUid,
  }) async {
    final uid = adminUid ??
        FirebaseAuth.instance.currentUser?.uid ??
        'admin_ui';
    final previous = await getAutoDispatchEnabled();

    await _settingsRef.set(
      {
        'autoDispatchEnabled': value,
        'lastModified': FieldValue.serverTimestamp(),
        'lastModifiedBy': uid,
      },
      SetOptions(merge: true),
    );

    await _logToggle(
      newValue: value,
      previousValue: previous,
      adminUid: uid,
    );
  }

  Future<void> _logToggle({
    required bool newValue,
    required bool previousValue,
    required String adminUid,
  }) async {
    try {
      await _firestore.collection('dispatch_events').add({
        'type': 'auto_dispatch_toggled',
        'payload': {
          'enabled': newValue,
          'adminUid': adminUid,
          'previousValue': previousValue,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'admin_ui',
      });
    } catch (e) {
      // Non-fatal; settings were saved
      print('[DispatchConfigService] Failed to log toggle: $e');
    }
  }
}
