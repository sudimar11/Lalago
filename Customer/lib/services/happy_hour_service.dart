import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/HappyHourConfig.dart';

class HappyHourService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static const String settingsDocId = 'happyHourSettings';
  static const String settingsCollection = Setting;

  // Get current Happy Hour settings
  static Future<HappyHourSettings> getHappyHourSettings() async {
    try {
      final docSnapshot = await firestore
          .collection(settingsCollection)
          .doc(settingsDocId)
          .get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return HappyHourSettings.empty();
      }

      final data = docSnapshot.data()!;
      return HappyHourSettings.fromJson(data);
    } catch (e) {
      print('Error getting Happy Hour settings: $e');
      return HappyHourSettings.empty();
    }
  }

  // Stream of Happy Hour settings for real-time updates
  static Stream<HappyHourSettings> getHappyHourSettingsStream() {
    return firestore
        .collection(settingsCollection)
        .doc(settingsDocId)
        .snapshots()
        .map((docSnapshot) {
      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return HappyHourSettings.empty();
      }

      final data = docSnapshot.data()!;
      return HappyHourSettings.fromJson(data);
    });
  }

  // Get server timestamp for accurate time validation
  static Future<Timestamp> getServerTimestamp() async {
    try {
      // Write a temporary document to get server timestamp
      final docRef = firestore.collection('_server_time').doc('current');
      await docRef.set({'timestamp': FieldValue.serverTimestamp()});
      final snapshot = await docRef.get();
      final data = snapshot.data();
      if (data != null && data['timestamp'] != null) {
        return data['timestamp'] as Timestamp;
      }
      return Timestamp.now();
    } catch (e) {
      print('Error getting server timestamp: $e');
      // Fallback to local time if server time fails
      return Timestamp.now();
    }
  }
}

