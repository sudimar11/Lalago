import 'package:flutter/material.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/new_arrival_card.dart';
import 'package:foodie_customer/ui/home/view_all_new_arrival_restaurant_screen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class NewRestaurantsSection extends StatelessWidget {
  final Stream<List<VendorModel>> vendorsStream;
  final List<VendorModel> fallbackVendors;
  final List<ProductModel> allProducts;
  final List<String> lstFav;
  final bool Function(VendorModel) isRestaurantOpen;
  final VoidCallback onFavoriteChanged;

  const NewRestaurantsSection({
    Key? key,
    required this.vendorsStream,
    required this.fallbackVendors,
    required this.allProducts,
    required this.lstFav,
    required this.isRestaurantOpen,
    required this.onFavoriteChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "New Restaurants",
          titleIcon: Icons.restaurant_rounded,
          onClick: () {
            push(
              context,
              const ViewAllNewArrivalRestaurantScreen(),
            );
          },
        ),
        StreamBuilder<List<VendorModel>>(
          stream: vendorsStream,
          initialData: const [],
          builder: (context, snapshot) {
            final raw = snapshot.data ?? const <VendorModel>[];

            final nearbyOpen = raw
                .where((vendor) => isRestaurantOpen(vendor))
                .toList();
            final fallbackOpen = fallbackVendors
                .where((vendor) => isRestaurantOpen(vendor))
                .toList();

            if (snapshot.connectionState == ConnectionState.waiting &&
                fallbackVendors.isEmpty) {
              return Container(
                width: MediaQuery.of(context).size.width,
                height: 260,
                margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                child: ShimmerWidgets.restaurantListShimmer(),
              );
            }

            if (context.mounted) {
              // Use all from stream (newest-first) so latest added show even if closed
              final displayList = raw.isNotEmpty
                  ? raw
                  : (nearbyOpen.isNotEmpty
                      ? nearbyOpen
                      : (fallbackVendors.isNotEmpty
                          ? fallbackVendors
                          : fallbackOpen));
              return displayList.isEmpty
                  ? showEmptyState('No Vendors', context)
                  : Container(
                      width: MediaQuery.of(context).size.width,
                      height: 260,
                      margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                      child: RepaintBoundary(
                        child: ListView.builder(
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          cacheExtent: 400.0,
                          itemCount: displayList.length >= 15
                              ? 15
                              : displayList.length,
                          itemBuilder: (context, index) => NewArrivalCard(
                            vendorModel: displayList[index],
                            allProducts: allProducts,
                            lstFav: lstFav,
                            onFavoriteChanged: onFavoriteChanged,
                          ),
                        ),
                      ),
                    );
            } else {
              return showEmptyState('No Vendors', context);
            }
          },
        ),
      ],
    );
  }
}
