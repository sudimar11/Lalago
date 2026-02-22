import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:foodie_driver/services/user_listener_service.dart';

/// Reports rider device health metrics to Firestore every five minutes.
/// Admins can use the `rider_health` collection to spot low battery,
/// memory leaks, or excessive listener counts before they cause issues.
class HealthTelemetryService {
  HealthTelemetryService._();
  static final HealthTelemetryService instance =
      HealthTelemetryService._();

  static const _interval = Duration(minutes: 5);
  static const _appVersion = '3.2.2+10';

  Timer? _timer;
  String? _riderId;
  final Battery _battery = Battery();

  String? _deviceModel;
  String? _osVersion;
  bool _deviceInfoLoaded = false;

  void start(String riderId) {
    if (_riderId == riderId && _timer != null) return;
    stop();
    _riderId = riderId;

    _timer = Timer.periodic(_interval, (_) => _report());
    _report();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _riderId = null;
  }

  Future<void> _report() async {
    final id = _riderId;
    if (id == null) return;

    try {
      await _loadDeviceInfoOnce();

      final batteryLevel = await _battery.batteryLevel;
      final memoryBytes = ProcessInfo.currentRss;
      final memoryMb = memoryBytes ~/ (1024 * 1024);

      await FirebaseFirestore.instance
          .collection('rider_health')
          .doc(id)
          .set(
        {
          'batteryLevel': batteryLevel,
          'memoryUsageMb': memoryMb,
          'activeListenerCount':
              UserListenerService.instance.callbackCount,
          'appVersion': _appVersion,
          'deviceModel': _deviceModel ?? 'unknown',
          'osVersion': _osVersion ?? 'unknown',
          'timestamp': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      log('HealthTelemetryService report error: $e');
    }
  }

  Future<void> _loadDeviceInfoOnce() async {
    if (_deviceInfoLoaded) return;
    _deviceInfoLoaded = true;

    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        _deviceModel = '${info.manufacturer} ${info.model}';
        _osVersion = 'Android ${info.version.release}';
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        _deviceModel = info.utsname.machine;
        _osVersion = '${info.systemName} ${info.systemVersion}';
      }
    } catch (e) {
      log('HealthTelemetryService device info error: $e');
    }
  }
}
