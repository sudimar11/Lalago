import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';

AudioPlayer? _player;
bool _isPreloaded = false;

const String _assetPath = 'audio/mixkit-happy-bells-notification-937.mp3';
const Duration _playTimeout = Duration(seconds: 2);

AudioPlayer get _audioPlayer {
  _player ??= AudioPlayer();
  return _player!;
}

Future<void> warmUp() async {
  if (_isPreloaded) return;
  try {
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer.setSource(AssetSource(_assetPath));
    _isPreloaded = true;
  } catch (e) {
    log('OrderSoundPlayerNative: error preloading audio: $e');
  }
}

Future<void> playBeep() async {
  if (!_isPreloaded) await warmUp();
  try {
    await _audioPlayer.seek(Duration.zero);
    await _audioPlayer.resume().timeout(
          _playTimeout,
          onTimeout: () {
            log('OrderSoundPlayerNative: play timeout');
            return Future<void>.value();
          },
        );
  } catch (e) {
    log('OrderSoundPlayerNative: error playing audio: $e');
  }
}
