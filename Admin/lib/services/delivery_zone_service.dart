import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/models/service_area.dart';

/// Result of matching a delivery location to a service area.
class DeliveryZoneMatch {
  final ServiceArea zone;
  final List<String> driverIds;

  const DeliveryZoneMatch({
    required this.zone,
    required this.driverIds,
  });
}

class DeliveryZoneService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _collection = 'service_areas';

  Stream<List<ServiceArea>> streamServiceAreas() {
    return _db.collection(_collection).snapshots().map((s) {
      final list =
          s.docs.map((d) => ServiceArea.fromDoc(d)).toList();
      list.sort((a, b) {
        final o = a.order.compareTo(b.order);
        if (o != 0) return o;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    });
  }

  Future<List<ServiceArea>> getServiceAreas() async {
    final snap = await _db.collection(_collection).get();
    final list =
        snap.docs.map((d) => ServiceArea.fromDoc(d)).toList();
    list.sort((a, b) {
      final o = a.order.compareTo(b.order);
      if (o != 0) return o;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Future<ServiceArea?> getServiceArea(String id) async {
    final doc = await _db.collection(_collection).doc(id).get();
    if (!doc.exists) return null;
    return ServiceArea.fromDoc(doc);
  }

  /// Returns assignedDriverIds for the first matching area,
  /// or null if none.
  Future<List<String>?> getAssignedDriverIdsForDelivery({
    required double? lat,
    required double? lng,
    required String? locality,
  }) async {
    final match = await getZoneMatchForDelivery(
      lat: lat,
      lng: lng,
      locality: locality,
    );
    return match?.driverIds;
  }

  /// Returns the matched [DeliveryZoneMatch] (zone + driver IDs)
  /// for a delivery location, or null if no zone matches.
  Future<DeliveryZoneMatch?> getZoneMatchForDelivery({
    required double? lat,
    required double? lng,
    required String? locality,
  }) async {
    final areas = await getServiceAreas();
    if (areas.isEmpty) return null;

    final sorted = List<ServiceArea>.from(areas)
      ..sort((a, b) {
        if (a.boundaryType == 'radius' &&
            b.boundaryType == 'radius') {
          final ar = a.radiusKm ?? double.infinity;
          final br = b.radiusKm ?? double.infinity;
          return ar.compareTo(br);
        }
        if (a.boundaryType == 'fixed' &&
            b.boundaryType == 'fixed') {
          return 0;
        }
        return a.boundaryType == 'radius' ? -1 : 1;
      });

    for (final area in sorted) {
      if (area.boundaryType == 'fixed') {
        if (locality != null && locality.trim().isNotEmpty) {
          final norm = locality.trim().toLowerCase();
          for (final b in area.barangays) {
            if (b.trim().toLowerCase() == norm) {
              return DeliveryZoneMatch(
                zone: area,
                driverIds: area.assignedDriverIds,
              );
            }
          }
        }
      } else if (area.boundaryType == 'radius') {
        final clat = area.centerLat;
        final clng = area.centerLng;
        final r = area.radiusKm ?? 0;
        if (clat == null || clng == null || r <= 0) continue;
        if (lat == null || lng == null) continue;
        final dist = _haversineKm(clat, clng, lat, lng);
        if (dist <= r) {
          return DeliveryZoneMatch(
            zone: area,
            driverIds: area.assignedDriverIds,
          );
        }
      }
    }
    return null;
  }

  double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<DocumentReference> create(ServiceArea area) async {
    return _db.collection(_collection).add(area.toMapForCreate());
  }

  Future<void> update(String id, ServiceArea area) async {
    await _db.collection(_collection).doc(id).update(area.toMap());
  }

  Future<void> delete(String id) async {
    await _db.collection(_collection).doc(id).delete();
  }
}
