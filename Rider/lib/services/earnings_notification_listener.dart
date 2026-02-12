import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/utils/shared_preferences_helper.dart';

class EarningsNotificationListener {
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  final NotificationService _notificationService;
  final String _userId;

  // Daily milestone thresholds
  static const List<int> dailyMilestones = [50, 100, 150];

  // Total milestone thresholds
  static const List<int> totalMilestones = [500, 1000, 5000];

  // Track last notified milestones to prevent duplicates
  int? _lastDailyMilestone;
  int? _lastTotalMilestone;

  static const String _prefKeyLastDailyMilestone = 'last_daily_milestone';
  static const String _prefKeyLastTotalMilestone = 'last_total_milestone';

  EarningsNotificationListener(
    this._notificationService,
    this._userId,
  );

  Future<void> start() async {
    try {
      // Load last notified milestones
      await _loadLastMilestones();

      // Listen to user document changes
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final todayVouchers =
                (snapshot.data()!['todayVoucherEarned'] as num?)?.toDouble() ??
                    0.0;
            final totalVouchers =
                (snapshot.data()!['totalVouchers'] as num?)?.toDouble() ?? 0.0;

            _checkDailyMilestones(todayVouchers);
            _checkTotalMilestones(totalVouchers);
          }
        },
        onError: (error) {
          log('❌ Error in earnings notification listener: $error');
        },
      );

      log('✅ Earnings notification listener started');
    } catch (e) {
      log('❌ Error starting earnings notification listener: $e');
    }
  }

  Future<void> _loadLastMilestones() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        _lastDailyMilestone = prefs.getInt(_prefKeyLastDailyMilestone);
        _lastTotalMilestone = prefs.getInt(_prefKeyLastTotalMilestone);
      }
    } catch (e) {
      log('⚠️ Error loading last milestones: $e');
    }
  }

  Future<void> _saveLastDailyMilestone(int milestone) async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setInt(_prefKeyLastDailyMilestone, milestone);
        _lastDailyMilestone = milestone;
      }
    } catch (e) {
      log('⚠️ Error saving last daily milestone: $e');
    }
  }

  Future<void> _saveLastTotalMilestone(int milestone) async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setInt(_prefKeyLastTotalMilestone, milestone);
        _lastTotalMilestone = milestone;
      }
    } catch (e) {
      log('⚠️ Error saving last total milestone: $e');
    }
  }

  void _checkDailyMilestones(double todayVouchers) {
    for (final milestone in dailyMilestones) {
      if (todayVouchers >= milestone &&
          (_lastDailyMilestone == null || _lastDailyMilestone! < milestone)) {
        _showDailyMilestoneNotification(milestone, todayVouchers);
        _saveLastDailyMilestone(milestone);
        break; // Only notify for the highest milestone reached
      }
    }
  }

  void _checkTotalMilestones(double totalVouchers) {
    for (final milestone in totalMilestones) {
      if (totalVouchers >= milestone &&
          (_lastTotalMilestone == null || _lastTotalMilestone! < milestone)) {
        _showTotalMilestoneNotification(milestone, totalVouchers);
        _saveLastTotalMilestone(milestone);
        break; // Only notify for the highest milestone reached
      }
    }
  }

  Future<void> _showDailyMilestoneNotification(
    int milestone,
    double currentVouchers,
  ) async {
    try {
      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.earning,
          title: '🎉 Daily Goal Achieved!',
          body: 'Great job! You\'ve earned $milestone vouchers today!',
          priority: NotificationPriority.normal,
          payload: {
            'type': 'earning',
            'milestoneType': 'daily',
            'milestone': milestone,
            'current': currentVouchers,
          },
          notificationId: NotificationService.idEarning + milestone,
        ),
      );

      log('✅ Daily milestone notification shown: $milestone');
    } catch (e) {
      log('❌ Error showing daily milestone notification: $e');
    }
  }

  Future<void> _showTotalMilestoneNotification(
    int milestone,
    double currentVouchers,
  ) async {
    try {
      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.earning,
          title: '🏆 Milestone Achieved!',
          body: 'Congratulations! You\'ve reached $milestone total vouchers!',
          priority: NotificationPriority.normal,
          payload: {
            'type': 'earning',
            'milestoneType': 'total',
            'milestone': milestone,
            'current': currentVouchers,
          },
          notificationId: NotificationService.idEarning + milestone + 1000,
        ),
      );

      log('✅ Total milestone notification shown: $milestone');
    } catch (e) {
      log('❌ Error showing total milestone notification: $e');
    }
  }

  void stop() {
    _userSubscription?.cancel();
    _userSubscription = null;
    log('🛑 Earnings notification listener stopped');
  }

  void dispose() {
    stop();
  }
}

