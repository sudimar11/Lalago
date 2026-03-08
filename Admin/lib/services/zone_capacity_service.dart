import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/models/service_area.dart';
import 'package:brgy/services/delivery_zone_service.dart';

class ZoneCapacity {
  final ServiceArea zone;
  final int currentActiveRiders;
  final int? maxRiders;

  const ZoneCapacity({
    required this.zone,
    required this.currentActiveRiders,
    required this.maxRiders,
  });

  bool get hasCapacity =>
      maxRiders == null || currentActiveRiders < maxRiders!;

  double get utilizationPercentage {
    if (maxRiders == null || maxRiders == 0) return 0;
    return (currentActiveRiders / maxRiders! * 100).clamp(0, 100);
  }

  String get capacityStatus {
    if (maxRiders == null) return 'unlimited';
    final pct = utilizationPercentage;
    if (pct >= 100) return 'full';
    if (pct >= 90) return 'critical';
    if (pct >= 70) return 'high';
    return 'normal';
  }

  Color get statusColor {
    switch (capacityStatus) {
      case 'full':
        return Colors.red;
      case 'critical':
        return Colors.orange;
      case 'high':
        return Colors.amber;
      case 'normal':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

class ZoneCapacityService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final DeliveryZoneService _zoneService = DeliveryZoneService();

  final Map<String, DateTime> _alertCooldowns = {};
  static const _alertCooldown = Duration(minutes: 15);

  /// Stream capacity data for all zones, refreshing active counts
  /// each time either service_areas or the drivers collection changes.
  Stream<List<ZoneCapacity>> streamAllZoneCapacities() {
    final zonesStream = _zoneService.streamServiceAreas();
    final driversStream = _db
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .snapshots();

    return zonesStream.asyncMap((zones) async {
      final driversSnap = await _db
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .get();
      return _buildCapacities(zones, driversSnap.docs);
    }).asyncExpand((initial) {
      final controller =
          StreamController<List<ZoneCapacity>>();
      controller.add(initial);

      final sub = driversStream.listen((_) async {
        try {
          final zones = await _zoneService.getServiceAreas();
          final driversSnap = await _db
              .collection('users')
              .where('role', isEqualTo: 'driver')
              .get();
          controller.add(
            _buildCapacities(zones, driversSnap.docs),
          );
        } catch (e) {
          controller.addError(e);
        }
      });

      controller.onCancel = () => sub.cancel();
      return controller.stream;
    });
  }

  /// Get capacity for a single zone by ID.
  Future<ZoneCapacity?> getZoneCapacity(String zoneId) async {
    final zone = await _zoneService.getServiceArea(zoneId);
    if (zone == null) return null;
    final count = await _countActiveRidersInZone(zone);
    return ZoneCapacity(
      zone: zone,
      currentActiveRiders: count,
      maxRiders: zone.maxRiders,
    );
  }

  /// Quick check: does this zone have room for another rider?
  Future<bool> hasCapacityForNewRider(String zoneId) async {
    final zc = await getZoneCapacity(zoneId);
    if (zc == null) return true;
    return zc.hasCapacity;
  }

  /// Stream only zones at critical (90%+) or full status.
  Stream<List<ZoneCapacity>> streamCapacityAlerts() {
    return streamAllZoneCapacities().map(
      (list) => list
          .where(
            (zc) =>
                zc.capacityStatus == 'full' ||
                zc.capacityStatus == 'critical',
          )
          .toList(),
    );
  }

  /// Send a capacity alert notification via the notification_jobs
  /// collection (processed by the existing Cloud Function).
  /// Respects a 15-minute cooldown per zone.
  Future<void> sendCapacityAlert(ZoneCapacity zc) async {
    final zoneId = zc.zone.id;
    final now = DateTime.now();
    final lastAlert = _alertCooldowns[zoneId];
    if (lastAlert != null &&
        now.difference(lastAlert) < _alertCooldown) {
      return;
    }
    _alertCooldowns[zoneId] = now;

    final status = zc.capacityStatus;
    final title = status == 'full'
        ? 'Zone Full: ${zc.zone.name}'
        : 'Zone Near Capacity: ${zc.zone.name}';
    final body =
        '${zc.currentActiveRiders}/${zc.maxRiders} riders active '
        '(${zc.utilizationPercentage.toStringAsFixed(0)}%).';

    await _db.collection('notification_jobs').add({
      'kind': 'broadcast',
      'payload': {
        'title': title,
        'body': body,
        'type': 'information',
      },
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'queued',
      'stats': {
        'totalRecipients': 0,
        'processedCount': 0,
        'successfulDeliveries': 0,
        'failedDeliveries': 0,
        'currentBatchNumber': 0,
        'totalBatches': 0,
        'percentComplete': 0.0,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  // ── helpers ──

  List<ZoneCapacity> _buildCapacities(
    List<ServiceArea> zones,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> drivers,
  ) {
    final fiveMinAgo = DateTime.now().subtract(
      const Duration(minutes: 5),
    );

    final activeByDriverId = <String, bool>{};
    for (final doc in drivers) {
      final d = doc.data();
      final avail = d['riderAvailability'] as String?;
      if (avail != 'available' && avail != 'on_delivery') continue;
      final ts = d['locationUpdatedAt'] as Timestamp?;
      if (ts != null && ts.toDate().isAfter(fiveMinAgo)) {
        activeByDriverId[doc.id] = true;
      }
    }

    return zones.map((zone) {
      int active = 0;
      for (final dId in zone.assignedDriverIds) {
        if (activeByDriverId.containsKey(dId)) active++;
      }
      return ZoneCapacity(
        zone: zone,
        currentActiveRiders: active,
        maxRiders: zone.maxRiders,
      );
    }).toList();
  }

  Future<int> _countActiveRidersInZone(ServiceArea zone) async {
    if (zone.assignedDriverIds.isEmpty) return 0;
    final fiveMinAgo = DateTime.now().subtract(
      const Duration(minutes: 5),
    );
    final snap = await _db
        .collection('users')
        .where('role', isEqualTo: 'driver')
        .get();
    int count = 0;
    for (final doc in snap.docs) {
      if (!zone.assignedDriverIds.contains(doc.id)) continue;
      final d = doc.data();
      if (d['checkedOutToday'] == true) continue;
      final ts = d['locationUpdatedAt'] as Timestamp?;
      if (ts != null && ts.toDate().isAfter(fiveMinAgo)) {
        count++;
      }
    }
    return count;
  }
}
