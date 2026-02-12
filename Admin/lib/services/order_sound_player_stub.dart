import 'package:flutter/services.dart';

Future<void> warmUp() async {
  // No-op on non-web platforms.
}

Future<void> playBeep() async {
  // Uses the platform/system alert sound (safe, no assets needed).
  SystemSound.play(SystemSoundType.alert);
}

