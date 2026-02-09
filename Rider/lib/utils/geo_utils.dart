import 'package:geolocator/geolocator.dart';

/// Utility class for geographical calculations and operations
class GeoUtils {
  /// Calculates the distance between two geographical points
  ///
  /// [lat1] - Latitude of the first point
  /// [lon1] - Longitude of the first point
  /// [lat2] - Latitude of the second point (optional, if null uses current position)
  /// [lon2] - Longitude of the second point (optional, if null uses current position)
  ///
  /// Returns the distance in kilometers
  static Future<double> calculateDistance(
    double lat1,
    double lon1,
    double? lat2,
    double? lon2,
  ) async {
    try {
      if (lat2 == null || lon2 == null) {
        final currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final meters = Geolocator.distanceBetween(
          currentPos.latitude,
          currentPos.longitude,
          lat1,
          lon1,
        );
        return meters / 1000;
      } else {
        final meters = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
        return meters / 1000;
      }
    } catch (_) {
      return 0.0;
    }
  }
}
