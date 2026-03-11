import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Single shared Firestore listener for the current rider's user document.
/// All consumers register callbacks instead of creating their own listeners.
class UserListenerService {
  UserListenerService._();
  static final UserListenerService instance = UserListenerService._();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? _userId;
  final Map<String, void Function(Map<String, dynamic>)> _callbacks = {};
  DateTime? _ignoreRemoteUntil;

  /// Number of currently registered callbacks.
  int get callbackCount => _callbacks.length;

  /// Start listening to the user document. Safe to call multiple times;
  /// restarts the listener only when the userId changes.
  void start(String userId) {
    if (_userId == userId && _subscription != null) return;
    stop();
    _userId = userId;

    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen(
      (snapshot) {
        if (_ignoreRemoteUntil != null &&
            DateTime.now().isBefore(_ignoreRemoteUntil!)) {
          return;
        }
        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data()!;
          for (final cb in _callbacks.values.toList()) {
            try {
              cb(data);
            } catch (e) {
              log('UserListenerService callback error: $e');
            }
          }
        }
      },
      onError: (error) {
        log('UserListenerService snapshot error: $error');
      },
    );

    log('UserListenerService started for $userId');
  }

  /// Stop listening and clear all callbacks.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _callbacks.clear();
    _userId = null;
    log('UserListenerService stopped');
  }

  /// Register a callback that receives the raw user document data map
  /// every time the document changes.
  void addCallback(
    String key,
    void Function(Map<String, dynamic>) callback,
  ) {
    _callbacks[key] = callback;
  }

  /// Remove a previously registered callback by key.
  void removeCallback(String key) {
    _callbacks.remove(key);
  }

  /// Ignore remote snapshots briefly after local optimistic writes.
  void markLocalMutation({Duration duration = const Duration(milliseconds: 500)}) {
    _ignoreRemoteUntil = DateTime.now().add(duration);
  }
}
