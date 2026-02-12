import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'order_sound_player_stub.dart'
    if (dart.library.html) 'order_sound_player_web.dart' as player;

class OrderSoundService {
  static const _prefsKey = 'order_sound_enabled';
  static const _minInterval = Duration(seconds: 6);

  static bool _initialized = false;
  static bool _enabled = false;
  static DateTime _lastPlayedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static bool get isEnabled => _enabled;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? false;

    if (_enabled) {
      await player.warmUp();
    }
  }

  static Future<void> setEnabled(bool value) async {
    await init();
    _enabled = value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);

    if (value) {
      await player.warmUp();
    }
  }

  static Future<void> playTest() async {
    await init();
    if (!_enabled) return;
    await player.playBeep();
  }

  static Future<void> playNewOrderSound() async {
    await init();
    if (!_enabled) return;

    final now = DateTime.now();
    if (now.difference(_lastPlayedAt) < _minInterval) return;
    _lastPlayedAt = now;

    await player.playBeep();
  }
}

