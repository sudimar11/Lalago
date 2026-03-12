import 'package:flutter/material.dart';

import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/trending_service.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/new_arrival_card.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class TrendingNowSection extends StatelessWidget {
  final List<ProductModel> allProducts;
  final List<String> lstFav;
  final VoidCallback onFavoriteChanged;

  const TrendingNowSection({
    super.key,
    required this.allProducts,
    required this.lstFav,
    required this.onFavoriteChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VendorModel>>(
      stream: TrendingService.getTrendingRestaurants(),
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
                  Icon(Icons.trending_up, color: Colors.orange[700], size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Trending Now',
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
                    clickSource: 'trending_now',
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
