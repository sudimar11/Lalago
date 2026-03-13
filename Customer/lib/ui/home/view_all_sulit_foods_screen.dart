import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/data_cache_service.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/ui/home/sections/widgets/restaurant_eta_fee_row.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
import 'package:foodie_customer/widgets/add_icon_button.dart';

class ViewAllSulitFoodsScreen extends StatefulWidget {
  final List<ProductModel> sulitProducts;
  final List<VendorModel> vendors;

  const ViewAllSulitFoodsScreen({
    Key? key,
    required this.sulitProducts,
    required this.vendors,
  }) : super(key: key);

  @override
  State<ViewAllSulitFoodsScreen> createState() =>
      _ViewAllSulitFoodsScreenState();
}

class _ViewAllSulitFoodsScreenState extends State<ViewAllSulitFoodsScreen> {
  List<ProductModel> _allSulitProducts = [];
  List<VendorModel> _allVendors = [];
  List<ProductModel> filteredProducts = [];
  TextEditingController searchController = TextEditingController();
  bool _isLoadingMore = false;
  bool _isInitialLoad = true;
  DocumentSnapshot<Map<String, dynamic>>? _lastProductDocument;
  bool _hasMore = true;
  static const double sulitCap = 150.0;
  static const int _pageSize = 20;
  late ScrollController _scrollController;
  Map<String, int> _vendorOrderCounts = {};
  static double _effectivePrice(ProductModel p) {
    final price = double.tryParse(p.price) ?? 0.0;
    final dis = double.tryParse(p.disPrice ?? '0') ?? 0.0;
    return dis > 0 && dis < price ? dis : price;
  }

  static bool _isSulit(ProductModel p) {
    final eff = _effectivePrice(p);
    return eff > 0 && eff <= sulitCap;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _allVendors = List.from(widget.vendors);
    _fetchSulitProductsPage();
    _loadVendorOrderCounts();
  }

  Future<void> _loadVendorOrderCounts() async {
    final user = MyAppState.currentUser;
    if (user == null || user.userID.isEmpty) return;
    try {
      final counts = await FireStoreUtils().getUserVendorOrderCounts(
        user.userID,
        orderLimit: 50,
      );
      if (mounted) setState(() => _vendorOrderCounts = counts);
    } catch (_) {}
  }

