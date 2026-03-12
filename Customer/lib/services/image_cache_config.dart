import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'device_capability.dart';

/// Custom image cache configuration for low-memory devices.
/// Reduces cache size on low-end devices to avoid OOM.
class ImageCacheConfig {
  ImageCacheConfig._();

  static const String _cacheKey = 'lalago_image_cache';
  static const int _defaultMaxObjects = 200;
  static const int _lowEndMaxObjects = 50;

  static CacheManager? _instance;
  static bool _initStarted = false;

  /// Initialize cache with device-appropriate limits. Call early (e.g. in
  /// ContainerScreen initState). Safe to call multiple times.
  static Future<void> ensureInitialized() async {
    if (_initStarted) return;
    _initStarted = true;
    try {
      final lowEnd = await DeviceCapability.isLowEndDevice();
      final maxObjects = lowEnd ? _lowEndMaxObjects : _defaultMaxObjects;
      _instance = CacheManager(
        Config(
          _cacheKey,
          stalePeriod: const Duration(days: 3),
          maxNrOfCacheObjects: maxObjects,
        ),
      );
    } catch (_) {
      _instance = null;
    }
  }

  /// Cache manager for CachedNetworkImage. Uses custom config on low-end
  /// devices after ensureInitialized. Otherwise uses DefaultCacheManager.
  static CacheManager get cacheManager =>
      _instance ?? DefaultCacheManager();
}
