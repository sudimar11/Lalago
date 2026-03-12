import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:foodie_customer/constants.dart';

class TimezoneService {
  static Future<void> updateUserTimezone() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null || userId.isEmpty) return;

      final timezone = await FlutterTimezone.getLocalTimezone();

      await FirebaseFirestore.instance.collection(USERS).doc(userId).update({
        'timezone': timezone,
        'timezoneUpdated': FieldValue.serverTimestamp(),
      });

      debugPrint(
          'TimezoneService: Updated timezone for user $userId: $timezone');
    } catch (e) {
      debugPrint('TimezoneService: Failed to update timezone: $e');
      try {
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId != null) {
          await FirebaseFirestore.instance.collection(USERS).doc(userId).update({
            'timezone': 'Asia/Manila',
            'timezoneUpdated': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {}
    }
  }

  static Future<String> getUserTimezone(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(USERS)
          .doc(userId)
          .get();
      return doc.data()?['timezone'] as String? ?? 'Asia/Manila';
    } catch (e) {
      return 'Asia/Manila';
    }
  }
}
