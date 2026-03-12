import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/services/sms_service.dart';
import 'package:brgy/widgets/orders/order_helpers.dart';

/// Service for handling order-related SMS notifications
/// Uses a queue system to prevent concurrent SMS sends
class OrderNotificationService {
  final SMSService _smsService = SMSService();

  /// Ash-voiced SMS templates for customer notifications
  static String _getAshSmsContent(
    String type,
    Map<String, dynamic> data,
  ) {
    final restaurantName =
        (data['restaurantName'] as String?) ?? 'the restaurant';
    final customerName = (data['customerName'] as String?) ?? '';

    switch (type) {
      case 'order_placed':
        return 'Ash here! Your order from $restaurantName is placed. '
            'I\'ll update you when it\'s confirmed!';
      case 'order_accepted':
        final isAutoAccepted = data['isAutoAccepted'] == true;
        if (isAutoAccepted) {
          return customerName.isNotEmpty
              ? 'Good news from Ash! Hi $customerName, our rider has '
                  'accepted your order and is confirming with the restaurant.'
              : 'Good news from Ash! Our rider has accepted your order and '
                  'is confirming with the restaurant.';
        }
        return customerName.isNotEmpty
            ? 'Good news from Ash! Hi $customerName, $restaurantName '
                'accepted your order. It\'s being prepared.'
            : 'Good news from Ash! $restaurantName accepted your order. '
                'It\'s being prepared.';
      case 'order_rejected':
        return 'Ash here – your order from $restaurantName couldn\'t be '
            'processed. Want to try another restaurant? Check the app.';
      case 'order_ready':
        return 'Your order is ready! Ash hopes you enjoy your meal from '
            '$restaurantName.';
      case 'order_delivered':
        return 'Delivered! Ash hopes everything is perfect. Let me know if '
            'you need anything else!';
      default:
        return 'LalaGO: Your order status has been updated.';
    }
  }

  // Queue to prevent concurrent SMS sends
  final List<Future<void> Function()> _smsQueue = [];
  bool _isProcessingQueue = false;

  /// Send all order acceptance notifications in sequence
  /// This prevents SMS conflicts by queuing all messages
  Future<void> sendOrderAcceptanceNotifications({
    required String orderId,
    required Map<String, dynamic> orderData,
    required bool isAutoAccepted,
  }) async {
    try {
      print(
          '[Order Notification] Queuing acceptance notifications for order $orderId');

      // Queue customer notification
      _queueSMS(() async {
        await sendOrderAcceptedToCustomer(
          orderData: orderData,
          isAutoAccepted: isAutoAccepted,
        );
      });

      // If auto-accepted, also queue restaurant notification
      if (isAutoAccepted) {
        _queueSMS(() async {
          await sendAutoAcceptedOrderToRestaurant(
            orderData: orderData,
            orderId: orderId,
          );
        });
      }

      // Process the queue
      _processQueue();
    } catch (e) {
      print('[Order Notification] Error queuing notifications: $e');
    }
  }

  /// Send driver assignment notification (queued)
  Future<void> sendDriverAssignmentNotification({
    required String driverId,
    required String orderId,
  }) async {
    try {
      print(
          '[Order Notification] Queuing driver notification for order $orderId');

      _queueSMS(() async {
        await sendOrderNotificationToDriver(
          driverId: driverId,
          orderId: orderId,
        );
      });

      // Process the queue
      _processQueue();
    } catch (e) {
      print('[Order Notification] Error queuing driver notification: $e');
    }
  }

  /// Add SMS to queue
  void _queueSMS(Future<void> Function() smsFunction) {
    _smsQueue.add(smsFunction);
  }

