/// Shared order status constants for Lalago Admin, Rider, Customer, and Restaurant apps.
/// Use these constants instead of string literals to ensure consistent status values.
///
/// Note: "Driver Pending" has been removed. Use "Driver Assigned" for orders awaiting
/// rider acceptance and "Driver Accepted" when rider has accepted.

const String ORDER_STATUS_PLACED = 'Order Placed';
const String ORDER_STATUS_ACCEPTED = 'Order Accepted';
const String ORDER_STATUS_REJECTED = 'Order Rejected';
const String ORDER_STATUS_CANCELLED = 'Order Cancelled';
const String ORDER_STATUS_DRIVER_ASSIGNED = 'Driver Assigned';
const String ORDER_STATUS_DRIVER_ACCEPTED = 'Driver Accepted';
const String ORDER_STATUS_DRIVER_REJECTED = 'Driver Rejected';
const String ORDER_STATUS_SHIPPED = 'Order Shipped';
const String ORDER_STATUS_IN_TRANSIT = 'In Transit';
const String ORDER_STATUS_COMPLETED = 'Order Completed';
const String ORDER_STATUS_PAYMENT_FAILED = 'Payment Failed';
