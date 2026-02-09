import 'dart:async';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:geolocator/geolocator.dart';

/// Service for monitoring driver proximity to order locations
class OrderLocationService {
  static const double PROXIMITY_THRESHOLD = 50.0; // meters
  static const Duration ARRIVAL_DETECTION_DELAY = Duration(seconds: 3);

  static final StreamController<bool> _proximityController =
      StreamController<bool>.broadcast();
  static final StreamController<String> _arrivalDetectedController =
      StreamController<String>.broadcast();
  static final StreamController<String> _departureDetectedController =
      StreamController<String>.broadcast();
  static final StreamController<String> _customerArrivalDetectedController =
      StreamController<String>.broadcast();
  static StreamSubscription<OrderModel?>? _orderSubscription;
  static bool _isNearRequiredLocation = false;
  static String? _currentOrderId;
  static Timer? _arrivalDetectionTimer;
  static Timer? _customerArrivalDetectionTimer;
  static final Set<String> _hasShownArrivalDialog = <String>{};
  static final Set<String> _hasShownCustomerArrival = <String>{};
  static bool _wasNearRestaurant = false;
  static bool _wasNearCustomer = false;

  /// Stream that emits proximity status (true when within 50m)
  static Stream<bool> get proximityStream => _proximityController.stream;

  /// Stream that emits order ID when arrival is detected (after delay)
  static Stream<String> get arrivalDetectedStream =>
      _arrivalDetectedController.stream;

  /// Stream that emits order ID when driver departs from restaurant
  static Stream<String> get departureDetectedStream =>
      _departureDetectedController.stream;

  /// Stream that emits order ID when customer arrival is detected (after delay)
  static Stream<String> get customerArrivalDetectedStream =>
      _customerArrivalDetectedController.stream;

  /// Check if driver is within 50m of restaurant
  static bool isNearRestaurant(
      OrderModel order, UserLocation driverLocation) {
    final distanceInMeters = Geolocator.distanceBetween(
      order.vendor.latitude,
      order.vendor.longitude,
      driverLocation.latitude,
      driverLocation.longitude,
    );

    return distanceInMeters <= PROXIMITY_THRESHOLD;
  }

  /// Check if driver is within 50m of customer
  static bool isNearCustomer(OrderModel order, UserLocation driverLocation) {
    if (order.address.location == null) {
      return false;
    }

    final distanceInMeters = Geolocator.distanceBetween(
      order.address.location!.latitude,
      order.address.location!.longitude,
      driverLocation.latitude,
      driverLocation.longitude,
    );

    return distanceInMeters <= PROXIMITY_THRESHOLD;
  }

  /// Check proximity based on order status
  /// Returns true if driver is at the required location for current status
  static bool isAtRequiredLocation(
      OrderModel order, UserLocation driverLocation) {
    // Monitor restaurant proximity for pickup states
    if (order.status == ORDER_STATUS_DRIVER_PENDING ||
        order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
        order.status == ORDER_STATUS_SHIPPED) {
      return isNearRestaurant(order, driverLocation);
    }

    // Monitor customer proximity for delivery state
    if (order.status == ORDER_STATUS_IN_TRANSIT) {
      return isNearCustomer(order, driverLocation);
    }

    return false;
  }

  /// Start monitoring proximity for an active order
  static void startMonitoring(String orderId, UserLocation driverLocation) {
    if (_currentOrderId == orderId) {
      // Already monitoring this order
      return;
    }

    stopMonitoring();
    _currentOrderId = orderId;

    // Listen to order updates
    _orderSubscription = FireStoreUtils()
        .getOrderByID(orderId)
        .listen((OrderModel? order) async {
      if (order == null) {
        _updateProximity(false);
        return;
      }

      // Get current driver location
      final currentDriver = await FireStoreUtils.getCurrentUser(
          order.driverID ?? '');
      if (currentDriver == null) {
        _updateProximity(false);
        return;
      }

      final isNear = isAtRequiredLocation(order, currentDriver.location);
      _updateProximity(isNear);

      // Check for restaurant arrival detection
      if (order.status == ORDER_STATUS_DRIVER_PENDING ||
          order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
          order.status == ORDER_STATUS_SHIPPED) {
        _checkRestaurantArrival(order, currentDriver.location);
      }

      // Check for customer arrival detection
      if (order.status == ORDER_STATUS_IN_TRANSIT) {
        _checkCustomerArrival(order, currentDriver.location);
      }
    });
  }

  /// Update proximity status when location changes
  static Future<void> onLocationUpdate(
      UserLocation driverLocation, String? activeOrderId) async {
    if (activeOrderId == null || activeOrderId.isEmpty) {
      _updateProximity(false);
      return;
    }

    // If we're not monitoring this order yet, start monitoring
    if (_currentOrderId != activeOrderId) {
      startMonitoring(activeOrderId, driverLocation);
      return;
    }

    // Get current order once
    try {
      final orderStream = FireStoreUtils().getOrderByID(activeOrderId);
      final order = await orderStream.first;
      if (order == null) {
        _updateProximity(false);
        return;
      }

      final isNear = isAtRequiredLocation(order, driverLocation);
      _updateProximity(isNear);

      // Check for restaurant arrival detection
      if (order.status == ORDER_STATUS_DRIVER_PENDING ||
          order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
          order.status == ORDER_STATUS_SHIPPED) {
        _checkRestaurantArrival(order, driverLocation);
      }

      // Check for customer arrival detection
      if (order.status == ORDER_STATUS_IN_TRANSIT) {
        _checkCustomerArrival(order, driverLocation);
      }
    } catch (e) {
      print('Error checking proximity: $e');
      _updateProximity(false);
    }
  }

