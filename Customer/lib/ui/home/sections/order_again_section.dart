import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/data_cache_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/orderHistory/order_history_screen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

/// Self-contained Order Again section. Owns loading/error/data state.
class OrderAgainSection extends StatefulWidget {
  const OrderAgainSection({Key? key}) : super(key: key);

  @override
  State<OrderAgainSection> createState() => _OrderAgainSectionState();
}

class _OrderAgainSectionState extends State<OrderAgainSection> {
  List<ProductModel> _products = [];
  bool _isLoading = true;
  bool _hasError = false;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (MyAppState.currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final result = await FireStoreUtils().getOrdersByStatusPaginated(
        userID: MyAppState.currentUser!.userID,
        status: ORDER_STATUS_COMPLETED,
        limit: 10,
      );
      final List<OrderModel> orders =
          (result['orders'] as List<OrderModel>?) ?? [];

      if (!mounted) return;
      if (orders.isEmpty) {
        setState(() {
          _products = [];
          _isLoading = false;
        });
        return;
      }

      var products = DataCacheService.instance.products ?? [];
      if (products.isEmpty) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        products = DataCacheService.instance.products ?? [];
      }

      Set<String> productIds = {};
      for (OrderModel order in orders) {
        for (var product in order.products) {
          String baseProductId = product.id.contains('~')
              ? product.id.split('~').first
              : product.id;
          if (baseProductId.isNotEmpty) productIds.add(baseProductId);
        }
      }

      final productIdsList = productIds.toList();
      final cacheIds = products.map((p) => p.id).toSet();
      final unmatchedIds =
          productIdsList.where((id) => !cacheIds.contains(id)).toList();

      List<ProductModel> orderAgainList = [];
      for (String productId in productIds) {
        try {
          final product = products.firstWhere(
            (p) => p.id == productId,
            orElse: () => ProductModel(),
          );
          if (product.id.isNotEmpty) orderAgainList.add(product);
        } catch (_) {}
      }

      // Fetch products not in cache from Firestore
      for (final productId in unmatchedIds) {
        if (!mounted) return;
        try {
          final product =
              await FireStoreUtils().getProductByID(productId);
          if (product.id.isNotEmpty) {
            orderAgainList.add(product);
            final vendor =
                await FireStoreUtils.getVendor(product.vendorID);
            if (vendor != null) {
              DataCacheService.instance.putVendor(vendor);
            }
          }
        } catch (_) {}
      }

      orderAgainList = orderAgainList.toSet().toList();
      orderAgainList = orderAgainList.take(10).toList();

      if (!mounted) return;
      setState(() {
        _products = orderAgainList;
        _isLoading = false;
        _retryAttempt = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _onRetry() {
    final delay = Duration(seconds: 1 << _retryAttempt.clamp(0, 2));
    _retryAttempt = (_retryAttempt + 1).clamp(0, 3);
    Future.delayed(delay, _fetch);
  }

  void _onViewAll() {
    if (MyAppState.currentUser == null) {
      push(context, LoginScreen());
    } else {
      push(context, const OrderHistoryScreen());
    }
  }

  Widget _orderAgainHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.replay, color: Colors.orange[700], size: 22),
              const SizedBox(width: 8),
              Text(
                'Order Again',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: _onViewAll,
            child: Text(
              'View All',
              style: TextStyle(
                color: Colors.orange[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MyAppState.currentUser == null) return const SizedBox.shrink();
    if (_isLoading && _products.isEmpty && !_hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _orderAgainHeader(),
          ShimmerWidgets.orderAgainSkeleton(),
        ],
      );
    }
    if (_products.isEmpty && !_isLoading && !_hasError) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _orderAgainHeader(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No recent orders',
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode(context)
                      ? Colors.white70
                      : Colors.grey.shade600,
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (_hasError) {
      return Column(
        children: [
          _orderAgainHeader(),
          HomeSectionUtils.sectionError(
            message: 'Failed to load order again',
            onRetry: _onRetry,
          ),
        ],
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isDark = isDarkMode(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _orderAgainHeader(),
        RepaintBoundary(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 10),
            child: SizedBox(
              width: screenWidth,
              height: 220,
              child: ListView.builder(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _products.length >= 10 ? 10 : _products.length,
              itemBuilder: (context, index) {
                final product = _products[index];
                final vendor =
                    DataCacheService.instance.getVendor(product.vendorID);
                if (vendor == null) return Container();
                return _buildCard(product, vendor, isDark, screenWidth);
              },
            ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(
    ProductModel product,
    VendorModel vendor,
    bool isDark,
    double screenWidth,
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
        width: screenWidth * 0.375,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                      memCacheWidth: (screenWidth * 0.4).round().clamp(1, 300),
                      memCacheHeight: 240,
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
                          child: Icon(Icons.error, size: 40, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedNetworkImage(
                        imageUrl: getImageVAlidUrl(vendor.photo),
                        memCacheWidth: 64,
                        memCacheHeight: 64,
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
            const SizedBox(height: 8),
            Text(
              product.name,
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              vendor.title,
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '₱ ${double.parse(product.price.toString()).toStringAsFixed(currencyModel!.decimal)}',
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
}
