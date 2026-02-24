import 'package:flutter/material.dart';

import '../../../../constants.dart';
import '../../../../main.dart';
import '../../../../model/CurrencyModel.dart';
import '../../../../model/VendorModel.dart';
import '../../../../services/helper.dart';
import '../../../../utils/restaurant_eta_delivery_helper.dart';

/// Compact inline widget displaying distance, ETA and delivery fee.
/// Format: "2.3 km • 25-35 min • ₱40" or "850 m • 15-20 min • Free".
/// Uses vendor.distanceInKM when set, else computes from coordinates.
class RestaurantEtaFeeRow extends StatelessWidget {
  final VendorModel vendorModel;
  final CurrencyModel? currencyModel;

  const RestaurantEtaFeeRow({
    Key? key,
    required this.vendorModel,
    this.currencyModel,
  }) : super(key: key);

  static String _formatDistance(double distanceKm) {
    if (distanceKm < 1 && distanceKm > 0) {
      return '${(distanceKm * 1000).round()} m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final userLocation = MyAppState.selectedPosotion.location;
    if (userLocation == null ||
        (userLocation.latitude == 0 && userLocation.longitude == 0)) {
      return const SizedBox.shrink();
    }

    final distanceKm = vendorModel.distanceInKM ??
        RestaurantEtaDeliveryHelper.calculateDistanceKm(
          vendorModel.latitude,
          vendorModel.longitude,
          userLocation.latitude,
          userLocation.longitude,
        );

    if (distanceKm == null || distanceKm <= 0) {
      return const SizedBox.shrink();
    }

    final eta = RestaurantEtaDeliveryHelper.calculateETA(distanceKm);
    if (eta == null) {
      return const SizedBox.shrink();
    }

    final distanceStr = _formatDistance(distanceKm);
    String line = '$distanceStr • $eta';

    if (currencyModel != null) {
      final fee = RestaurantEtaDeliveryHelper.calculateDeliveryFee(
        distanceKm,
        vendorModel.deliveryCharge,
      );
      final feeStr = (fee != null && fee > 0)
          ? amountShow(amount: fee.round().toString())
          : 'Free';
      line = '$distanceStr • $eta • $feeStr';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line,
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
