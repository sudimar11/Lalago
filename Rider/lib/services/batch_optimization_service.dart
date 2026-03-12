import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/utils/order_ready_time_helper.dart';
import 'package:geolocator/geolocator.dart';

/// Optimized pickup sequence for a batch of orders.
class OrderRoute {
  const OrderRoute({
    required this.order,
    required this.etaMinutes,
    required this.sequence,
    required this.readyAt,
  });

  final OrderModel order;
  final int etaMinutes;
  final int sequence;
  final DateTime? readyAt;
}

/// Service to optimize pickup sequence for riders with multiple orders.
class BatchOptimizationService {
  /// ~300 m/min average travel speed for ETA.
  static const double metersPerMinute = 300.0;

  /// Sort orders by leaveBy (earliest first) and build route with ETAs.
  static List<OrderRoute> optimizePickupSequence(
    List<OrderModel> orders, {
    UserLocation? riderLocation,
  }) {
    if (orders.isEmpty) return [];

    double currentLat = riderLocation?.latitude ?? orders.first.vendor.latitude;
    double currentLng = riderLocation?.longitude ?? orders.first.vendor.longitude;

    final withLeaveBy = <_OrderWithLeaveBy>[];
    for (final o in orders) {
      final baseTime = o.acceptedAt?.toDate() ?? o.createdAt.toDate();
      final prepMinutes =
          OrderReadyTimeHelper.parsePreparationMinutes(o.estimatedTimeToPrepare);
      final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
      final distanceM = Geolocator.distanceBetween(
        currentLat,
        currentLng,
        o.vendor.latitude,
        o.vendor.longitude,
      );
      final distanceKm = distanceM / 1000;
      final leaveBy = OrderReadyTimeHelper.getLeaveBy(readyAt, distanceKm);
      withLeaveBy.add(_OrderWithLeaveBy(order: o, leaveBy: leaveBy, readyAt: readyAt));
    }

    withLeaveBy.sort((a, b) => a.leaveBy.compareTo(b.leaveBy));

    final route = <OrderRoute>[];
    double lat = currentLat;
    double lng = currentLng;

    for (var i = 0; i < withLeaveBy.length; i++) {
      final item = withLeaveBy[i];
      final distanceM = Geolocator.distanceBetween(
        lat,
        lng,
        item.order.vendor.latitude,
        item.order.vendor.longitude,
      );
      final etaMinutes = (distanceM / metersPerMinute).ceil().clamp(1, 60);
      route.add(OrderRoute(
        order: item.order,
        etaMinutes: etaMinutes,
        sequence: i + 1,
        readyAt: item.readyAt,
      ));
      lat = item.order.vendor.latitude;
      lng = item.order.vendor.longitude;
    }

    return route;
  }
}

class _OrderWithLeaveBy {
  _OrderWithLeaveBy({
    required this.order,
    required this.leaveBy,
    required this.readyAt,
  });

  final OrderModel order;
  final DateTime leaveBy;
  final DateTime readyAt;
}
