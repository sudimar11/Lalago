import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/discovery_service.dart';
import 'package:foodie_customer/ui/home/sections/restaurant_card.dart';

class PersonalizedRecommendationsSection extends StatefulWidget {
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
  State<PersonalizedRecommendationsSection> createState() =>
      _PersonalizedRecommendationsSectionState();
}

class _PersonalizedRecommendationsSectionState
    extends State<PersonalizedRecommendationsSection> {
  final Set<String> _dismissedIds = {};

  void _sendFeedback(VendorModel v, String feedback) {
    final userId = MyAppState.currentUser?.userID;
    if (userId == null || userId.isEmpty) return;
    try {
      FirebaseFirestore.instance.collection(RECOMMENDATION_FEEDBACK).add({
        'userId': userId,
        'vendorId': v.id,
        'productId': null,
        'feedback': feedback,
        'source': 'personalized_section',
        'recommendationReason': DiscoveryService.getRecommendationReason(
          v,
          userId,
        ),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    if (feedback == 'dismiss' && mounted) {
      setState(() => _dismissedIds.add(v.id));
    }
  }

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

        final vendors = (snapshot.data!)
            .where((v) => !_dismissedIds.contains(v.id))
            .toList();
        if (vendors.isEmpty) return const SizedBox.shrink();

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
                      offerList: widget.offerList,
                      allProducts: widget.allProducts,
                      currencyModel: widget.currencyModel,
                      source: 'personalized',
                      position: index,
                      recommendationReason: reason,
                      showFeedbackButtons: true,
                      onFeedback: (feedback) => _sendFeedback(v, feedback),
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
