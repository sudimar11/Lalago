import 'package:cloud_firestore/cloud_firestore.dart';

/// Fetches rider time settings from config/rider_time_settings with caching.
class RiderTimeConfigService {
  RiderTimeConfigService._();

  static final RiderTimeConfigService _instance = RiderTimeConfigService._();
  static RiderTimeConfigService get instance => _instance;

  static Map<String, dynamic>? _cachedConfig;
  static DateTime? _cachedAt;
  static const Duration _cacheValidity = Duration(minutes: 5);

  /// Get rider time config. Returns cached value if still valid.
  Future<Map<String, dynamic>> getConfig({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedConfig != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _cacheValidity) {
      return _cachedConfig!;
    }

    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('rider_time_settings')
        .get()
        .timeout(const Duration(seconds: 10));

    final data = doc.exists && doc.data() != null
        ? Map<String, dynamic>.from(doc.data()!)
        : <String, dynamic>{};

    _cachedConfig = {
      'inactivityTimeoutMinutes': data['inactivityTimeoutMinutes'] ?? 15,
      'excludeWithActiveOrders': data['excludeWithActiveOrders'] ?? true,
    };
    _cachedAt = now;
    return _cachedConfig!;
  }

  /// Get inactivity timeout in minutes.
  Future<int> getInactivityTimeoutMinutes() async {
    final config = await getConfig();
    final v = config['inactivityTimeoutMinutes'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 15;
  }
}
