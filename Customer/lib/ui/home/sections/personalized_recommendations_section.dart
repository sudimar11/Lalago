import 'package:flutter/material.dart';

import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/discovery_service.dart';
import 'package:foodie_customer/ui/home/sections/restaurant_card.dart';

class PersonalizedRecommendationsSection extends StatelessWidget {
  final List<ProductModel> allProducts;
  final List<OfferModel> offerList;
  final dynamic currencyModel;

  const PersonalizedRecommendationsSection({
    super.key,
    required this.allProducts,
    required this.offerList,
    required this.currencyModel,
  });

  @override
  Widget build(BuildContext context) {
    final userId = MyAppState.currentUser?.userID;
    if (userId == null || userId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<VendorModel>>(
      future: DiscoveryService.getDiscoveryRecommendations(userId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final vendors = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.recommend, color: Colors.orange[700], size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Recommended for You',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 340,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                physics: const BouncingScrollPhysics(),
                cacheExtent: 400,
                itemCount: vendors.length >= 10 ? 10 : vendors.length,
                itemBuilder: (context, index) {
                  final v = vendors[index];
                  final reason = DiscoveryService.getRecommendationReason(
                    v,
                    userId,
                  );
                  return SizedBox(
                    width: 220,
                    child: RestaurantCard(
                      vendorModel: v,
                      offerList: offerList,
                      allProducts: allProducts,
                      currencyModel: currencyModel,
                      source: 'personalized',
                      position: index,
                      recommendationReason: reason,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
