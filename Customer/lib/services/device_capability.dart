import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

const int _defaultProductLimit = 50;
const int _lowEndProductLimit = 20;
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

  /// Product limit for home screen: 20 for low-end, 50 otherwise.
  static Future<int> getInitialProductLimit() async {
    final lowEnd = await isLowEndDevice();
    return lowEnd ? _lowEndProductLimit : _defaultProductLimit;
  }

  /// Image cache size in pixels: 150 for low-end, 280 otherwise.
  static Future<int> getImageCacheSize() async {
    final lowEnd = await isLowEndDevice();
    return lowEnd ? _lowEndImageCacheSize : _defaultImageCacheSize;
  }
}
