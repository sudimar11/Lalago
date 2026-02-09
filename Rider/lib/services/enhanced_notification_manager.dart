import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:foodie_driver/model/notification_preferences.dart';
import 'package:foodie_driver/services/unified_notification_listener.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/utils/shared_preferences_helper.dart';

class EnhancedNotificationManager {
  final NotificationService _notificationService;
  UnifiedNotificationListener? _unifiedListener;

  NotificationPreferences _preferences = const NotificationPreferences();

  static const String _prefKeyPreferences = 'notification_preferences';

  EnhancedNotificationManager(this._notificationService);

  /// Initialize notification manager and start all listeners
  Future<void> initialize() async {
    try {
      // Load preferences
      await _loadPreferences();

      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        log('⚠️ No user logged in, cannot start notification listeners');
        return;
      }

      // Start unified listener
      _unifiedListener = UnifiedNotificationListener(
        _notificationService,
        user.uid,
        _preferences,
      );
      await _unifiedListener!.start();

      log('✅ Enhanced notification manager initialized');
    } catch (e) {
      log('❌ Error initializing notification manager: $e');
    }
  }

  /// Update notification preferences and restart listeners if needed
  Future<void> updatePreferences(NotificationPreferences preferences) async {
    try {
      _preferences = preferences;
      await _savePreferences();

      // Restart listeners with new preferences
      await stop();
      await initialize();

      log('✅ Notification preferences updated');
    } catch (e) {
      log('❌ Error updating notification preferences: $e');
    }
  }

  /// Get current notification preferences
  NotificationPreferences getPreferences() => _preferences;

  /// Stop all notification listeners
  Future<void> stop() async {
    try {
      _unifiedListener?.stop();
      _unifiedListener = null;

      log('✅ All notification listeners stopped');
    } catch (e) {
      log('❌ Error stopping notification listeners: $e');
    }
  }

  /// Restart all listeners (useful after user login)
  Future<void> restart() async {
    await stop();
    await initialize();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        final prefsJson = prefs.getString(_prefKeyPreferences);
        if (prefsJson != null) {
          // Simple JSON parsing (you might want to use json_serializable)
          final prefsMap = <String, dynamic>{};
          final parts = prefsJson.split(',');
          for (final part in parts) {
            final keyValue = part.split(':');
            if (keyValue.length == 2) {
              prefsMap[keyValue[0]] = keyValue[1] == 'true';
            }
          }
          _preferences = NotificationPreferences.fromJson(prefsMap);
        }
      }
    } catch (e) {
      log('⚠️ Error loading notification preferences: $e');
      // Use default preferences
      _preferences = const NotificationPreferences();
    }
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferencesHelper.getInstanceSafe();
      if (prefs != null) {
        // Simple JSON serialization (you might want to use json_serializable)
        final prefsJson = 'orderNotificationsEnabled:${_preferences.orderNotificationsEnabled},'
            'earningNotificationsEnabled:${_preferences.earningNotificationsEnabled},'
            'performanceNotificationsEnabled:${_preferences.performanceNotificationsEnabled},'
            'checkoutRemindersEnabled:${_preferences.checkoutRemindersEnabled}';
        await prefs.setString(_prefKeyPreferences, prefsJson);
      }
    } catch (e) {
      log('⚠️ Error saving notification preferences: $e');
    }
  }

  void dispose() {
    stop();
  }
}

