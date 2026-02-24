import 'dart:developer';

import 'package:audioplayers/audioplayers.dart';

/// Plays custom notification sounds for new orders and order updates.
///
/// Uses a single [AudioPlayer] instance and debouncing to avoid overlapping
/// or repeated playback. Tracks which order IDs have already triggered a sound
/// so the same order does not play again until [markOrderAsNotified] is called
/// (e.g. when the rider accepts).
///
/// Future: A Firestore `sound_config` document could drive asset path per
/// event (new_order, food_ready, order_cancelled), volume, and vibration;
/// this implementation is hard-coded to the single asset for simplicity.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  static const Duration _debounceWindow = Duration(seconds: 3);
  /// Path relative to assets/ (audioplayers adds assets/ prefix).
  static const String _assetPath =
      'audio/mixkit-happy-bells-notification-937.mp3';
  static const String _reassignAssetPath = 'audio/reassign.wav';
  static const Duration _playTimeout = Duration(seconds: 2);

  DateTime? _lastPlayTime;
  final Set<String> _notifiedOrderIds = {};
  DateTime? _lastReassignPlayTime;
  final Set<String> _playedReassignOrderIds = {};
  AudioPlayer? _player;

  AudioPlayer get _audioPlayer {
    _player ??= AudioPlayer();
    return _player!;
  }

  /// Plays the new-order sound if debounce and order-ID checks pass.
  /// [orderId] optional; when set, skips if this order already triggered a play.
  Future<void> playNewOrderSound({String? orderId}) async {
    if (orderId != null && orderId.isNotEmpty && _notifiedOrderIds.contains(orderId)) {
      return;
    }
    final now = DateTime.now();
    if (_lastPlayTime != null &&
        now.difference(_lastPlayTime!) < _debounceWindow) {
      return;
    }
    _lastPlayTime = now;
    if (orderId != null && orderId.isNotEmpty) {
      _notifiedOrderIds.add(orderId);
    }

    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource(_assetPath)).timeout(
            _playTimeout,
            onTimeout: () {
              log('AudioService: play timeout');
              return Future<void>.value();
            },
          );
    } catch (e) {
      log('AudioService: failed to play $e');
    }
  }

  /// Removes [orderId] from the notified set so a later event can play again.
  void markOrderAsNotified(String orderId) {
    _notifiedOrderIds.remove(orderId);
  }

  /// Plays the reassign sound when an order is reassigned (e.g. timeout).
  /// Uses its own debounce and order-ID set so it does not block new-order sound.
  Future<void> playReassignSound({String? orderId}) async {
    final now = DateTime.now();
    if (_lastReassignPlayTime != null &&
        now.difference(_lastReassignPlayTime!) < _debounceWindow) {
      return;
    }
    if (orderId != null &&
        orderId.isNotEmpty &&
        _playedReassignOrderIds.contains('reassign_$orderId')) {
      return;
    }
    _lastReassignPlayTime = now;
    if (orderId != null && orderId.isNotEmpty) {
      _playedReassignOrderIds.add('reassign_$orderId');
    }
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.release);
      await _audioPlayer.play(AssetSource(_reassignAssetPath)).timeout(
            _playTimeout,
            onTimeout: () {
              log('AudioService: reassign play timeout');
              return Future<void>.value();
            },
          );
    } catch (e) {
      log('AudioService: failed to play reassign sound: $e');
    }
  }

  /// Removes [orderId] from the reassign-played set so a later event can play.
  void clearReassignFlag(String orderId) {
    _playedReassignOrderIds.remove('reassign_$orderId');
  }

  /// For tests; disposes the internal player. No-op if never played.
  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
