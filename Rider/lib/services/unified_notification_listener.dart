import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/order_notification_listener.dart';
import 'package:foodie_driver/services/pautos_order_notification_listener.dart';
import 'package:foodie_driver/services/earnings_notification_listener.dart';
import 'package:foodie_driver/services/performance_notification_listener.dart';
import 'package:foodie_driver/services/checkout_reminder_service.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/model/notification_preferences.dart';

class UnifiedNotificationListener {
  StreamSubscription<DocumentSnapshot>? _userSubscription;
  final NotificationService _notificationService;
  final String _userId;
  final NotificationPreferences _preferences;

  // Handler instances (not listeners - just handlers)
  OrderNotificationHandler? _orderHandler;
  PautosOrderNotificationHandler? _pautosHandler;
  EarningsNotificationHandler? _earningsHandler;
  PerformanceNotificationHandler? _performanceHandler;
  CheckoutReminderHandler? _checkoutHandler;

  UnifiedNotificationListener(
    this._notificationService,
    this._userId,
    this._preferences,
  );

  Future<void> start() async {
    try {
      // Initialize handlers based on preferences
      if (_preferences.orderNotificationsEnabled) {
        _orderHandler = OrderNotificationHandler(_notificationService, _userId);
        await _orderHandler!.initialize();
      }

      _pautosHandler = PautosOrderNotificationHandler(
        _notificationService,
        _userId,
      );
      await _pautosHandler!.initialize();

      if (_preferences.earningNotificationsEnabled) {
        _earningsHandler = EarningsNotificationHandler(_notificationService, _userId);
        await _earningsHandler!.initialize();
      }

      if (_preferences.performanceNotificationsEnabled) {
        _performanceHandler = PerformanceNotificationHandler(_notificationService, _userId);
        await _performanceHandler!.initialize();
      }

      if (_preferences.checkoutRemindersEnabled) {
        _checkoutHandler = CheckoutReminderHandler(_notificationService, _userId);
        await _checkoutHandler!.initialize();
      }

      // Create single snapshot listener
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .snapshots()
          .listen(
        (snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data()!;

            // Dispatch to handlers based on preferences
            if (_preferences.orderNotificationsEnabled && _orderHandler != null) {
              final orderRequestData = data['orderRequestData'] as List<dynamic>?;
              _orderHandler!.handleOrderRequestDataChange(orderRequestData ?? []);
            }

            if (_pautosHandler != null) {
              final pautosOrderRequestData =
                  data['pautosOrderRequestData'] as List<dynamic>?;
              _pautosHandler!.handlePautosOrderRequestDataChange(
                pautosOrderRequestData ?? [],
              );
            }

            if (_preferences.earningNotificationsEnabled && _earningsHandler != null) {
              final todayVouchers = (data['todayVoucherEarned'] as num?)?.toDouble() ?? 0.0;
              final totalVouchers = (data['totalVouchers'] as num?)?.toDouble() ?? 0.0;
              _earningsHandler!.handleEarningsUpdate(todayVouchers, totalVouchers);
            }

            if (_preferences.performanceNotificationsEnabled && _performanceHandler != null) {
              final performance = (data['driver_performance'] as num?)?.toDouble() ?? 100.0;
              _performanceHandler!.handlePerformanceUpdate(performance);
            }

            if (_preferences.checkoutRemindersEnabled && _checkoutHandler != null) {
              final user = User.fromJson(data);
              _checkoutHandler!.handleUserUpdate(user);
            }
          }
        },
        onError: (error) {
          log('❌ Error in unified notification listener: $error');
        },
      );

      log('✅ Unified notification listener started');
    } catch (e) {
      log('❌ Error starting unified notification listener: $e');
    }
  }

  void stop() {
    _userSubscription?.cancel();
    _userSubscription = null;
    _orderHandler?.dispose();
    _pautosHandler?.dispose();
    _earningsHandler?.dispose();
    _performanceHandler?.dispose();
    _checkoutHandler?.dispose();
    log('🛑 Unified notification listener stopped');
  }

  void dispose() {
    stop();
  }
}
