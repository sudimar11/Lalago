import 'dart:developer' as developer;
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/CurrencyModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/restaurant_filter_card.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/widget/lazy_loading_widget.dart';
import 'package:foodie_customer/widgets/native_ad_restaurant_card.dart';
import 'package:foodie_customer/widgets/performance_badge.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/FavouriteModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/click_tracking_service.dart';

class AllRestaurantsSection extends StatefulWidget {
  final List<OfferModel> offerList;
  final List<ProductModel> allProducts;
  final CurrencyModel? currencyModel;
  final String orderType;
  final int pageSize;
  final List<String> lstFav;
  final ScrollController? scrollController;
  final VoidCallback? onFavoriteChanged;
  final bool Function(VendorModel)? isRestaurantOpen;

  const AllRestaurantsSection({
    super.key,
    required this.offerList,
    required this.allProducts,
    this.currencyModel,
    this.orderType = 'delivery',
    this.pageSize = 10,
    required this.lstFav,
    this.scrollController,
    this.onFavoriteChanged,
    this.isRestaurantOpen,
  });

  @override
  State<AllRestaurantsSection> createState() => _AllRestaurantsSectionState();
}

class _AllRestaurantsSectionState extends State<AllRestaurantsSection> {
  SortOption _sortBy = SortOption.none;
  bool _filterRating4Plus = false;
  bool _filterHalal = false;

  // Key to force rebuild of LazyLoadingRestaurantList when filters change
  Key _listKey = UniqueKey();

  // Cache for sorted restaurants to avoid re-sorting on every rebuild
  List<VendorModel>? _cachedSortedRestaurants;
  List<VendorModel>? _lastRestaurantsList;
  bool _isSorting = false;
  String? _lastSortOption;
  bool _lastFilterRating4Plus = false;
  bool _lastFilterHalal = false;

  void _resetFilters() {
    setState(() {
      _sortBy = SortOption.none;
      _filterRating4Plus = false;
      _filterHalal = false;
      _listKey = UniqueKey(); // Force rebuild
      _cachedSortedRestaurants = null; // Clear cache
      _lastRestaurantsList = null;
      _lastSortOption = null;
      _lastFilterRating4Plus = false;
      _lastFilterHalal = false;
    });
  }

  String? get _sortByString {
    switch (_sortBy) {
      case SortOption.distance:
        return 'distance';
      case SortOption.rating:
        return 'rating';
      case SortOption.open:
        return 'open';
      case SortOption.closed:
        return 'closed';
      case SortOption.none:
        return null;
    }
  }

  // Sort restaurants and cache the result to prevent scroll position jumps
  Future<void> _sortAndCacheRestaurants(List<VendorModel> restaurants) async {
    // Check if we need to re-sort
    final needsResort = 
        _cachedSortedRestaurants == null ||
        _lastRestaurantsList == null ||
        _lastRestaurantsList!.length != restaurants.length ||
        _lastSortOption != _sortByString ||
        _lastFilterRating4Plus != _filterRating4Plus ||
        _lastFilterHalal != _filterHalal ||
        !_lastRestaurantsList!.every((r) => restaurants.any((nr) => nr.id == r.id));

    // Skip if already sorting or if no resort needed
    if (_isSorting || !needsResort) {
      return;
    }

    _isSorting = true;
    _lastRestaurantsList = List.from(restaurants);
    _lastSortOption = _sortByString;
    _lastFilterRating4Plus = _filterRating4Plus;
    _lastFilterHalal = _filterHalal;

    try {
      // Convert to serializable format
      final List<Map<String, dynamic>> restaurantMaps = 
          restaurants.map((r) => r.toJson()).toList();
      
      // Prepare input for isolate
      final Map<String, dynamic> input = {
        'restaurants': restaurantMaps,
        'sortOption': _sortByString,
        'filterRating4Plus': _filterRating4Plus,
        'filterHalal': _filterHalal,
      };
      
      // Process in isolate
      final List<Map<String, dynamic>> processedMaps = 
          await compute(filterAndSortRestaurants, input);
      
      // Convert back to VendorModel objects
      final sortedRestaurants = processedMaps.map((map) => VendorModel.fromJson(map)).toList();
      
      if (mounted) {
        setState(() {
          _cachedSortedRestaurants = sortedRestaurants;
          _isSorting = false;
        });
      }
    } catch (e) {
      // Fallback to synchronous processing on error
      if (mounted) {
        setState(() {
          _cachedSortedRestaurants = _sortRestaurantsSync(restaurants);
          _isSorting = false;
        });
      }
    }
  }

