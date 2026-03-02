/// Shared constants and helpers for interactive notification action payloads.
/// Used across Customer, Rider, and Restaurant apps.
/// No Flutter/Firebase dependencies - keeps lalago_shared lightweight.

const String ACTION_SEPARATOR = '|';

/// Action IDs for interactive notifications.
const String ACTION_ACCEPT_ORDER = 'accept_order';
const String ACTION_DECLINE_ORDER = 'decline_order';
const String ACTION_REORDER = 'reorder';
const String ACTION_REMIND_LATER = 'remind_later';
const String ACTION_VIEW_ORDER = 'view_order';
const String ACTION_CHAT_REPLY = 'chat_reply';
const String ACTION_MARK_READY = 'mark_ready';
const String ACTION_CONFIRM_DELIVERY = 'confirm_delivery';

/// Parses action string like "accept_order|order_123|from_notification".
/// Returns map with action, targetId, and source.
Map<String, String> parseActionString(String actionString) {
  if (actionString.isEmpty) {
    return {'action': '', 'targetId': '', 'source': 'notification'};
  }
  final parts = actionString.split(ACTION_SEPARATOR);
  if (parts.length >= 2) {
    return {
      'action': parts[0].trim(),
      'targetId': parts[1].trim(),
      'source': parts.length > 2 ? parts[2].trim() : 'notification',
    };
  }
  return {
    'action': actionString.trim(),
    'targetId': '',
    'source': 'notification',
  };
}

/// Builds action string for payload.
String buildActionString(
  String action,
  String targetId, {
  String source = 'notification',
}) {
  if (targetId.isEmpty) return action;
  return '$action$ACTION_SEPARATOR$targetId$ACTION_SEPARATOR$source';
}
