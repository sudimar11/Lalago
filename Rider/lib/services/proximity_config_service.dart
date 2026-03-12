import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Fetches proximity detection settings from config/proximity_settings.
/// Used for GPS smoothing, hysteresis, and accuracy filtering in the Rider app.
class ProximityConfigService {
  ProximityConfigService._();

  static final ProximityConfigService _instance = ProximityConfigService._();
  static ProximityConfigService get instance => _instance;

  static Map<String, dynamic>? _cachedConfig;
  static DateTime? _cachedAt;
  static const Duration _cacheValidity = Duration(minutes: 5);

  /// Defaults when Firestore doc is missing or field is absent.
  static const double defaultEnterThreshold = 45.0;
  static const double defaultExitThreshold = 55.0;
  static const int defaultSmoothingWindow = 5;
  static const int defaultArrivalDelaySeconds = 3;
  static const int defaultMinTimeBetweenChangesSeconds = 5;
  static const double defaultMaxAllowedAccuracy = 20.0;

  /// Fetches config and caches it. Call once at listener start so sync getters work.
  Future<Map<String, dynamic>> getConfig(
      {bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedConfig != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheValidity) {
      return _cachedConfig!;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('proximity_settings')
          .get()
          .timeout(const Duration(seconds: 10));

      final data = doc.exists && doc.data() != null
          ? Map<String, dynamic>.from(doc.data()!)
          : <String, dynamic>{};

      _cachedConfig = {
        'enterThreshold': _toDouble(data['enterThreshold'], defaultEnterThreshold),
        'exitThreshold': _toDouble(data['exitThreshold'], defaultExitThreshold),
        'smoothingWindow': _toInt(data['smoothingWindow'], defaultSmoothingWindow),
        'arrivalDelaySeconds': _toInt(
            data['arrivalDelaySeconds'], defaultArrivalDelaySeconds),
        'minTimeBetweenChangesSeconds': _toInt(
            data['minTimeBetweenChangesSeconds'],
            defaultMinTimeBetweenChangesSeconds),
        'maxAllowedAccuracy': data['maxAllowedAccuracy'] == null
            ? defaultMaxAllowedAccuracy
            : _toDouble(data['maxAllowedAccuracy'], defaultMaxAllowedAccuracy),
      };
      _cachedAt = now;
      return _cachedConfig!;
    } catch (e, st) {
      developer.log('ProximityConfigService getConfig failed: $e', stackTrace: st);
      _cachedConfig = _defaultsMap();
      _cachedAt = now;
      return _cachedConfig!;
    }
  }

  static Map<String, dynamic> _defaultsMap() => {
        'enterThreshold': defaultEnterThreshold,
        'exitThreshold': defaultExitThreshold,
        'smoothingWindow': defaultSmoothingWindow,
        'arrivalDelaySeconds': defaultArrivalDelaySeconds,
        'minTimeBetweenChangesSeconds': defaultMinTimeBetweenChangesSeconds,
        'maxAllowedAccuracy': defaultMaxAllowedAccuracy,
      };

  static double _toDouble(dynamic v, double fallback) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return fallback;
  }

  static int _toInt(dynamic v, int fallback) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  /// Enter "near" when distance < this (meters). Uses cache; call getConfig() first.
  double get enterThreshold =>
      _cachedConfig?['enterThreshold'] ?? defaultEnterThreshold;

  /// Exit "near" when distance > this (meters).
  double get exitThreshold =>
      _cachedConfig?['exitThreshold'] ?? defaultExitThreshold;

  /// Max size of location buffer for smoothing (e.g. 3–5).
  int get smoothingWindow =>
      _cachedConfig?['smoothingWindow'] ?? defaultSmoothingWindow;

  /// Delay in seconds before emitting arrival event.
  int get arrivalDelaySeconds =>
      _cachedConfig?['arrivalDelaySeconds'] ?? defaultArrivalDelaySeconds;

  /// Min seconds between proximity state flips (debounce).
  int get minTimeBetweenChangesSeconds =>
      _cachedConfig?['minTimeBetweenChangesSeconds'] ??
      defaultMinTimeBetweenChangesSeconds;

  /// Discard location if accuracy > this (meters). Uses cache; call getConfig() first.
  double get maxAllowedAccuracy =>
      _cachedConfig?['maxAllowedAccuracy'] ?? defaultMaxAllowedAccuracy;
}
