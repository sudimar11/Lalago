import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/click_tracking_service.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/widgets/performance_badge.dart';

class RestaurantCard extends StatelessWidget {
  final VendorModel vendorModel;
  final List<OfferModel> offerList;
  final List<ProductModel> allProducts;
  final dynamic currencyModel;
  final String? source;
  final int? position;
  final String? recommendationReason;
  final bool showFeedbackButtons;
  final void Function(String feedback)? onFeedback;

  const RestaurantCard({
    Key? key,
    required this.vendorModel,
    required this.offerList,
    required this.allProducts,
    required this.currencyModel,
    this.source,
    this.position,
    this.recommendationReason,
    this.showFeedbackButtons = false,
    this.onFeedback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    bool restaurantIsOpen = isRestaurantOpen(vendorModel);

    List<OfferModel> tempList = [];
    List<double> discountAmountTempList = [];

    offerList.forEach((element) {
      if (vendorModel.id == element.restaurantId &&
          element.expireOfferDate!.toDate().isAfter(DateTime.now())) {
        tempList.add(element);
        discountAmountTempList.add(double.parse(element.discount.toString()));
      }
    });

    // Choose a random product image from this vendor (excluding placeholder/empty), fallback to vendor photo
    List<ProductModel> vendorProducts =
        allProducts.where((p) => p.vendorID == vendorModel.id).toList();
    List<ProductModel> validVendorProducts = vendorProducts.where((p) {
      final String photo = p.photo.trim();
      if (photo.isEmpty) return false;
      if (AppGlobal.placeHolderImage != null &&
          photo == AppGlobal.placeHolderImage) return false;
      return true;
    }).toList();

    String cardImage = vendorModel.photo;
    if (validVendorProducts.isNotEmpty) {
      final seededRandom = Random(vendorModel.id.hashCode);
      final ProductModel randomProduct =
          validVendorProducts[seededRandom.nextInt(validVendorProducts.length)];
      cardImage = randomProduct.photo;
    }

    return GestureDetector(
      onTap: () {
        ClickTrackingService.logClick(
          userId: MyAppState.currentUser?.userID ?? 'guest',
          restaurantId: vendorModel.id,
          source: source ?? 'home_section',
          metadata: {
            if (position != null) 'position': position,
            if (recommendationReason != null)
              'recommendationReason': recommendationReason,
          },
        );
        push(context, NewVendorProductsScreen(vendorModel: vendorModel));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDarkMode(context)
                  ? const Color(DarkContainerBorderColor)
                  : Colors.grey.shade100,
              width: 1),
          color: isDarkMode(context)
              ? const Color(DarkContainerColor)
              : Colors.white,
          boxShadow: [
            isDarkMode(context)
                ? const BoxShadow()
                : BoxShadow(
                    color: Colors.grey.withOpacity(0.5),
                    blurRadius: 5,
                  ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: getImageVAlidUrl(cardImage),
                        width: MediaQuery.of(context).size.width,
                        height: 180,
                        memCacheWidth: 200,
                        memCacheHeight: 200,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: double.infinity,
                          height: 180,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: Icon(Icons.restaurant,
                                color: Colors.grey,
                                size: 40),
                          ),
                        ),
                        errorWidget: (context, url, error) => ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: CachedNetworkImage(
                              imageUrl: AppGlobal.placeHolderImage!,
                              width: MediaQuery.of(context).size.width,
                              height: 180,
                              memCacheWidth: 200,
                              memCacheHeight: 200,
                              fit: BoxFit.cover,
                              errorWidget: (context, u, e) => Container(
                                color: Colors.grey.shade200,
                                child: Icon(Icons.restaurant,
                                    size: 50, color: Colors.grey.shade400),
                              ),
                            )),
                      ),
                    ),
                    if (discountAmountTempList.isNotEmpty)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          decoration: const BoxDecoration(
                              image: DecorationImage(
                                  image: AssetImage(
                                      'assets/images/offer_badge.png'))),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              discountAmountTempList
                                      .reduce(min)
                                      .toStringAsFixed(currencyModel!.decimal) +
                                  "% OFF",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
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
                              horizontal: 5, vertical: 2),
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
                                    fontFamily: "Poppinsm",
                                    letterSpacing: 0.5,
                                    fontSize: 12,
                                    color: Colors.white,
                                  )),
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
                    )
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
                              vendorModel.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                letterSpacing: 0.5,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode(context)
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ),
                          PerformanceBadge(
                            vendorModel: vendorModel,
                            compact: true,
                          ),
                        ],
                      ),
                      if (source != 'personalized') ...[
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
                                vendorModel.location ?? '',
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
                      ],
                      RestaurantEtaFeeRow(
                        vendorModel: vendorModel,
                        currencyModel: currencyModel,
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
                                vendorModel.reviewsCount != 0
                                    ? '${(vendorModel.reviewsSum / vendorModel.reviewsCount).toStringAsFixed(1)}'
                                    : 0.toString(),
                                style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : const Color(0xff000000),
                                )),
                            const SizedBox(width: 3),
                            Text(
                                '(${vendorModel.reviewsCount.toStringAsFixed(1)})',
                                style: TextStyle(
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5,
                                  color: isDarkMode(context)
                                      ? Colors.white60
                                      : const Color(0xff666666),
                                )),
                          ],
                        ),
                      ),
                      if (showFeedbackButtons && onFeedback != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.thumb_up_outlined, size: 18),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => onFeedback!('like'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.thumb_down_outlined, size: 18),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => onFeedback!('dislike'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => onFeedback!('dismiss'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                )
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
                        if (getNextOpeningTimeText(vendorModel) != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            getNextOpeningTimeText(vendorModel)!,
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
