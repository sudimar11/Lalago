import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:intl/intl.dart';

class CheckoutReminderService {
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  final NotificationService _notificationService;
  final String _userId;

  static const int reminderMinutesBefore = 30;
  static const int notificationId = NotificationService.idReminder + 1;

  CheckoutReminderService(
    this._notificationService,
    this._userId,
  );

  Future<void> start() async {
    try {
      // Listen to user document changes
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final user = User.fromJson(snapshot.data()!);
            _updateCheckoutReminder(user);
          }
        },
        onError: (error) {
          log('❌ Error in checkout reminder service: $error');
        },
      );

      // Also check immediately
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final user = User.fromJson(userDoc.data()!);
        _updateCheckoutReminder(user);
      }

      log('✅ Checkout reminder service started');
    } catch (e) {
      log('❌ Error starting checkout reminder service: $e');
    }
  }

  Future<void> _updateCheckoutReminder(User user) async {
    try {
      // Cancel existing reminder
      await _notificationService.cancelNotification(notificationId);

      // Don't schedule if already checked out
      if (user.checkedOutToday == true) {
        log('ℹ️ User already checked out, skipping reminder');
        return;
      }

      // Don't schedule if no checkout time set
      if (user.checkOutTime == null || user.checkOutTime!.isEmpty) {
        log('ℹ️ No checkout time set, skipping reminder');
        return;
      }

      // Parse checkout time
      final checkoutDateTime = _parseTimeString(user.checkOutTime!);
      if (checkoutDateTime == null) {
        log('⚠️ Could not parse checkout time: ${user.checkOutTime}');
        return;
      }

      // Calculate reminder time (30 minutes before checkout)
      final reminderTime = checkoutDateTime.subtract(
        const Duration(minutes: reminderMinutesBefore),
      );

      final now = DateTime.now();

      // Only schedule if reminder time is in the future
      if (reminderTime.isAfter(now)) {
        // Format checkout time for display
        final checkoutTimeFormatted = DateFormat('h:mm a').format(checkoutDateTime);

        await _notificationService.scheduleNotification(
          NotificationData(
            type: NotificationType.reminder,
            title: 'Checkout Reminder',
            body: 'Don\'t forget to checkout at $checkoutTimeFormatted',
            priority: NotificationPriority.normal,
            payload: {
              'type': 'reminder',
              'checkoutTime': user.checkOutTime,
            },
            notificationId: notificationId,
          ),
          reminderTime,
        );

        log('✅ Checkout reminder scheduled for $reminderTime (checkout at $checkoutTimeFormatted)');
      } else {
        log('ℹ️ Reminder time has passed, not scheduling');
      }
    } catch (e) {
      log('❌ Error updating checkout reminder: $e');
    }
  }

  DateTime? _parseTimeString(String timeString) {
    try {
      final parts = timeString.trim().split(' ');
      if (parts.length < 2) {
        return null;
      }

      final timePart = parts[0]; // "9" or "9:00"
      final period = parts[1].toUpperCase(); // "AM" or "PM"

      final timeComponents = timePart.split(':');
      int hour = int.parse(timeComponents[0]);
      int minute = timeComponents.length > 1 ? int.parse(timeComponents[1]) : 0;

      // Convert to 24-hour format
      if (period == 'PM' && hour != 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      // Create DateTime for today with checkout time
      final now = DateTime.now();
      var checkoutDateTime = DateTime(now.year, now.month, now.day, hour, minute);

      // If checkout time is before current time, assume it's for tomorrow
      if (checkoutDateTime.isBefore(now)) {
        checkoutDateTime = checkoutDateTime.add(const Duration(days: 1));
      }

      return checkoutDateTime;
    } catch (e) {
      log('❌ Error parsing time string "$timeString": $e');
      return null;
    }
  }

  void stop() {
    _userSubscription?.cancel();
    _userSubscription = null;
    _notificationService.cancelNotification(notificationId);
    log('🛑 Checkout reminder service stopped');
  }

  void dispose() {
    stop();
  }
}

/// Handler class that processes checkout reminders (used by UnifiedNotificationListener)
class CheckoutReminderHandler {
  final NotificationService _notificationService;
  final String _userId;

  static const int reminderMinutesBefore = 30;
  static const int notificationId = NotificationService.idReminder + 1;

  CheckoutReminderHandler(this._notificationService, this._userId);

  Future<void> initialize() async {
    // Also check immediately on initialization
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final user = User.fromJson(userDoc.data()!);
        await handleUserUpdate(user);
      }
    } catch (e) {
      log('⚠️ Error checking checkout reminder on initialization: $e');
    }
  }

  Future<void> handleUserUpdate(User user) async {
    await _updateCheckoutReminder(user);
  }

  Future<void> _updateCheckoutReminder(User user) async {
    try {
      // Cancel existing reminder
      await _notificationService.cancelNotification(notificationId);

      // Don't schedule if already checked out
      if (user.checkedOutToday == true) {
        log('ℹ️ User already checked out, skipping reminder');
        return;
      }

      // Don't schedule if no checkout time set
      if (user.checkOutTime == null || user.checkOutTime!.isEmpty) {
        log('ℹ️ No checkout time set, skipping reminder');
        return;
      }

      // Parse checkout time
      final checkoutDateTime = _parseTimeString(user.checkOutTime!);
      if (checkoutDateTime == null) {
        log('⚠️ Could not parse checkout time: ${user.checkOutTime}');
        return;
      }

      // Calculate reminder time (30 minutes before checkout)
      final reminderTime = checkoutDateTime.subtract(
        const Duration(minutes: reminderMinutesBefore),
      );

      final now = DateTime.now();

      // Only schedule if reminder time is in the future
      if (reminderTime.isAfter(now)) {
        // Format checkout time for display
        final checkoutTimeFormatted = DateFormat('h:mm a').format(checkoutDateTime);

        await _notificationService.scheduleNotification(
          NotificationData(
            type: NotificationType.reminder,
            title: 'Checkout Reminder',
            body: 'Don\'t forget to checkout at $checkoutTimeFormatted',
            priority: NotificationPriority.normal,
            payload: {
              'type': 'reminder',
              'checkoutTime': user.checkOutTime,
            },
            notificationId: notificationId,
          ),
          reminderTime,
        );

        log('✅ Checkout reminder scheduled for $reminderTime (checkout at $checkoutTimeFormatted)');
      } else {
        log('ℹ️ Reminder time has passed, not scheduling');
      }
    } catch (e) {
      log('❌ Error updating checkout reminder: $e');
    }
  }

  DateTime? _parseTimeString(String timeString) {
    try {
      final parts = timeString.trim().split(' ');
      if (parts.length < 2) {
        return null;
      }

      final timePart = parts[0]; // "9" or "9:00"
      final period = parts[1].toUpperCase(); // "AM" or "PM"

      final timeComponents = timePart.split(':');
      int hour = int.parse(timeComponents[0]);
      int minute = timeComponents.length > 1 ? int.parse(timeComponents[1]) : 0;

      // Convert to 24-hour format
      if (period == 'PM' && hour != 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      // Create DateTime for today with checkout time
      final now = DateTime.now();
      var checkoutDateTime = DateTime(now.year, now.month, now.day, hour, minute);

      // If checkout time is before current time, assume it's for tomorrow
      if (checkoutDateTime.isBefore(now)) {
        checkoutDateTime = checkoutDateTime.add(const Duration(days: 1));
      }

      return checkoutDateTime;
    } catch (e) {
      log('❌ Error parsing time string "$timeString": $e');
      return null;
    }
  }

  void dispose() {
    _notificationService.cancelNotification(notificationId);
  }
}
