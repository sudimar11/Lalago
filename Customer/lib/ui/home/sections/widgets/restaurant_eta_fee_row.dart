import 'package:flutter/material.dart';

import '../../../../main.dart';
import '../../../../model/CurrencyModel.dart';
import '../../../../model/VendorModel.dart';
import '../../../../services/helper.dart';
import '../../../../utils/restaurant_eta_delivery_helper.dart';

/// Compact inline widget displaying ETA and delivery fee for a restaurant.
/// Gracefully hides when data is unavailable.
/// Uses the global delivery charge model from Firestore (matching CartScreen).
class RestaurantEtaFeeRow extends StatelessWidget {
  final VendorModel vendorModel;
  final CurrencyModel? currencyModel;

  const RestaurantEtaFeeRow({
    Key? key,
    required this.vendorModel,
    this.currencyModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Check if user location is available
    final userLocation = MyAppState.selectedPosotion.location;
    if (userLocation == null ||
        (userLocation.latitude == 0 && userLocation.longitude == 0)) {
      return const SizedBox.shrink();
    }

    // Calculate distance
    final distanceKm = RestaurantEtaDeliveryHelper.calculateDistanceKm(
      vendorModel.latitude,
      vendorModel.longitude,
      userLocation.latitude,
      userLocation.longitude,
    );

    if (distanceKm == null || distanceKm <= 0) {
      return const SizedBox.shrink();
    }

    // Calculate ETA
    final eta = RestaurantEtaDeliveryHelper.calculateETA(distanceKm);
    if (eta == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '⏱ $eta',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: "Poppinsm",
                letterSpacing: 0.5,
                fontSize: 12,
                color: isDarkMode(context)
                    ? Colors.white70
                    : const Color(0xff555353),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
