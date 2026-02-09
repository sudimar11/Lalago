import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/utils/shared_preferences_helper.dart';

class PerformanceNotificationListener {
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  final NotificationService _notificationService;
  final String _userId;

  // Performance thresholds
  static const double threshold80 = 80.0;
  static const double threshold70 = 70.0;
  static const double threshold50 = 50.0;

  // Track last notified threshold to prevent spam
  double? _lastNotifiedThreshold;
  static const String _prefKeyLastThreshold = 'last_performance_threshold';

  PerformanceNotificationListener(
    this._notificationService,
    this._userId,
  );

  Future<void> start() async {
    try {
      // Load last notified threshold
      await _loadLastThreshold();
      log('📊 Last notified threshold: $_lastNotifiedThreshold');

      // Listen to user document changes
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final performance =
                (snapshot.data()!['driver_performance'] as num?)?.toDouble() ??
                    100.0;
            log('📊 Performance update received: $performance%');
            _checkPerformanceThresholds(performance);
          }
        },
        onError: (error) {
          log('❌ Error in performance notification listener: $error');
        },
      );

      log('✅ Performance notification listener started for user: $_userId');
    } catch (e) {
      log('❌ Error starting performance notification listener: $e');
    }
  }

  Future<void> _loadLastThreshold() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        _lastNotifiedThreshold = prefs.getDouble(_prefKeyLastThreshold);
      }
    } catch (e) {
      log('⚠️ Error loading last threshold: $e');
    }
  }

  Future<void> _saveLastThreshold(double threshold) async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setDouble(_prefKeyLastThreshold, threshold);
        _lastNotifiedThreshold = threshold;
      }
    } catch (e) {
      log('⚠️ Error saving last threshold: $e');
    }
  }

  void _checkPerformanceThresholds(double performance) {
    // Check thresholds in descending order (most critical first)
    if (performance <= threshold50) {
      if (_lastNotifiedThreshold == null || _lastNotifiedThreshold! > threshold50) {
        _showPerformanceNotification(
          performance,
          threshold50,
          NotificationPriority.critical,
          'Critical: Performance at ${performance.toStringAsFixed(0)}%. Contact support if needed.',
        );
        _saveLastThreshold(threshold50);
      }
    } else if (performance <= threshold70) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > threshold70) {
        _showPerformanceNotification(
          performance,
          threshold70,
          NotificationPriority.high,
          'Performance at ${performance.toStringAsFixed(0)}%. Check in on time to improve!',
        );
        _saveLastThreshold(threshold70);
      }
    } else if (performance <= threshold80) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > threshold80) {
        _showPerformanceNotification(
          performance,
          threshold80,
          NotificationPriority.normal,
          'Performance at ${performance.toStringAsFixed(0)}%. Keep up the good work!',
        );
        _saveLastThreshold(threshold80);
      }
    } else {
      // Performance is good (above 80%), reset threshold tracking
      if (_lastNotifiedThreshold != null) {
        _lastNotifiedThreshold = null;
        _saveLastThreshold(0); // Use 0 to indicate "good performance"
      }
    }
  }

  Future<void> _showPerformanceNotification(
    double currentPerformance,
    double threshold,
    NotificationPriority priority,
    String message,
  ) async {
    try {
      // Use unique ID based on threshold to avoid collision
      int notificationId;
      if (threshold == threshold50) {
        notificationId = NotificationService.idPerformance + 1;
      } else if (threshold == threshold70) {
        notificationId = NotificationService.idPerformance + 2;
      } else {
        notificationId = NotificationService.idPerformance + 3;
      }

      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.performance,
          title: 'Performance Alert',
          body: message,
          priority: priority,
          payload: {
            'type': 'performance',
            'current': currentPerformance,
            'threshold': threshold,
          },
          notificationId: notificationId,
        ),
      );

      log('✅ Performance notification shown: $currentPerformance% (threshold: $threshold, ID: $notificationId)');
    } catch (e) {
      log('❌ Error showing performance notification: $e');
    }
  }

  void stop() {
    _userSubscription?.cancel();
    _userSubscription = null;
    log('🛑 Performance notification listener stopped');
  }

  void dispose() {
    stop();
  }
}

