import 'dart:core';
import 'package:cloud_firestore/cloud_firestore.dart';

class DeliveryChargeModel {
  num baseDeliveryCharge;
  num deliveryChargePerKm;
  num deliveryCommissionPercent;
  num minimumDistanceKm;
  Timestamp? lastUpdated;
  
  // New properties for updated delivery charge calculation
  num deliveryChargesPerKm;
  num minimumDeliveryCharges;
  num minimumDeliveryChargesWithinKm;
  num amount;

  DeliveryChargeModel({
    this.baseDeliveryCharge = 0,
    this.deliveryChargePerKm = 0,
    this.deliveryCommissionPercent = 0,
    this.minimumDistanceKm = 0,
    this.lastUpdated,
    this.deliveryChargesPerKm = 0,
    this.minimumDeliveryCharges = 0,
    this.minimumDeliveryChargesWithinKm = 0,
    this.amount = 0,
  });

  factory DeliveryChargeModel.fromJson(Map<String, dynamic> parsedJson) {
    return DeliveryChargeModel(
      baseDeliveryCharge: parsedJson['baseDeliveryCharge'] ?? 
          parsedJson['base_delivery_charge'] ?? 0,
      deliveryChargePerKm: parsedJson['deliveryChargePerKm'] ?? 
          parsedJson['delivery_charge_per_km'] ?? 0,
      deliveryCommissionPercent: parsedJson['deliveryCommissionPercent'] ?? 
          parsedJson['delivery_commission'] ?? 0,
      minimumDistanceKm: parsedJson['minimumDistanceKm'] ?? 
          parsedJson['minimum_distance_km'] ?? 0,
      lastUpdated: parsedJson['lastUpdated'] ?? parsedJson['last_updated'],
      // New properties - check both snake_case (from database) and camelCase (for backward compatibility)
      deliveryChargesPerKm: parsedJson['delivery_charges_per_km'] ?? 
          parsedJson['deliveryChargesPerKm'] ?? 0,
      minimumDeliveryCharges: parsedJson['minimum_delivery_charges'] ?? 
          parsedJson['minimumDeliveryCharges'] ?? 0,
      minimumDeliveryChargesWithinKm: parsedJson['minimum_delivery_charges_within_km'] ?? 
          parsedJson['minimumDeliveryChargesWithinKm'] ?? 0,
      amount: parsedJson['amount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseDeliveryCharge': baseDeliveryCharge,
      'deliveryChargePerKm': deliveryChargePerKm,
      'deliveryCommissionPercent': deliveryCommissionPercent,
      'minimumDistanceKm': minimumDistanceKm,
      'lastUpdated': lastUpdated,
      'deliveryChargesPerKm': deliveryChargesPerKm,
      'minimumDeliveryCharges': minimumDeliveryCharges,
      'minimumDeliveryChargesWithinKm': minimumDeliveryChargesWithinKm,
      'amount': amount,
    };
  }
}