  /// Process SMS queue sequentially with delays
  Future<void> _processQueue() async {
    // If already processing, don't start another process
    if (_isProcessingQueue) {
      return;
    }

    _isProcessingQueue = true;

    while (_smsQueue.isNotEmpty) {
      // Get the next SMS from queue
      final smsFunction = _smsQueue.removeAt(0);

      try {
        // Send SMS
        await smsFunction();

        // Wait 2 seconds before sending next SMS to prevent conflicts
        if (_smsQueue.isNotEmpty) {
          print('[Order Notification] Waiting 2 seconds before next SMS...');
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        print('[Order Notification] Error processing SMS from queue: $e');
        // Continue with next SMS even if one fails
      }
    }

    _isProcessingQueue = false;
    print('[Order Notification] Queue processing complete');
  }

  /// Send acceptance confirmation to customer
  Future<Map<String, dynamic>> sendOrderAcceptedToCustomer({
    required Map<String, dynamic> orderData,
    required bool isAutoAccepted,
  }) async {
    try {
      // Get customer phone number
      final phoneNumber = await _fetchCustomerPhone(orderData);
      if (phoneNumber.isEmpty) {
        print('[Order Notification] Customer phone number not available');
        return {
          'success': false,
          'message': 'Customer phone number not available'
        };
      }

      // Different messages based on acceptance type
      final author = (orderData['author'] ?? {}) as Map<String, dynamic>;
      final firstName = (author['firstName'] ?? '').toString();
      final lastName = (author['lastName'] ?? '').toString();
      final combined = '$firstName $lastName'.trim();
      String customerName =
          combined.isNotEmpty ? combined : (author['name'] ?? '').toString();
      if (customerName.trim().isEmpty) customerName = 'Customer';

      final vendor = (orderData['vendor'] ?? {}) as Map<String, dynamic>;
      final restaurantName =
          (vendor['title'] ?? vendor['name'] ?? 'the restaurant').toString();

      final message = _getAshSmsContent(
        'order_accepted',
        {
          'customerName': customerName,
          'restaurantName': restaurantName,
          'isAutoAccepted': isAutoAccepted,
        },
      );

      // Send SMS (without fallback to prevent SMS app opening)
      final result = await _smsService.sendSingleSMS(
        phoneNumber: phoneNumber,
        message: message,
        useFallback: false,
      );

      print(
          '[Order Notification] Sent to customer: $message (${result['success']})');
      return result;
    } catch (e) {
      print('[Order Notification] Error sending to customer: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Send order notification to driver
  Future<Map<String, dynamic>> sendOrderNotificationToDriver({
    required String driverId,
    required String orderId,
  }) async {
    try {
      // Fetch driver information
      final driverInfo = await fetchDriverInfo(driverId);
      final driverPhone = driverInfo['phone'] ?? '';

      if (driverPhone.isEmpty) {
        print('[Order Notification] Driver phone number not available');
        return {
          'success': false,
          'message': 'Driver phone number not available'
        };
      }

      // Send SMS
      final message =
          'You have a new order request. Please open your LalaGO app to review and confirm it.';
      final result = await _smsService.sendSingleSMS(
        phoneNumber: driverPhone,
        message: message,
        useFallback: false,
      );

      print(
          '[Order Notification] Sent to driver: $message (${result['success']})');
      return result;
    } catch (e) {
      print('[Order Notification] Error sending to driver: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Send auto-accepted order details to restaurant owner
  Future<Map<String, dynamic>> sendAutoAcceptedOrderToRestaurant({
    required Map<String, dynamic> orderData,
    required String orderId,
  }) async {
    try {
      // Get restaurant owner information
      final ownerInfo = await fetchRestaurantOwnerInfo(orderData);
      final ownerPhone = ownerInfo['phone'] ?? '';

      if (ownerPhone.isEmpty) {
        print(
            '[Order Notification] Restaurant owner phone number not available');
        return {
          'success': false,
          'message': 'Restaurant owner phone number not available'
        };
      }

      // Build order items message
      final orderItems = _buildOrderItemsMessage(orderData);
      final message = 'You have new orders:\n$orderItems';

      // Send SMS
      final result = await _smsService.sendSingleSMS(
        phoneNumber: ownerPhone,
        message: message,
        useFallback: false,
      );

      print('[Order Notification] Sent to restaurant: (${result['success']})');
      return result;
    } catch (e) {
      print('[Order Notification] Error sending to restaurant: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Build a formatted message with order items
  String _buildOrderItemsMessage(Map<String, dynamic> orderData) {
    try {
      // Prefer 'products' (name/quantity/price); fall back to 'productList' (title/quantity)
      final List<dynamic> raw = (orderData['products'] as List<dynamic>?) ??
          (orderData['productList'] as List<dynamic>?) ??
          [];

      if (raw.isEmpty) return 'No items listed';

      final lines = <String>[];
      for (final p in raw) {
        if (p is! Map) continue;
        final name = (p['name'] ?? p['title'] ?? 'Unknown item').toString();
        final qty = p['quantity'] ?? 1;
        final price = p['price']; // may be num or String

        String line = '${qty}x $name';
        if (price != null && price.toString().isNotEmpty) {
          final priceStr = price is num ? price.toString() : price.toString();
          line += ' - ₱$priceStr';
        }
        lines.add(line);
      }

      return lines.isEmpty ? 'No items listed' : lines.join('\n');
    } catch (e) {
      print('[Order Notification] Error building order items: $e');
      return 'Order details unavailable';
    }
  }

  /// Helper method to fetch customer phone number
  Future<String> _fetchCustomerPhone(Map<String, dynamic> orderData) async {
    try {
      // Get customer ID from order data
      final author = orderData['author'] as Map<String, dynamic>?;
      final customerId = author?['id'] as String? ?? '';

      if (customerId.isEmpty) {
        return '';
      }

      final customerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(customerId)
          .get();

      if (customerDoc.exists) {
        final customerData = customerDoc.data();
        return (customerData?['phoneNumber'] ?? '').toString();
      }
      return '';
    } catch (e) {
      print('[Order Notification] Error fetching customer phone: $e');
      return '';
    }
  }

  /// Clear the SMS queue (use when disposing or resetting)
  void clearQueue() {
    _smsQueue.clear();
    _isProcessingQueue = false;
  }

  /// Queue and send rejection SMS to customer
  Future<void> sendOrderRejectedNotification({
    required Map<String, dynamic> orderData,
  }) async {
    try {
      _queueSMS(() async {
        final phoneNumber = await _fetchCustomerPhone(orderData);
        if (phoneNumber.isEmpty) {
          print('[Order Notification] Customer phone number not available');
          return;
        }

        // Build personalized rejection message
        final author = (orderData['author'] ?? {}) as Map<String, dynamic>;
        final firstName = (author['firstName'] ?? '').toString();
        final lastName = (author['lastName'] ?? '').toString();
        final combined = '$firstName $lastName'.trim();
        String customerName =
            combined.isNotEmpty ? combined : (author['name'] ?? '').toString();
        if (customerName.trim().isEmpty) customerName = 'Customer';

        final vendor = (orderData['vendor'] ?? {}) as Map<String, dynamic>;
        String restaurantName = (vendor['title'] ?? '').toString().trim();
        if (restaurantName.isEmpty) restaurantName = 'the restaurant';

        final message =
            'LalaGO SMS: Salam $customerName Sorry, your order from $restaurantName is not available. Please check the app for other options.';

        final result = await _smsService.sendSingleSMS(
          phoneNumber: phoneNumber,
          message: message,
          useFallback: false,
        );

        print(
            '[Order Notification] Sent rejection to customer (${result['success']})');
      });

      _processQueue();
    } catch (e) {
      print('[Order Notification] Error queuing rejection SMS: $e');
    }
  }
}
