import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';

class NewArrivalCard extends StatefulWidget {
  final VendorModel vendorModel;
  final List<ProductModel> allProducts;
  final List<String> lstFav;
  final VoidCallback? onFavoriteChanged;
  final String? clickSource;

  const NewArrivalCard({
    Key? key,
    required this.vendorModel,
    required this.allProducts,
    required this.lstFav,
    this.onFavoriteChanged,
    this.clickSource,
  }) : super(key: key);

  @override
  State<NewArrivalCard> createState() => _NewArrivalCardState();
}

class _NewArrivalCardState extends State<NewArrivalCard> {
  final fireStoreUtils = FireStoreUtils();

  @override
  Widget build(BuildContext context) {
    bool restaurantIsOpen = isRestaurantOpen(widget.vendorModel);

    // Choose a random product image from this vendor (excluding placeholder/empty), fallback to vendor photo
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: GestureDetector(
        onTap: () {
          ClickTrackingService.logClick(
            userId: MyAppState.currentUser?.userID ?? 'guest',
            restaurantId: widget.vendorModel.id,
            source: widget.clickSource ?? 'new_arrivals',
          );
          push(context, NewVendorProductsScreen(vendorModel: widget.vendorModel));
        },
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.75,
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Image Container with overlay
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
                                      Color(COLOR_PRIMARY)),
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
                        // Gradient overlay for better text readability
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
                        // Favorite button
                        Positioned(
                          top: 12,
                          right: 12,
                          child: GestureDetector(
                            onTap: () async {
                              if (MyAppState.currentUser == null) {
                                // Show login prompt if not logged in
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Please login to add favorites'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }

                              setState(() {
                                if (widget.lstFav
                                    .contains(widget.vendorModel.id)) {
                                  // Remove from favorites
                                  widget.lstFav.removeWhere(
                                      (item) => item == widget.vendorModel.id);
                                  FavouriteModel favouriteModel =
                                      FavouriteModel(
                                    restaurantId: widget.vendorModel.id,
                                    userId: MyAppState.currentUser!.userID,
                                  );
                                  fireStoreUtils.removeFavouriteRestaurant(
                                      favouriteModel);
                                } else {
                                  // Add to favorites
                                  widget.lstFav.add(widget.vendorModel.id);
                                  FavouriteModel favouriteModel =
                                      FavouriteModel(
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
                                widget.lstFav.contains(widget.vendorModel.id)
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 20,
                                color: widget.lstFav
                                        .contains(widget.vendorModel.id)
                                    ? Colors.red
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        // "NEW" badge
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(COLOR_PRIMARY),
                                  Color(COLOR_PRIMARY).withOpacity(0.8),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(COLOR_PRIMARY).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              'NEW',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        // Overlay for closed restaurants - only on image
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
                                            widget.vendorModel) !=
                                        null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        getNextOpeningTimeText(
                                            widget.vendorModel)!,
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
                  // Content section
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Restaurant name and rating row
                        Row(
                          children: [
                            // Restaurant name
                            Expanded(
                              child: Text(
                                widget.vendorModel.title,
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
                            const SizedBox(width: 8),
                            // Rating display
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
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
                                    widget.vendorModel.reviewsCount != 0
                                        ? '${(widget.vendorModel.reviewsSum / widget.vendorModel.reviewsCount).toStringAsFixed(1)}'
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
                        // Order count below name
                        FutureBuilder<int>(
                          key: ValueKey('order_count_${widget.vendorModel.id}'),
                          future: fireStoreUtils
                              .getVendorOrderCount(widget.vendorModel.id),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
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
                                  color: isDarkMode(context)
                                      ? Colors.white70
                                      : Colors.grey.shade600,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        // Distance indicator below orders
                        Builder(
                          builder: (context) {
                            double distanceInMeters =
                                Geolocator.distanceBetween(
                                    widget.vendorModel.latitude,
                                    widget.vendorModel.longitude,
                                    MyAppState
                                        .selectedPosition.location!.latitude,
                                    MyAppState
                                        .selectedPosition.location!.longitude);
                            double kilometer = distanceInMeters / 1000;

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
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
                                      color: isDarkMode(context)
                                          ? Colors.white70
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        // ETA and Delivery Fee
                        RestaurantEtaFeeRow(
                          vendorModel: widget.vendorModel,
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

  // Helper function to check if restaurant is open
  bool isRestaurantOpen(VendorModel vendorModel) {
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

            if (isCurrentDateInRange(start, end)) {
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

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    final currentDate = DateTime.now();
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }
}
