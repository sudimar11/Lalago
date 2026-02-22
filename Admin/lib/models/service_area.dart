import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceArea {
  final String id;
  final String name;
  final List<String> barangays;
  final String boundaryType; // 'radius' | 'fixed'
  final double? centerLat;
  final double? centerLng;
  final double? radiusKm;
  final List<String> assignedDriverIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int order;
  final int? maxRiders; // null = unlimited
  final int currentActiveRiders;

  bool get isAtCapacity =>
      maxRiders != null && currentActiveRiders >= maxRiders!;

  const ServiceArea({
    required this.id,
    required this.name,
    required this.barangays,
    required this.boundaryType,
    this.centerLat,
    this.centerLng,
    this.radiusKm,
    required this.assignedDriverIds,
    this.createdAt,
    this.updatedAt,
    this.order = 0,
    this.maxRiders,
    this.currentActiveRiders = 0,
  });

  ServiceArea copyWith({
    int? currentActiveRiders,
    int? maxRiders,
  }) {
    return ServiceArea(
      id: id,
      name: name,
      barangays: barangays,
      boundaryType: boundaryType,
      centerLat: centerLat,
      centerLng: centerLng,
      radiusKm: radiusKm,
      assignedDriverIds: assignedDriverIds,
      createdAt: createdAt,
      updatedAt: updatedAt,
      order: order,
      maxRiders: maxRiders ?? this.maxRiders,
      currentActiveRiders:
          currentActiveRiders ?? this.currentActiveRiders,
    );
  }

  factory ServiceArea.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    final rawBarangays = d['barangays'];
    final rawDrivers = d['assignedDriverIds'];
    return ServiceArea(
      id: doc.id,
      name: (d['name'] ?? '').toString(),
      barangays: rawBarangays is List
          ? (rawBarangays).map((e) => e.toString()).toList()
          : [],
      boundaryType: (d['boundaryType'] ?? 'fixed').toString(),
      centerLat: _toDouble(d['centerLat']),
      centerLng: _toDouble(d['centerLng']),
      radiusKm: _toDouble(d['radiusKm']),
      assignedDriverIds: rawDrivers is List
          ? (rawDrivers).map((e) => e.toString()).toList()
          : [],
      createdAt: _toDateTime(d['createdAt']),
      updatedAt: _toDateTime(d['updatedAt']),
      order: _toInt(d['order']) ?? 0,
      maxRiders: _toInt(d['maxRiders']),
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'name': name,
      'barangays': barangays,
      'boundaryType': boundaryType,
      'assignedDriverIds': assignedDriverIds,
      'order': order,
    };
    if (boundaryType == 'radius') {
      if (centerLat != null) m['centerLat'] = centerLat;
      if (centerLng != null) m['centerLng'] = centerLng;
      if (radiusKm != null) m['radiusKm'] = radiusKm;
    }
    if (maxRiders != null) {
      m['maxRiders'] = maxRiders;
    } else {
      m['maxRiders'] = null;
    }
    m['updatedAt'] = FieldValue.serverTimestamp();
    return m;
  }

  Map<String, dynamic> toMapForCreate() {
    final m = toMap();
    m['createdAt'] = FieldValue.serverTimestamp();
    return m;
  }
}