/// Handler class that processes performance notifications (used by UnifiedNotificationListener)
class PerformanceNotificationHandler {
  final NotificationService _notificationService;
  final String _userId;

  // Performance thresholds
  static const double threshold80 = 80.0;
  static const double threshold70 = 70.0;
  static const double threshold50 = 50.0;

  // Track last notified threshold to prevent spam
  double? _lastNotifiedThreshold;
  static const String _prefKeyLastThreshold = 'last_performance_threshold';

  PerformanceNotificationHandler(this._notificationService, this._userId);

  Future<void> initialize() async {
    await _loadLastThreshold();
    log('📊 Last notified threshold: $_lastNotifiedThreshold');
  }

  void handlePerformanceUpdate(double performance) {
    log('📊 Performance update received: $performance%');
    _checkPerformanceThresholds(performance);
  }

  Future<void> _loadLastThreshold() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        _lastNotifiedThreshold = prefs.getDouble(_prefKeyLastThreshold);
      }
    } catch (e) {
      log('⚠️ Error loading last threshold: $e');
    }
  }

  Future<void> _saveLastThreshold(double threshold) async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setDouble(_prefKeyLastThreshold, threshold);
        _lastNotifiedThreshold = threshold;
      }
    } catch (e) {
      log('⚠️ Error saving last threshold: $e');
    }
  }

  void _checkPerformanceThresholds(double performance) {
    // Check thresholds in descending order (most critical first)
    if (performance <= threshold50) {
      if (_lastNotifiedThreshold == null || _lastNotifiedThreshold! > threshold50) {
        _showPerformanceNotification(
          performance,
          threshold50,
          NotificationPriority.critical,
          'Critical: Performance at ${performance.toStringAsFixed(0)}%. Contact support if needed.',
        );
        _saveLastThreshold(threshold50);
      }
    } else if (performance <= threshold70) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > threshold70) {
        _showPerformanceNotification(
          performance,
          threshold70,
          NotificationPriority.high,
          'Performance at ${performance.toStringAsFixed(0)}%. Check in on time to improve!',
        );
        _saveLastThreshold(threshold70);
      }
    } else if (performance <= threshold80) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > threshold80) {
        _showPerformanceNotification(
          performance,
          threshold80,
          NotificationPriority.normal,
          'Performance at ${performance.toStringAsFixed(0)}%. Keep up the good work!',
        );
        _saveLastThreshold(threshold80);
      }
    } else {
      // Performance is good (above 80%), reset threshold tracking
      if (_lastNotifiedThreshold != null) {
        _lastNotifiedThreshold = null;
        _saveLastThreshold(0); // Use 0 to indicate "good performance"
      }
    }
  }

  Future<void> _showPerformanceNotification(
    double currentPerformance,
    double threshold,
    NotificationPriority priority,
    String message,
  ) async {
    try {
      // Use unique ID based on threshold to avoid collision
      int notificationId;
      if (threshold == threshold50) {
        notificationId = NotificationService.idPerformance + 1;
      } else if (threshold == threshold70) {
        notificationId = NotificationService.idPerformance + 2;
      } else {
        notificationId = NotificationService.idPerformance + 3;
      }

      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.performance,
          title: 'Performance Alert',
          body: message,
          priority: priority,
          payload: {
            'type': 'performance',
            'current': currentPerformance,
            'threshold': threshold,
          },
          notificationId: notificationId,
        ),
      );

      log('✅ Performance notification shown: $currentPerformance% (threshold: $threshold, ID: $notificationId)');
    } catch (e) {
      log('❌ Error showing performance notification: $e');
    }
  }

  void dispose() {
    // Cleanup if needed
  }
}
