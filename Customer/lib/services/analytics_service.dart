import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:foodie_customer/utils/session_manager.dart';

/// Tracks funnel steps and user engagement for Ash analytics.
class AnalyticsService {
  AnalyticsService._();
  static final _firestore = FirebaseFirestore.instance;

  /// Track a funnel step (cart_view, checkout_start, order_place).
  static Future<void> trackFunnelStep(
    String userId,
    String stage, {
    Map<String, dynamic>? metadata,
  }) async {
    if (userId.isEmpty) return;
    try {
      await _firestore.collection('funnel_steps').add({
        'userId': userId,
        'sessionId': SessionManager.sessionId,
        'stage': stage,
        'timestamp': FieldValue.serverTimestamp(),
        ...?metadata,
      });
    } catch (e) {
      debugPrint('AnalyticsService.trackFunnelStep: $e');
    }
  }

  /// Track user engagement (app_open, app_background).
  static Future<void> trackUserEngagement(
    String userId,
    String eventType, {
    Map<String, dynamic>? metadata,
  }) async {
    if (userId.isEmpty) return;
    try {
      final date = DateTime.now().toIso8601String().split('T')[0];
      await _firestore.collection('user_engagement').add({
        'userId': userId,
        'eventType': eventType,
        'date': date,
        'timestamp': FieldValue.serverTimestamp(),
        ...?metadata,
      });
    } catch (e) {
      debugPrint('AnalyticsService.trackUserEngagement: $e');
    }
  }
}
