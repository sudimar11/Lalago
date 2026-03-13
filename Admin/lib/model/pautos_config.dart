import 'package:cloud_firestore/cloud_firestore.dart';

class PautosConfig {
  double serviceFeePercent;
  bool useDistanceDeliveryFee;
  double flatDeliveryFee;
  double deliveryBaseFee;
  double deliveryPerKm;
  double minimumDistanceKm;
  double? riderCommissionPercent;
  Timestamp? updatedAt;
  bool enabled;

  PautosConfig({
    this.serviceFeePercent = 10,
    this.useDistanceDeliveryFee = true,
    this.flatDeliveryFee = 0,
    this.deliveryBaseFee = 0,
    this.deliveryPerKm = 0,
    this.minimumDistanceKm = 1,
    this.riderCommissionPercent,
    this.updatedAt,
    this.enabled = true,
  });

  static double _num(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  factory PautosConfig.fromJson(Map<String, dynamic> json) {
    final rider = json['riderCommissionPercent'];
    return PautosConfig(
      serviceFeePercent: _num(json, 'serviceFeePercent') != 0
          ? _num(json, 'serviceFeePercent')
          : 10,
      useDistanceDeliveryFee: json['useDistanceDeliveryFee'] != false,
      flatDeliveryFee: _num(json, 'flatDeliveryFee'),
      deliveryBaseFee: _num(json, 'deliveryBaseFee'),
      deliveryPerKm: _num(json, 'deliveryPerKm'),
      minimumDistanceKm: _num(json, 'minimumDistanceKm') != 0
          ? _num(json, 'minimumDistanceKm')
          : 1,
      riderCommissionPercent: rider != null
          ? (rider is num ? rider.toDouble() : double.tryParse(rider.toString()))
          : null,
      updatedAt: json['updatedAt'] is Timestamp
          ? json['updatedAt'] as Timestamp
          : null,
      enabled: json['enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serviceFeePercent': serviceFeePercent,
      'useDistanceDeliveryFee': useDistanceDeliveryFee,
      'flatDeliveryFee': flatDeliveryFee,
      'deliveryBaseFee': deliveryBaseFee,
      'deliveryPerKm': deliveryPerKm,
      'minimumDistanceKm': minimumDistanceKm,
      if (riderCommissionPercent != null) 'riderCommissionPercent': riderCommissionPercent,
      'updatedAt': updatedAt ?? Timestamp.now(),
      'enabled': enabled,
    };
  }
}
