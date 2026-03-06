import 'package:flutter/material.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/home/sections/home_header_section.dart';
import 'package:foodie_customer/ui/home/sections/home_categories_section.dart';
import 'package:foodie_customer/ui/home/sections/home_nearby_foods_section.dart';
import 'package:foodie_customer/ui/home/sections/home_popular_today_section.dart';
import 'package:foodie_customer/ui/home/sections/home_order_again_section.dart';
import 'package:foodie_customer/ui/home/sections/home_all_restaurants_section.dart';
import 'package:foodie_customer/ui/home/sections/home_pautos_entry_section.dart';

class HomeSections extends StatelessWidget {
  final String? selctedOrderTypeValue;
  final Function(String?) onOrderTypeChanged;
  final Function() onLocationChange;
  final Function() onSearchTap;
  final VoidCallback? onMessageTap;
  final VoidCallback? onFavoriteTap;
  final List<String> rotatingHints;
  final List<ProductModel> lstNearByFood;
  final List<VendorModel> vendors;
  final List<ProductModel> popularTodayFoods;
  final List<VendorModel> popularTodayVendors;
  final List<ProductModel> orderAgainProducts;
  final bool isLoadingOrderAgain;

  const HomeSections({
    Key? key,
    required this.selctedOrderTypeValue,
    required this.onOrderTypeChanged,
    required this.onLocationChange,
    required this.onSearchTap,
    this.onMessageTap,
    this.onFavoriteTap,
    this.rotatingHints = const [],
    required this.lstNearByFood,
    required this.vendors,
    required this.popularTodayFoods,
    required this.popularTodayVendors,
    required this.orderAgainProducts,
    required this.isLoadingOrderAgain,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Container(
        color: isDarkMode(context)
            ? const Color.fromARGB(255, 212, 197, 128)
            : const Color(0xffFFFFFF),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            HomeHeaderSection(
              selctedOrderTypeValue: selctedOrderTypeValue,
              onOrderTypeChanged: onOrderTypeChanged,
              onLocationTap: onLocationChange,
              onSearchTap: onSearchTap,
              onMessageTap: onMessageTap ?? () {},
              onFavoriteTap: onFavoriteTap ?? () {},
              rotatingHints: rotatingHints.isEmpty
                  ? const ['Search food or restaurants']
                  : rotatingHints,
            ),

            // PAUTOS Entry Section
            const HomePautosEntrySection(),

            // Divider above Categories section
            Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: Divider(
                color: isDarkMode(context)
                    ? Colors.white.withOpacity(0.2)
                    : Colors.grey.shade300,
                thickness: 1,
                height: 1,
              ),
            ),

            // Categories Section
            HomeCategoriesSection(),

            // Popular Today Section
            HomePopularTodaySection(
              popularTodayFoods: popularTodayFoods,
              vendors: popularTodayVendors,
            ),

            // Nearby Foods Section
            HomeNearbyFoodsSection(
              lstNearByFood: lstNearByFood,
              vendors: vendors,
            ),

            // Order Again Section
            HomeOrderAgainSection(
              orderAgainProducts: orderAgainProducts,
              isLoadingOrderAgain: isLoadingOrderAgain,
              vendors: vendors,
            ),

            // All Restaurants Section
            HomeAllRestaurantsSection(
              orderType: selctedOrderTypeValue ?? "Delivery",
            ),
          ],
        ),
      ),
    );
  }
}
