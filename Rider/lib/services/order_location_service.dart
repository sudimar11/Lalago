import 'dart:async';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/proximity_config_service.dart';
import 'package:geolocator/geolocator.dart';

/// Service for monitoring driver proximity to order locations.
/// Uses hysteresis, moving-average smoothing, and debounce to reduce GPS flicker.
class OrderLocationService {
  static const double PROXIMITY_THRESHOLD = 50.0; // legacy; prefer config

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

  /// Location buffer for moving-average smoothing (max size from config).
  static final List<UserLocation> _locationBuffer = [];
  static UserLocation? _lastSmoothedLocation;
  static DateTime? _lastProximityStateChangeAt;

  /// Stream that emits proximity status (true when within hysteresis "near" zone)
  static Stream<bool> get proximityStream => _proximityController.stream;

  static Stream<String> get arrivalDetectedStream =>
      _arrivalDetectedController.stream;
  static Stream<String> get departureDetectedStream =>
      _departureDetectedController.stream;
  static Stream<String> get customerArrivalDetectedStream =>
      _customerArrivalDetectedController.stream;

  /// Check if driver is within enter-threshold of restaurant (for UI).
  static bool isNearRestaurant(
      OrderModel order, UserLocation driverLocation) {
    final enterT = ProximityConfigService.instance.enterThreshold;
    final distanceInMeters = Geolocator.distanceBetween(
      order.vendor.latitude,
      order.vendor.longitude,
      driverLocation.latitude,
      driverLocation.longitude,
    );
    return distanceInMeters <= enterT;
  }

  /// Check if driver is within enter-threshold of customer (for UI).
  static bool isNearCustomer(OrderModel order, UserLocation driverLocation) {
    if (order.address.location == null) return false;
    final enterT = ProximityConfigService.instance.enterThreshold;
    final distanceInMeters = Geolocator.distanceBetween(
      order.address.location!.latitude,
      order.address.location!.longitude,
      driverLocation.latitude,
      driverLocation.longitude,
    );
    return distanceInMeters <= enterT;
  }

  static bool isAtRequiredLocation(
      OrderModel order, UserLocation driverLocation) {
    if (order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
        order.status == ORDER_STATUS_SHIPPED) {
      return isNearRestaurant(order, driverLocation);
    }
    if (order.status == ORDER_STATUS_IN_TRANSIT) {
      return isNearCustomer(order, driverLocation);
    }
    return false;
  }

  /// Add location to buffer and return smoothed location (average of buffer).
  static UserLocation _addAndGetSmoothed(
      UserLocation location, int smoothingWindow) {
    _locationBuffer.add(location);
    if (smoothingWindow < 2 || _locationBuffer.length < 2) {
      _lastSmoothedLocation = location;
      return location;
    }
    while (_locationBuffer.length > smoothingWindow) {
      _locationBuffer.removeAt(0);
    }
    double sumLat = 0.0, sumLng = 0.0;
    for (final loc in _locationBuffer) {
      sumLat += loc.latitude;
      sumLng += loc.longitude;
    }
    final n = _locationBuffer.length;
    final smoothed = UserLocation(
      latitude: sumLat / n,
      longitude: sumLng / n,
    );
    _lastSmoothedLocation = smoothed;
    return smoothed;
  }

  static double _distanceToRestaurant(OrderModel order, UserLocation loc) {
    return Geolocator.distanceBetween(
      order.vendor.latitude,
      order.vendor.longitude,
      loc.latitude,
      loc.longitude,
    );
  }

  static double _distanceToCustomer(OrderModel order, UserLocation loc) {
    if (order.address.location == null) return double.infinity;
    return Geolocator.distanceBetween(
      order.address.location!.latitude,
      order.address.location!.longitude,
      loc.latitude,
      loc.longitude,
    );
  }

  /// Hysteresis: enter when distance < enterT, exit when distance > exitT.
  static bool _wouldBeNearWithHysteresis(
      bool currentlyNear, double distance, double enterT, double exitT) {
    if (currentlyNear) {
      return distance <= exitT;
    }
    return distance < enterT;
  }

