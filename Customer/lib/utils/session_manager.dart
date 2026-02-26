import 'dart:async';
import 'dart:math';

/// Manages app session for analytics (e.g. click tracking).
/// Resets session on 30 minutes of inactivity.
class SessionManager {
  SessionManager._();
  static final SessionManager _instance = SessionManager._();
  factory SessionManager() => _instance;

  static String? _sessionId;
  static DateTime? _lastActivity;
  static Timer? _inactivityTimer;

  static const int _inactivityTimeoutMinutes = 30;

  static String get sessionId {
    _sessionId ??= _generateSessionId();
    return _sessionId!;
  }

  /// Call at app startup.
  static Future<void> initialize() async {
    _updateLastActivity();
    _startInactivityTimer();
  }

  /// Call when user performs an activity (e.g. click).
  static void recordActivity() {
    _updateLastActivity();
    _resetInactivityTimer();
  }

  static void _updateLastActivity() {
    _lastActivity = DateTime.now();
  }

  static void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkInactivity(),
    );
  }

  static void _checkInactivity() {
    if (_lastActivity == null) return;
    final elapsed =
        DateTime.now().difference(_lastActivity!).inMinutes;
    if (elapsed >= _inactivityTimeoutMinutes) {
      _resetSession();
    }
  }

  static void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _startInactivityTimer();
  }

  static void _resetSession() {
    _sessionId = _generateSessionId();
    _updateLastActivity();
  }

  static String _generateSessionId() {
    return '${DateTime.now().millisecondsSinceEpoch}_'
        '${_generateRandomString(8)}';
  }

  static String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random();
    return List.generate(
      length,
      (_) => chars[r.nextInt(chars.length)],
    ).join();
  }
}
