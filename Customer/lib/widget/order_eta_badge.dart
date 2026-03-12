import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/routing_service.dart';

/// Shows ETA (e.g. "ETA: X min") in a green badge for In Transit orders.
/// Uses FutureBuilder: loading indicator while fetching, then badge or hidden.
class OrderETABadge extends StatelessWidget {
  const OrderETABadge({Key? key, required this.order}) : super(key: key);

  final OrderModel order;

  static bool _isInTransit(String status) {
    final s = status.trim().toLowerCase();
    return s == ORDER_STATUS_IN_TRANSIT.toLowerCase() || s == 'in transit';
  }

  Future<int?> _fetchETAMinutes() async {
    if (!_isInTransit(order.status)) return null;
    final driverId = order.driverID ?? order.driver?.userID;
    if (driverId == null || driverId.isEmpty) return null;
    final dest = order.address?.location;
    if (dest == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(driverId)
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    final loc = data['location'];
    if (loc is! Map<String, dynamic>) return null;
    final lat = (loc['latitude'] as num?)?.toDouble();
    final lng = (loc['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    return RoutingService.getETA(
      lat,
      lng,
      dest.latitude,
      dest.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInTransit(order.status)) return const SizedBox.shrink();

    return FutureBuilder<int?>(
      future: _fetchETAMinutes(),
      builder: (BuildContext context, AsyncSnapshot<int?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.green.shade700,
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          final mins = snapshot.data!;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade700, width: 1),
            ),
            child: Text(
              'ETA: $mins min',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green.shade800,
                fontFamily: 'Poppinsm',
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
