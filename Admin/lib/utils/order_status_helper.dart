// Admin/lib/utils/order_status_helper.dart

class OrderStatusHelper {
  OrderStatusHelper._();

  /// Statuses that admin can manually assign (excludes automatic ones)
  static const List<String> manualAssignableStatuses = [
    'Order Placed',
    'Order Accepted',
    'Driver Assigned',
    'Driver Accepted',
    'Order Shipped',
    'In Transit',
    'Order Completed',
    'Order Cancelled',
  ];

  /// All possible statuses (including automatic)
  static const List<String> allPossibleStatuses = [
    'Order Placed',
    'Order Accepted',
    'Driver Assigned',
    'Driver Accepted',
    'Order Shipped',
    'In Transit',
    'Order Completed',
    'Order Cancelled',
    'Driver Rejected',
    'Order Rejected',
  ];

  static bool isManualAssignable(String status) {
    return manualAssignableStatuses.contains(status);
  }

  /// Returns a valid dropdown value; if current is automatic, returns default
  static String getValidStatusOrDefault(String? currentStatus) {
    if (currentStatus != null &&
        manualAssignableStatuses.contains(currentStatus)) {
      return currentStatus;
    }
    return manualAssignableStatuses.isNotEmpty
        ? manualAssignableStatuses.first
        : 'Order Accepted';
  }

  static String? getStatusRestrictionReason(String status) {
    if (status == 'Driver Rejected') {
      return 'Driver Rejected is automatic and cannot be manually set. '
          'It occurs when a rider rejects an order or when it times out.';
    }
    if (status == 'Order Rejected') {
      return 'Order Rejected is automatic and cannot be manually set. '
          'It occurs when a restaurant rejects an order.';
    }
    return null;
  }
}
