import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/orderHistory/order_history_screen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';

class HomeOrderAgainSection extends StatelessWidget {
  final List<ProductModel> orderAgainProducts;
  final bool isLoadingOrderAgain;
  final List<VendorModel> vendors;

  const HomeOrderAgainSection({
    Key? key,
    required this.orderAgainProducts,
    required this.isLoadingOrderAgain,
    required this.vendors,
  }) : super(key: key);

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
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "Order Again",
          onClick: () {
            if (MyAppState.currentUser == null) {
              push(context, LoginScreen());
            } else {
              push(context, const OrderHistoryScreen());
            }
          },
        ),
        SizedBox(
          height: 130,
          child: isLoadingOrderAgain
              ? Center(
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                  ),
                )
              : orderAgainProducts.isEmpty
                  ? showEmptyState('No previous orders found', context)
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: orderAgainProducts.length >= 15
                          ? 15
                          : orderAgainProducts.length,
                      itemBuilder: (context, index) {
                        final product = orderAgainProducts[index];
                        final vendor = vendors.firstWhere(
                          (v) => v.id == product.vendorID,
                          orElse: () => VendorModel(title: 'Unknown Vendor'),
                        );
                        return orderAgainProductItem(context, product, vendor);
                      },
                    ),
        ),
      ],
    );
  }

  Widget orderAgainProductItem(
    BuildContext context,
    ProductModel product,
    VendorModel vendor,
  ) {
    return GestureDetector(
      onTap: () {
        final int tapStartMs = DateTime.now().millisecondsSinceEpoch;
        // #region agent log
        _writeDebugLog(
          runId: 'baseline',
          hypothesisId: 'B',
          location: 'home_order_again_section.dart:onTap:start',
          message: 'order_again_tap_started',
          data: {
            'productId': product.id,
            'vendorId': product.vendorID,
            'localVendorAvailable': vendor.id.isNotEmpty,
          },
        );
        // #endregion
        final VendorModel? vendorModel =
            vendor.id.isNotEmpty ? vendor : null;

        if (vendorModel != null) {
          final int navigateMs = DateTime.now().millisecondsSinceEpoch;
          // #region agent log
          _writeDebugLog(
            runId: 'post-fix',
            hypothesisId: 'A',
            location: 'home_order_again_section.dart:onTap:navigate',
            message: 'order_again_navigating_product_details',
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
        width: MediaQuery.of(context).size.width * 0.375,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section with restaurant logo
            Stack(
              children: [
                // Main product image
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDarkMode(context)
                          ? const Color(DarkContainerBorderColor)
                          : Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(product.photo),
                      memCacheWidth: 300,
                      memCacheHeight: 300,
                      maxWidthDiskCache: 600,
                      maxHeightDiskCache: 600,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: CircularProgressIndicator.adaptive(
                          valueColor:
                              AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey.shade100,
                        child: Icon(
                          Icons.fastfood,
                          color: Colors.grey.shade400,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
                // Restaurant logo overlay
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: getImageVAlidUrl(vendor.photo),
                        memCacheWidth: 100,
                        memCacheHeight: 100,
                        maxWidthDiskCache: 200,
                        maxHeightDiskCache: 200,
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) => Icon(
                          Icons.restaurant,
                          size: 16,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Product name
            Text(
              product.name,
              style: TextStyle(
                fontFamily: "Poppinsm",
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Restaurant name
            Text(
              vendor.title,
              style: TextStyle(
                fontFamily: "Poppinsm",
                fontSize: 12,
                color:
                    isDarkMode(context) ? Colors.white70 : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Price
            Text(
              "₱ ${double.parse(product.price.toString()).toStringAsFixed(currencyModel!.decimal)}",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(COLOR_PRIMARY),
              ),
            ),
          ],
        ),
      ),
    );
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
      location: 'home_order_again_section.dart:onTap:fallbackStart',
      message: 'order_again_fallback_fetch_started',
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
        location: 'home_order_again_section.dart:onTap:fallbackDone',
        message: 'order_again_fallback_fetch_completed',
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
