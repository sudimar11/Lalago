import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';

class DispatchPrecheckResult {
  final bool canCheckout;
  final String? blockedMessage;
  final String? blockedEventType;
  final int activeOrders;
  final int activeRiders;

  const DispatchPrecheckResult({
    required this.canCheckout,
    required this.blockedMessage,
    required this.blockedEventType,
    required this.activeOrders,
    required this.activeRiders,
  });
}

class DispatchPrecheckService {
  static const int _defaultMaxOrdersPerRider = 3;
  static const Duration _locationStaleThreshold =
      Duration(minutes: 15);
  static const Duration _stuckOrderThreshold =
      Duration(hours: 2);

  static const String _eventCheckoutBlockedOverload =
      'checkout_blocked_overload';

  static const List<String> _activeOrderStatuses = <String>[
    'Awaiting Rider',
    ORDER_STATUS_DRIVER_ACCEPTED,
    ORDER_STATUS_ACCEPTED,
    ORDER_STATUS_SHIPPED,
    ORDER_STATUS_IN_TRANSIT,
  ];

  static const List<String> _earlyStatuses = <String>[
    'Awaiting Rider',
    ORDER_STATUS_DRIVER_ACCEPTED,
  ];

  final FirebaseFirestore _firestore;

  DispatchPrecheckService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<DispatchPrecheckResult> runPrecheck({
    required String customerId,
    required String vendorId,
    double? deliveryLat,
    double? deliveryLng,
    String? deliveryLocality,
  }) async {
    print('==== PRECHECK START ====');
    print('[PRECHECK] customer=$customerId '
        'vendor=$vendorId');
    print('[PRECHECK] deliveryLat=$deliveryLat '
        'deliveryLng=$deliveryLng '
        'locality=$deliveryLocality');

    final maxPerRider = await _loadMaxOrdersPerRider();
    print('[PRECHECK] maxOrdersPerRider=$maxPerRider');

    // Resolve zone for delivery address
    print('[PRECHECK] Resolving delivery zone...');
    final zoneMatch = await _resolveZone(
      lat: deliveryLat,
      lng: deliveryLng,
      locality: deliveryLocality,
    );
    final zoneDriverIds =
        zoneMatch?['driverIds'] as List<String>?;
    final zoneName =
        zoneMatch?['zoneName'] as String? ?? 'none';
    print('[PRECHECK] zone=$zoneName '
        'assignedDriverIds='
        '${zoneDriverIds?.length ?? "ALL (no zone match)"}');
    if (zoneDriverIds != null) {
      print('[PRECHECK] zoneDriverIds=$zoneDriverIds');
    }

    print('[PRECHECK] Counting active orders...');
    final activeOrders = await _countActiveOrders();

    print('[PRECHECK] Counting active riders...');
    final activeRiders = await _countActiveRiders(
      zoneDriverIds: zoneDriverIds,
      maxPerRider: maxPerRider,
    );

    final threshold = activeRiders * maxPerRider;
    final isOverloaded = activeOrders >= threshold;

    print('==== PRECHECK RESULT ====');
    print('[PRECHECK] activeOrders=$activeOrders');
    print('[PRECHECK] activeRiders=$activeRiders');
    print('[PRECHECK] threshold='
        '$activeRiders x $maxPerRider = $threshold');
    print('[PRECHECK] $activeOrders >= $threshold ? '
        '$isOverloaded');

    if (isOverloaded) {
      print('[PRECHECK] BLOCKED: '
          '$activeOrders >= $threshold');
      print('==== PRECHECK END ====');
      await _tryLogEvent(
        eventType: _eventCheckoutBlockedOverload,
        customerId: customerId,
        vendorId: vendorId,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
      return DispatchPrecheckResult(
        canCheckout: false,
        blockedMessage:
            'Our delivery team is at full capacity at the '
            'moment. Please try again in a few minutes.',
        blockedEventType: _eventCheckoutBlockedOverload,
        activeOrders: activeOrders,
        activeRiders: activeRiders,
      );
    }

    print('[PRECHECK] ALLOWED: checkout can proceed');
    print('==== PRECHECK END ====');
    return DispatchPrecheckResult(
      canCheckout: true,
      blockedMessage: null,
      blockedEventType: null,
      activeOrders: activeOrders,
      activeRiders: activeRiders,
    );
  }

  // ── Rider counting ──────────────────────────────────────

  Future<int> _countActiveRiders({
    List<String>? zoneDriverIds,
    required int maxPerRider,
  }) async {
    final List<DocumentSnapshot<Map<String, dynamic>>>
        riderDocs;

    if (zoneDriverIds != null && zoneDriverIds.isNotEmpty) {
      print('[PRECHECK] Fetching ${zoneDriverIds.length} '
          'zone-assigned drivers by ID');

      final List<DocumentSnapshot<Map<String, dynamic>>>
          allDocs = [];
      // Firestore whereIn limit is 10 per query
      for (var i = 0; i < zoneDriverIds.length; i += 10) {
        final batch = zoneDriverIds.sublist(
          i,
          i + 10 > zoneDriverIds.length
              ? zoneDriverIds.length
              : i + 10,
        );
        print('[PRECHECK] Batch query IDs: $batch');
        final snap = await _firestore
            .collection(USERS)
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        allDocs.addAll(snap.docs);
      }
      riderDocs = allDocs;
      print('[PRECHECK] Fetched ${riderDocs.length} '
          'driver docs from zone assignedDriverIds');
    } else {
      print('[PRECHECK] No zone match — '
          'querying ALL drivers with role=driver');
      final snap = await _firestore
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_DRIVER)
          .get();
      riderDocs = snap.docs;
      print('[PRECHECK] Fetched ${riderDocs.length} '
          'drivers (all)');
    }

    final now = DateTime.now();
    int count = 0;

    for (final doc in riderDocs) {
      final d = doc.data();
      if (d == null) {
        print('[PRECHECK] Rider ${doc.id}: '
            'doc data is null -> SKIP');
        continue;
      }
      final id = doc.id;

      final locTs =
          (d['locationUpdatedAt'] as Timestamp?)?.toDate();
      final locAge = locTs != null
          ? '${now.difference(locTs).inMinutes}m ago'
          : 'null';
      final inProgress = d['inProgressOrderID'];
      final currentOrders =
          (inProgress is List) ? inProgress.length : 0;

      print('[PRECHECK] Rider $id: '
          'role=${d['role']}, '
          'checkedOut=${d['checkedOutToday']}, '
          'location='
          '${d['location'] != null ? "yes" : "null"}, '
          'locAge=$locAge, '
          'orders=$currentOrders/$maxPerRider');

      // ── Filter 1: checkedOutToday ──
      if (d['checkedOutToday'] == true) {
        print('[PRECHECK]   -> SKIP: checkedOutToday=true');
        continue;
      }

      // ── Filter 2: valid location ──
      final location = d['location'];
      if (location == null || location is! Map) {
        print('[PRECHECK]   -> SKIP: no location data');
        continue;
      }
      final lat =
          (location['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng =
          (location['longitude'] as num?)?.toDouble() ??
              0.0;
      if (lat == 0.0 && lng == 0.0) {
        print('[PRECHECK]   -> SKIP: location is 0,0');
        continue;
      }

      // ── Filter 3: location freshness ──
      if (locTs == null) {
        print('[PRECHECK]   -> SKIP: '
            'locationUpdatedAt is null');
        continue;
      }
      final locAgeMins = now.difference(locTs).inMinutes;
      if (locAgeMins > _locationStaleThreshold.inMinutes) {
        print('[PRECHECK]   -> SKIP: stale location '
            '(${locAgeMins}m > '
            '${_locationStaleThreshold.inMinutes}m)');
        continue;
      }

      // ── Filter 4: order capacity ──
      if (currentOrders >= maxPerRider) {
        print('[PRECHECK]   -> SKIP: at capacity '
            '($currentOrders >= $maxPerRider)');
        continue;
      }

      print('[PRECHECK]   -> COUNTED as active '
          '(orders=$currentOrders/$maxPerRider, '
          'locAge=${locAgeMins}m)');
      count++;
    }

    print('[PRECHECK] Active riders: $count '
        '(of ${riderDocs.length} evaluated)');
    return count;
  }

  // ── Order counting ──────────────────────────────────────

  Future<int> _countActiveOrders() async {
    try {
      final now = DateTime.now();
      final startOfToday =
          DateTime(now.year, now.month, now.day);
      final endOfToday =
          startOfToday.add(const Duration(days: 1));
      final startTs = Timestamp.fromDate(startOfToday);
      final endTs = Timestamp.fromDate(endOfToday);

      print('[PRECHECK] Querying orders: '
          'statuses=$_activeOrderStatuses, today only');
      final snap = await _firestore
          .collection(ORDERS)
          .where('status', whereIn: _activeOrderStatuses)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: startTs,
          )
          .where('createdAt', isLessThan: endTs)
          .orderBy('createdAt')
          .get();

      print('[PRECHECK] Raw order query returned '
          '${snap.size} orders');

      final stuckCutoff =
          now.subtract(_stuckOrderThreshold);
      int validCount = 0;
      int stuckCount = 0;

      for (final doc in snap.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        final createdAt =
            (data['createdAt'] as Timestamp?)?.toDate();
        final age = createdAt != null
            ? '${now.difference(createdAt).inMinutes}m ago'
            : 'unknown';

        if (_earlyStatuses.contains(status) &&
            createdAt != null &&
            createdAt.isBefore(stuckCutoff)) {
          stuckCount++;
          print('[PRECHECK] Order ${doc.id}: '
              'status=$status, created=$age '
              '-> STUCK (excluded)');
          continue;
        }
        print('[PRECHECK] Order ${doc.id}: '
            'status=$status, created=$age '
            '-> COUNTED');
        validCount++;
      }

      print('[PRECHECK] Active orders: $validCount '
          '(total=${snap.size}, stuck=$stuckCount)');
      return validCount;
    } catch (e) {
      print('[PRECHECK] Failed to count orders: $e');
      return 0;
    }
  }

  // ── Zone resolution ─────────────────────────────────────

  Future<Map<String, dynamic>?> _resolveZone({
    double? lat,
    double? lng,
    String? locality,
  }) async {
    try {
      final snap =
          await _firestore.collection('service_areas').get();
      if (snap.docs.isEmpty) {
        print('[PRECHECK] No service_areas found');
        return null;
      }

      print('[PRECHECK] Found ${snap.docs.length} '
          'service areas');

      final areas = snap.docs.map((d) {
        final data = d.data();
        return {'id': d.id, ...data};
      }).toList();

      areas.sort((a, b) {
        final aType =
            a['boundaryType'] as String? ?? 'radius';
        final bType =
            b['boundaryType'] as String? ?? 'radius';
        if (aType == 'radius' && bType == 'radius') {
          final ar =
              (a['radiusKm'] as num?)?.toDouble() ??
                  double.infinity;
          final br =
              (b['radiusKm'] as num?)?.toDouble() ??
                  double.infinity;
          return ar.compareTo(br);
        }
        if (aType == 'fixed' && bType == 'fixed') return 0;
        return aType == 'radius' ? -1 : 1;
      });

      for (final area in areas) {
        final name = area['name'] as String? ?? '?';
        final boundaryType =
            area['boundaryType'] as String? ?? 'radius';

        if (boundaryType == 'fixed') {
          if (locality != null &&
              locality.trim().isNotEmpty) {
            final norm = locality.trim().toLowerCase();
            final barangays = (area['barangays'] as List?)
                    ?.cast<String>() ??
                [];
            for (final b in barangays) {
              if (b.trim().toLowerCase() == norm) {
                print('[PRECHECK] Zone matched: '
                    '$name (fixed/barangay=$b)');
                return _zoneResult(area);
              }
            }
          }
        } else if (boundaryType == 'radius') {
          final cLat =
              (area['centerLat'] as num?)?.toDouble();
          final cLng =
              (area['centerLng'] as num?)?.toDouble();
          final r =
              (area['radiusKm'] as num?)?.toDouble() ?? 0;
          if (cLat == null || cLng == null || r <= 0) {
            continue;
          }
          if (lat == null || lng == null) continue;
          final dist = _haversineKm(cLat, cLng, lat, lng);
          if (dist <= r) {
            print('[PRECHECK] Zone matched: '
                '$name (radius, '
                'dist=${dist.toStringAsFixed(2)}km '
                '<= ${r}km)');
            return _zoneResult(area);
          } else {
            print('[PRECHECK] Zone $name: '
                'dist=${dist.toStringAsFixed(2)}km '
                '> ${r}km (no match)');
          }
        }
      }
      print('[PRECHECK] No zone matched delivery address');
      return null;
    } catch (e) {
      print('[PRECHECK] zone resolution failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _zoneResult(
    Map<String, dynamic> area,
  ) {
    final ids = (area['assignedDriverIds'] as List?)
            ?.cast<String>() ??
        <String>[];
    return {
      'zoneName': area['name'] as String? ?? 'Unknown',
      'driverIds': ids,
    };
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) *
            math.cos(lat2 * (math.pi / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c =
        2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  // ── Config loading ──────────────────────────────────────

  Future<int> _loadMaxOrdersPerRider() async {
    try {
      final doc = await _firestore
          .collection('config')
          .doc('dispatch_weights')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final v = data['checkoutCapacityMultiplier']
            ?? data['maxOrdersPerRider'];
        if (v is int && v > 0) {
          print('[PRECHECK] Config: '
              'checkoutCapacityMultiplier=$v '
              '(from Firestore)');
          return v;
        }
        if (v is num && v > 0) {
          print('[PRECHECK] Config: '
              'checkoutCapacityMultiplier=${v.toInt()} '
              '(from Firestore)');
          return v.toInt();
        }
      }
      print('[PRECHECK] Config: '
          'checkoutCapacityMultiplier='
          '$_defaultMaxOrdersPerRider (default)');
    } catch (e) {
      print('[PRECHECK] Config load failed: $e, '
          'using default=$_defaultMaxOrdersPerRider');
    }
    return _defaultMaxOrdersPerRider;
  }

  // ── Event logging ───────────────────────────────────────

  Future<void> _tryLogEvent({
    required String eventType,
    required String customerId,
    required String vendorId,
    required int activeOrders,
    required int activeRiders,
  }) async {
    try {
      await _firestore.collection('dispatch_events').add({
        'type': eventType,
        'customerId': customerId,
        'vendorId': vendorId,
        'activeOrders': activeOrders,
        'activeRiders': activeRiders,
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'customer_checkout',
      });
    } catch (e) {
      print('[PRECHECK] Failed to log event '
          '$eventType: $e');
    }
  }
}
