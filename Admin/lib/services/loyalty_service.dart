import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/LoyaltyConfig.dart';

class LoyaltyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _settingsCollection = 'settings';
  static const String _configDocId = 'loyaltyConfig';

  static Stream<LoyaltyConfig> getConfigStream() {
    return _firestore
        .collection(_settingsCollection)
        .doc(_configDocId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) {
        return LoyaltyConfig();
      }
      return LoyaltyConfig.fromJson(snap.data());
    });
  }

  static Future<LoyaltyConfig> getConfig() async {
    final snap = await _firestore
        .collection(_settingsCollection)
        .doc(_configDocId)
        .get();
    if (!snap.exists || snap.data() == null) {
      return LoyaltyConfig();
    }
    return LoyaltyConfig.fromJson(snap.data());
  }

  static Future<void> updateConfig(LoyaltyConfig config) async {
    config.updatedAt = Timestamp.now();
    await _firestore
        .collection(_settingsCollection)
        .doc(_configDocId)
        .set(config.toJson(), SetOptions(merge: true));
  }

  static Future<void> updateMasterToggle(bool enabled) async {
    final config = await getConfig();
    await _firestore
        .collection(_settingsCollection)
        .doc(_configDocId)
        .set(config.toJson()..['enabled'] = enabled, SetOptions(merge: true));
  }

  static Future<void> initializeDefaultConfig() async {
    final config = LoyaltyConfig(enabled: true);
    await updateConfig(config);
  }
}
