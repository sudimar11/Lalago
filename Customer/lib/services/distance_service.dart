import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';

/// Hardcoded fallback key so Directions API is always attempted.
/// Prevents "no valid API key" fallback to straight-line distance.
const String _kDirectionsApiFallbackKey =
    'AIzaSyBXNXXV60p-VYnIMD0mevMk8HeW9kSJnPs';

/// Cache entry for storing distance calculations with expiration.
class _CachedDistance {
  final double distanceKm;
  final DateTime timestamp;

  _CachedDistance(this.distanceKm, this.timestamp);

  /// Checks if the cache entry is still valid (within expiration duration).
  bool isValid(Duration cacheValidDuration) {
    return DateTime.now().difference(timestamp) < cacheValidDuration;
  }
}

/// Service for calculating road-based distance using Google Directions API.
/// Falls back to straight-line distance if API call fails.
class DistanceService {
  /// In-memory cache for distance calculations.
  static final Map<String, _CachedDistance> _distanceCache = {};

  /// Duration for which cached distances are considered valid.
  static const Duration _cacheValidDuration = Duration(hours: 2);

  /// Maximum number of cache entries before cleanup.
  static const int _maxCacheEntries = 100;

  /// Counter for cache hits (for monitoring).
  static int _cacheHitCounter = 0;

  /// Counter for API calls (for monitoring).
  static int _apiCallCounter = 0;

  /// Creates a cache key from rounded coordinates.
  /// Rounds to 5 decimal places (~1.1m precision) for checkout accuracy.
  /// Format: "lat1,lng1->lat2,lng2"
  static String _getCacheKey(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    // Round to 5 decimal places (~1.1m precision)
    final roundedLat1 = (lat1 * 100000).round() / 100000;
    final roundedLng1 = (lng1 * 100000).round() / 100000;
    final roundedLat2 = (lat2 * 100000).round() / 100000;
    final roundedLng2 = (lng2 * 100000).round() / 100000;

    return '$roundedLat1,$roundedLng1->$roundedLat2,$roundedLng2';
  }

  /// Cleans up expired cache entries and limits cache size.
  static void _cleanupCache() {
    if (_distanceCache.length <= _maxCacheEntries) {
      // Only remove expired entries if cache is not too large
      _distanceCache.removeWhere((key, value) => !value.isValid(_cacheValidDuration));
    } else {
      // If cache exceeds max size, remove expired entries first
      _distanceCache.removeWhere((key, value) => !value.isValid(_cacheValidDuration));
      
      // If still too large, remove oldest entries
      if (_distanceCache.length > _maxCacheEntries) {
        final sortedEntries = _distanceCache.entries.toList()
          ..sort((a, b) => a.value.timestamp.compareTo(b.value.timestamp));
        
        final entriesToRemove = sortedEntries.length - _maxCacheEntries;
        for (var i = 0; i < entriesToRemove; i++) {
          _distanceCache.remove(sortedEntries[i].key);
        }
      }
    }
  }

  /// Calculates road-based distance between two points using Google Directions API.
  /// Returns distance in kilometers.
  ///
  /// Uses intelligent caching with coordinate rounding and expiration to minimize
  /// API calls. Falls back to straight-line distance if API call fails or API key
  /// is not available.
  ///
  /// [originLat] - Origin latitude
  /// [originLng] - Origin longitude
  /// [destLat] - Destination latitude
  /// [destLng] - Destination longitude
  ///
  /// Returns distance in kilometers as a Future<double>.
  /// Set [bypassCache] true to always call API (e.g. at checkout).
  static Future<double> getRoadDistanceKm(
    double originLat,
    double originLng,
    double destLat,
    double destLng, {
    bool bypassCache = false,
  }) async {
    final cacheKey = _getCacheKey(originLat, originLng, destLat, destLng);

    if (!bypassCache && _distanceCache.containsKey(cacheKey)) {
      final cached = _distanceCache[cacheKey]!;
      if (cached.isValid(_cacheValidDuration)) {
        _cacheHitCounter++;
        debugPrint(
            "DistanceService: Cache HIT #$_cacheHitCounter for $cacheKey (${cached.distanceKm}km, saved \$${(_cacheHitCounter * 0.005).toStringAsFixed(4)})");
        return cached.distanceKm;
      } else {
        final age = DateTime.now().difference(cached.timestamp);
        debugPrint(
            "DistanceService: Cache EXPIRED for $cacheKey (age: ${age.inMinutes}min)");
        _distanceCache.remove(cacheKey);
      }
    }

    debugPrint("DistanceService: Cache MISS for $cacheKey - calling API");

    // Use Firestore key if valid, otherwise hardcoded fallback (never skip API)
    final bool hasValidKey = GOOGLE_API_KEY.isNotEmpty &&
        GOOGLE_API_KEY != 'Replace with your Server key';
    final String apiKey =
        hasValidKey ? GOOGLE_API_KEY : _kDirectionsApiFallbackKey;

    _apiCallCounter++;
    try {
      final String url =
          'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=$originLat,$originLng'
          '&destination=$destLat,$destLng'
          '&key=$apiKey';

      debugPrint(
          "DistanceService: API CALL #$_apiCallCounter - Requesting road distance from Google Directions API");

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Check if API returned an error status
        if (data['status'] == 'OK' &&
            data['routes'] != null &&
            data['routes'].isNotEmpty) {
          final distanceInMeters =
              data['routes'][0]['legs'][0]['distance']['value'] as int;
          final distanceKm = distanceInMeters / 1000.0;

          // Store in cache
          _distanceCache[cacheKey] = _CachedDistance(distanceKm, DateTime.now());
          
          // Cleanup cache if needed
          _cleanupCache();

          debugPrint(
              "DistanceService: Road distance calculated and cached: ${distanceKm}km (cache size: ${_distanceCache.length})");
          return distanceKm;
        } else {
          // API returned an error status (e.g., ZERO_RESULTS, NOT_FOUND)
          debugPrint(
              "DistanceService: Directions API returned status: ${data['status']}, falling back to straight-line distance");
          return _getStraightLineDistanceKm(
              originLat, originLng, destLat, destLng);
        }
      } else {
        // HTTP error response
        debugPrint(
            "DistanceService: HTTP error ${response.statusCode}, falling back to straight-line distance");
        return _getStraightLineDistanceKm(
            originLat, originLng, destLat, destLng);
      }
    } catch (e) {
      // Network error, timeout, or parsing error
      debugPrint(
          "DistanceService: Error calling Directions API: $e, falling back to straight-line distance");
      return _getStraightLineDistanceKm(
          originLat, originLng, destLat, destLng);
    }
  }

  /// Calculates straight-line distance using Geolocator.
  /// Used as fallback when Directions API is unavailable.
  static double _getStraightLineDistanceKm(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) {
    final distanceInMeters = Geolocator.distanceBetween(
        originLat, originLng, destLat, destLng);
    final distanceKm = distanceInMeters / 1000.0;
    debugPrint("DistanceService: Straight-line distance: ${distanceKm}km");
    return distanceKm;
  }
}

