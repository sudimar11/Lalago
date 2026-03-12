import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'package:brgy/constants.dart';

class RouteData {
  final double roadDistanceKm;
  final double durationMinutes;
  final bool isFromCache;
  final bool isFallback;

  const RouteData({
    required this.roadDistanceKm,
    required this.durationMinutes,
    this.isFromCache = false,
    this.isFallback = false,
  });
}

class RoutingService {
  static const int _coordPrecision = 3;
  static const int _cacheTtlDays = 30;

  static final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  static double _round(double v) {
    final f = pow(10, _coordPrecision);
    return (v * f).roundToDouble() / f;
  }

  static String _cacheKey(
    double oLat,
    double oLng,
    double dLat,
    double dLng,
  ) {
    return '${_round(oLat)},${_round(oLng)}'
        '->${_round(dLat)},${_round(dLng)}';
  }

  static Future<RouteData> getRouteData(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    final results = await getRouteDataBatch(
      originLat,
      originLng,
      [RoutingLatLng(destLat, destLng)],
    );
    return results.first;
  }

  static Future<List<RouteData>> getRouteDataBatch(
    double originLat,
    double originLng,
    List<RoutingLatLng> destinations,
  ) async {
    final results =
        List<RouteData?>.filled(destinations.length, null);
    final uncached = <int>[];

    for (int i = 0; i < destinations.length; i++) {
      final d = destinations[i];
      final key = _cacheKey(
          originLat, originLng, d.lat, d.lng);
      try {
        final doc = await _firestore
            .collection('routes_cache')
            .doc(key)
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          final expires = data['expiresAt'] as Timestamp?;
          if (expires != null &&
              expires
                  .toDate()
                  .isAfter(DateTime.now())) {
            results[i] = RouteData(
              roadDistanceKm:
                  (data['roadDistanceKm'] as num)
                      .toDouble(),
              durationMinutes:
                  (data['durationMinutes'] as num)
                      .toDouble(),
              isFromCache: true,
            );
            continue;
          }
        }
      } catch (_) {}
      uncached.add(i);
    }

    if (uncached.isNotEmpty) {
      try {
        final destParam = uncached
            .map((i) =>
                '${destinations[i].lat},'
                '${destinations[i].lng}')
            .join('|');
        final url =
            'https://maps.googleapis.com/maps/api'
            '/distancematrix/json'
            '?origins=$originLat,$originLng'
            '&destinations=$destParam'
            '&mode=driving'
            '&key=$GOOGLE_API_KEY';

        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          final json =
              jsonDecode(resp.body) as Map<String, dynamic>;
          if (json['status'] == 'OK') {
            final rows =
                json['rows'] as List<dynamic>?;
            if (rows != null && rows.isNotEmpty) {
              final elements =
                  (rows[0] as Map)['elements']
                      as List<dynamic>;
              final now = DateTime.now();
              final expires =
                  now.add(Duration(days: _cacheTtlDays));
              final batch = _firestore.batch();

              for (int j = 0;
                  j < uncached.length;
                  j++) {
                final idx = uncached[j];
                final el = elements[j] as Map;
                if (el['status'] == 'OK') {
                  final km =
                      (el['distance']['value'] as num) /
                          1000;
                  final mins =
                      (el['duration']['value'] as num) /
                          60;
                  results[idx] = RouteData(
                    roadDistanceKm: km,
                    durationMinutes: mins,
                  );
                  final key = _cacheKey(
                    originLat,
                    originLng,
                    destinations[idx].lat,
                    destinations[idx].lng,
                  );
                  batch.set(
                    _firestore
                        .collection('routes_cache')
                        .doc(key),
                    {
                      'originLat': _round(originLat),
                      'originLng': _round(originLng),
                      'destLat':
                          _round(destinations[idx].lat),
                      'destLng':
                          _round(destinations[idx].lng),
                      'roadDistanceKm': km,
                      'durationMinutes': mins,
                      'source':
                          'google_distance_matrix',
                      'createdAt':
                          FieldValue.serverTimestamp(),
                      'expiresAt':
                          Timestamp.fromDate(expires),
                    },
                  );
                }
              }
              await batch.commit();
            }
          }
        }
      } catch (_) {}
    }

    for (int i = 0; i < results.length; i++) {
      if (results[i] == null) {
        final km = _haversineKm(
          originLat,
          originLng,
          destinations[i].lat,
          destinations[i].lng,
        );
        results[i] = RouteData(
          roadDistanceKm: km,
          durationMinutes: max(km / 0.5, 1),
          isFallback: true,
        );
      }
    }

    return results.cast<RouteData>();
  }

  static double _haversineKm(
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
}

class RoutingLatLng {
  final double lat;
  final double lng;
  const RoutingLatLng(this.lat, this.lng);
}
