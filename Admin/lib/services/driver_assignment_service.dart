import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/services/order_notification_service.dart';
import 'package:brgy/services/delivery_zone_service.dart';
import 'package:brgy/services/zone_capacity_service.dart';
import 'package:brgy/services/dispatch_scoring_service.dart';
import 'package:brgy/services/acceptance_probability_service.dart';
import 'package:brgy/services/routing_service.dart';
import 'package:brgy/services/dynamic_capacity_service.dart';

/// Service responsible for finding and assigning drivers to orders.
/// Uses multi-factor scoring algorithm for optimal driver selection.
class DriverAssignmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static int? _cachedInactivityTimeoutMinutes;
  static DateTime? _inactivityTimeoutCachedAt;
  static const Duration _inactivityTimeoutCacheTtl = Duration(seconds: 60);

  Future<int> _getRiderTimeoutSeconds() async {
    try {
      final w = await DispatchScoringService.loadWeights();
      return w.riderTimeoutSeconds;
    } catch (_) {
      return 60;
    }
  }

  Future<int> _getInactivityTimeoutMinutes() async {
    final now = DateTime.now();
    if (_cachedInactivityTimeoutMinutes != null &&
        _inactivityTimeoutCachedAt != null &&
        now.difference(_inactivityTimeoutCachedAt!) <
            _inactivityTimeoutCacheTtl) {
      return _cachedInactivityTimeoutMinutes!;
    }
    try {
      final doc = await _firestore
          .collection('config')
          .doc('rider_time_settings')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = doc.data();
      final v = data?['inactivityTimeoutMinutes'];
      final mins = v is int ? v : (v is num ? v.toInt() : 15);
      _cachedInactivityTimeoutMinutes = mins;
      _inactivityTimeoutCachedAt = now;
      return mins;
    } catch (_) {
      _cachedInactivityTimeoutMinutes ??= 15;
      return _cachedInactivityTimeoutMinutes!;
    }
  }
  final OrderNotificationService _notificationService =
      OrderNotificationService();
  final ZoneCapacityService _capacityService =
      ZoneCapacityService();

  static const int maxActiveOrdersPerRider = 2;

  static int _activeOrderCount(Map<String, dynamic> driverData) {
    final raw = driverData['inProgressOrderID'];
    if (raw is List) return raw.length;
    if (raw is num) return raw.toInt();
    return 0;
  }

  /// Find and assign the best available driver to an order
  /// Returns a map with success status and driver information.
  /// When delivery info is provided, restricts to riders in matching service area.
  Future<Map<String, dynamic>> findAndAssignDriver({
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    String? excludeDriverId,
    double? deliveryLat,
    double? deliveryLng,
    String? deliveryLocality,
    double? restaurantPrepMinutes,
    required void Function({
      required String orderId,
      required String driverId,
      required String assignmentLogId,
    }) setupDriverResponseListener,
  }) async {
    try {
      // Phase 1A: Acquire dispatch lock
      final orderRef =
          _firestore.collection('restaurant_orders').doc(orderId);
      final lockAcquired =
          await _firestore.runTransaction<bool>((tx) async {
        final snap = await tx.get(orderRef);
        final data = snap.data() ?? {};
        final dispatch =
            data['dispatch'] as Map<String, dynamic>? ?? {};
        final lock = dispatch['lock'] as bool? ?? false;
        final lockExpires =
            dispatch['lockExpiresAt'] as Timestamp?;
        final now = Timestamp.now();
        if (lock &&
            lockExpires != null &&
            lockExpires.seconds > now.seconds) {
          return false;
        }
        tx.update(orderRef, {
          'dispatch.lock': true,
          'dispatch.lockHolder': 'admin_ui',
          'dispatch.lockAcquiredAt':
              FieldValue.serverTimestamp(),
          'dispatch.lockExpiresAt':
              Timestamp(now.seconds + 60, 0),
        });
        return true;
      });

      if (!lockAcquired) {
        return {
          'success': false,
          'reason':
              'Dispatch already in progress from another path',
        };
      }

      List<QueryDocumentSnapshot<Map<String, dynamic>>> driverDocs;
      List<String>? zoneDriverIds;
      DeliveryZoneMatch? zoneMatch;

      if (deliveryLat != null ||
          deliveryLng != null ||
          (deliveryLocality?.trim().isNotEmpty == true)) {
        zoneMatch = await DeliveryZoneService()
            .getZoneMatchForDelivery(
          lat: deliveryLat,
          lng: deliveryLng,
          locality: deliveryLocality,
        );
        zoneDriverIds = zoneMatch?.driverIds;
      }

      // Capacity check: if the matched zone has a rider cap, verify
      if (zoneMatch != null) {
        final hasRoom = await _capacityService
            .hasCapacityForNewRider(zoneMatch.zone.id);
        if (!hasRoom) {
          final zc = await _capacityService
              .getZoneCapacity(zoneMatch.zone.id);
          final current = zc?.currentActiveRiders ?? 0;
          final max = zc?.maxRiders ?? 0;
          await _firestore.collection('assignments_log').add({
            'order_id': orderId,
            'status': 'zone_at_capacity',
            'zoneId': zoneMatch.zone.id,
            'zoneName': zoneMatch.zone.name,
            'currentRiders': current,
            'maxRiders': max,
            'createdAt': FieldValue.serverTimestamp(),
          });
          return {
            'success': false,
            'reason': 'Zone at capacity. '
                '$current/$max riders active in '
                '${zoneMatch.zone.name}.',
          };
        }
      }

      final driversQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();

      if (zoneDriverIds != null && zoneDriverIds.isNotEmpty) {
        driverDocs = driversQuery.docs
            .where((d) => zoneDriverIds!.contains(d.id))
            .toList();
        if (driverDocs.isEmpty) {
          return {
            'success': false,
            'reason':
                'No active drivers in this delivery zone',
          };
        }
      } else {
        driverDocs = driversQuery.docs;
      }

      print('[Dispatch] After zone filter: ${driverDocs.length} drivers'
          '${zoneDriverIds != null ? " (zone restricted to ${zoneDriverIds.length} IDs)" : ""}');

      if (driverDocs.isEmpty) {
        return {'success': false, 'reason': 'No drivers'};
      }

      final weights =
          await DispatchScoringService.loadWeights();

      final drivers = await _buildDriversListScored(
        driverDocs,
        vendorLat,
        vendorLng,
        excludeDriverId,
        restaurantPrepMinutes ?? 0,
        weights,
      );

      if (drivers.isEmpty) {
        await orderRef.update({'dispatch.lock': false});
        return {
          'success': false,
          'reason': 'No active drivers with valid location',
        };
      }

      drivers.sort((a, b) =>
          (a['score'] as double).compareTo(b['score'] as double));

      // Select the best driver
      final selectedDriver = drivers.first;
      final driverId = selectedDriver['id'] as String;
      final driverData = selectedDriver['data'] as Map<String, dynamic>;
      final distance = selectedDriver['distance'] as double;

      final driverName =
          '${driverData['firstName'] ?? ''} ${driverData['lastName'] ?? ''}'
              .trim();

      print(
          '[Driver Assignment] Found driver: $driverName ($driverId) at ${distance.toStringAsFixed(2)} km');

      // Assign driver to order + update driver (atomic transaction)
      await _assignDriverToOrder(orderId, driverId, distance);

      final driverDataMap =
          selectedDriver['data'] as Map<String, dynamic>?;
      final riderOrders = driverDataMap != null
          ? _activeOrderCount(driverDataMap)
          : 0;

      // Read batch fields from the order if present
      final orderSnap = await _firestore
          .collection('restaurant_orders')
          .doc(orderId)
          .get();
      final orderData = orderSnap.data() ?? {};
      final orderBatchId =
          orderData['batch']?['batchId'] as String?;
      final orderZoneId = (orderData['zoneId'] ??
              orderData['vendorID'] ??
              '')
          .toString();

      final assignmentLogRef = await _logAssignment(
        orderId,
        driverId,
        distance,
        scoreComponents:
            selectedDriver['scoreComponents']
                as Map<String, double>?,
        totalScore: selectedDriver['score'] as double?,
        acceptanceProb:
            selectedDriver['acceptanceProb'] as double?,
        alternativeDrivers: drivers.length > 1
            ? drivers.skip(1).take(5).map((d) {
                return {
                  'riderId': d['id'],
                  'score': d['score'],
                  'distance': d['distance'],
                };
              }).toList()
            : null,
        riderCurrentOrders: riderOrders,
        riderHeadingMatch:
            selectedDriver['headingMatch'] as double?,
        restaurantPrepMinutes: restaurantPrepMinutes,
        batchId: orderBatchId,
        zoneId: orderZoneId,
        activeWeights: weights,
        routingSource:
            selectedDriver['routingSource'] as String?,
        durationMinutes:
            selectedDriver['durationMinutes'] as double?,
      );

      print(
          '[Driver Assignment] Assignment logged with ID: ${assignmentLogRef.id}');

      // Set up listener to track driver response
      setupDriverResponseListener(
        orderId: orderId,
        driverId: driverId,
        assignmentLogId: assignmentLogRef.id,
      );

      // Send SMS notification to driver
      await _notificationService.sendDriverAssignmentNotification(
        driverId: driverId,
        orderId: orderId,
      );

      return {
        'success': true,
        'driverId': driverId,
        'driverName': driverName.isEmpty ? 'Driver' : driverName,
        'distance': distance,
      };
    } catch (e, stackTrace) {
      print('[Driver Assignment] Error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Assign an order to a specific driver (e.g. the recommended rider).
  /// Caller must ensure driver has fewer than maxActiveOrdersPerRider.
  Future<void> assignOrderToDriver({
    required String orderId,
    required String driverId,
    required double distance,
    required void Function({
      required String orderId,
      required String driverId,
      required String assignmentLogId,
    }) setupDriverResponseListener,
  }) async {
    await _assignDriverToOrder(orderId, driverId, distance);
    final assignmentLogRef =
        await _logAssignment(orderId, driverId, distance);
    setupDriverResponseListener(
      orderId: orderId,
      driverId: driverId,
      assignmentLogId: assignmentLogRef.id,
    );
    await _notificationService.sendDriverAssignmentNotification(
      driverId: driverId,
      orderId: orderId,
    );
  }

  /// Fetch drivers filtered by zone. If [driverIds] is null or empty,
  /// returns all active drivers (same as fetchActiveDriversWithLocations).
  Future<List<Map<String, dynamic>>> fetchActiveDriversInZone(
    List<String>? driverIds,
  ) async {
    final all = await fetchActiveDriversWithLocations();
    if (driverIds == null || driverIds.isEmpty) return all;
    return all.where((e) => driverIds.contains(e['id'] as String)).toList();
  }

  /// Fetch drivers who are available for dispatch with valid location.
  /// Returns list of { 'id': doc.id, 'data': doc.data() }.
  Future<List<Map<String, dynamic>>> fetchActiveDriversWithLocations() async {
    final driversQuery = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .where('riderAvailability', isEqualTo: 'available')
        .get();

    final List<Map<String, dynamic>> result = [];
    for (final doc in driversQuery.docs) {
      final driverData = doc.data();
      final location = driverData['location'];
      if (location != null && location is Map) {
        final driverLat = _asDouble(location['latitude']) ?? 0.0;
        final driverLng = _asDouble(location['longitude']) ?? 0.0;
        if (driverLat != 0.0 && driverLng != 0.0) {
          result.add({'id': doc.id, 'data': driverData});
        }
      }
    }
    print('[Recommendation] fetchActiveDriversWithLocations count=${result.length}');
    return result;
  }

  /// Synchronous recommendation for UI display using simple
  /// distance+penalty scoring. Use the async variant for dispatch.
  Map<String, dynamic>? getRecommendedDriverFromListSync(
    List<Map<String, dynamic>> drivers,
    double vendorLat,
    double vendorLng,
  ) {
    if (drivers.isEmpty || vendorLat == 0.0 || vendorLng == 0.0) {
      return null;
    }
    final w = DispatchScoringService.cachedWeights ??
        const DispatchWeights();
    final isPeak = DispatchScoringService.isPeakHourNow(w);
    final List<Map<String, dynamic>> scored = [];
    for (final entry in drivers) {
      final id = entry['id'] as String?;
      final d = entry['data'] as Map<String, dynamic>?;
      if (id == null || d == null) continue;
      final effCap = DynamicCapacityService.calculateEffectiveCapacity(
        w: w,
        isPeakHour: isPeak,
        driverPerformance:
            (d['driver_performance'] as num?)?.toDouble() ?? 0,
        multipleOrders: d['multipleOrders'] == true,
      );
      if (_activeOrderCount(d) >= effCap) continue;
      final loc = d['location'];
      if (loc is Map) {
        final lat = _asDouble(loc['latitude']) ?? 0.0;
        final lng = _asDouble(loc['longitude']) ?? 0.0;
        if (lat != 0.0 && lng != 0.0) {
          final dist = _calculateDistance(
              vendorLat, vendorLng, lat, lng);
          final orders = _activeOrderCount(d);
          scored.add({
            'id': id,
            'data': d,
            'distance': dist,
            'simpleScore': dist + (orders * 3.0),
          });
        }
      }
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => (a['simpleScore'] as double)
        .compareTo(b['simpleScore'] as double));
    final best = scored.first;
    final bd = best['data'] as Map<String, dynamic>;
    final name =
        '${bd['firstName'] ?? ''} ${bd['lastName'] ?? ''}'.trim();
    final status =
        bd['riderDisplayStatus'] as String? ?? '';
    return {
      'driverId': best['id'] as String,
      'driverName': name.isEmpty ? 'Driver' : name,
      'distance': best['distance'] as double,
      'riderDisplayStatus': status,
    };
  }

  /// Async recommendation with full multi-factor scoring.
  /// Returns { 'driverId', 'driverName', 'distance' } or null.
  Future<Map<String, dynamic>?> getRecommendedDriverFromList(
    List<Map<String, dynamic>> drivers,
    double vendorLat,
    double vendorLng,
  ) async {
    if (drivers.isEmpty || vendorLat == 0.0 || vendorLng == 0.0) {
      return null;
    }
    final weights =
        await DispatchScoringService.loadWeights();
    final withScore = await _buildDriversListFromMapsScored(
      drivers,
      vendorLat,
      vendorLng,
      0,
      weights,
    );
    if (withScore.isEmpty) return null;
    withScore.sort((a, b) =>
        (a['score'] as double).compareTo(b['score'] as double));
    final best = withScore.first;
    final driverData =
        best['data'] as Map<String, dynamic>;
    final driverName =
        '${driverData['firstName'] ?? ''} ${driverData['lastName'] ?? ''}'
            .trim();
    return {
      'driverId': best['id'] as String,
      'driverName':
          driverName.isEmpty ? 'Driver' : driverName,
      'distance': best['distance'] as double,
    };
  }

  /// Build list with distances and unified scores from pre-fetched maps.
  Future<List<Map<String, dynamic>>> _buildDriversListFromMapsScored(
    List<Map<String, dynamic>> driverMaps,
    double vendorLat,
    double vendorLng,
    double prepMinutes,
    DispatchWeights weights,
  ) async {
    final List<Map<String, dynamic>> list = [];
    final todayCompleted = await _getAvgCompletedToday();

    final isPeak = DispatchScoringService.isPeakHourNow(weights);
    for (final entry in driverMaps) {
      final id = entry['id'] as String?;
      final driverData = entry['data'] as Map<String, dynamic>?;
      if (id == null || driverData == null) continue;
      final currentOrders = _activeOrderCount(driverData);
      final effCap = DynamicCapacityService.calculateEffectiveCapacity(
        w: weights,
        isPeakHour: isPeak,
        driverPerformance:
            (driverData['driver_performance'] as num?)?.toDouble() ?? 0,
        multipleOrders: driverData['multipleOrders'] == true,
      );
      if (currentOrders >= effCap) continue;

      final location = driverData['location'];
      if (location != null && location is Map) {
        final driverLat =
            _asDouble(location['latitude']) ?? 0.0;
        final driverLng =
            _asDouble(location['longitude']) ?? 0.0;
        if (driverLat != 0.0 && driverLng != 0.0) {
          final distance = _calculateDistance(
            vendorLat, vendorLng, driverLat, driverLng,
          );
          final prevLoc =
              driverData['previousLocation'] as Map?;
          final headingMatch =
              DispatchScoringService.calculateHeadingMatch(
            riderLat: driverLat,
            riderLng: driverLng,
            prevLat: _asDouble(prevLoc?['latitude']),
            prevLng: _asDouble(prevLoc?['longitude']),
            restaurantLat: vendorLat,
            restaurantLng: vendorLng,
          );
          final acceptProb =
              await AcceptanceProbabilityService.calculate(
            riderId: id,
            distanceKm: distance,
            currentOrders: currentOrders,
          );
          final completed =
              (driverData['completedToday'] as num?)?.toInt() ?? 0;

          final result = DispatchScoringService.calculateScore(
            distanceKm: distance,
            currentOrders: currentOrders,
            headingMatch: headingMatch,
            predictedAcceptanceProb: acceptProb,
            completedToday: completed,
            avgCompletedToday: todayCompleted,
            restaurantPrepMinutes: prepMinutes,
            w: weights,
            effectiveCapacity: effCap,
          );

          list.add({
            'id': id,
            'data': driverData,
            'distance': distance,
            'score': result.total,
            'scoreComponents': result.components,
            'acceptanceProb': acceptProb,
            'headingMatch': headingMatch,
          });
        }
      }
    }
    return list;
  }

  /// Build list of available drivers with unified scores.
  /// Uses batched queries to avoid N+1 Firestore reads.
  Future<List<Map<String, dynamic>>> _buildDriversListScored(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    double vendorLat,
    double vendorLng,
    String? excludeDriverId,
    double prepMinutes,
    DispatchWeights weights,
  ) async {
    final List<Map<String, dynamic>> drivers = [];
    final isPeak = DispatchScoringService.isPeakHourNow(weights);
    final inactivityTimeoutMinutes = await _getInactivityTimeoutMinutes();
    final inactivityThreshold =
        DateTime.now().subtract(Duration(minutes: inactivityTimeoutMinutes));

    // Pass 1: collect eligible drivers with distances and order counts.
    // Stale riders (inactive) are tracked separately; used only when no other
    // riders pass the inactivity check.
    final List<String> eligibleIds = [];
    final List<String> staleButEligibleIds = [];
    final Map<String, double> distanceMap = {};
    final Map<String, int> orderCountMap = {};
    final Map<String, Map<String, dynamic>> candidateMap = {};

    for (final doc in docs) {
      if (excludeDriverId != null && doc.id == excludeDriverId) {
        print('[Dispatch] Driver ${doc.id} EXCLUDED: excludeDriverId');
        continue;
      }
      final driverData = doc.data();
      final rawOrders = driverData['inProgressOrderID'];
      print('[Dispatch] Checking rider ${doc.id} - '
          'inProgressOrderID: $rawOrders');
      print('[Dispatch] Order count: '
          '${(rawOrders is List) ? rawOrders.length : 0}, '
          'availability: '
          '${driverData['riderAvailability'] ?? "null"}');
      if (driverData['checkedOutToday'] == true) {
        print('[Dispatch] Driver ${doc.id} EXCLUDED: checkedOutToday');
        continue;
      }
      final lastActTs = driverData['lastActivityTimestamp'] as Timestamp?;
      final locTs = driverData['locationUpdatedAt'] as Timestamp?;
      final lastAct = lastActTs ?? locTs;
      final bool isStale = lastAct != null &&
          lastAct.toDate().isBefore(inactivityThreshold);
      if (isStale) {
        print('[Dispatch] Driver ${doc.id} has stale activity - '
            'will allow only if no other riders in zone');
      }
      final currentOrders = _activeOrderCount(driverData);
      final effCap = DynamicCapacityService.calculateEffectiveCapacity(
        w: weights,
        isPeakHour: isPeak,
        driverPerformance:
            (driverData['driver_performance'] as num?)
                    ?.toDouble() ??
                0,
        multipleOrders: driverData['multipleOrders'] == true,
      );
      if (currentOrders >= effCap) {
        print('[Dispatch] Driver ${doc.id} EXCLUDED: '
            'at capacity ($currentOrders/$effCap)');
        continue;
      }

      final location = driverData['location'];
      if (location == null || location is! Map) {
        print('[Dispatch] Driver ${doc.id} EXCLUDED: '
            'location null or not a Map');
        continue;
      }
      final driverLat =
          _asDouble(location['latitude']) ?? 0.0;
      final driverLng =
          _asDouble(location['longitude']) ?? 0.0;
      if (driverLat == 0.0 && driverLng == 0.0) {
        print('[Dispatch] Driver ${doc.id} EXCLUDED: '
            'location is 0,0');
        continue;
      }

      final distance = _calculateDistance(
        vendorLat, vendorLng, driverLat, driverLng,
      );

      if (isStale) {
        staleButEligibleIds.add(doc.id);
        print('[Dispatch] Driver ${doc.id} STALE-BUT-ELIGIBLE: '
            'orders=$currentOrders/$effCap, '
            'dist=${distance.toStringAsFixed(1)}km - '
            'will use if no active riders');
      } else {
        eligibleIds.add(doc.id);
        print('[Dispatch] Driver ${doc.id} ELIGIBLE: '
            'orders=$currentOrders/$effCap, '
            'dist=${distance.toStringAsFixed(1)}km, '
            'avail=${driverData['riderAvailability']}');
      }
      distanceMap[doc.id] = distance;
      orderCountMap[doc.id] = currentOrders;
      candidateMap[doc.id] = {
        'data': driverData,
        'driverLat': driverLat,
        'driverLng': driverLng,
        'distance': distance,
        'currentOrders': currentOrders,
        'effectiveCapacity': effCap,
      };
    }

    // Allow stale riders when no other riders are available in the zone
    if (eligibleIds.isEmpty && staleButEligibleIds.isNotEmpty) {
      for (final id in staleButEligibleIds) {
        eligibleIds.add(id);
        print('[Dispatch] Driver $id ALLOWED: stale but ONLY rider in zone');
      }
    }

    print('[Dispatch] Eligible: ${eligibleIds.length}/${docs.length} '
        '(excluded=${docs.length - eligibleIds.length})');

    if (eligibleIds.isEmpty) return drivers;

    // Pass 2: batch query acceptance probabilities
    final acceptProbs =
        await AcceptanceProbabilityService.calculateBatch(
      riderIds: eligibleIds,
      distances: distanceMap,
      orderCounts: orderCountMap,
    );

    // Compute average completed today from driver docs
    int totalCompleted = 0;
    int driverCount = 0;
    for (final id in eligibleIds) {
      final d = candidateMap[id]!['data'] as Map<String, dynamic>;
      totalCompleted +=
          (d['completedToday'] as num?)?.toInt() ?? 0;
      driverCount++;
    }
    final avgCompleted =
        driverCount > 0 ? (totalCompleted / driverCount).round() : 5;

    // Pass 3: score each eligible driver
    for (final id in eligibleIds) {
      final c = candidateMap[id]!;
      final driverData = c['data'] as Map<String, dynamic>;
      final distance = c['distance'] as double;
      final driverLat = c['driverLat'] as double;
      final driverLng = c['driverLng'] as double;
      final currentOrders = c['currentOrders'] as int;
      final effCap = c['effectiveCapacity'] as int;

      final prevLoc =
          driverData['previousLocation'] as Map?;
      final headingMatch =
          DispatchScoringService.calculateHeadingMatch(
        riderLat: driverLat,
        riderLng: driverLng,
        prevLat: _asDouble(prevLoc?['latitude']),
        prevLng: _asDouble(prevLoc?['longitude']),
        restaurantLat: vendorLat,
        restaurantLng: vendorLng,
      );
      final acceptProb = acceptProbs[id] ?? 0.7;
      final completed =
          (driverData['completedToday'] as num?)
              ?.toInt() ?? 0;

      final result = DispatchScoringService.calculateScore(
        distanceKm: distance,
        currentOrders: currentOrders,
        headingMatch: headingMatch,
        predictedAcceptanceProb: acceptProb,
        completedToday: completed,
        avgCompletedToday: avgCompleted,
        restaurantPrepMinutes: prepMinutes,
        w: weights,
        effectiveCapacity: effCap,
      );

      drivers.add({
        'id': id,
        'data': driverData,
        'distance': distance,
        'driverLat': driverLat,
        'driverLng': driverLng,
        'score': result.total,
        'scoreComponents': result.components,
        'acceptanceProb': acceptProb,
        'headingMatch': headingMatch,
        'currentOrders': currentOrders,
        'completedToday': completed,
        'effectiveCapacity': effCap,
        'routingSource': 'haversine',
      });
    }

    // Two-pass: refine top 8 with road-network ETA
    drivers.sort((a, b) =>
        (a['score'] as double).compareTo(
            b['score'] as double));
    final topN = drivers.take(8).toList();
    if (topN.isNotEmpty) {
      try {
        final destinations = topN
            .map((d) => RoutingLatLng(
                  d['driverLat'] as double,
                  d['driverLng'] as double,
                ))
            .toList();
        final routes =
            await RoutingService.getRouteDataBatch(
          vendorLat,
          vendorLng,
          destinations,
        );
        for (int i = 0; i < topN.length; i++) {
          final r = routes[i];
          topN[i]['routingSource'] = r.isFallback
              ? 'haversine'
              : 'google_distance_matrix';
          topN[i]['roadDistanceKm'] =
              r.roadDistanceKm;
          topN[i]['durationMinutes'] =
              r.durationMinutes;
          final rescore =
              DispatchScoringService.calculateScore(
            distanceKm: r.roadDistanceKm,
            durationMinutes: r.durationMinutes,
            currentOrders:
                topN[i]['currentOrders'] as int,
            headingMatch:
                topN[i]['headingMatch'] as double,
            predictedAcceptanceProb:
                topN[i]['acceptanceProb'] as double,
            completedToday:
                topN[i]['completedToday'] as int,
            avgCompletedToday: avgCompleted,
            restaurantPrepMinutes: prepMinutes,
            w: weights,
            effectiveCapacity:
                topN[i]['effectiveCapacity'] as int,
          );
          topN[i]['score'] = rescore.total;
          topN[i]['scoreComponents'] =
              rescore.components;
          topN[i]['distance'] = r.roadDistanceKm;
        }
        topN.sort((a, b) =>
            (a['score'] as double).compareTo(
                b['score'] as double));
        final topIds =
            topN.map((d) => d['id']).toSet();
        final rest = drivers
            .where((d) => !topIds.contains(d['id']))
            .toList();
        drivers
          ..clear()
          ..addAll(topN)
          ..addAll(rest);
      } catch (_) {
        // Routing failed; keep Haversine scores
      }
    }

    return drivers;
  }

  /// Get average completed orders today across all active riders.
  Future<int> _getAvgCompletedToday() async {
    try {
      final snap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();
      if (snap.docs.isEmpty) return 5;
      int total = 0;
      int count = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['checkedOutToday'] == true) continue;
        total +=
            (d['completedToday'] as num?)?.toInt() ?? 0;
        count++;
      }
      return count > 0 ? (total / count).round() : 5;
    } catch (_) {
      return 5;
    }
  }

  /// Assign driver to order and update driver status atomically
  /// using a Firestore transaction to prevent race conditions.
  Future<void> _assignDriverToOrder(
    String orderId,
    String driverId,
    double distance,
  ) async {
    final orderRef =
        _firestore.collection('restaurant_orders').doc(orderId);
    final driverRef =
        _firestore.collection('users').doc(driverId);
    final timeoutSec = await _getRiderTimeoutSeconds();

    await _firestore.runTransaction((tx) async {
      final orderSnap = await tx.get(orderRef);
      final existingDriverId =
          orderSnap.data()?['driverID']?.toString() ?? '';
      if (existingDriverId.isNotEmpty) {
        throw Exception(
          'Order already has driver assigned: $existingDriverId',
        );
      }

      final driverSnap = await tx.get(driverRef);
      if (!driverSnap.exists) {
        throw Exception('Driver $driverId not found');
      }

      final dData = driverSnap.data() ?? {};
      final currentOrders = dData['inProgressOrderID'];
      final count = (currentOrders is List)
          ? currentOrders.length
          : 0;
      final txWeights =
          DispatchScoringService.cachedWeights ??
              const DispatchWeights();
      final txCap =
          DynamicCapacityService.calculateEffectiveCapacity(
        w: txWeights,
        isPeakHour: DispatchScoringService.isPeakHourNow(
            txWeights),
        driverPerformance:
            (dData['driver_performance'] as num?)
                    ?.toDouble() ??
                0,
        multipleOrders: dData['multipleOrders'] == true,
      );
      if (count >= txCap) {
        throw Exception(
          'Driver already at max orders ($count/$txCap)',
        );
      }

      final deadline = Timestamp(
        Timestamp.now().seconds + timeoutSec.toInt(),
        0,
      );
      print('[TIMER] Order $orderId assigned, deadline: $deadline, '
          'timeoutSec: $timeoutSec');
      tx.update(orderRef, {
        'status': 'Driver Assigned',
        'driverID': driverId,
        'driverDistance': distance,
        'assignedAt': FieldValue.serverTimestamp(),
        'autoReassigned': true,
        'dispatch.riderAcceptDeadline': deadline,
        'dispatch.lock': false,
        'dispatch.attemptCount': FieldValue.increment(1),
      });

      tx.update(driverRef, {
        'orderRequestData': FieldValue.arrayUnion([orderId]),
      });
    });

    print('[Driver Assignment] Assigned order $orderId to driver $driverId: '
        'status=Driver Assigned, orderRequestData updated');
  }

  /// Kept for backward compatibility with assignOrderToDriver
  Future<void> _updateDriverStatus(
    String driverId,
    String orderId,
  ) async {
    // Now handled inside _assignDriverToOrder transaction,
    // but this remains for direct assignOrderToDriver calls.
    await _firestore.collection('users').doc(driverId).update({
      'isActive': false,
      'inProgressOrderID': FieldValue.arrayUnion([orderId]),
    });

    print('[Driver Assignment] Updated driver status');
  }

  /// Log assignment to assignments_log and dispatch_events.
  Future<DocumentReference> _logAssignment(
    String orderId,
    String driverId,
    double distance, {
    Map<String, double>? scoreComponents,
    double? totalScore,
    double? acceptanceProb,
    List<Map<String, dynamic>>? alternativeDrivers,
    int? riderCurrentOrders,
    double? riderHeadingMatch,
    double? restaurantPrepMinutes,
    String? batchId,
    String? zoneId,
    DispatchWeights? activeWeights,
    String? routingSource,
    double? durationMinutes,
  }) async {
    final etaMins = durationMinutes ?? (distance / 0.5);
    final logData = <String, dynamic>{
      'order_id': orderId,
      'driverId': driverId,
      'status': 'offered',
      'etaMinutes': etaMins.round(),
      'km': distance,
      'score': totalScore ?? 1.0,
      'acceptanceProb': acceptanceProb ?? 1.0,
      'createdAt': FieldValue.serverTimestamp(),
      'autoReassigned': true,
      'offeredAt': FieldValue.serverTimestamp(),
    };

    if (scoreComponents != null) {
      logData['scoringComponents'] = scoreComponents;
    }
    if (alternativeDrivers != null) {
      logData['alternativeRiders'] = alternativeDrivers;
    }

    final assignmentLogRef =
        await _firestore.collection('assignments_log').add(logData);

    final now = DateTime.now();
    final isPeak = activeWeights != null &&
        ((now.hour >= activeWeights.peakHourStart &&
                now.hour < activeWeights.peakHourEnd) ||
            (now.hour >= activeWeights.peakHourStart2 &&
                now.hour < activeWeights.peakHourEnd2));

    await _firestore.collection('dispatch_events').add({
      'type': 'admin_dispatch_assigned',
      'orderId': orderId,
      'riderId': driverId,
      'source': 'admin_ui',
      'timestamp': FieldValue.serverTimestamp(),
      'decisionTime': FieldValue.serverTimestamp(),
      if (batchId != null) 'batchId': batchId,
      'factors': {
        'distanceKm': distance,
        'etaMinutes': etaMins.round(),
        'riderCurrentOrders': riderCurrentOrders ?? 0,
        'riderHeadingMatch': riderHeadingMatch ?? 0.5,
        'predictedAcceptanceProb': acceptanceProb ?? 1.0,
        'restaurantPrepMinutes':
            restaurantPrepMinutes ?? 0,
        'timeOfDay': '${now.hour}:00',
        'dayOfWeek': now.weekday,
        'isPeakHour': isPeak,
        'zoneId': zoneId ?? '',
        'routingSource':
            routingSource ?? 'haversine',
      },
      'scoringComponents': scoreComponents,
      'totalScore': totalScore,
      'alternativeRiders': alternativeDrivers,
      if (activeWeights != null)
        'activeWeights': {
          'weightETA': activeWeights.eta,
          'weightWorkload': activeWeights.workload,
          'weightDirection': activeWeights.direction,
          'weightAcceptanceProb':
              activeWeights.acceptanceProb,
          'weightFairness': activeWeights.fairness,
        },
      'outcome': null,
    });

    return assignmentLogRef;
  }

  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Earth's radius in kilometers
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c; // Distance in kilometers
  }

  /// Safely convert dynamic value to double
  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Remove completed/cancelled/non-existent orders that
  /// are stuck in a rider's inProgressOrderID array.
  static Future<int> cleanupStuckOrders(
    String riderId,
  ) async {
    final fs = FirebaseFirestore.instance;
    print('[CLEANUP] Checking rider $riderId');

    final riderDoc =
        await fs.collection('users').doc(riderId).get();
    final orders =
        riderDoc.data()?['inProgressOrderID'] as List? ??
            [];

    if (orders.isEmpty) {
      print('[CLEANUP] Array already empty');
      return 0;
    }

    print('[CLEANUP] Found ${orders.length} orders: '
        '$orders');

    final List<String> toRemove = [];
    for (final orderId in orders) {
      final orderDoc = await fs
          .collection('restaurant_orders')
          .doc(orderId as String)
          .get();

      if (!orderDoc.exists) {
        print('[CLEANUP] $orderId: does not exist '
            '-> remove');
        toRemove.add(orderId);
        continue;
      }

      final status =
          orderDoc.data()?['status'] as String? ?? '';
      const doneStatuses = [
        'Order Completed',
        'Order Cancelled',
        'Order Rejected',
        'Driver Rejected',
      ];
      if (doneStatuses.contains(status)) {
        print('[CLEANUP] $orderId: $status -> remove');
        toRemove.add(orderId);
      } else {
        print('[CLEANUP] $orderId: $status -> keep');
      }
    }

    if (toRemove.isEmpty) {
      print('[CLEANUP] Nothing to remove');
      return 0;
    }

    print('[CLEANUP] Removing ${toRemove.length} '
        'stuck orders');
    await fs.collection('users').doc(riderId).update({
      'inProgressOrderID':
          FieldValue.arrayRemove(toRemove),
    });

    final afterDoc =
        await fs.collection('users').doc(riderId).get();
    final remaining =
        afterDoc.data()?['inProgressOrderID'] as List? ??
            [];
    print('[CLEANUP] Remaining: $remaining '
        '(${remaining.length})');

    return toRemove.length;
  }
}
