import 'package:foodie_customer/constants.dart';

/// Returns a friendly, user-facing message for the given order status.
String getStatusMessage(String status) {
  final s = status.trim().toLowerCase();
  if (s.isEmpty) return status;

  switch (s) {
    case 'order placed':
    case 'placed':
      return 'Order confirmed';
    case 'order accepted':
    case 'accepted':
      return 'Looking for rider';
    case 'driver assigned':
    case 'driver pending':
      return 'Rider on the way to restaurant';
    case 'driver accepted':
      return 'Restaurant preparing';
    case 'order shipped':
    case 'shipped':
      return 'Ready for pickup';
    case 'in transit':
      return 'On the way to you';
    case 'order completed':
    case 'completed':
    case 'delivered':
      return 'Delivered';
    case 'order rejected':
    case 'rejected':
      return 'Order rejected';
    case 'order cancelled':
    case 'cancelled':
      return 'Order cancelled';
    case 'driver rejected':
      return 'Rider declined';
    case 'payment failed':
      return 'Payment failed';
    default:
      return status;
  }
}

/// Returns the appropriate primary action label for the given order status.
String getButtonText(String status) {
  final s = status.trim().toLowerCase();
  if (s.isEmpty) return 'View Details';

  if (s == ORDER_STATUS_COMPLETED.toLowerCase() ||
      s == 'completed' ||
      s == 'delivered') {
    return 'Reorder';
  }
  if (s == ORDER_STATUS_SHIPPED.toLowerCase() ||
      s == 'shipped' ||
      s == ORDER_STATUS_IN_TRANSIT.toLowerCase() ||
      s == 'in transit') {
    return 'Track';
  }
  return 'View Details';
}

/// Returns progress percentage (0-100) for the given order status.
int getProgressPercentage(String status) {
  final s = status.trim().toLowerCase();
  if (s.isEmpty) return 0;

  switch (s) {
    case 'order placed':
    case 'placed':
      return 10;
    case 'order accepted':
    case 'accepted':
      return 30;
    case 'driver assigned':
    case 'driver pending':
      return 40;
    case 'driver accepted':
      return 60;
    case 'order shipped':
    case 'shipped':
      return 80;
    case 'in transit':
      return 90;
    case 'order completed':
    case 'completed':
    case 'delivered':
      return 100;
    case 'order rejected':
    case 'rejected':
    case 'order cancelled':
    case 'cancelled':
    case 'driver rejected':
    case 'payment failed':
    default:
      return 0;
  }
}
