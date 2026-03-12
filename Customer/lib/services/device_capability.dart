import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

const int _defaultProductLimit = 50;
const int _lowEndProductLimit = 20;
const int _veryLowMemoryProductLimit = 10;
const int _defaultImageCacheSize = 280;
const int _lowEndImageCacheSize = 150;

/// Detects device capabilities for performance tuning.
class DeviceCapability {
  DeviceCapability._();

  static bool? _cachedIsLowEnd;
  static bool _initialized = false;

  /// Returns true for devices with &lt; 3GB RAM or isLowRamDevice flag.
  static Future<bool> isLowEndDevice() async {
    if (_initialized && _cachedIsLowEnd != null) return _cachedIsLowEnd!;
    _initialized = true;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        _cachedIsLowEnd = android.isLowRamDevice;
      } else {
        _cachedIsLowEnd = false;
      }
    } catch (_) {
      _cachedIsLowEnd = false;
    }
    return _cachedIsLowEnd ?? false;
  }

  /// Heuristic RAM estimate in MB. Uses isLowEndDevice: ~1GB for low-end,
  /// ~2GB otherwise. Use for stricter limits on very low memory.
  static Future<int> getEstimatedAvailableRamMb() async {
    final lowEnd = await isLowEndDevice();
    return lowEnd ? 1024 : 2048;
  }

  /// Product limit for home screen: 10 for very low memory, 20 for low-end,
  /// 50 otherwise.
  static Future<int> getInitialProductLimit() async {
    final lowEnd = await isLowEndDevice();
    if (!lowEnd) return _defaultProductLimit;
    final ramMb = await getEstimatedAvailableRamMb();
    return ramMb < 1500 ? _veryLowMemoryProductLimit : _lowEndProductLimit;
  }

  /// Image cache size in pixels: 150 for low-end, 280 otherwise.
  static Future<int> getImageCacheSize() async {
    final lowEnd = await isLowEndDevice();
    return lowEnd ? _lowEndImageCacheSize : _defaultImageCacheSize;
  }
}
