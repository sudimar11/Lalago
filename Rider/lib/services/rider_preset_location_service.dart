import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:foodie_driver/model/User.dart';

const _serviceAreasCollection = 'service_areas';

class RiderPresetLocationData {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  /// Radius in km; null for fixed boundary type
  final double? radiusKm;

  RiderPresetLocationData({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusKm,
  });

  /// Whether this preset has a valid radius for geofencing
  bool get hasRadius => radiusKm != null && radiusKm! > 0;
}

class RiderPresetLocationService {
  static Future<List<RiderPresetLocationData>> getPresetLocations() async {
    final snap = await FirebaseFirestore.instance
        .collection(_serviceAreasCollection)
        .get();
    final list = <RiderPresetLocationData>[];
    for (final doc in snap.docs) {
      final d = doc.data();
      final lat = _toDouble(d['centerLat']);
      final lng = _toDouble(d['centerLng']);
      if (lat == null || lng == null) continue;
      final radiusKm = _toDouble(d['radiusKm']);
      list.add(RiderPresetLocationData(
        id: doc.id,
        name: (d['name'] ?? '').toString(),
        latitude: lat,
        longitude: lng,
        radiusKm: radiusKm,
      ));
    }
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  static Future<RiderPresetLocationData?> getPresetById(String id) async {
    final doc = await FirebaseFirestore.instance
        .collection(_serviceAreasCollection)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    final d = doc.data();
    if (d == null) return null;
    final lat = _toDouble(d['centerLat']);
    final lng = _toDouble(d['centerLng']);
    if (lat == null || lng == null) return null;
    final radiusKm = _toDouble(d['radiusKm']);
    return RiderPresetLocationData(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      latitude: lat,
      longitude: lng,
      radiusKm: radiusKm,
    );
  }

  /// Haversine distance in km between two points
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
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  /// Returns true if [currentLocation] is within [preset] radius.
  static bool isWithinRadius(
    UserLocation currentLocation,
    RiderPresetLocationData preset,
  ) {
    if (!preset.hasRadius) return true;
    final distKm = _haversineKm(
      preset.latitude,
      preset.longitude,
      currentLocation.latitude,
      currentLocation.longitude,
    );
    return distKm <= preset.radiusKm!;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