  // Fallback synchronous sorting method
  List<VendorModel> _sortRestaurantsSync(List<VendorModel> restaurants) {
    // Separate open and closed restaurants
    List<VendorModel> openRestaurants = [];
    List<VendorModel> closedRestaurants = [];

    for (var restaurant in restaurants) {
      // Use restaurant_processing function for checking open status
      if (checkRestaurantOpen(restaurant.toJson())) {
        openRestaurants.add(restaurant);
      } else {
        closedRestaurants.add(restaurant);
      }
    }

    // Sort each group by existing sort option (if rating or distance is selected)
    if (_sortBy == SortOption.rating) {
      openRestaurants.sort((a, b) {
        final double ratingA =
            a.reviewsCount != 0 ? (a.reviewsSum / a.reviewsCount) : 0;
        final double ratingB =
            b.reviewsCount != 0 ? (b.reviewsSum / b.reviewsCount) : 0;
        return ratingB.compareTo(ratingA); // Descending
      });
      closedRestaurants.sort((a, b) {
        final double ratingA =
            a.reviewsCount != 0 ? (a.reviewsSum / a.reviewsCount) : 0;
        final double ratingB =
            b.reviewsCount != 0 ? (b.reviewsSum / b.reviewsCount) : 0;
        return ratingB.compareTo(ratingA); // Descending
      });
    } else if (_sortBy == SortOption.distance) {
      // Note: Distance sorting would require location data, keeping original order for now
      // If distance data is available, it should be sorted here
    }

    // Apply filter by rating 4+
    if (_filterRating4Plus) {
      openRestaurants = openRestaurants.where((r) {
        final double rating = r.reviewsCount != 0
            ? (r.reviewsSum / r.reviewsCount)
            : 0.0;
        return rating >= 4.0;
      }).toList();
      closedRestaurants = closedRestaurants.where((r) {
        final double rating = r.reviewsCount != 0
            ? (r.reviewsSum / r.reviewsCount)
            : 0.0;
        return rating >= 4.0;
      }).toList();
    }

    // Apply filter by halal
    if (_filterHalal) {
      openRestaurants = openRestaurants.where((r) {
        final filters = r.filters;
        return filters.containsKey('Halal') && filters['Halal'] == 'Yes';
      }).toList();
      closedRestaurants = closedRestaurants.where((r) {
        final filters = r.filters;
        return filters.containsKey('Halal') && filters['Halal'] == 'Yes';
      }).toList();
    }

    // Apply sort based on selected option
    if (_sortBy == SortOption.open) {
      // Open restaurants first, then closed
      return [...openRestaurants, ...closedRestaurants];
    } else if (_sortBy == SortOption.closed) {
      // Closed restaurants first, then open
      return [...closedRestaurants, ...openRestaurants];
    } else {
      // Default: open first, then closed (for distance, rating, or none)
      return [...openRestaurants, ...closedRestaurants];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter Card
        RestaurantFilterCard(
          sortBy: _sortBy,
          filterRating4Plus: _filterRating4Plus,
          filterHalal: _filterHalal,
          onSortChanged: (sortOption) {
            setState(() {
              _sortBy = sortOption;
              _listKey = UniqueKey(); // Force rebuild
              _cachedSortedRestaurants = null; // Clear cache when filter changes
              _lastRestaurantsList = null;
              _lastSortOption = null;
            });
          },
          onRating4PlusChanged: (value) {
            setState(() {
              _filterRating4Plus = value;
              _listKey = UniqueKey(); // Force rebuild
              _cachedSortedRestaurants = null; // Clear cache when filter changes
              _lastRestaurantsList = null;
              _lastFilterRating4Plus = false;
            });
          },
          onHalalChanged: (value) {
            setState(() {
              _filterHalal = value;
              _listKey = UniqueKey(); // Force rebuild
              _cachedSortedRestaurants = null; // Clear cache when filter changes
              _lastRestaurantsList = null;
              _lastFilterHalal = false;
            });
          },
          onReset: _resetFilters,
        ),

        HomeSectionUtils.buildTitleRow(
          titleValue: "All Restaurants",
          onClick: () {},
          isViewAll: true,
        ),

        LazyLoadingRestaurantList(
          key: _listKey,
          orderType: widget.orderType,
          pageSize: widget.pageSize,
          scrollController: widget.scrollController,
          builder: (restaurants, isLoading, hasMore) {
            if (restaurants.isEmpty && !isLoading) {
              return showEmptyState('No Vendors', context);
            }

            // Sort restaurants asynchronously and cache result
            // This won't cause scroll position jumps because we use cached results
            _sortAndCacheRestaurants(restaurants);

            // Show cached sorted restaurants if available, otherwise show original list
            // This prevents the FutureBuilder from resetting scroll position
            final sortedRestaurants = _cachedSortedRestaurants ?? restaurants;

            // Local sort: open restaurants first, closed last
            final openCheck =
                widget.isRestaurantOpen ?? _AllRestaurantCard.isRestaurantOpen;
            // Temporary debug: confirm open/closed detection during sort
            for (final vendor in sortedRestaurants) {
              final isOpen = openCheck(vendor);
              final reststatus = vendor.reststatus;
              final workingHoursEmpty = vendor.workingHours.isEmpty;
              developer.log(
                'name=${vendor.title} '
                'isRestaurantOpen=$isOpen reststatus=$reststatus '
                'workingHours=${workingHoursEmpty ? "empty" : "not empty"}',
                name: 'AllRestaurantsSection.sort',
              );
            }
            // Only apply local open-first order when user did not choose
            // Sort: Open or Sort: Closed (cache already has correct order then)
            final List<VendorModel> displayList;
            if (_sortBy == SortOption.open || _sortBy == SortOption.closed) {
              displayList = List<VendorModel>.from(sortedRestaurants);
            } else {
              displayList = List<VendorModel>.from(sortedRestaurants)
                ..sort((a, b) {
                  final aOpen = openCheck(a);
                  final bOpen = openCheck(b);
                  if (aOpen && !bOpen) return -1;
                  if (!aOpen && bOpen) return 1;
                  return 0;
                });
            }

            return _buildRestaurantList(displayList, isLoading, hasMore);
          },
        ),
      ],
    );
  }

  Widget _buildRestaurantList(
    List<VendorModel> sortedRestaurants,
    bool isLoading,
    bool hasMore,
  ) {
    return Container(
      width: MediaQuery.of(context).size.width,
      margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
      child: Column(
        children: [
          RepaintBoundary(
            child: ListView.builder(
              shrinkWrap: true,
              scrollDirection: Axis.vertical,
              physics: const NeverScrollableScrollPhysics(),
              cacheExtent: 500.0,
              itemCount: sortedRestaurants.length +
                  (sortedRestaurants.length / 5).floor(),
              itemBuilder: (context, index) {
                if ((index + 1) % 6 == 0) {
                  return const NativeAdRestaurantCard();
                }
                final restaurantIndex = index - (index + 1) ~/ 6;
                if (restaurantIndex >= sortedRestaurants.length) {
                  return const SizedBox.shrink();
                }
                final vendorModel = sortedRestaurants[restaurantIndex];
                return _AllRestaurantCard(
                  vendorModel: vendorModel,
                  offerList: widget.offerList,
                  allProducts: widget.allProducts,
                  currencyModel: widget.currencyModel,
                  lstFav: widget.lstFav,
                  onFavoriteChanged: widget.onFavoriteChanged,
                );
              },
            ),
          ),
          // Loading indicator at the bottom
          if (isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Shimmer loading for restaurant cards
                  ...List.generate(
                    3,
                    (index) => ShimmerWidgets.baseShimmer(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Container(
                            height: 120,
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Restaurant image placeholder
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Restaurant details placeholder
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        height: 16,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 14,
                                        width: 120,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 12,
                                        width: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[300],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loading more restaurants...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          // End of list indicator
          if (!hasMore && sortedRestaurants.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No more restaurants to load',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AllRestaurantCard extends StatefulWidget {
  final VendorModel vendorModel;
  final List<OfferModel> offerList;
  final List<ProductModel> allProducts;
  final CurrencyModel? currencyModel;
  final List<String> lstFav;
  final VoidCallback? onFavoriteChanged;

  const _AllRestaurantCard({
    required this.vendorModel,
    required this.offerList,
    required this.allProducts,
    this.currencyModel,
    required this.lstFav,
    this.onFavoriteChanged,
  });

  /// Static open-check used for sorting; same logic as instance [_isRestaurantOpen].
  static bool isRestaurantOpen(VendorModel vendorModel) {
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

            if (_isCurrentDateInRangeStatic(start, end)) {
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

  static bool _isCurrentDateInRangeStatic(
      DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    if (currentDate.isAfter(startDate) && currentDate.isBefore(endDate)) {
      return true;
    }
    return false;
  }

  @override
  State<_AllRestaurantCard> createState() => _AllRestaurantCardState();
}

class _AllRestaurantCardState extends State<_AllRestaurantCard> {
  final fireStoreUtils = FireStoreUtils();

  @override
  Widget build(BuildContext context) {
    bool restaurantIsOpen = _isRestaurantOpen(widget.vendorModel);

    List<OfferModel> tempList = [];
    List<double> discountAmountTempList = [];

    widget.offerList.forEach((element) {
      if (element.restaurantId != null &&
          widget.vendorModel.id == element.restaurantId &&
          element.expireOfferDate != null &&
          element.expireOfferDate!.toDate().isAfter(DateTime.now())) {
        tempList.add(element);
        if (element.discount != null) {
          discountAmountTempList.add(double.parse(element.discount.toString()));
        }
      }
    });

    // Choose a random product image from this vendor
    List<ProductModel> vendorProducts = widget.allProducts
        .where((p) => p.vendorID == widget.vendorModel.id)
        .toList();
    List<ProductModel> validVendorProducts = vendorProducts.where((p) {
      final String photo = p.photo.trim();
      if (photo.isEmpty) return false;
      if (AppGlobal.placeHolderImage != null &&
          photo == AppGlobal.placeHolderImage) return false;
      return true;
    }).toList();

    String cardImage = widget.vendorModel.photo;
    if (validVendorProducts.isNotEmpty) {
      final seededRandom = Random(widget.vendorModel.id.hashCode);
      final ProductModel randomProduct =
          validVendorProducts[seededRandom.nextInt(validVendorProducts.length)];
      cardImage = randomProduct.photo;
    }

    String? bestImageUrl;
    if (_isValidImageUrl(cardImage)) {
      bestImageUrl = cardImage.trim();
    } else if (_isValidImageUrl(widget.vendorModel.photo)) {
      bestImageUrl = widget.vendorModel.photo.trim();
    } else {
      for (final p in validVendorProducts) {
        if (_isValidImageUrl(p.photo)) {
          bestImageUrl = p.photo.trim();
          break;
        }
      }
    }

    final cardWidth = MediaQuery.of(context).size.width;
    const cardHeight = 180.0;
    final neutralBackground = Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
    );

    bool isFavorited = widget.lstFav.contains(widget.vendorModel.id);
    bool hasOfferBadge = discountAmountTempList.isNotEmpty;

    return GestureDetector(
      onTap: () {
        ClickTrackingService.logClick(
          userId: MyAppState.currentUser?.userID ?? 'guest',
          restaurantId: widget.vendorModel.id,
          source: 'all_restaurants',
        );
        push(context, NewVendorProductsScreen(vendorModel: widget.vendorModel));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: bestImageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: getImageVAlidUrl(bestImageUrl!),
                              width: cardWidth,
                              height: cardHeight,
                              memCacheWidth: 280,
                              memCacheHeight: 280,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => neutralBackground,
                              errorWidget: (context, url, error) =>
                                  neutralBackground,
                            )
                          : neutralBackground,
                    ),
                    // Favorite icon - positioned at top-right
                    Positioned(
                      top: 10,
                      right: 10,
                      child: GestureDetector(
                        onTap: () async {
                          if (MyAppState.currentUser == null) {
                            // Show login prompt if not logged in
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Please login to add favorites'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }

                          setState(() {
                            if (widget.lstFav.contains(widget.vendorModel.id)) {
                              // Remove from favorites
                              widget.lstFav.removeWhere(
                                  (item) => item == widget.vendorModel.id);
                              FavouriteModel favouriteModel = FavouriteModel(
                                restaurantId: widget.vendorModel.id,
                                userId: MyAppState.currentUser!.userID,
                              );
                              fireStoreUtils
                                  .removeFavouriteRestaurant(favouriteModel);
                            } else {
                              // Add to favorites
                              widget.lstFav.add(widget.vendorModel.id);
                              FavouriteModel favouriteModel = FavouriteModel(
                                restaurantId: widget.vendorModel.id,
                                userId: MyAppState.currentUser!.userID,
                              );
                              fireStoreUtils
                                  .setFavouriteRestaurant(favouriteModel);
                            }
                          });

                          // Notify parent widget of favorite change
                          widget.onFavoriteChanged?.call();
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
                            isFavorited
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 20,
                            color:
                                isFavorited ? Colors.red : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                    // Offer badge - positioned at top-left
                    if (hasOfferBadge)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          decoration: const BoxDecoration(
                            image: DecorationImage(
                              image:
                                  AssetImage('assets/images/offer_badge.png'),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              discountAmountTempList
                                      .reduce(min)
                                      .toStringAsFixed(
                                          widget.currencyModel?.decimal ?? 1) +
                                  "% OFF",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.vendorModel.reviewsCount != 0
                                    ? (widget.vendorModel.reviewsSum /
                                            widget.vendorModel.reviewsCount)
                                        .toStringAsFixed(1)
                                    : 0.toString(),
                                style: const TextStyle(
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5,
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Icon(
                                Icons.star,
                                size: 16,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              widget.vendorModel.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                letterSpacing: 0.5,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color:
                                    isDarkMode(context)
                                        ? Colors.white
                                        : Colors.black,
                              ),
                            ),
                          ),
                          PerformanceBadge(
                            vendorModel: widget.vendorModel,
                            compact: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ImageIcon(
                            const AssetImage('assets/images/location3x.png'),
                            size: 15,
                            color: Color(COLOR_PRIMARY),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              widget.vendorModel.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                letterSpacing: 0.5,
                                color: isDarkMode(context)
                                    ? Colors.white70
                                    : const Color(0xff555353),
                              ),
                            ),
                          ),
                        ],
                      ),
                      RestaurantEtaFeeRow(
                        vendorModel: widget.vendorModel,
                        currencyModel: widget.currencyModel,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 20,
                              color: Color(COLOR_PRIMARY),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              widget.vendorModel.reviewsCount != 0
                                  ? (widget.vendorModel.reviewsSum /
                                          widget.vendorModel.reviewsCount)
                                      .toStringAsFixed(1)
                                  : 0.toString(),
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                letterSpacing: 0.5,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode(context)
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              "(${widget.vendorModel.reviewsCount})",
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                letterSpacing: 0.5,
                                fontSize: 12,
                                color: isDarkMode(context)
                                    ? Colors.white70
                                    : const Color(0xff555353),
                              ),
                            ),
                            const Spacer(),
                            if (!restaurantIsOpen)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Closed',
                                  style: const TextStyle(
                                    fontFamily: "Poppinsm",
                                    letterSpacing: 0.5,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Overlay for closed restaurants
            if (!restaurantIsOpen)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
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
                        if (getNextOpeningTimeText(widget.vendorModel) != null)
                          ...[
                            const SizedBox(height: 4),
                            Text(
                              getNextOpeningTimeText(widget.vendorModel)!,
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
    );
  }

  bool _isValidImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final trimmed = url.trim();
    if (AppGlobal.placeHolderImage != null &&
        trimmed == AppGlobal.placeHolderImage!.trim()) {
      return false;
    }
    return Uri.tryParse(trimmed) != null;
  }

  // Helper function to check if restaurant is open
  bool _isRestaurantOpen(VendorModel vendorModel) =>
      _AllRestaurantCard.isRestaurantOpen(vendorModel);

  bool _isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    if (currentDate.isAfter(startDate) && currentDate.isBefore(endDate)) {
      return true;
    }
    return false;
  }
}
