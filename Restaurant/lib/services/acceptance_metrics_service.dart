import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:foodie_restaurant/constants.dart';

/// Handles acceptance metrics (consecutive misses, auto-pause) for restaurants.
class AcceptanceMetricsService {
  AcceptanceMetricsService._();

  static final _firestore = FirebaseFirestore.instance;

  /// Increment consecutive misses when order expires or is rejected.
  static Future<void> incrementConsecutiveMisses(String vendorId) async {
    final vendorRef = _firestore.collection(VENDORS).doc(vendorId);

    await _firestore.runTransaction((transaction) async {
      final vendorSnap = await transaction.get(vendorRef);
      if (!vendorSnap.exists) return;

      final data = vendorSnap.data() ?? {};
      final metrics = Map<String, dynamic>.from(
        data['acceptanceMetrics'] ?? {
          'consecutiveUnaccepted': 0,
          'totalUnacceptedToday': 0,
          'lastResetDate': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      );

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (metrics['lastResetDate'] != today) {
        metrics['totalUnacceptedToday'] = 0;
        metrics['lastResetDate'] = today;
      }

      final current = (metrics['consecutiveUnaccepted'] ?? 0) as int;
      final todayCount = (metrics['totalUnacceptedToday'] ?? 0) as int;

      metrics['consecutiveUnaccepted'] = current + 1;
      metrics['totalUnacceptedToday'] = todayCount + 1;
      metrics['lastUnacceptedAt'] = FieldValue.serverTimestamp();

      transaction.update(vendorRef, {'acceptanceMetrics': metrics});
    });

    await checkAndTriggerAutoPause(vendorId);
  }

  /// Reset consecutive misses when restaurant accepts an order.
  static Future<void> resetConsecutiveMisses(String vendorId) async {
    final vendorRef = _firestore.collection(VENDORS).doc(vendorId);
    await vendorRef.update({
      'acceptanceMetrics.consecutiveUnaccepted': 0,
    });
  }

  /// Get current acceptance metrics for a vendor.
  static Future<Map<String, dynamic>?> getAcceptanceMetrics(
    String vendorId,
  ) async {
    final doc = await _firestore.collection(VENDORS).doc(vendorId).get();
    if (!doc.exists) return null;
    return doc.data()?['acceptanceMetrics'] as Map<String, dynamic>?;
  }

  /// Check threshold and trigger auto-pause if exceeded.
  static Future<void> checkAndTriggerAutoPause(String vendorId) async {
    final vendorRef = _firestore.collection(VENDORS).doc(vendorId);
    final vendorSnap = await vendorRef.get();
    if (!vendorSnap.exists) return;

    final data = vendorSnap.data() ?? {};
    final metrics = data['acceptanceMetrics'] as Map<String, dynamic>? ?? {};
    final settings =
        data['acceptanceSettings'] as Map<String, dynamic>? ?? {};

    final consecutive =
        (metrics['consecutiveUnaccepted'] ?? 0) as int;
    final threshold =
        (settings['consecutiveMissesThreshold'] ?? 2) as int;
    final autoPauseEnabled = settings['autoPauseEnabled'] != false;

    if (consecutive < threshold || !autoPauseEnabled) return;

    final now = DateTime.now();
    var autoUnpauseAt = DateTime(now.year, now.month, now.day, 6, 0, 0);
    if (autoUnpauseAt.isBefore(now)) {
      autoUnpauseAt = autoUnpauseAt.add(const Duration(days: 1));
    }

    await vendorRef.update({
      'autoPause': {
        'isPaused': true,
        'pausedAt': FieldValue.serverTimestamp(),
        'pauseReason': 'consecutive_unaccepted',
        'autoUnpauseAt': Timestamp.fromDate(autoUnpauseAt),
        'pausedBy': 'system',
      },
    });

    await logPauseEvent(
      vendorId,
      'consecutive_unaccepted',
      consecutiveMisses: consecutive,
      autoUnpauseAt: autoUnpauseAt,
    );
  }

  /// Log a pause event to pauseHistory subcollection.
  static Future<void> logPauseEvent(
    String vendorId,
    String reason, {
    int? consecutiveMisses,
    DateTime? autoUnpauseAt,
  }) async {
    await _firestore
        .collection(VENDORS)
        .doc(vendorId)
        .collection('pauseHistory')
        .add({
      'pauseReason': reason,
      'consecutiveMisses': consecutiveMisses ?? 0,
      'pausedAt': FieldValue.serverTimestamp(),
      if (autoUnpauseAt != null)
        'autoUnpauseAt': Timestamp.fromDate(autoUnpauseAt),
    });
  }
}
