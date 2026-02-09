import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/ui/home/view_all_sulit_foods_screen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class MealForOneSection extends StatelessWidget {
  final List<ProductModel> mealForOneProducts;
  final List<VendorModel> vendors;
  final List<ProductModel> allProducts;
  final bool isLoadingMealForOne;
  static const double sulitCap = 150.0;

  const MealForOneSection({
    Key? key,
    required this.mealForOneProducts,
    required this.vendors,
    required this.allProducts,
    required this.isLoadingMealForOne,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<ProductModel> displayProducts = _filteredMealForOneProducts();
    final List<ProductModel> displayWithPhotos = displayProducts
        .where((product) => _hasPhoto(product.photo))
        .toList();
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _mealForOneHeader(context),
        isLoadingMealForOne
            ? Container(
                width: MediaQuery.of(context).size.width,
                height: 220,
                margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                child: ShimmerWidgets.productListShimmer(),
              )
            : displayWithPhotos.isEmpty
                ? Container(
                    height: 100,
                    child: Center(
                      child: Text(
                        'No sulit meals found',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                : Container(
                    width: MediaQuery.of(context).size.width,
                    height: 240,
                    margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                    child: RepaintBoundary(
                      child: ListView.builder(
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        cacheExtent: 300.0,
                        itemCount: displayWithPhotos.length >= 10
                            ? 10
                            : displayWithPhotos.length,
                        itemBuilder: (context, index) {
                          ProductModel product = displayWithPhotos[index];
                          VendorModel? vendorModel;
                          for (VendorModel vendor in vendors) {
                            if (vendor.id == product.vendorID) {
                              vendorModel = vendor;
                              break;
                            }
                          }
                          if (vendorModel == null) {
                            return Container();
                          }
                          return _mealForOneCard(context, product, vendorModel);
                        },
                      ),
                    ),
                  ),
      ],
    );
  }

  List<ProductModel> _filteredMealForOneProducts() {
    final List<ProductModel> openProducts = [];
    final List<ProductModel> closedProducts = [];

    for (final product in mealForOneProducts) {
      final VendorModel? vendor = _findVendorForProduct(product);
      if (vendor == null) {
        continue;
      }
      if (_isRestaurantOpen(vendor)) {
        openProducts.add(product);
      } else {
        closedProducts.add(product);
      }
    }

    return openProducts.isNotEmpty ? openProducts : closedProducts;
  }

  VendorModel? _findVendorForProduct(ProductModel product) {
    for (final vendor in vendors) {
      if (vendor.id == product.vendorID) {
        return vendor;
      }
    }
    return null;
  }

  bool _isRestaurantOpen(VendorModel vendorModel) {
    final now = DateTime.now();
    final day = DateFormat('EEEE', 'en_US').format(now);
    final date = DateFormat('dd-MM-yyyy').format(now);

    bool isOpen = false;

    for (final workingHour in vendorModel.workingHours) {
      if (day == workingHour.day.toString()) {
        final timeSlots = workingHour.timeslot;
        if (timeSlots != null && timeSlots.isNotEmpty) {
          for (final timeSlot in timeSlots) {
            final start = DateFormat("dd-MM-yyyy HH:mm").parse(
              '$date ${timeSlot.from}',
            );
            final end = DateFormat("dd-MM-yyyy HH:mm").parse(
              '$date ${timeSlot.to}',
            );

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
    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  Widget _mealForOneHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: "Meal for one ",
                        style: TextStyle(
                          fontFamily: 'Poppinssb',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode(context)
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      TextSpan(
                        text: "sulit prices",
                        style: TextStyle(
                          fontFamily: 'Poppinssb',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              final List<ProductModel> sulitAll = allProducts.where((p) {
                final double price = double.tryParse(p.price) ?? 0.0;
                return price > 0 && price <= sulitCap;
              }).toList();

              push(
                context,
                ViewAllSulitFoodsScreen(
                  sulitProducts: sulitAll,
                  vendors: vendors,
                ),
              );
            },
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mealForOneCard(
    BuildContext context,
    ProductModel product,
    VendorModel vendor,
  ) {
    return GestureDetector(
      onTap: () {
        push(
          context,
          ProductDetailsScreen(
            productModel: product,
            vendorModel: vendor,
          ),
        );
      },
      child: Container(
        width: MediaQuery.of(context).size.width * 0.375,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(product.photo),
                      memCacheWidth: 300,
                      memCacheHeight: 300,
                      maxWidthDiskCache: 600,
                      maxHeightDiskCache: 600,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 40,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.error,
                            size: 40,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: getImageVAlidUrl(vendor.photo),
                        memCacheWidth: 100,
                        memCacheHeight: 100,
                        maxWidthDiskCache: 200,
                        maxHeightDiskCache: 200,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                        errorWidget: (context, url, error) => const Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vendor.title,
                          style: TextStyle(
                            fontFamily: 'Poppinsm',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.star,
                        size: 12,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        vendor.reviewsCount != 0
                            ? '${(vendor.reviewsSum / vendor.reviewsCount).toStringAsFixed(1)}'
                            : '0.0',
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode(context)
                              ? Colors.white70
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.name,
                    style: TextStyle(
                      fontFamily: 'Poppinssb',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          isDarkMode(context) ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '₱ ${product.price}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // ETA and Delivery Fee
                  RestaurantEtaFeeRow(
                    vendorModel: vendor,
                    currencyModel: null,
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
