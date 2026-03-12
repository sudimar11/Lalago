import 'package:foodie_driver/services/notification_service.dart';
import 'package:lalago_shared/notification_action_payload.dart';

/// Handles interactive notification actions for the Rider app.
class NotificationActionHandler {
  /// Handles action from notification tap or action button.
  static Future<void> handleAction(
    String actionString,
    Map<String, dynamic>? payload,
  ) async {
    final parsed = parseActionString(actionString);
    final action = parsed['action'] ?? '';
    final targetId = parsed['targetId'] ?? payload?['orderId']?.toString() ?? '';

    if (targetId.isEmpty) return;

    switch (action) {
      case ACTION_ACCEPT_ORDER:
      case 'accept_delivery':
        NotificationService.onOrderActionFromNotification?.call(
          targetId,
          'accept',
        );
        break;
      case ACTION_DECLINE_ORDER:
        NotificationService.onOrderActionFromNotification?.call(
          targetId,
          'decline',
        );
        break;
      case ACTION_VIEW_ORDER:
      case 'view_order':
      case ACTION_CONFIRM_DELIVERY:
      case 'mark_delivered':
        NotificationService.onOrderActionFromNotification?.call(
          targetId,
          'view',
        );
        break;
      default:
        NotificationService.onOrderActionFromNotification?.call(
          targetId,
          'view',
        );
    }
  }
}
