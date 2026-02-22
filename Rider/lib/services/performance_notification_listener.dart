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

  static const double thresholdSilver = 75.0;
  static const double thresholdBronze = 60.0;
  static const double thresholdCritical = 50.0;

  double? _lastNotifiedThreshold;
  static const String _prefKeyLastThreshold =
      'last_performance_threshold';

  PerformanceNotificationListener(
    this._notificationService,
    this._userId,
  );

  Future<void> start() async {
    try {
      await _loadLastThreshold();
      log('📊 Last notified threshold: $_lastNotifiedThreshold');

      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final performance = (snapshot.data()![
                        'driver_performance'] as num?)
                    ?.toDouble() ??
                75.0;
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
      final prefs =
          await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        _lastNotifiedThreshold =
            prefs.getDouble(_prefKeyLastThreshold);
      }
    } catch (e) {
      log('⚠️ Error loading last threshold: $e');
    }
  }

  Future<void> _saveLastThreshold(double threshold) async {
    try {
      final prefs =
          await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setDouble(
            _prefKeyLastThreshold, threshold);
        _lastNotifiedThreshold = threshold;
      }
    } catch (e) {
      log('⚠️ Error saving last threshold: $e');
    }
  }

  void _checkPerformanceThresholds(double performance) {
    if (performance <= thresholdCritical) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > thresholdCritical) {
        _showPerformanceNotification(
          performance,
          thresholdCritical,
          NotificationPriority.critical,
          'Critical: Performance at ${performance.toStringAsFixed(0)}%. Contact support if needed.',
        );
        _saveLastThreshold(thresholdCritical);
      }
    } else if (performance <= thresholdBronze) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > thresholdBronze) {
        _showPerformanceNotification(
          performance,
          thresholdBronze,
          NotificationPriority.high,
          'Performance dropped to Bronze (${performance.toStringAsFixed(0)}%). Improve acceptance rate and attendance!',
        );
        _saveLastThreshold(thresholdBronze);
      }
    } else if (performance <= thresholdSilver) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > thresholdSilver) {
        _showPerformanceNotification(
          performance,
          thresholdSilver,
          NotificationPriority.normal,
          'Performance at Silver (${performance.toStringAsFixed(0)}%). Keep improving to reach Gold!',
        );
        _saveLastThreshold(thresholdSilver);
      }
    } else {
      if (_lastNotifiedThreshold != null) {
        _lastNotifiedThreshold = null;
        _saveLastThreshold(0);
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
      int notificationId;
      if (threshold == thresholdCritical) {
        notificationId =
            NotificationService.idPerformance + 1;
      } else if (threshold == thresholdBronze) {
        notificationId =
            NotificationService.idPerformance + 2;
      } else {
        notificationId =
            NotificationService.idPerformance + 3;
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

class PerformanceNotificationHandler {
  final NotificationService _notificationService;
  final String _userId;

  static const double thresholdSilver = 75.0;
  static const double thresholdBronze = 60.0;
  static const double thresholdCritical = 50.0;

  double? _lastNotifiedThreshold;
  static const String _prefKeyLastThreshold =
      'last_performance_threshold';

  PerformanceNotificationHandler(
    this._notificationService,
    this._userId,
  );

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
      final prefs =
          await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        _lastNotifiedThreshold =
            prefs.getDouble(_prefKeyLastThreshold);
      }
    } catch (e) {
      log('⚠️ Error loading last threshold: $e');
    }
  }

  Future<void> _saveLastThreshold(double threshold) async {
    try {
      final prefs =
          await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setDouble(
            _prefKeyLastThreshold, threshold);
        _lastNotifiedThreshold = threshold;
      }
    } catch (e) {
      log('⚠️ Error saving last threshold: $e');
    }
  }

  void _checkPerformanceThresholds(double performance) {
    if (performance <= thresholdCritical) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > thresholdCritical) {
        _showPerformanceNotification(
          performance,
          thresholdCritical,
          NotificationPriority.critical,
          'Critical: Performance at ${performance.toStringAsFixed(0)}%. Contact support if needed.',
        );
        _saveLastThreshold(thresholdCritical);
      }
    } else if (performance <= thresholdBronze) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > thresholdBronze) {
        _showPerformanceNotification(
          performance,
          thresholdBronze,
          NotificationPriority.high,
          'Performance dropped to Bronze (${performance.toStringAsFixed(0)}%). Improve acceptance rate and attendance!',
        );
        _saveLastThreshold(thresholdBronze);
      }
    } else if (performance <= thresholdSilver) {
      if (_lastNotifiedThreshold == null ||
          _lastNotifiedThreshold! > thresholdSilver) {
        _showPerformanceNotification(
          performance,
          thresholdSilver,
          NotificationPriority.normal,
          'Performance at Silver (${performance.toStringAsFixed(0)}%). Keep improving to reach Gold!',
        );
        _saveLastThreshold(thresholdSilver);
      }
    } else {
      if (_lastNotifiedThreshold != null) {
        _lastNotifiedThreshold = null;
        _saveLastThreshold(0);
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
      int notificationId;
      if (threshold == thresholdCritical) {
        notificationId =
            NotificationService.idPerformance + 1;
      } else if (threshold == thresholdBronze) {
        notificationId =
            NotificationService.idPerformance + 2;
      } else {
        notificationId =
            NotificationService.idPerformance + 3;
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

  void dispose() {}
}
