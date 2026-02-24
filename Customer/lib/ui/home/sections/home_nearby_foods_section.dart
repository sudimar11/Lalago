import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/home/view_all_popular_food_near_by_screen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
import 'package:foodie_customer/AppGlobal.dart';

class HomeNearbyFoodsSection extends StatelessWidget {
  final List<ProductModel> lstNearByFood;
  final List<VendorModel> vendors;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;

  const HomeNearbyFoodsSection({
    Key? key,
    required this.lstNearByFood,
    required this.vendors,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (hasError && onRetry != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          HomeSectionUtils.buildTitleRow(
            titleValue: "Nearby Foods",
            onClick: () {},
          ),
          HomeSectionUtils.sectionError(
            message: 'Failed to load nearby foods',
            onRetry: onRetry!,
          ),
        ],
      );
    }
    if (isLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          HomeSectionUtils.buildTitleRow(
            titleValue: "Nearby Foods",
            onClick: () {},
          ),
          SizedBox(
            height: 150,
            child: ShimmerWidgets.productListShimmer(),
          ),
        ],
      );
    }
    final List<ProductModel> displayFoods = lstNearByFood
        .where((product) => _hasPhoto(product.photo))
        .toList();
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "Nearby Foods",
          onClick: () {
            push(
              context,
              const ViewAllPopularFoodNearByScreen(),
            );
          },
        ),
        SizedBox(
          height: 150,
          child: displayFoods.isEmpty
              ? showEmptyState('No popular Item found', context)
              : RepaintBoundary(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    cacheExtent: 300.0,
                    itemCount:
                        displayFoods.length >= 15
                            ? 15
                            : displayFoods.length,
                    itemBuilder: (context, index) {
                      VendorModel? popularNearFoodVendorModel;

                      if (vendors.isNotEmpty) {
                        for (int a = 0; a < vendors.length; a++) {
                          if (vendors[a].id ==
                              displayFoods[index].vendorID) {
                            popularNearFoodVendorModel = vendors[a];
                          }
                        }
                      }

                      return popularNearFoodVendorModel == null
                          ? Container()
                          : popularFoodItem(
                              context,
                              displayFoods[index],
                              popularNearFoodVendorModel,
                            );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget popularFoodItem(
    BuildContext context,
    ProductModel product,
    VendorModel popularNearFoodVendorModel,
  ) {
    final double rating = product.reviewsCount != 0
        ? (product.reviewsSum / product.reviewsCount)
        : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {
        VendorModel? vendorModel =
            await FireStoreUtils.getVendor(product.vendorID);

        if (vendorModel != null) {
          push(
            context,
            ProductDetailsScreen(
              vendorModel: vendorModel,
              productModel: product,
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDarkMode(context)
                ? const Color(DarkContainerBorderColor)
                : Colors.grey.shade100,
            width: 1,
          ),
          color: isDarkMode(context)
              ? const Color(DarkContainerColor)
              : Colors.white,
          boxShadow: [
            isDarkMode(context)
                ? const BoxShadow()
                : BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.5),
                    blurRadius: 5,
                  ),
          ],
        ),
        width: MediaQuery.of(context).size.width * 0.8,
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        padding: const EdgeInsets.all(5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: getImageVAlidUrl(product.photo),
                height: 100,
                width: 100,
                memCacheHeight: 300,
                memCacheWidth: 300,
                maxWidthDiskCache: 600,
                maxHeightDiskCache: 600,
                imageBuilder: (context, imageProvider) => Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    image: DecorationImage(
                      image: imageProvider,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                placeholder: (context, url) => Center(
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                  ),
                ),
                errorWidget: (context, url, error) => ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(
                    AppGlobal.placeHolderImage!,
                    fit: BoxFit.cover,
                  ),
                ),
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontFamily: "Poppinsm",
                      fontSize: 18,
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    product.description,
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: "Poppinsm",
                      fontSize: 16,
                      color: Color(0xff9091A4),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontFamily: "Poppinsm",
                          fontSize: 12,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RestaurantEtaFeeRow(
                          vendorModel: popularNearFoodVendorModel,
                          currencyModel: null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  product.disPrice == "" || product.disPrice == "0"
                      ? Text(
                          amountShow(amount: product.price),
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(COLOR_PRIMARY),
                          ),
                        )
                      : Row(
                          children: [
                            Text(
                              "${amountShow(amount: product.disPrice)}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(COLOR_PRIMARY),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${amountShow(amount: product.price)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasPhoto(String photo) {
    final String trimmed = photo.trim();
    return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
  }
}
