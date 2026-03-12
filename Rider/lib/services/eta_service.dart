import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Computes rider ETA to restaurant using haversine distance and average speed.
class EtaService {
  /// ~18 km/h average city speed in m/s.
  static const double averageSpeedMps = 5.0;

  /// Compute ETA in minutes from rider location to restaurant.
  /// Returns clamped value 1-60, or 999 if location invalid.
  static int computeEtaMinutes({
    required double riderLat,
    required double riderLng,
    required double restaurantLat,
    required double restaurantLng,
  }) {
    final distanceMeters = Geolocator.distanceBetween(
      riderLat,
      riderLng,
      restaurantLat,
      restaurantLng,
    );
    if (distanceMeters <= 0) return 999;
    final etaMinutes = (distanceMeters / averageSpeedMps / 60).ceil();
    return etaMinutes.clamp(1, 60);
  }

  /// Same as above but using GeoPoint.
  static int computeEtaFromGeoPoint(
    GeoPoint riderLoc,
    GeoPoint restaurantLoc,
  ) {
    return computeEtaMinutes(
      riderLat: riderLoc.latitude,
      riderLng: riderLoc.longitude,
      restaurantLat: restaurantLoc.latitude,
      restaurantLng: restaurantLoc.longitude,
    );
  }

  /// Extract lat/lng from Firestore location (GeoPoint or map).
  static (double, double)? _parseLocation(dynamic loc) {
    if (loc == null) return null;
    if (loc is GeoPoint) {
      return (loc.latitude, loc.longitude);
    }
    if (loc is Map) {
      final lat = loc['latitude'];
      final lng = loc['longitude'];
      if (lat is num && lng is num) {
        return (lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  /// Stream of ETA minutes, updated when rider location changes.
  /// Returns 999 when rider location unavailable.
  static Stream<int> watchEtaMinutes({
    required String riderId,
    required double restaurantLat,
    required double restaurantLng,
  }) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(riderId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 999;
      final loc = snapshot.data()?['location'];
      final parsed = _parseLocation(loc);
      if (parsed == null) return 999;
      final (riderLat, riderLng) = parsed;
      return computeEtaMinutes(
        riderLat: riderLat,
        riderLng: riderLng,
        restaurantLat: restaurantLat,
        restaurantLng: restaurantLng,
      );
    });
  }
}
