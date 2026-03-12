import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Service for Ash notification history.
/// Cloud Functions create history docs when sending; client calls markOpened
/// when user taps a notification.
class AshNotificationHistory {
  static const String _collection = 'ash_notification_history';

  /// Marks a notification as opened when user taps it.
  static Future<void> markOpened(String notificationId, {String? action}) async {
    try {
      if (notificationId.isEmpty) return;

      await FirebaseFirestore.instance.collection(_collection).doc(notificationId).update({
        'openedAt': FieldValue.serverTimestamp(),
        'actionTimestamp': FieldValue.serverTimestamp(),
        if (action != null) 'actionTaken': action,
      });
    } catch (e) {
      // Best-effort; don't crash the app
      debugPrint('AshNotificationHistory.markOpened failed: $e');
    }
  }
}
