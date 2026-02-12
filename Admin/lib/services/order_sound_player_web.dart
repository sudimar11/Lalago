// Web-only sound implementation (no assets needed).
//
// Note: browsers often block audio until there has been a user gesture.
// The Settings toggle calls warmUp/play from a user interaction to unlock it.

import 'dart:async';
import 'dart:js_util' as js_util;

Object? _ctx;

Object _createAudioContext() {
  final root = js_util.globalThis;
  final ctor = js_util.getProperty(root, 'AudioContext') ??
      js_util.getProperty(root, 'webkitAudioContext');
  if (ctor == null) {
    throw UnsupportedError('WebAudio AudioContext not available.');
  }
  return js_util.callConstructor(ctor as Object, const []);
}

Future<void> _resume(Object ctx) async {
  try {
    final result = js_util.callMethod(ctx, 'resume', const []);
    if (result != null) {
      await js_util.promiseToFuture(result);
    }
  } catch (_) {}
}

Future<void> warmUp() async {
  _ctx ??= _createAudioContext();
  await _resume(_ctx!);
}

Future<void> playBeep() async {
  _ctx ??= _createAudioContext();
  await _resume(_ctx!);

  final ctx = _ctx!;
  final osc = js_util.callMethod(ctx, 'createOscillator', const []);
  final gain = js_util.callMethod(ctx, 'createGain', const []);

  js_util.setProperty(osc, 'type', 'sine');
  final freq = js_util.getProperty(osc, 'frequency');
  if (freq != null) {
    js_util.setProperty(freq, 'value', 880); // A5
  }
  final gainNode = js_util.getProperty(gain, 'gain');
  if (gainNode != null) {
    js_util.setProperty(gainNode, 'value', 0.05); // quiet
  }

  js_util.callMethod(osc, 'connect', [gain]);
  final destination = js_util.getProperty(ctx, 'destination');
  js_util.callMethod(gain, 'connect', [destination]);

  js_util.callMethod(osc, 'start', const []);
  final currentTime = (js_util.getProperty(ctx, 'currentTime') as num?) ?? 0;
  js_util.callMethod(osc, 'stop', [currentTime + 0.16]);

  // Cleanup
  Future<void>.delayed(const Duration(milliseconds: 220), () {
    try {
      js_util.callMethod(osc, 'disconnect', const []);
      js_util.callMethod(gain, 'disconnect', const []);
    } catch (_) {}
  });
}