  @override
  void dispose() {
    _scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _fetchSulitProductsPage();
    }
  }

  Future<void> _fetchSulitProductsPage() async {
    if (_isLoadingMore || !_hasMore || !mounted) return;
    _isLoadingMore = true;
    if (mounted) setState(() {});
    List<ProductModel> toAdd = [];
    try {
      final result = await FireStoreUtils().getProductsPaginatedWithPublishResult(
        limit: _pageSize,
        lastDocument: _lastProductDocument,
      );
      if (!mounted) return;
      final newSulit = result.products.where(_isSulit).toList();
      final existingIds = _allSulitProducts.map((p) => p.id).toSet();
      toAdd = newSulit.where((p) => !existingIds.contains(p.id)).toList();
      for (final p in toAdd) {
        if (!_allVendors.any((v) => v.id == p.vendorID) &&
            p.vendorID.isNotEmpty) {
          final v = DataCacheService.instance.getVendor(p.vendorID) ??
              await FireStoreUtils.getVendor(p.vendorID);
          if (v != null) {
            _allVendors.add(v);
            DataCacheService.instance.putVendor(v);
          }
        }
      }
      final needFallback =
          toAdd.length + _allSulitProducts.length < 5 &&
          result.products.length < _pageSize;
      if (needFallback && mounted) {
        Future.microtask(() => _fallbackFetchAllSulit());
        return;
      }
      _allSulitProducts.addAll(toAdd);
      _lastProductDocument = result.lastDocument;
      _hasMore = result.products.length >= _pageSize;
      filteredProducts = _applySearch(searchController.text);
      _isInitialLoad = false;
    } finally {
      if (mounted) {
        _isLoadingMore = false;
        setState(() {});
        if (toAdd.isEmpty && _hasMore) {
          Future.microtask(() => _fetchSulitProductsPage());
        }
      }
    }
  }

  Future<void> _fallbackFetchAllSulit() async {
    if (_isLoadingMore || !mounted) return;
    _isLoadingMore = true;
    if (mounted) setState(() {});
    try {
      final all = await FireStoreUtils().getAllProducts();
      if (!mounted) return;
      final newSulit = all.where(_isSulit).toList();
      final existingIds = _allSulitProducts.map((p) => p.id).toSet();
      final toAdd =
          newSulit.where((p) => !existingIds.contains(p.id)).toList();
      for (final p in toAdd) {
        if (!_allVendors.any((v) => v.id == p.vendorID) &&
            p.vendorID.isNotEmpty) {
          final v = DataCacheService.instance.getVendor(p.vendorID) ??
              await FireStoreUtils.getVendor(p.vendorID);
          if (v != null) {
            _allVendors.add(v);
            DataCacheService.instance.putVendor(v);
          }
        }
      }
      _allSulitProducts.addAll(toAdd);
      _hasMore = false;
      filteredProducts = _applySearch(searchController.text);
    } finally {
      if (mounted) {
        _isLoadingMore = false;
        setState(() {});
      }
    }
  }

  List<ProductModel> _applySearch(String query) {
    final base = _allSulitProducts;
    if (query.isEmpty) return List.from(base);
    final q = query.toLowerCase();
    return base
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q))
        .toList();
  }

  void filterProducts(String query) {
    setState(() => filteredProducts = _applySearch(query));
  }

  VendorModel? getVendorForProduct(String vendorId) {
    try {
      return _allVendors.firstWhere((v) => v.id == vendorId);
    } catch (_) {
      return null;
    }
  }

  List<({VendorModel vendor, List<ProductModel> products})>
      _getProductsGroupedByVendor() {
    final grouped = <String, List<ProductModel>>{};
    for (final p in filteredProducts) {
      grouped.putIfAbsent(p.vendorID, () => []).add(p);
    }
    final result = <({VendorModel vendor, List<ProductModel> products})>[];
    for (final e in grouped.entries) {
      final vendor = getVendorForProduct(e.key);
      if (vendor != null && e.value.isNotEmpty) {
        result.add((vendor: vendor, products: e.value));
      }
    }
    result.sort((a, b) {
      final countA = _vendorOrderCounts[a.vendor.id] ?? 0;
      final countB = _vendorOrderCounts[b.vendor.id] ?? 0;
      return countB.compareTo(countA);
    });
    return result;
  }

  Widget _buildGroupedContent(BuildContext context) {
    final groups = _getProductsGroupedByVendor();
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index < groups.length) {
                final group = groups[index];
                return _buildRestaurantSection(
                  context,
                  group.vendor,
                  group.products,
                );
              }
              if (index == groups.length &&
                  _hasMore &&
                  _isLoadingMore) {
                return const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return null;
            },
            childCount: groups.length + (_hasMore && _isLoadingMore ? 1 : 0),
          ),
        ),
      ],
    );
  }

  Widget _buildRestaurantSection(
    BuildContext context,
    VendorModel vendor,
    List<ProductModel> products,
  ) {
    final rating = vendor.reviewsCount != 0
        ? (vendor.reviewsSum / vendor.reviewsCount).toStringAsFixed(1)
        : '0.0';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              push(context, NewVendorProductsScreen(vendorModel: vendor));
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(vendor.photo),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: 100,
                      memCacheHeight: 100,
                      placeholder: (_, __) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.restaurant, size: 24),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.restaurant, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendor.title,
                          style: TextStyle(
                            fontFamily: 'Poppinssb',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        RestaurantEtaFeeRow(
                          vendorModel: vendor,
                          currencyModel: null,
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              rating,
                              style: TextStyle(
                                fontFamily: 'Poppinsm',
                                fontSize: 13,
                                color: isDarkMode(context)
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: isDarkMode(context)
                        ? Colors.white54
                        : Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) => _buildProductCard(
              context,
              products[i],
              vendor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    BuildContext context,
    ProductModel product,
    VendorModel vendor,
  ) {
    final isRestaurantOpen = checkRestaurantOpen(vendor.toJson());
    return RepaintBoundary(
      key: ValueKey(product.id),
      child: GestureDetector(
        onTap: () {
          push(
            context,
            ProductDetailsScreen(
              productModel: product,
              vendorModel: vendor,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: getImageVAlidUrl(product.photo),
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: 280,
                        memCacheHeight: 280,
                        maxWidthDiskCache: 600,
                        maxHeightDiskCache: 600,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.restaurant, size: 40),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: Icon(Icons.error, size: 40),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(COLOR_PRIMARY),
                              Color(COLOR_PRIMARY).withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Color(COLOR_PRIMARY).withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Text(
                          'SULIT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: AddIconButton(
                        productModel: product,
                        size: 30.0,
                        margin: EdgeInsets.zero,
                        onCartUpdated: null,
                        isRestaurantOpen: isRestaurantOpen,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      style: TextStyle(
                        fontFamily: 'Poppinssb',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode(context)
                            ? Colors.white
                            : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₱ ${product.price}',
                      style: TextStyle(
                        fontFamily: 'Poppinsb',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(COLOR_PRIMARY),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context) ? Color(DARK_COLOR) : Colors.white,
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Meal for One • Sulit Prices",
          style: TextStyle(
            fontFamily: 'Poppinssb',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white54),
            ),
            child: Text(
              "₱${sulitCap.toStringAsFixed(0)} & below",
              style: const TextStyle(
                fontFamily: 'Poppinssb',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode(context)
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: searchController,
              onChanged: filterProducts,
              decoration: InputDecoration(
                hintText: "Search sulit foods...",
                hintStyle: TextStyle(
                  color: isDarkMode(context)
                      ? Colors.white70
                      : Colors.grey.shade600,
                  fontFamily: 'Poppinsr',
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDarkMode(context)
                      ? Colors.white70
                      : Colors.grey.shade600,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: TextStyle(
                color: isDarkMode(context) ? Colors.white : Colors.black87,
                fontFamily: 'Poppinsr',
              ),
            ),
          ),

          // Results count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  "${filteredProducts.length} sulit foods found",
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode(context)
                        ? Colors.white70
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Products grouped by restaurant
          Expanded(
            child: _isInitialLoad && filteredProducts.isEmpty
                ? ShimmerWidgets.productGridShimmer()
                : filteredProducts.isEmpty && !_isLoadingMore
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: isDarkMode(context)
                                  ? Colors.white54
                                  : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              searchController.text.isEmpty
                                  ? "No sulit foods available"
                                  : "No foods found for '${searchController.text}'",
                              style: TextStyle(
                                fontFamily: 'Poppinsr',
                                fontSize: 16,
                                color: isDarkMode(context)
                                    ? Colors.white70
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _buildGroupedContent(context),
          ),
        ],
      ),
    );
  }
}
