import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/utils/order_status_messages.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({Key? key}) : super(key: key);

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<OrderModel> _orders = [];
  bool _isLoading = false;
  bool _hasMore = true;
  dynamic _lastDocument;
  String _searchQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) {
      return;
    }
    setState(() {
      _error = null;
      _orders = [];
      _lastDocument = null;
      _hasMore = true;
    });
    await _fetchPage();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || _lastDocument == null) return;
    await _fetchPage();
  }

  Future<void> _fetchPage() async {
    if (_isLoading) return;
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final result = await _fireStoreUtils.getOrdersByStatusPaginated(
        userID: MyAppState.currentUser!.userID,
        status: ORDER_STATUS_COMPLETED,
        limit: 10,
        lastDocument: _lastDocument,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Order history load timed out'),
      );

      final List<OrderModel> newOrders =
          (result['orders'] as List<OrderModel>?) ?? [];
      final lastDoc = result['lastDocument'];

      if (mounted) {
        setState(() {
          _orders.addAll(newOrders);
          _lastDocument = lastDoc;
          _hasMore = newOrders.length == 10;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e, st) {
      debugPrint('OrderHistoryScreen fetch error: $e $st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<OrderModel> get _filteredOrders {
    if (_searchQuery.isEmpty) return _orders;
    return _orders.where((o) {
      final idMatch =
          o.id.toLowerCase().contains(_searchQuery);
      final vendorMatch =
          o.vendor.title.toLowerCase().contains(_searchQuery);
      final dateStr =
          DateFormat('MMM d yyyy').format(o.createdAt.toDate()).toLowerCase();
      final dateMatch = dateStr.contains(_searchQuery);
      return idMatch || vendorMatch || dateMatch;
    }).toList();
  }

  CartProduct? _validateAndTransformCartProduct(CartProduct product) {
    try {
      if (product.id.isEmpty ||
          product.name.isEmpty ||
          product.vendorID.isEmpty ||
          product.price.isEmpty) {
        return null;
      }
      String categoryId = product.category_id ?? product.id.split('~').first;
      if (categoryId.isEmpty) categoryId = product.id;

      String? extrasString;
      if (product.extras != null) {
        if (product.extras is List) {
          final extrasList =
              (product.extras as List).map((e) => e.toString()).toList();
          extrasString = extrasList.join(',');
        } else if (product.extras is String) {
          extrasString = product.extras as String;
        } else {
          extrasString = product.extras.toString();
        }
      }

      return CartProduct(
        id: product.id,
        category_id: categoryId,
        name: product.name,
        photo: product.photo.isNotEmpty
            ? product.photo
            : (AppGlobal.placeHolderImage ?? ''),
        price: product.price,
        discountPrice: product.discountPrice ?? '',
        vendorID: product.vendorID,
        quantity: product.quantity > 0 ? product.quantity : 1,
        extras_price: product.extras_price ?? '0.0',
        extras: extrasString,
        variant_info: product.variant_info,
        addedAt: product.addedAt,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _reorder(OrderModel orderModel) async {
    if (orderModel.products.isEmpty) {
      showAlertDialog(
        context,
        'Reorder Failed',
        'This order has no products to reorder.',
        true,
      );
      return;
    }

    await showProgress(context, 'Please wait', false);

    int successCount = 0;
    int failCount = 0;
    final List<String> failedProducts = [];

    Future<void> runReorder() async {
      final cartDb = Provider.of<CartDatabase>(context, listen: false);
      await cartDb.deleteAllProducts().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Clear cart timed out'),
      );

      for (final CartProduct p in orderModel.products) {
        try {
          final validated = _validateAndTransformCartProduct(p);
          if (validated != null) {
            await cartDb.reAddProduct(validated).timeout(
              const Duration(seconds: 5),
              onTimeout: () =>
                  throw TimeoutException('Add product timed out'),
            );
            successCount++;
          } else {
            failCount++;
            failedProducts.add(p.name);
          }
        } catch (e) {
          failCount++;
          failedProducts.add(p.name);
        }
      }
    }

    try {
      await runReorder().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('Reorder timed out'),
      );
    } catch (e) {
      if (mounted) {
        showAlertDialog(
          context,
          'Reorder Failed',
          'An error occurred. Please try again.',
          true,
        );
      }
      return;
    } finally {
      await hideProgress();
    }

    if (!mounted) return;

    if (successCount > 0) {
      if (failCount > 0) {
        showAlertDialog(
          context,
          'Partial Reorder',
          '$successCount product(s) added. $failCount could not be added: '
              '${failedProducts.join(', ')}',
          true,
        );
      }
      push(context, CartScreen(fromContainer: false));
    } else {
      showAlertDialog(
        context,
        'Reorder Failed',
        'Unable to add products to cart. Please try again.',
        true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Color(COLOR_PRIMARY),
          title: const Text('Order History'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                'Please sign in to view your order history',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  color: isDarkMode(context)
                      ? Colors.white70
                      : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => push(context, LoginScreen()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                ),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredOrders;
    final isDark = isDarkMode(context);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(DARK_COLOR) : const Color(0xffFFFFFF),
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Order Again',
          style: TextStyle(
            fontFamily: 'Poppinsm',
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by order ID, restaurant, or date',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade400,
                  fontFamily: 'Poppinsr',
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ),
      ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error: $_error',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppinsm',
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _loadInitial,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _isLoading && _orders.isEmpty
              ? Center(
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                  ),
                )
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 64,
                            color: isDark
                                ? Colors.grey.shade500
                                : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No completed orders yet'
                                : 'No orders match your search',
                            style: TextStyle(
                              fontFamily: 'Poppinsm',
                              fontSize: 16,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadInitial,
                      color: Color(COLOR_PRIMARY),
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: filtered.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= filtered.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: CircularProgressIndicator.adaptive(
                                  valueColor: AlwaysStoppedAnimation(
                                    Color(COLOR_PRIMARY),
                                  ),
                                ),
                              ),
                            );
                          }
                          return _buildOrderCard(filtered[index]);
                        },
                      ),
                    ),
    );
  }

  Widget _buildOrderCard(OrderModel orderModel) {
    final isDark = isDarkMode(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(DARK_CARD_BG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? const Color.fromARGB(255, 126, 125, 125).withOpacity(0.2)
              : const Color.fromARGB(255, 126, 125, 125).withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.4)
                : Colors.grey.withOpacity(0.15),
            spreadRadius: 0,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => push(
            context,
            OrderDetailsScreen(orderModel: orderModel),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORDER ID',
                            style: TextStyle(
                              fontFamily: 'Poppinsm',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '#${orderModel.id.length >= 8 ? orderModel.id.substring(0, 8).toUpperCase() : orderModel.id.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                              fontFamily: 'Poppinssb',
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge(orderModel.status),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 90,
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            spreadRadius: 0,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: orderModel.products.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: orderModel.products.first.photo
                                    .isNotEmpty
                                    ? orderModel.products.first.photo
                                    : placeholderImage,
                                memCacheWidth: 200,
                                memCacheHeight: 200,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  child: Icon(
                                    Icons.restaurant,
                                    color: Colors.grey.shade400,
                                    size: 32,
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey.shade200,
                                child: Icon(
                                  Icons.restaurant,
                                  color: Colors.grey.shade400,
                                  size: 32,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (orderModel.vendor.title.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                orderModel.vendor.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : Colors.black87,
                                  fontFamily: 'Poppinsb',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ...orderModel.products
                              .take(2)
                              .map(
                                (p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                      fontFamily: 'Poppinsm',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          if (orderModel.products.length > 2)
                            Text(
                              '+${orderModel.products.length - 2} more items',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontFamily: 'Poppinsr',
                              ),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                orderDate(orderModel.createdAt),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                  fontFamily: 'Poppinsr',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      currencyModel != null
                          ? amountShow(
                              amount: orderModel.totalAmount.toString(),
                            )
                          : '₱${orderModel.totalAmount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Color(COLOR_PRIMARY),
                        fontFamily: 'Poppinsm',
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              push(context, OrderDetailsScreen(orderModel: orderModel)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Color(COLOR_PRIMARY)),
                          ),
                          child: Text(
                            'View',
                            style: TextStyle(
                              color: Color(COLOR_PRIMARY),
                              fontFamily: 'Poppinsm',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _reorder(orderModel),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(COLOR_PRIMARY),
                          ),
                          child: const Text(
                            'Reorder',
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: 'Poppinsm',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final statusColor = Colors.green;
    final backgroundColor = Colors.green.withOpacity(0.1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: statusColor),
          const SizedBox(width: 4),
          Text(
            getStatusMessage(status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: statusColor,
              fontFamily: 'Poppinsm',
            ),
          ),
        ],
      ),
    );
  }
}
