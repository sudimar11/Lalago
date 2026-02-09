import 'package:cloud_firestore/cloud_firestore.dart';

class Driver {
  final String id;
  final String name;
  final String phoneNumber;
  final bool active;
  final DateTime? createdAt;
  final bool checkedOutToday;
  final double? latitude;
  final double? longitude;

  Driver({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.active,
    this.createdAt,
    this.checkedOutToday = false,
    this.latitude,
    this.longitude,
  });

  bool get hasLocation =>
      latitude != null && longitude != null &&
      latitude!.abs() > 0.0001 && longitude!.abs() > 0.0001;

  /// Active today = checked in and not checked out (same as Active Riders Live Map).
  bool get activeToday => !checkedOutToday;

  bool get signedUpToday {
    if (createdAt == null) return false;
    final now = DateTime.now();
    final d = createdAt!;
    return d.year == now.year &&
        d.month == now.month &&
        d.day == now.day;
  }

  factory Driver.fromMap(String id, Map<String, dynamic> data) {
    final String firstName = (data['firstName'] ?? '').toString().trim();
    final String lastName = (data['lastName'] ?? '').toString().trim();
    final String fullName = ('$firstName $lastName').trim();
    DateTime? createdAt;
    final raw = data['createdAt'];
    if (raw is Timestamp) {
      createdAt = raw.toDate();
    } else if (raw is DateTime) {
      createdAt = raw;
    }
    final bool checkedOutToday = (data['checkedOutToday'] ?? false) == true;
    double? latitude;
    double? longitude;
    final loc = data['location'];
    if (loc != null) {
      if (loc is GeoPoint) {
        latitude = loc.latitude;
        longitude = loc.longitude;
      } else if (loc is Map) {
        final lat = loc['latitude'];
        final lng = loc['longitude'];
        if (lat != null && lng != null) {
          latitude = (lat is num) ? lat.toDouble() : double.tryParse('$lat');
          longitude = (lng is num) ? lng.toDouble() : double.tryParse('$lng');
        }
      }
    }
    return Driver(
      id: id,
      name: fullName.isEmpty ? 'Unknown Driver' : fullName,
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      active: (data['isActive'] ?? false) == true,
      createdAt: createdAt,
      checkedOutToday: checkedOutToday,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
