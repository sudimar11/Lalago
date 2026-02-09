import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/services/order_notification_service.dart';

/// Service responsible for finding and assigning drivers to orders
/// Uses AI-powered algorithms to select optimal drivers
class DriverAssignmentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrderNotificationService _notificationService =
      OrderNotificationService();

  /// Find and assign the best available driver to an order
  /// Returns a map with success status and driver information
  Future<Map<String, dynamic>> findAndAssignDriver({
    required String orderId,
    required double vendorLat,
    required double vendorLng,
    String? excludeDriverId,
    required void Function({
      required String orderId,
      required String driverId,
      required String assignmentLogId,
    }) setupDriverResponseListener,
  }) async {
    try {
      // Find active drivers
      final driversQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'driver')
          .where('isActive', isEqualTo: true)
          .get();

      if (driversQuery.docs.isEmpty) {
        return {'success': false, 'reason': 'No active drivers'};
      }

      // Calculate distances for all active drivers (excluding rejected one)
      final drivers = _buildDriversList(
        driversQuery.docs,
        vendorLat,
        vendorLng,
        excludeDriverId,
      );

      if (drivers.isEmpty) {
        return {'success': false, 'reason': 'No drivers with valid location'};
      }

      // Sort drivers by optimal score
      _sortDriversByScore(drivers);

      // Select the best driver
      final selectedDriver = drivers.first;
      final driverId = selectedDriver['id'] as String;
      final driverData = selectedDriver['data'] as Map<String, dynamic>;
      final distance = selectedDriver['distance'] as double;

      final driverName =
          '${driverData['firstName'] ?? ''} ${driverData['lastName'] ?? ''}'
              .trim();

      print(
          '[Driver Assignment] Found driver: $driverName ($driverId) at ${distance.toStringAsFixed(2)} km');

      // Assign driver to order
      await _assignDriverToOrder(orderId, driverId, distance);

      // Update driver status
      await _updateDriverStatus(driverId, orderId);

      // Log assignment
      final assignmentLogRef =
          await _logAssignment(orderId, driverId, distance);

      print(
          '[Driver Assignment] Assignment logged with ID: ${assignmentLogRef.id}');

      // Set up listener to track driver response
      setupDriverResponseListener(
        orderId: orderId,
        driverId: driverId,
        assignmentLogId: assignmentLogRef.id,
      );

      // Send SMS notification to driver
      await _notificationService.sendDriverAssignmentNotification(
        driverId: driverId,
        orderId: orderId,
      );

      return {
        'success': true,
        'driverId': driverId,
        'driverName': driverName.isEmpty ? 'Driver' : driverName,
        'distance': distance,
      };
    } catch (e, stackTrace) {
      print('[Driver Assignment] Error: $e\n$stackTrace');
      rethrow;
    }
  }

  /// Build list of available drivers with distances
  List<Map<String, dynamic>> _buildDriversList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    double vendorLat,
    double vendorLng,
    String? excludeDriverId,
  ) {
    List<Map<String, dynamic>> drivers = [];

    for (final doc in docs) {
      // Skip the driver who rejected the order
      if (excludeDriverId != null && doc.id == excludeDriverId) {
        print('[Driver Assignment] Skipping excluded driver: ${doc.id}');
        continue;
      }

      final driverData = doc.data();
      final location = driverData['location'];

      if (location != null && location is Map) {
        final driverLat = _asDouble(location['latitude']) ?? 0.0;
        final driverLng = _asDouble(location['longitude']) ?? 0.0;

        if (driverLat != 0.0 && driverLng != 0.0) {
          final distance =
              _calculateDistance(vendorLat, vendorLng, driverLat, driverLng);

          drivers.add({
            'id': doc.id,
            'data': driverData,
            'distance': distance,
          });
        }
      }
    }

    return drivers;
  }

  /// Sort drivers by combined score (distance + order load)
  /// Lower score is better
  void _sortDriversByScore(List<Map<String, dynamic>> drivers) {
    // Each active order counts as 3 km penalty to balance load
    const double orderPenaltyKm = 3.0;

    drivers.sort((a, b) {
      final aData = a['data'] as Map<String, dynamic>;
      final bData = b['data'] as Map<String, dynamic>;

      final aDistance = a['distance'] as double;
      final bDistance = b['distance'] as double;

      final aOrders = (aData['inProgressOrderID'] is List)
          ? (aData['inProgressOrderID'] as List).length
          : 0;
      final bOrders = (bData['inProgressOrderID'] is List)
          ? (bData['inProgressOrderID'] as List).length
          : 0;

      final aScore = aDistance + (aOrders * orderPenaltyKm);
      final bScore = bDistance + (bOrders * orderPenaltyKm);

      // Primary sort by score, tie-breaker by raw distance
      final cmp = aScore.compareTo(bScore);
      if (cmp != 0) return cmp;
      return aDistance.compareTo(bDistance);
    });
  }

  /// Assign driver to order in Firestore
  Future<void> _assignDriverToOrder(
    String orderId,
    String driverId,
    double distance,
  ) async {
    final orderRef = _firestore.collection('restaurant_orders').doc(orderId);

    await orderRef.update({
      'status': 'Driver Pending',
      'driverID': driverId,
      'driverDistance': distance,
      'assignedAt': FieldValue.serverTimestamp(),
      'autoReassigned': true,
    });

    print('[Driver Assignment] Updated order with driver assignment');
  }

  /// Update driver status in Firestore
  Future<void> _updateDriverStatus(String driverId, String orderId) async {
    await _firestore.collection('users').doc(driverId).update({
      'isActive': false,
      'inProgressOrderID': FieldValue.arrayUnion([orderId]),
    });

    print('[Driver Assignment] Updated driver status');
  }

  /// Log assignment to assignments_log collection
  Future<DocumentReference> _logAssignment(
    String orderId,
    String driverId,
    double distance,
  ) async {
    final assignmentLogRef =
        await _firestore.collection('assignments_log').add({
      'order_id': orderId,
      'driverId': driverId,
      'status': 'offered', // Initial status is 'offered'
      'etaMinutes': (distance / 0.5).round(),
      'km': distance,
      'score': 1.0,
      'acceptanceProb': 1.0,
      'createdAt': FieldValue.serverTimestamp(),
      'autoReassigned': true,
      'offeredAt': FieldValue.serverTimestamp(),
    });

    return assignmentLogRef;
  }

  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Earth's radius in kilometers
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c; // Distance in kilometers
  }

  /// Safely convert dynamic value to double
  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
