import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/FavouriteModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/click_tracking_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/widgets/performance_badge.dart';
import 'package:foodie_customer/ui/home/view_all_popular_restaurant_screen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class TopRestaurantsSection extends StatelessWidget {
  final List<VendorModel> popularRestaurantLst;
  final List<ProductModel> allProducts;
  final List<String> lstFav;
  final VoidCallback onFavoriteChanged;
  final List<VendorModel> fallbackRestaurants;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;
  final FireStoreUtils fireStoreUtils = FireStoreUtils();

  TopRestaurantsSection({
    super.key,
    required this.popularRestaurantLst,
    required this.allProducts,
    required this.lstFav,
    required this.onFavoriteChanged,
    required this.fallbackRestaurants,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "Top Restaurants",
          onClick: () {
            push(
              context,
              const ViewAllPopularRestaurantScreen(),
            );
          },
        ),
        hasError && onRetry != null
            ? HomeSectionUtils.sectionError(
                message: 'Failed to load top restaurants',
                onRetry: onRetry!,
              )
            : isLoading
                ? Container(
                    width: MediaQuery.of(context).size.width,
                    height: 260,
                    margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                    child: ShimmerWidgets.restaurantListShimmer(),
                  )
                : popularRestaurantLst.isEmpty
            ? (fallbackRestaurants.isEmpty
                ? showEmptyState('No Popular restaurant', context)
                : _buildRestaurantList(
                    context,
                    fallbackRestaurants,
                  ))
            : Builder(
                builder: (context) {
                  final uniqueRestaurants =
                      popularRestaurantLst.toSet().toList();
                  final count = uniqueRestaurants.length >= 5
                      ? 5
                      : uniqueRestaurants.length;
                  return Container(
                    width: MediaQuery.of(context).size.width,
                    height: 260,
                    margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                    child: RepaintBoundary(
                      child: ListView.builder(
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        cacheExtent: 400.0,
                        itemCount: count,
                        itemBuilder: (context, index) =>
                            _buildRestaurantCard(uniqueRestaurants[index]),
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }

  Widget _buildRestaurantList(
    BuildContext context,
    List<VendorModel> restaurants,
  ) {
    final List<VendorModel> uniqueRestaurants = restaurants.toSet().toList();
    return Container(
      width: MediaQuery.of(context).size.width,
      height: 260,
      margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
      child: RepaintBoundary(
        child: ListView.builder(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          cacheExtent: 400.0,
          itemCount: uniqueRestaurants.length >= 5
              ? 5
              : uniqueRestaurants.length,
          itemBuilder: (context, index) =>
              _buildRestaurantCard(uniqueRestaurants[index]),
        ),
      ),
    );
  }

  Widget _buildRestaurantCard(VendorModel vendorModel) {
    // Get random product image from this vendor
    List<ProductModel> vendorProducts =
        allProducts.where((p) => p.vendorID == vendorModel.id).toList();
    List<ProductModel> validVendorProducts = vendorProducts.where((p) {
      final String photo = p.photo.trim();
      if (photo.isEmpty) return false;
      if (AppGlobal.placeHolderImage != null &&
          photo == AppGlobal.placeHolderImage) {
        return false;
      }
      return true;
    }).toList();

    String cardImage = vendorModel.photo;
    if (validVendorProducts.isNotEmpty) {
      final seededRandom = Random(vendorModel.id.hashCode);
      final ProductModel randomProduct =
          validVendorProducts[seededRandom.nextInt(validVendorProducts.length)];
      cardImage = randomProduct.photo;
    }

    return _TopRestaurantCard(
      vendorModel: vendorModel,
      cardImage: cardImage,
      lstFav: lstFav,
      onFavoriteChanged: onFavoriteChanged,
      fireStoreUtils: fireStoreUtils,
    );
  }
}

class _TopRestaurantCard extends StatelessWidget {
  final VendorModel vendorModel;
  final String cardImage;
  final List<String> lstFav;
  final VoidCallback onFavoriteChanged;
  final FireStoreUtils fireStoreUtils;

  const _TopRestaurantCard({
    required this.vendorModel,
    required this.cardImage,
    required this.lstFav,
    required this.onFavoriteChanged,
    required this.fireStoreUtils,
  });

  @override
  Widget build(BuildContext context) {
    final bool restaurantIsOpen =
        isRestaurantOpenFromModel(vendorModel);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: GestureDetector(
        onTap: () {
          ClickTrackingService.logClick(
            userId: MyAppState.currentUser?.userID ?? 'guest',
            restaurantId: vendorModel.id,
            source: 'top_restaurants',
          );
          push(context, NewVendorProductsScreen(vendorModel: vendorModel));
        },
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.75,
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Image Container
                  Expanded(
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: getImageVAlidUrl(cardImage),
                            width: double.infinity,
                            height: double.infinity,
                            memCacheWidth: 280,
                            memCacheHeight: 280,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(COLOR_PRIMARY).withOpacity(0.1),
                                    Color(COLOR_PRIMARY).withOpacity(0.05),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: CircularProgressIndicator.adaptive(
                                  valueColor: AlwaysStoppedAnimation(
                                    Color(COLOR_PRIMARY),
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                                color: Colors.grey.shade200,
                              ),
                              child: Icon(
                                Icons.restaurant,
                                size: 50,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                        // Gradient overlay
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(24),
                                topRight: Radius.circular(24),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.3),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Overlay for closed restaurants
                        if (!restaurantIsOpen)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.black.withOpacity(0.6),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Temporarily Closed',
                                      style: TextStyle(
                                        fontFamily: 'Poppinsm',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    if (getNextOpeningTimeText(
                                            vendorModel) !=
                                        null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        getNextOpeningTimeText(vendorModel)!,
                                        style: const TextStyle(
                                          fontFamily: 'Poppinsm',
                                          fontSize: 12,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // Favorite button
                        Positioned(
                          top: 12,
                          right: 12,
                          child: _FavoriteButton(
                            vendorModel: vendorModel,
                            lstFav: lstFav,
                            onFavoriteChanged: onFavoriteChanged,
                            fireStoreUtils: fireStoreUtils,
                          ),
                        ),
                        // "TOP" badge
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.amber,
                                  Colors.amber.shade700,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Text(
                              'TOP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Content section
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Restaurant name, badge, and rating
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                vendorModel.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            PerformanceBadge(
                              vendorModel: vendorModel,
                              compact: true,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Color(COLOR_PRIMARY).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    size: 12,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    vendorModel.reviewsCount != 0
                                        ? '${(vendorModel.reviewsSum / vendorModel.reviewsCount).toStringAsFixed(1)}'
                                        : '0.0',
                                    style: TextStyle(
                                      fontFamily: "Poppinsm",
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(COLOR_PRIMARY),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Order count
                        _OrderCountWidget(
                          vendorModel: vendorModel,
                          fireStoreUtils: fireStoreUtils,
                        ),
                        const SizedBox(height: 4),
                        // Distance
                        _DistanceWidget(vendorModel: vendorModel),
                        const SizedBox(height: 4),
                        // ETA and Delivery Fee
                        RestaurantEtaFeeRow(
                          vendorModel: vendorModel,
                          currencyModel: null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final VendorModel vendorModel;
  final List<String> lstFav;
  final VoidCallback onFavoriteChanged;
  final FireStoreUtils fireStoreUtils;

  const _FavoriteButton({
    required this.vendorModel,
    required this.lstFav,
    required this.onFavoriteChanged,
    required this.fireStoreUtils,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (MyAppState.currentUser == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please login to add favorites'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }

        if (lstFav.contains(vendorModel.id)) {
          lstFav.removeWhere((item) => item == vendorModel.id);
          FavouriteModel favouriteModel = FavouriteModel(
            restaurantId: vendorModel.id,
            userId: MyAppState.currentUser!.userID,
          );
          fireStoreUtils.removeFavouriteRestaurant(favouriteModel);
        } else {
          lstFav.add(vendorModel.id);
          FavouriteModel favouriteModel = FavouriteModel(
            restaurantId: vendorModel.id,
            userId: MyAppState.currentUser!.userID,
          );
          fireStoreUtils.setFavouriteRestaurant(favouriteModel);
        }
        onFavoriteChanged();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          lstFav.contains(vendorModel.id)
              ? Icons.favorite
              : Icons.favorite_border,
          size: 20,
          color: lstFav.contains(vendorModel.id)
              ? Colors.red
              : Colors.grey.shade700,
        ),
      ),
    );
  }
}

class _OrderCountWidget extends StatelessWidget {
  final VendorModel vendorModel;
  final FireStoreUtils fireStoreUtils;

  const _OrderCountWidget({
    required this.vendorModel,
    required this.fireStoreUtils,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      key: ValueKey('order_count_${vendorModel.id}'),
      future: fireStoreUtils.getVendorOrderCount(vendorModel.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 16,
            width: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(6),
            ),
          );
        }

        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        int orderCount = snapshot.data ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isDarkMode(context)
                ? Colors.white.withOpacity(0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$orderCount orders',
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color:
                  isDarkMode(context) ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
        );
      },
    );
  }
}

class _DistanceWidget extends StatelessWidget {
  final VendorModel vendorModel;

  const _DistanceWidget({required this.vendorModel});

  @override
  Widget build(BuildContext context) {
    double distanceInMeters = Geolocator.distanceBetween(
      vendorModel.latitude,
      vendorModel.longitude,
      MyAppState.selectedPosition.location!.latitude,
      MyAppState.selectedPosition.location!.longitude,
    );
    double kilometer = distanceInMeters / 1000;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Color(COLOR_PRIMARY).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_walk,
            size: 12,
            color: Color(COLOR_PRIMARY),
          ),
          const SizedBox(width: 2),
          Text(
            'Nearby',
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(COLOR_PRIMARY),
            ),
          ),
          const Spacer(),
          Text(
            '${kilometer.toStringAsFixed(1)} km',
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color:
                  isDarkMode(context) ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