/// Handler class that processes earnings notifications (used by UnifiedNotificationListener)
class EarningsNotificationHandler {
  final NotificationService _notificationService;
  final String _userId;

  // Daily milestone thresholds
  static const List<int> dailyMilestones = [50, 100, 150];

  // Total milestone thresholds
  static const List<int> totalMilestones = [500, 1000, 5000];

  // Track last notified milestones to prevent duplicates
  int? _lastDailyMilestone;
  int? _lastTotalMilestone;

  static const String _prefKeyLastDailyMilestone = 'last_daily_milestone';
  static const String _prefKeyLastTotalMilestone = 'last_total_milestone';

  EarningsNotificationHandler(this._notificationService, this._userId);

  Future<void> initialize() async {
    await _loadLastMilestones();
  }

  void handleEarningsUpdate(double todayVouchers, double totalVouchers) {
    _checkDailyMilestones(todayVouchers);
    _checkTotalMilestones(totalVouchers);
  }

  Future<void> _loadLastMilestones() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        _lastDailyMilestone = prefs.getInt(_prefKeyLastDailyMilestone);
        _lastTotalMilestone = prefs.getInt(_prefKeyLastTotalMilestone);
      }
    } catch (e) {
      log('⚠️ Error loading last milestones: $e');
    }
  }

  Future<void> _saveLastDailyMilestone(int milestone) async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setInt(_prefKeyLastDailyMilestone, milestone);
        _lastDailyMilestone = milestone;
      }
    } catch (e) {
      log('⚠️ Error saving last daily milestone: $e');
    }
  }

  Future<void> _saveLastTotalMilestone(int milestone) async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        await prefs.setInt(_prefKeyLastTotalMilestone, milestone);
        _lastTotalMilestone = milestone;
      }
    } catch (e) {
      log('⚠️ Error saving last total milestone: $e');
    }
  }

  void _checkDailyMilestones(double todayVouchers) {
    for (final milestone in dailyMilestones) {
      if (todayVouchers >= milestone &&
          (_lastDailyMilestone == null || _lastDailyMilestone! < milestone)) {
        _showDailyMilestoneNotification(milestone, todayVouchers);
        _saveLastDailyMilestone(milestone);
        break; // Only notify for the highest milestone reached
      }
    }
  }

  void _checkTotalMilestones(double totalVouchers) {
    for (final milestone in totalMilestones) {
      if (totalVouchers >= milestone &&
          (_lastTotalMilestone == null || _lastTotalMilestone! < milestone)) {
        _showTotalMilestoneNotification(milestone, totalVouchers);
        _saveLastTotalMilestone(milestone);
        break; // Only notify for the highest milestone reached
      }
    }
  }

  Future<void> _showDailyMilestoneNotification(
    int milestone,
    double currentVouchers,
  ) async {
    try {
      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.earning,
          title: '🎉 Daily Goal Achieved!',
          body: 'Great job! You\'ve earned $milestone vouchers today!',
          priority: NotificationPriority.normal,
          payload: {
            'type': 'earning',
            'milestoneType': 'daily',
            'milestone': milestone,
            'current': currentVouchers,
          },
          notificationId: NotificationService.idEarning + milestone,
        ),
      );

      log('✅ Daily milestone notification shown: $milestone');
    } catch (e) {
      log('❌ Error showing daily milestone notification: $e');
    }
  }

  Future<void> _showTotalMilestoneNotification(
    int milestone,
    double currentVouchers,
  ) async {
    try {
      await _notificationService.showNotification(
        NotificationData(
          type: NotificationType.earning,
          title: '🏆 Milestone Achieved!',
          body: 'Congratulations! You\'ve reached $milestone total vouchers!',
          priority: NotificationPriority.normal,
          payload: {
            'type': 'earning',
            'milestoneType': 'total',
            'milestone': milestone,
            'current': currentVouchers,
          },
          notificationId: NotificationService.idEarning + milestone + 1000,
        ),
      );

      log('✅ Total milestone notification shown: $milestone');
    } catch (e) {
      log('❌ Error showing total milestone notification: $e');
    }
  }

  void dispose() {
    // Cleanup if needed
  }
}