  static bool _debounceAllowsChange(int minSeconds) {
    if (_lastProximityStateChangeAt == null) return true;
    return DateTime.now()
            .difference(_lastProximityStateChangeAt!)
            .inSeconds >=
        minSeconds;
  }

  static bool _isRestaurantPhase(OrderModel order) {
    return order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
        order.status == ORDER_STATUS_SHIPPED;
  }

  static bool _getCurrentNearState(OrderModel order) {
    if (_isRestaurantPhase(order)) return _wasNearRestaurant;
    if (order.status == ORDER_STATUS_IN_TRANSIT) return _wasNearCustomer;
    return false;
  }

  /// Start monitoring proximity for an active order
  static void startMonitoring(String orderId, UserLocation driverLocation) {
    if (_currentOrderId == orderId) return;

    stopMonitoring();
    _currentOrderId = orderId;

    _orderSubscription = FireStoreUtils()
        .getOrderByID(orderId)
        .listen((OrderModel? order) async {
      if (order == null) {
        _updateProximity(false);
        return;
      }

      final currentDriver = await FireStoreUtils.getCurrentUser(
          order.driverID ?? '');
      if (currentDriver == null) {
        _updateProximity(false);
        return;
      }

      await ProximityConfigService.instance.getConfig();
      final config = ProximityConfigService.instance;
      final effectiveLocation =
          _lastSmoothedLocation ?? currentDriver.location;
      final enterT = config.enterThreshold;
      final exitT = config.exitThreshold;
      final minSec = config.minTimeBetweenChangesSeconds;
      final delaySec = config.arrivalDelaySeconds;

      if (_isRestaurantPhase(order)) {
        final distance = _distanceToRestaurant(order, effectiveLocation);
        final wouldBeNear = _wouldBeNearWithHysteresis(
            _wasNearRestaurant, distance, enterT, exitT);
        _applyRestaurantStateChange(
            order, wouldBeNear, distance, enterT, exitT, minSec, delaySec);
      } else if (order.status == ORDER_STATUS_IN_TRANSIT) {
        final distance = _distanceToCustomer(order, effectiveLocation);
        final wouldBeNear = _wouldBeNearWithHysteresis(
            _wasNearCustomer, distance, enterT, exitT);
        _applyCustomerStateChange(
            order, wouldBeNear, distance, enterT, exitT, minSec, delaySec);
      }

      _updateProximity(_getCurrentNearState(order));
    });
  }

  /// Update proximity status when location changes (from ContainerScreen).
  static Future<void> onLocationUpdate(
      UserLocation driverLocation, String? activeOrderId) async {
    if (activeOrderId == null || activeOrderId.isEmpty) {
      _updateProximity(false);
      return;
    }

    if (_currentOrderId != activeOrderId) {
      startMonitoring(activeOrderId, driverLocation);
      return;
    }

    try {
      await ProximityConfigService.instance.getConfig();
      final config = ProximityConfigService.instance;
      final window = config.smoothingWindow;
      UserLocation effectiveLocation;
      if (window < 2) {
        _lastSmoothedLocation = driverLocation;
        effectiveLocation = driverLocation;
      } else {
        effectiveLocation = _addAndGetSmoothed(driverLocation, window);
      }

      final orderStream = FireStoreUtils().getOrderByID(activeOrderId);
      final order = await orderStream.first;
      if (order == null) {
        _updateProximity(false);
        return;
      }

      final enterT = config.enterThreshold;
      final exitT = config.exitThreshold;
      final minSec = config.minTimeBetweenChangesSeconds;
      final delaySec = config.arrivalDelaySeconds;

      if (_isRestaurantPhase(order)) {
        final distance = _distanceToRestaurant(order, effectiveLocation);
        final wouldBeNear = _wouldBeNearWithHysteresis(
            _wasNearRestaurant, distance, enterT, exitT);
        _applyRestaurantStateChange(
            order, wouldBeNear, distance, enterT, exitT, minSec, delaySec);
      } else if (order.status == ORDER_STATUS_IN_TRANSIT) {
        final distance = _distanceToCustomer(order, effectiveLocation);
        final wouldBeNear = _wouldBeNearWithHysteresis(
            _wasNearCustomer, distance, enterT, exitT);
        _applyCustomerStateChange(
            order, wouldBeNear, distance, enterT, exitT, minSec, delaySec);
      }

      _updateProximity(_getCurrentNearState(order));
    } catch (e) {
      print('Error checking proximity: $e');
      _updateProximity(false);
    }
  }

