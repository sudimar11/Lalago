import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/pautos_config.dart';

class PautosConfigService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _docId = 'PAUTOS_SETTINGS';
  static const String _collection = 'settings';

  static Stream<PautosConfig> getPautosConfigStream() {
    return _firestore
        .collection(_collection)
        .doc(_docId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) {
        return PautosConfig();
      }
      return PautosConfig.fromJson(snap.data()!);
    });
  }

  static Future<PautosConfig> getPautosConfig() async {
    final snap = await _firestore.collection(_collection).doc(_docId).get();
    if (!snap.exists || snap.data() == null) return PautosConfig();
    return PautosConfig.fromJson(snap.data()!);
  }

  static Future<void> updatePautosConfig(PautosConfig config) async {
    config.updatedAt = Timestamp.now();
    await _firestore
        .collection(_collection)
        .doc(_docId)
        .set(config.toJson(), SetOptions(merge: true));
  }
}
