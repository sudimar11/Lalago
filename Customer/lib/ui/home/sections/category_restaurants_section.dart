import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/CurrencyModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/click_tracking_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/ui/home/view_all_category_product_screen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class CategoryRestaurantsSection extends StatelessWidget {
  final List<VendorCategoryModel> categoryWiseProductList;
  final List<ProductModel> allProducts;
  final CurrencyModel? currencyModel;
  final bool isLoadingCategories;
  final VoidCallback? onRetry;
  final FireStoreUtils fireStoreUtils = FireStoreUtils();

  CategoryRestaurantsSection({
    super.key,
    required this.categoryWiseProductList,
    required this.allProducts,
    this.currencyModel,
    this.isLoadingCategories = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (categoryWiseProductList.isEmpty && isLoadingCategories) {
      return Column(
        children: [
          SizedBox(
            height: 100,
            child: ShimmerWidgets.categoryListShimmer(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: ShimmerWidgets.restaurantListShimmer(),
          ),
        ],
      );
    }
    debugPrint('🎯 CategoryRestaurantsSection.build(): Creating ListView with itemCount=${categoryWiseProductList.length}');
    return ListView.builder(
      itemCount: categoryWiseProductList.length,
      shrinkWrap: true,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final category = categoryWiseProductList[index];
        return _CategoryRestaurantRow(
          category: category,
          allProducts: allProducts,
          currencyModel: currencyModel,
          fireStoreUtils: fireStoreUtils,
          onRetry: onRetry,
        );
      },
    );
  }
}

class _CategoryRestaurantRow extends StatefulWidget {
  final VendorCategoryModel category;
  final List<ProductModel> allProducts;
  final CurrencyModel? currencyModel;
  final FireStoreUtils fireStoreUtils;
  final VoidCallback? onRetry;

  const _CategoryRestaurantRow({
    required this.category,
    required this.allProducts,
    this.currencyModel,
    required this.fireStoreUtils,
    this.onRetry,
  });

  @override
  State<_CategoryRestaurantRow> createState() => _CategoryRestaurantRowState();
}

class _CategoryRestaurantRowState extends State<_CategoryRestaurantRow> {
  final ScrollController _scrollController = ScrollController();
  List<VendorModel> _vendors = [];
  int _displayedCount = 5;
  StreamSubscription<List<VendorModel>>? _streamSubscription;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _streamSubscription = widget.fireStoreUtils
        .getCategoryRestaurants(widget.category.id.toString())
        .listen(
          (List<VendorModel> data) {
            if (mounted) {
              setState(() {
                _vendors = data;
                _hasError = false;
              });
            }
          },
          onError: (_) {
            if (mounted) {
              setState(() => _hasError = true);
            }
          },
        );
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _displayedCount >= _vendors.length) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      setState(() {
        _displayedCount = (_displayedCount + 5).clamp(0, _vendors.length);
      });
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError && widget.onRetry != null) {
      return HomeSectionUtils.sectionError(
        message: 'Failed to load restaurants for ${widget.category.title}',
        onRetry: widget.onRetry!,
      );
    }
    if (_vendors.isEmpty) {
      return Container();
    }
    final count = _displayedCount.clamp(0, _vendors.length);
    return Column(
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: widget.category.title.toString(),
          onClick: () {
            push(
              context,
              ViewAllCategoryProductScreen(
                vendorCategoryModel: widget.category,
              ),
            );
          },
          isViewAll: false,
        ),
        SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height * 0.29,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: RepaintBoundary(
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                cacheExtent: 400.0,
                itemCount: count,
                itemBuilder: (context, index) {
                  final vendorModel = _vendors[index];
                  return _CategoryRestaurantCard(
                    vendorModel: vendorModel,
                    allProducts: widget.allProducts,
                    currencyModel: widget.currencyModel,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryRestaurantCard extends StatelessWidget {
  final VendorModel vendorModel;
  final List<ProductModel> allProducts;
  final CurrencyModel? currencyModel;

  const _CategoryRestaurantCard({
    required this.vendorModel,
    required this.allProducts,
    this.currencyModel,
  });

  @override
  Widget build(BuildContext context) {
    double distanceInMeters = Geolocator.distanceBetween(
      vendorModel.latitude,
      vendorModel.longitude,
      MyAppState.selectedPosition.location!.latitude,
      MyAppState.selectedPosition.location!.longitude,
    );

    double kilometer = distanceInMeters / 1000;
    double minutes = 1.2;
    double value = minutes * kilometer;
    final int hour = value ~/ 60;
    final double minute = value % 60;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: GestureDetector(
        onTap: () {
          ClickTrackingService.logClick(
            userId: MyAppState.currentUser?.userID ?? 'guest',
            restaurantId: vendorModel.id,
            source: 'category_food',
          );
          push(context, NewVendorProductsScreen(vendorModel: vendorModel));
        },
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.7,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: _getStableRandomProductImage(vendorModel),
                          memCacheWidth: 200,
                          memCacheHeight: 200,
                          imageBuilder: (context, imageProvider) => Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(24),
                                topRight: Radius.circular(24),
                              ),
                              image: DecorationImage(
                                image: imageProvider,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          placeholder: (context, url) => Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
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
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                              ),
                              color: Colors.grey.shade200,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.restaurant,
                                size: 40,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                          fit: BoxFit.cover,
                        ),
                        // Vendor logo badge overlay
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: CachedNetworkImage(
                                imageUrl: getImageVAlidUrl(vendorModel.photo),
                                memCacheWidth: 200,
                                memCacheHeight: 200,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: Icon(
                                    Icons.restaurant,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    const Center(
                                  child: Icon(
                                    Icons.restaurant,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.amber.shade400,
                                  Colors.amber.shade600,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amber.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    vendorModel.reviewsCount != 0
                                        ? (vendorModel.reviewsSum /
                                                vendorModel.reviewsCount)
                                            .toStringAsFixed(1)
                                        : 0.toString(),
                                    style: const TextStyle(
                                      fontFamily: "Poppinsb",
                                      letterSpacing: 0.5,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Overlay for closed restaurants - only on image
                        if (!_isRestaurantOpen(vendorModel))
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                                color: Colors.black.withOpacity(0.6),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Temporarily Closed',
                                      style: TextStyle(
                                        fontFamily: "Poppinsm",
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
                                        getNextOpeningTimeText(
                                            vendorModel)!,
                                        style: TextStyle(
                                          fontFamily: "Poppinsm",
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vendorModel.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: "Poppinsb",
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Color(COLOR_PRIMARY).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.location_on_rounded,
                                  color: Color(COLOR_PRIMARY),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  vendorModel.location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: "Poppinsr",
                                    fontSize: 13,
                                    color: isDarkMode(context)
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          RestaurantEtaFeeRow(
                            vendorModel: vendorModel,
                            currencyModel: currencyModel,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Color(COLOR_PRIMARY).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.access_time_rounded,
                                  color: Color(COLOR_PRIMARY),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${hour.toString().padLeft(2, "0")}h ${minute.toStringAsFixed(0).padLeft(2, "0")}m',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: "Poppinssb",
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode(context)
                                      ? Colors.white70
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Color(COLOR_PRIMARY).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  Icons.directions_car_rounded,
                                  color: Color(COLOR_PRIMARY),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "${kilometer.toDouble().toStringAsFixed(currencyModel?.decimal ?? 1)} km",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: "Poppinssb",
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.white70
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
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

  // Helper function to get stable random product image for vendor
  String _getStableRandomProductImage(VendorModel vendor) {
    // Filter products by vendor ID
    List<ProductModel> vendorProducts =
        allProducts.where((p) => p.vendorID == vendor.id).toList();

    // Filter out products with empty or placeholder images
    List<ProductModel> validVendorProducts = vendorProducts.where((p) {
      final String photo = p.photo.trim();
      if (photo.isEmpty) return false;
      if (AppGlobal.placeHolderImage != null &&
          photo == AppGlobal.placeHolderImage) return false;
      return true;
    }).toList();

    // If no valid products, return vendor photo
    if (validVendorProducts.isEmpty) {
      return vendor.photo;
    }

    // Use vendor ID as seed for consistent random selection
    final seededRandom = Random(vendor.id.hashCode);
    final ProductModel randomProduct =
        validVendorProducts[seededRandom.nextInt(validVendorProducts.length)];

    return randomProduct.photo;
  }

  // Helper function to check if restaurant is open
  bool _isRestaurantOpen(VendorModel vendorModel) {
    final now = DateTime.now();
    var day = DateFormat('EEEE', 'en_US').format(now);
    var date = DateFormat('dd-MM-yyyy').format(now);

    bool isOpen = false;

    for (var workingHour in vendorModel.workingHours) {
      if (day == workingHour.day.toString()) {
        if (workingHour.timeslot != null && workingHour.timeslot!.isNotEmpty) {
          for (var timeSlot in workingHour.timeslot!) {
            var start = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + timeSlot.from.toString());
            var end = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + timeSlot.to.toString());

            if (_isCurrentDateInRange(start, end)) {
              isOpen = true;
              break;
            }
          }
        }
        if (isOpen) break;
      }
    }

    return isOpen && vendorModel.reststatus;
  }

  bool _isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    if (currentDate.isAfter(startDate) && currentDate.isBefore(endDate)) {
      return true;
    }
    return false;
  }
}