  /// Check for restaurant arrival and trigger detection after delay
  static void _checkRestaurantArrival(
      OrderModel order, UserLocation driverLocation) {
    final nearRestaurant = isNearRestaurant(order, driverLocation);

    if (nearRestaurant && !_wasNearRestaurant) {
      // Driver just entered restaurant proximity
      _wasNearRestaurant = true;
      _startArrivalDetectionTimer(order.id);
    } else if (!nearRestaurant && _wasNearRestaurant) {
      // Driver left restaurant proximity
      _wasNearRestaurant = false;
      _cancelArrivalDetectionTimer();
      // Emit departure event
      _departureDetectedController.add(order.id);
    }
  }

  /// Start timer for arrival detection
  static void _startArrivalDetectionTimer(String orderId) {
    _cancelArrivalDetectionTimer();

    // Check if dialog was already shown for this order
    if (_hasShownArrivalDialog.contains(orderId)) {
      return;
    }

    _arrivalDetectionTimer = Timer(ARRIVAL_DETECTION_DELAY, () {
      // Check if still near restaurant
      if (_wasNearRestaurant && !_hasShownArrivalDialog.contains(orderId)) {
        _arrivalDetectedController.add(orderId);
        _hasShownArrivalDialog.add(orderId);
      }
    });
  }

  /// Cancel arrival detection timer
  static void _cancelArrivalDetectionTimer() {
    _arrivalDetectionTimer?.cancel();
    _arrivalDetectionTimer = null;
  }

  /// Check for customer arrival and trigger detection after delay
  static void _checkCustomerArrival(
      OrderModel order, UserLocation driverLocation) {
    final nearCustomer = isNearCustomer(order, driverLocation);

    if (nearCustomer && !_wasNearCustomer) {
      // Driver just entered customer proximity
      _wasNearCustomer = true;
      _startCustomerArrivalDetectionTimer(order.id);
    } else if (!nearCustomer && _wasNearCustomer) {
      // Driver left customer proximity
      _wasNearCustomer = false;
      _cancelCustomerArrivalDetectionTimer();
    }
  }

  /// Start timer for customer arrival detection
  static void _startCustomerArrivalDetectionTimer(String orderId) {
    _cancelCustomerArrivalDetectionTimer();

    // Check if arrival was already detected for this order
    if (_hasShownCustomerArrival.contains(orderId)) {
      return;
    }

    _customerArrivalDetectionTimer = Timer(ARRIVAL_DETECTION_DELAY, () {
      // Check if still near customer
      if (_wasNearCustomer && !_hasShownCustomerArrival.contains(orderId)) {
        _customerArrivalDetectedController.add(orderId);
        _hasShownCustomerArrival.add(orderId);
      }
    });
  }

  /// Cancel customer arrival detection timer
  static void _cancelCustomerArrivalDetectionTimer() {
    _customerArrivalDetectionTimer?.cancel();
    _customerArrivalDetectionTimer = null;
  }

  /// Update proximity state and emit to stream
  static void _updateProximity(bool isNear) {
    if (_isNearRequiredLocation != isNear) {
      _isNearRequiredLocation = isNear;
      _proximityController.add(isNear);
    }
  }

  /// Get current proximity status
  static bool get isNearRequiredLocation => _isNearRequiredLocation;

  /// Stop monitoring proximity
  static void stopMonitoring() {
    _orderSubscription?.cancel();
    _orderSubscription = null;
    _currentOrderId = null;
    _cancelArrivalDetectionTimer();
    _cancelCustomerArrivalDetectionTimer();
    _wasNearRestaurant = false;
    _wasNearCustomer = false;
    _updateProximity(false);
  }

  /// Mark arrival dialog as shown for an order (called after confirmation)
  static void markArrivalDialogShown(String orderId) {
    _hasShownArrivalDialog.add(orderId);
  }

  /// Reset arrival dialog state for an order (useful for testing or order reset)
  static void resetArrivalDialogState(String orderId) {
    _hasShownArrivalDialog.remove(orderId);
  }

  /// Mark customer arrival as detected for an order (called after navigation)
  static void markCustomerArrivalDetected(String orderId) {
    _hasShownCustomerArrival.add(orderId);
  }

  /// Reset customer arrival state for an order (useful for testing or order reset)
  static void resetCustomerArrivalState(String orderId) {
    _hasShownCustomerArrival.remove(orderId);
  }

  /// Dispose resources
  static void dispose() {
    stopMonitoring();
    _proximityController.close();
    _arrivalDetectedController.close();
    _departureDetectedController.close();
    _customerArrivalDetectedController.close();
  }
}

