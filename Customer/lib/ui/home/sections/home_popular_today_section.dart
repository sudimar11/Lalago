import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
import 'package:foodie_customer/AppGlobal.dart';

class HomePopularTodaySection extends StatelessWidget {
  final List<ProductModel> popularTodayFoods;
  final List<VendorModel> vendors;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onRetry;

  const HomePopularTodaySection({
    Key? key,
    required this.popularTodayFoods,
    required this.vendors,
    this.isLoading = false,
    this.hasError = false,
    this.onRetry,
  }) : super(key: key);

  Widget _popularTodayHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(Icons.whatshot, color: Colors.orange[700], size: 22),
          const SizedBox(width: 8),
          Text(
            'Popular Today',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.orange[800],
            ),
          ),
        ],
      ),
    );
  }

  void _writeDebugLog({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    required Map<String, dynamic> data,
  }) {
    try {
      final payload = <String, dynamic>{
        'sessionId': 'cb7231',
        'runId': runId,
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      debugPrint(jsonEncode(payload));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (hasError && onRetry != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _popularTodayHeader(),
          HomeSectionUtils.sectionError(
            message: 'Failed to load popular today',
            onRetry: onRetry!,
          ),
        ],
      );
    }
    if (isLoading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _popularTodayHeader(),
          SizedBox(
            height: 150,
            child: ShimmerWidgets.productListShimmer(),
          ),
        ],
      );
    }
    final List<ProductModel> displayFoods = popularTodayFoods
        .where((product) => _hasPhoto(product.photo))
        .toList();
    // #region agent log
    try {
      File('/Users/sudimard/Downloads/Lalago/.cursor/debug.log')
          .writeAsStringSync(
        '${jsonEncode({"location":"HomePopularTodaySection.build","message":"Popular Today display","data":{"popularTodayFoodsCount":popularTodayFoods.length,"displayFoodsCount":displayFoods.length,"vendorsCount":vendors.length},"hypothesisId":"C","timestamp":DateTime.now().millisecondsSinceEpoch})}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    // #endregion
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _popularTodayHeader(),
        SizedBox(
          height: 150,
          child: displayFoods.isEmpty
              ? showEmptyState('No popular items today', context)
              : RepaintBoundary(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    cacheExtent: 300.0,
                    itemCount:
                        displayFoods.length >= 15
                            ? 15
                            : displayFoods.length,
                    itemBuilder: (context, index) {
                      VendorModel? popularTodayVendorModel;

                      if (vendors.isNotEmpty) {
                        for (int a = 0; a < vendors.length; a++) {
                          if (vendors[a].id ==
                              displayFoods[index].vendorID) {
                            popularTodayVendorModel = vendors[a];
                          }
                        }
                      }

                      return popularTodayVendorModel == null
                          ? KeyedSubtree(
                              key: ValueKey('empty_$index'),
                              child: Container(),
                            )
                          : KeyedSubtree(
                              key: ValueKey(displayFoods[index].id),
                              child: popularFoodItem(
                                context,
                                displayFoods[index],
                                popularTodayVendorModel,
                              ),
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
    VendorModel popularTodayVendorModel,
  ) {
    final double rating = product.reviewsCount != 0
        ? (product.reviewsSum / product.reviewsCount)
        : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final int tapStartMs = DateTime.now().millisecondsSinceEpoch;
        // #region agent log
        _writeDebugLog(
          runId: 'baseline',
          hypothesisId: 'B',
          location: 'home_popular_today_section.dart:onTap:start',
          message: 'popular_today_tap_started',
          data: {
            'productId': product.id,
            'vendorId': product.vendorID,
            'localVendorAvailable': popularTodayVendorModel.id.isNotEmpty,
          },
        );
        // #endregion
        final VendorModel? vendorModel =
            popularTodayVendorModel.id.isNotEmpty
                ? popularTodayVendorModel
                : null;

        if (vendorModel != null) {
          final int navigateMs = DateTime.now().millisecondsSinceEpoch;
          // #region agent log
          _writeDebugLog(
            runId: 'post-fix',
            hypothesisId: 'A',
            location: 'home_popular_today_section.dart:onTap:navigate',
            message: 'popular_today_navigating_product_details',
            data: {
              'productId': product.id,
              'vendorId': product.vendorID,
              'usedLocalVendor': true,
              'tapToNavigateMs': navigateMs - tapStartMs,
            },
          );
          // #endregion
          push(
            context,
            ProductDetailsScreen(
              vendorModel: vendorModel,
              productModel: product,
            ),
          );
        } else {
          _navigateWithFallbackFetch(
            context: context,
            product: product,
            tapStartMs: tapStartMs,
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
                  child: CachedNetworkImage(
                    imageUrl: AppGlobal.placeHolderImage!,
                    memCacheWidth: 200,
                    memCacheHeight: 200,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, e) =>
                        const Icon(Icons.broken_image),
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
                          vendorModel: popularTodayVendorModel,
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

  void _navigateWithFallbackFetch({
    required BuildContext context,
    required ProductModel product,
    required int tapStartMs,
  }) {
    // #region agent log
    _writeDebugLog(
      runId: 'post-fix',
      hypothesisId: 'D',
      location: 'home_popular_today_section.dart:onTap:fallbackStart',
      message: 'popular_today_fallback_fetch_started',
      data: {
        'productId': product.id,
        'vendorId': product.vendorID,
      },
    );
    // #endregion
    FireStoreUtils.getVendor(product.vendorID).then((vendorModel) {
      final int fetchDoneMs = DateTime.now().millisecondsSinceEpoch;
      // #region agent log
      _writeDebugLog(
        runId: 'post-fix',
        hypothesisId: 'D',
        location: 'home_popular_today_section.dart:onTap:fallbackDone',
        message: 'popular_today_fallback_fetch_completed',
        data: {
          'productId': product.id,
          'vendorId': product.vendorID,
          'durationMs': fetchDoneMs - tapStartMs,
          'fetchedVendorNull': vendorModel == null,
        },
      );
      // #endregion
      if (vendorModel != null) {
        push(
          context,
          ProductDetailsScreen(
            vendorModel: vendorModel,
            productModel: product,
          ),
        );
      }
    });
  }
}
