import 'dart:convert';

import 'package:foodie_customer/constants.dart';
import 'package:http/http.dart' as http;

class RoutingService {
  RoutingService._();

  /// Returns estimated travel time in minutes from origin to destination,
  /// or null on failure.
  static Future<int?> getETA(
  double originLat,
  double originLng,
  double destLat,
  double destLng,
) async {
  if (GOOGLE_API_KEY.isEmpty) return null;
  final url =
      'https://maps.googleapis.com/maps/api/distancematrix/json'
      '?origins=$originLat,$originLng'
      '&destinations=$destLat,$destLng'
      '&mode=driving'
      '&key=$GOOGLE_API_KEY';
  try {
    final resp = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return null;
    final json = jsonDecode(resp.body) as Map<String, dynamic>?;
    if (json == null || json['status'] != 'OK') return null;
    final rows = json['rows'] as List<dynamic>?;
    if (rows == null || rows.isEmpty) return null;
    final elements = (rows[0] as Map)['elements'] as List<dynamic>?;
    if (elements == null || elements.isEmpty) return null;
    final el = elements[0] as Map;
    if (el['status'] != 'OK') return null;
    final duration = el['duration'];
    if (duration == null) return null;
    final seconds = (duration['value'] as num?)?.toInt() ?? 0;
    if (seconds <= 0) return null;
    return (seconds / 60).round();
  } catch (_) {
    return null;
  }
  }
}