  static void _applyRestaurantStateChange(
      OrderModel order,
      bool wouldBeNear,
      double distance,
      double enterT,
      double exitT,
      int minSec,
      int delaySec) {
    if (wouldBeNear == _wasNearRestaurant) return;

    if (!_debounceAllowsChange(minSec)) return;

    _lastProximityStateChangeAt = DateTime.now();
    _wasNearRestaurant = wouldBeNear;

    if (_wasNearRestaurant) {
      _startArrivalDetectionTimer(order.id, delaySec);
    } else {
      _cancelArrivalDetectionTimer();
      _departureDetectedController.add(order.id);
    }
  }

  static void _applyCustomerStateChange(
      OrderModel order,
      bool wouldBeNear,
      double distance,
      double enterT,
      double exitT,
      int minSec,
      int delaySec) {
    if (wouldBeNear == _wasNearCustomer) return;

    if (!_debounceAllowsChange(minSec)) return;

    _lastProximityStateChangeAt = DateTime.now();
    _wasNearCustomer = wouldBeNear;

    if (_wasNearCustomer) {
      _startCustomerArrivalDetectionTimer(order.id, delaySec);
    } else {
      _cancelCustomerArrivalDetectionTimer();
    }
  }

  static void _startArrivalDetectionTimer(String orderId, int delaySeconds) {
    _cancelArrivalDetectionTimer();
    if (_hasShownArrivalDialog.contains(orderId)) return;

    _arrivalDetectionTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_wasNearRestaurant && !_hasShownArrivalDialog.contains(orderId)) {
        _arrivalDetectedController.add(orderId);
        _hasShownArrivalDialog.add(orderId);
      }
    });
  }

  static void _cancelArrivalDetectionTimer() {
    _arrivalDetectionTimer?.cancel();
    _arrivalDetectionTimer = null;
  }

  static void _startCustomerArrivalDetectionTimer(
      String orderId, int delaySeconds) {
    _cancelCustomerArrivalDetectionTimer();
    if (_hasShownCustomerArrival.contains(orderId)) return;

    _customerArrivalDetectionTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_wasNearCustomer &&
          !_hasShownCustomerArrival.contains(orderId)) {
        _customerArrivalDetectedController.add(orderId);
        _hasShownCustomerArrival.add(orderId);
      }
    });
  }

  static void _cancelCustomerArrivalDetectionTimer() {
    _customerArrivalDetectionTimer?.cancel();
    _customerArrivalDetectionTimer = null;
  }

  static void _updateProximity(bool isNear) {
    if (_isNearRequiredLocation != isNear) {
      _isNearRequiredLocation = isNear;
      _proximityController.add(isNear);
    }
  }

  static bool get isNearRequiredLocation => _isNearRequiredLocation;

  static void stopMonitoring() {
    _orderSubscription?.cancel();
    _orderSubscription = null;
    _currentOrderId = null;
    _cancelArrivalDetectionTimer();
    _cancelCustomerArrivalDetectionTimer();
    _wasNearRestaurant = false;
    _wasNearCustomer = false;
    _locationBuffer.clear();
    _lastSmoothedLocation = null;
    _lastProximityStateChangeAt = null;
    _updateProximity(false);
  }

  static void markArrivalDialogShown(String orderId) {
    _hasShownArrivalDialog.add(orderId);
  }

  static void resetArrivalDialogState(String orderId) {
    _hasShownArrivalDialog.remove(orderId);
  }

  static void markCustomerArrivalDetected(String orderId) {
    _hasShownCustomerArrival.add(orderId);
  }

  static void resetCustomerArrivalState(String orderId) {
    _hasShownCustomerArrival.remove(orderId);
  }

  static void dispose() {
    stopMonitoring();
    _proximityController.close();
    _arrivalDetectedController.close();
    _departureDetectedController.close();
    _customerArrivalDetectedController.close();
  }
}
