import 'package:geolocator/geolocator.dart';

import '../model/DeliveryChargeModel.dart';

/// Utility functions for calculating restaurant ETA and delivery fees.
/// All functions are synchronous and return null when data is unavailable.
class RestaurantEtaDeliveryHelper {
  /// Calculates distance in kilometers between two coordinates.
  /// Returns null if coordinates are invalid.
  static double? calculateDistanceKm(
    double vendorLat,
    double vendorLng,
    double userLat,
    double userLng,
  ) {
    if (vendorLat == 0.0 && vendorLng == 0.0) return null;
    if (userLat == 0.0 && userLng == 0.0) return null;

    try {
      final distanceInMeters = Geolocator.distanceBetween(
        vendorLat,
        vendorLng,
        userLat,
        userLng,
      );
      return distanceInMeters / 1000.0;
    } catch (e) {
      return null;
    }
  }

  /// Calculates ETA based on distance using 1.2 minutes per kilometer formula.
  /// Returns formatted string like "25-35 min" or null if distance is invalid.
  static String? calculateETA(double? distanceKm) {
    if (distanceKm == null || distanceKm <= 0) return null;

    // Formula: 1.2 minutes per kilometer
    const double minutesPerKm = 1.2;
    final double totalMinutes = distanceKm * minutesPerKm;

    // Add base preparation time (15-20 minutes)
    const int minPrepTime = 15;
    const int maxPrepTime = 20;

    final int minTotalMinutes = (totalMinutes + minPrepTime).round();
    final int maxTotalMinutes = (totalMinutes + maxPrepTime).round();

    return '$minTotalMinutes-$maxTotalMinutes min';
  }

  /// Calculates delivery fee based on distance and delivery charge model.
  /// Returns null if delivery charge model is unavailable or fee is 0.
  /// Uses the exact same logic as CartScreen delivery charge calculation.
  static double? calculateDeliveryFee(
    double? distanceKm,
    DeliveryChargeModel? deliveryChargeModel,
  ) {
    if (distanceKm == null || distanceKm <= 0) return null;
    if (deliveryChargeModel == null) return null;

    // New_DeliveryCharge formula: < 1km = baseDeliveryCharge,
    // >= 1km = baseDeliveryCharge + distance * deliveryChargePerKm
    final double baseCharge =
        deliveryChargeModel.baseDeliveryCharge.toDouble();
    final double perKm =
        deliveryChargeModel.deliveryChargePerKm.toDouble();
    final double thresholdKm =
        deliveryChargeModel.minimumDistanceKm.toDouble();

    double calculatedDeliveryCharges = 0.0;
    final double effectiveThreshold = thresholdKm > 0 ? thresholdKm : 1;

    if (distanceKm < effectiveThreshold) {
      calculatedDeliveryCharges = baseCharge;
    } else {
      calculatedDeliveryCharges = baseCharge + (distanceKm * perKm);
    }

    if (calculatedDeliveryCharges <= 0 && baseCharge > 0) {
      calculatedDeliveryCharges = baseCharge;
    }

    // Return null if fee is 0 or invalid
    if (calculatedDeliveryCharges <= 0) return null;

    // Round to whole number (no decimal points)
    return calculatedDeliveryCharges.roundToDouble();
  }

  /// Formats delivery fee for display.
  /// Returns "Free delivery" if fee is 0 or null, otherwise "₱XX delivery".
  /// Uses whole numbers only (no decimal points).
  static String formatDeliveryFeeDisplay(
    double? fee,
    String currencySymbol,
    int decimalPlaces,
  ) {
    if (fee == null || fee <= 0) {
      return 'Free delivery';
    }

    // Format as whole number (0 decimal places)
    final String formattedFee = fee.round().toString();
    return '$currencySymbol$formattedFee delivery';
  }
}
