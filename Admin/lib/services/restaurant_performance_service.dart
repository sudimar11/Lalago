import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// Service for restaurant performance metrics, pause management, and daily stats.
class RestaurantPerformanceService {
  RestaurantPerformanceService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream of all restaurants with basic info.
  static Stream<List<Map<String, dynamic>>> getRestaurantsStream() {
    return _firestore
        .collection('vendors')
        .orderBy('title')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] ?? data['authorName'] ?? 'Unknown',
          'reststatus': data['reststatus'] ?? false,
          'acceptanceMetrics': data['acceptanceMetrics'] ?? {},
          'autoPause': data['autoPause'] ?? {'isPaused': false},
        };
      }).toList();
    });
  }

  /// Get daily metrics for a vendor on a given date.
  static Future<Map<String, dynamic>> getDailyMetrics(
    String vendorId,
    DateTime date,
  ) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final doc = await _firestore
        .collection('vendors')
        .doc(vendorId)
        .collection('dailyMetrics')
        .doc(dateStr)
        .get();
    return doc.data() ?? {};
  }

  /// Stream pause history for a vendor.
  static Stream<List<Map<String, dynamic>>> getPauseHistoryStream(
    String vendorId,
  ) {
    return _firestore
        .collection('vendors')
        .doc(vendorId)
        .collection('pauseHistory')
        .orderBy('pausedAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Set restaurant pause status (admin manual pause/unpause).
  static Future<void> setRestaurantPauseStatus({
    required String vendorId,
    required bool isPaused,
    required String reason,
    String? adminId,
    DateTime? autoUnpauseAt,
  }) async {
    final uid = adminId ?? FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    final vendorRef = _firestore.collection('vendors').doc(vendorId);

    if (isPaused) {
      final updates = <String, dynamic>{
        'autoPause.isPaused': true,
        'autoPause.pausedAt': FieldValue.serverTimestamp(),
        'autoPause.pauseReason': reason,
        'autoPause.pausedBy': uid,
      };
      if (autoUnpauseAt != null) {
        updates['autoPause.autoUnpauseAt'] =
            Timestamp.fromDate(autoUnpauseAt);
      }
      await vendorRef.update(updates);

      await vendorRef.collection('pauseHistory').add({
        'pausedAt': FieldValue.serverTimestamp(),
        'pauseReason': reason,
        'pausedBy': uid,
        if (autoUnpauseAt != null)
          'autoUnpauseAt': Timestamp.fromDate(autoUnpauseAt),
      });
    } else {
      await vendorRef.update({
        'autoPause.isPaused': false,
        'autoPause.resumedAt': FieldValue.serverTimestamp(),
        'autoPause.resumedBy': uid,
        'autoPause.autoUnpauseAt': FieldValue.delete(),
      });

      final historySnap = await vendorRef
          .collection('pauseHistory')
          .where('resumedAt', isEqualTo: null)
          .orderBy('pausedAt', descending: true)
          .limit(1)
          .get();

      for (final doc in historySnap.docs) {
        await doc.reference.update({
          'resumedAt': FieldValue.serverTimestamp(),
          'resumedBy': uid,
        });
      }
    }
  }

  /// Get performance summary metrics for a date range.
  static Future<Map<String, dynamic>> getPerformanceSummary({
    required DateTime start,
    required DateTime end,
  }) async {
    final vendorsSnap = await _firestore.collection('vendors').get();
    final ordersSnap = await _firestore
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    int total = vendorsSnap.docs.length;
    int active = 0;
    int paused = 0;
    int flagged = 0;
    double totalAcceptanceRate = 0;
    int restaurantsWithOrders = 0;

    final Map<String, int> acceptedByVendor = {};
    final Map<String, int> totalByVendor = {};

    for (final doc in ordersSnap.docs) {
      final data = doc.data();
      final vendorId = _extractVendorId(data);
      if (vendorId.isEmpty) continue;

      totalByVendor[vendorId] = (totalByVendor[vendorId] ?? 0) + 1;

      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'order accepted') {
        acceptedByVendor[vendorId] =
            (acceptedByVendor[vendorId] ?? 0) + 1;
      }
    }

    for (final doc in vendorsSnap.docs) {
      final data = doc.data();
      final reststatus = data['reststatus'] == true;
      final autoPause = data['autoPause'] as Map<String, dynamic>? ?? {};
      final isPaused = autoPause['isPaused'] == true;
      final metrics = data['acceptanceMetrics'] as Map<String, dynamic>? ?? {};

      if (reststatus && !isPaused) active++;
      if (isPaused) paused++;

      final consecutive =
          (metrics['consecutiveUnaccepted'] as num?)?.toInt() ?? 0;
      final totalUnacceptedToday =
          (metrics['totalUnacceptedToday'] as num?)?.toInt() ?? 0;
      if (consecutive >= 2 || totalUnacceptedToday >= 5) flagged++;

      final vid = doc.id;
      final totalOrders = totalByVendor[vid] ?? 0;
      final accepted = acceptedByVendor[vid] ?? 0;
      if (totalOrders > 0) {
        totalAcceptanceRate += (accepted / totalOrders) * 100;
        restaurantsWithOrders++;
      }
    }

    final avgAcceptanceRate = restaurantsWithOrders > 0
        ? totalAcceptanceRate / restaurantsWithOrders
        : 100.0;

    return {
      'totalRestaurants': total,
      'activeToday': active,
      'paused': paused,
      'flagged': flagged,
      'avgAcceptanceRate': avgAcceptanceRate,
    };
  }

  /// Get order counts for a vendor in a date range.
  static Future<Map<String, int>> getOrderCountsForVendor({
    required String vendorId,
    required DateTime start,
    required DateTime end,
  }) async {
    final q1 = await _firestore
        .collection('restaurant_orders')
        .where('vendorID', isEqualTo: vendorId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final q2 = await _firestore
        .collection('restaurant_orders')
        .where('vendor.id', isEqualTo: vendorId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final seen = <String>{};
    int accepted = 0;
    int missed = 0;
    int total = 0;

    for (final doc in q1.docs) {
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);
      final data = doc.data();
      total++;
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'order accepted') {
        accepted++;
      } else if (status == 'order rejected' ||
          status == 'order placed' ||
          status == 'driver rejected') {
        missed++;
      }
    }

    for (final doc in q2.docs) {
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);
      final data = doc.data();
      total++;
      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'order accepted') {
        accepted++;
      } else if (status == 'order rejected' ||
          status == 'order placed' ||
          status == 'driver rejected') {
        missed++;
      }
    }

    return {'total': total, 'accepted': accepted, 'missed': missed};
  }

  /// Get daily average acceptance rate for chart (date string -> rate 0-100).
  static Future<Map<String, double>> getAcceptanceRateByDay({
    required DateTime start,
    required DateTime end,
  }) async {
    final ordersSnap = await _firestore
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();

    final Map<String, Map<String, int>> byDay =
        {}; // dateStr -> {vendorId: accepted count}
    final Map<String, Map<String, int>> totalByDay = {};

    for (final doc in ordersSnap.docs) {
      final data = doc.data();
      final vendorId = _extractVendorId(data);
      if (vendorId.isEmpty) continue;

      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      final dateStr = DateFormat('yyyy-MM-dd').format(createdAt.toDate());

      totalByDay.putIfAbsent(dateStr, () => {});
      totalByDay[dateStr]![vendorId] =
          (totalByDay[dateStr]![vendorId] ?? 0) + 1;

      final status = (data['status'] ?? '').toString().toLowerCase();
      if (status == 'order accepted') {
        byDay.putIfAbsent(dateStr, () => {});
        byDay[dateStr]![vendorId] = (byDay[dateStr]![vendorId] ?? 0) + 1;
      }
    }

    final result = <String, double>{};
    for (final dateStr in totalByDay.keys) {
      final totals = totalByDay[dateStr]!;
      final accepted = byDay[dateStr] ?? {};
      double sumRate = 0;
      int vendorCount = 0;
      for (final vid in totals.keys) {
        final t = totals[vid]!;
        final a = accepted[vid] ?? 0;
        if (t > 0) {
          sumRate += (a / t) * 100;
          vendorCount++;
        }
      }
      result[dateStr] =
          vendorCount > 0 ? sumRate / vendorCount : 100.0;
    }
    return result;
  }

  static String _extractVendorId(Map<String, dynamic> data) {
    final top = data['vendorID'] ?? data['vendorId'];
    if (top != null && top.toString().isNotEmpty) {
      return top.toString();
    }
    final vendor = data['vendor'];
    if (vendor is Map<String, dynamic>) {
      final id = vendor['id'] ?? vendor['vendorId'];
      if (id != null && id.toString().isNotEmpty) {
        return id.toString();
      }
    }
    return '';
  }
}
