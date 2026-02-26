import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/utils/session_manager.dart';

/// Logs restaurant clicks for recommendation analytics.
class ClickTrackingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> logClick({
    required String userId,
    required String restaurantId,
    required String source,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      SessionManager.recordActivity();
      final sessionId = SessionManager.sessionId;

      String appVersion = 'unknown';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {}

      await _firestore.collection(USER_CLICKS).add({
        'userId': userId,
        'restaurantId': restaurantId,
        'source': source,
        'sessionId': sessionId,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': metadata ?? {},
        'platform': Platform.operatingSystem,
        'appVersion': appVersion,
      });
    } catch (e) {
      // Silently ignore tracking errors
      assert(false, 'ClickTrackingService.logClick error: $e');
    }
  }

  static Future<void> logOrderFromClick({
    required String clickId,
    required String orderId,
  }) async {
    try {
      await _firestore.collection(USER_CLICKS).doc(clickId).update({
        'convertedToOrder': true,
        'orderId': orderId,
        'convertedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      assert(false, 'ClickTrackingService.logOrderFromClick error: $e');
    }
  }
}
