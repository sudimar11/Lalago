import 'package:flutter/material.dart';
import 'package:foodie_restaurant/services/notification_service.dart';
import 'package:foodie_restaurant/ui/order_acceptance_screen.dart';
import 'package:lalago_shared/notification_action_payload.dart';

/// Handles interactive notification actions for the Restaurant app.
class NotificationActionHandler {
  /// Handles action from notification tap or action button.
  /// [actionString] can be "accept_order|orderId" or from response.actionId.
  /// [payload] is the full data map from the notification.
  static Future<void> handleAction(
    BuildContext? context,
    String actionString,
    Map<String, dynamic>? payload,
  ) async {
    final parsed = parseActionString(actionString);
    final action = parsed['action'] ?? '';
    final targetId = parsed['targetId'] ?? payload?['orderId']?.toString() ?? '';

    if (targetId.isEmpty) return;

    switch (action) {
      case ACTION_ACCEPT_ORDER:
        NotificationService.onNewOrder?.call(targetId);
        break;
      case ACTION_DECLINE_ORDER:
        NotificationService.onDeclineOrder?.call(targetId);
        break;
      case ACTION_VIEW_ORDER:
      case 'view_order':
        NotificationService.onNewOrder?.call(targetId);
        break;
      case ACTION_MARK_READY:
        NotificationService.onPrepTimeReminder?.call(targetId, '');
        break;
      default:
        NotificationService.onNewOrder?.call(targetId);
    }
  }
}
