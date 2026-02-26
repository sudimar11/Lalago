import 'package:flutter/material.dart';

import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/time_based_recommendations.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/new_arrival_card.dart';

class TimeBasedSection extends StatelessWidget {
  final List<ProductModel> allProducts;
  final List<String> lstFav;
  final VoidCallback onFavoriteChanged;

  const TimeBasedSection({
    super.key,
    required this.allProducts,
    required this.lstFav,
    required this.onFavoriteChanged,
  });

  static String _mealTitle(String period) {
    switch (period) {
      case 'breakfast':
        return 'Breakfast';
      case 'lunch':
        return 'Lunch';
      case 'dinner':
        return 'Dinner';
      default:
        return 'Late Night';
    }
  }

  @override
  Widget build(BuildContext context) {
    final mealPeriod = TimeBasedRecommendations.getMealPeriod();
    final mealTitle = _mealTitle(mealPeriod);

    return StreamBuilder<List<VendorModel>>(
      stream: TimeBasedRecommendations.getRecommendations(),
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
                  Icon(
                    _mealIcon(mealPeriod),
                    color: Colors.orange[700],
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Perfect for $mealTitle',
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
              height: 260,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                physics: const BouncingScrollPhysics(),
                cacheExtent: 400,
                itemCount: vendors.length >= 10 ? 10 : vendors.length,
                itemBuilder: (context, index) {
                  return NewArrivalCard(
                    vendorModel: vendors[index],
                    allProducts: allProducts,
                    lstFav: lstFav,
                    onFavoriteChanged: onFavoriteChanged,
                    clickSource: 'time_based',
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  IconData _mealIcon(String period) {
    switch (period) {
      case 'breakfast':
        return Icons.free_breakfast;
      case 'lunch':
        return Icons.lunch_dining;
      case 'dinner':
        return Icons.dinner_dining;
      default:
        return Icons.nightlife;
    }
  }
}
