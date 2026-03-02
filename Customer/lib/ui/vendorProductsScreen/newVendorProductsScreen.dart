import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:foodie_customer/common/common_elevated_button.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/widgets/add_icon_button.dart';

import 'package:foodie_customer/model/FavouriteModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/model/bundle_model.dart';
import 'package:foodie_customer/services/bundle_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/bundle/bundle_card.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/main.dart';
// import 'package:foodie_customer/ui/vendorProductsScreen/widgets/fappbar.dart';
import 'package:provider/provider.dart';
import 'package:rect_getter/rect_getter.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../common/common_cachend_network_image.dart';
import '../../common/common_image.dart';
import '../../resources/assets.dart';
import '../../resources/colors.dart';
import 'photos.dart';
import 'widgets/vendor_header_delegate.dart';
import '../searchScreen/SearchScreen.dart';
import 'package:foodie_customer/ui/orderHistory/order_history_screen.dart';
import 'package:foodie_customer/services/reorder_service.dart';

class NewVendorProductsScreen extends StatefulWidget {
  final VendorModel vendorModel;
  final bool showReorderBanner;

  const NewVendorProductsScreen({
    Key? key,
    required this.vendorModel,
    this.showReorderBanner = false,
  }) : super(key: key);

  @override
  State<NewVendorProductsScreen> createState() =>
      _NewVendorProductsScreenState();
}

class _NewVendorProductsScreenState extends State<NewVendorProductsScreen>
    with SingleTickerProviderStateMixin {
  final FireStoreUtils fireStoreUtils = FireStoreUtils();

  final listViewKey = RectGetter.createGlobalKey();

  bool isCollapsed = false;

  late AutoScrollController scrollController;

  TabController? tabController;

  final double expandedHeight = 500.0;

  // final PageData data = ExampleData.data;

  final double collapsedHeight = kToolbarHeight;

  Map<int, dynamic> itemKeys = {};

  // prevent animate when press on tab bar

  bool pauseRectGetterIndex = false;

  bool isFavorite = false;

  // Visitor tracking (real-time + per week)
  int _viewingNow = 0;
  int _visitorsThisWeek = 0;
  bool _lowPerfWarningDismissed = false;
  String? _activeViewerSessionId;
  StreamSubscription<int>? _activeViewerSub;
  StreamSubscription<int>? _weeklyVisitSub;

  @override
  void initState() {
    getFoodType();
    log("ETO: ${widget.vendorModel.categoryID}");
    statusCheck();
    _checkFavoriteStatus();
    _startVisitorTracking();

    scrollController = AutoScrollController();

    super.initState();
  }

  Future<void> _startVisitorTracking() async {
    final vendorId = widget.vendorModel.id;
    _activeViewerSessionId =
        await fireStoreUtils.addActiveViewerSession(vendorId);
    await fireStoreUtils.incrementWeeklyVisitCount(vendorId);

    _activeViewerSub = fireStoreUtils.getActiveViewerCountStream(vendorId).listen(
          (count) {
        if (mounted) setState(() => _viewingNow = count);
      },
    );
    _weeklyVisitSub = fireStoreUtils.getWeeklyVisitCountStream(vendorId).listen(
          (count) {
        if (mounted) setState(() => _visitorsThisWeek = count);
      },
    );
  }

  Future<void> _stopVisitorTracking() async {
    await _activeViewerSub?.cancel();
    await _weeklyVisitSub?.cancel();
    if (_activeViewerSessionId != null) {
      await fireStoreUtils.removeActiveViewerSession(
        widget.vendorModel.id,
        _activeViewerSessionId!,
      );
    }
  }

  Future<void> _checkFavoriteStatus() async {
    if (MyAppState.currentUser == null) return;
    try {
      final favorites = await fireStoreUtils
          .getFavouriteRestaurant(MyAppState.currentUser!.userID);
      if (mounted) {
        setState(() {
          isFavorite = favorites
              .any((fav) => fav.restaurantId == widget.vendorModel.id);
        });
      }
    } catch (e) {
      debugPrint('Error checking favorite status: $e');
    }
  }

  void _handleToggleFavorite() {
    if (MyAppState.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to add favorites'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final favouriteModel = FavouriteModel(
      restaurantId: widget.vendorModel.id,
      userId: MyAppState.currentUser!.userID,
    );

    if (isFavorite) {
      fireStoreUtils.removeFavouriteRestaurant(favouriteModel);
      setState(() => isFavorite = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Removed from favorites')),
      );
    } else {
      fireStoreUtils.setFavouriteRestaurant(favouriteModel);
      setState(() => isFavorite = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to favorites')),
      );
    }
  }

  Widget _buildReorderBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.restore, color: Colors.orange.shade700, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reorder from ${widget.vendorModel.title}?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to see your previous items',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => push(context, const OrderHistoryScreen()),
            child: const Text('View'),
          ),
          TextButton(
            onPressed: () => ReorderService.reorderFromVendor(
              context,
              widget.vendorModel.id,
            ),
            child: const Text('Reorder'),
          ),
        ],
      ),
    );
  }

  bool _shouldShowLowPerfWarning() {
    if (_lowPerfWarningDismissed) return false;
    final badge = widget.vendorModel.performanceBadge?.toLowerCase();
    final rate = widget.vendorModel.acceptanceRate;
    return badge == 'slow' || (rate != null && rate < 80);
  }

  Widget _buildLowPerfWarningBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.amber.shade800, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This restaurant sometimes takes longer to confirm orders. '
                  'You may experience delays or cancellations.',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppinsr',
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() => _lowPerfWarningDismissed = true);
                },
                child: const Text('Continue Anyway'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SearchScreen(
                        shouldAutoFocus: true,
                      ),
                    ),
                  );
                },
                child: const Text('Find Faster Restaurant'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void filterProducts(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          searchQuery = query;
          if (query.isEmpty) {
            filteredProducts.clear();
          } else {
            final lowerQuery = query.toLowerCase();
            filteredProducts = productModel.where((product) {
              final nameMatch = product.name.toLowerCase().contains(lowerQuery);
              final descMatch =
                  product.description.toLowerCase().contains(lowerQuery);
              return nameMatch || descMatch;
            }).toList();
          }
        });
      }
    });
  }

  String? foodType;

  List a = [];

  List<ProductModel> productModel = [];

  // Search state
  final TextEditingController searchController = TextEditingController();
  String searchQuery = "";
  List<ProductModel> filteredProducts = [];
  Timer? _searchDebounceTimer;

  void getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    foodType = sp.getString("foodType") ?? "Delivery";

    if (foodType == "Takeaway") {
      await fireStoreUtils
          .getVendorProductsTakeAWay(widget.vendorModel.id)
          .then((value) {
        productModel.clear();

        productModel.addAll(value);

        getVendorCategoryById();

        setState(() {});
      });
    } else {
      await fireStoreUtils
          .getVendorProductsDelivery(widget.vendorModel.id)
          .then((value) {
        productModel.clear();

        productModel.addAll(value);

        getVendorCategoryById();

        setState(() {});
      });
    }
  }

  List<VendorCategoryModel> vendorCateoryModel = [];

  List<OfferModel> offerList = [];

  getVendorCategoryById() async {
    vendorCateoryModel.clear();
    a.clear();

    // Collect all unique category IDs first
    final Set<String> uniqueCategoryIds = {};
    for (int i = 0; i < productModel.length; i++) {
      if (!uniqueCategoryIds.contains(productModel[i].categoryID)) {
        uniqueCategoryIds.add(productModel[i].categoryID);
        a.add(productModel[i].categoryID);
      }
    }

    // Fetch all categories and offers in parallel
    final List<Future<VendorCategoryModel?>> categoryFutures = uniqueCategoryIds
        .map((categoryId) => fireStoreUtils.getVendorCategoryById(categoryId))
        .toList();

    final offerFuture =
        FireStoreUtils().getOfferByVendorID(widget.vendorModel.id);

    // Wait for both categories and offers in parallel
    final results = await Future.wait([
      Future.wait(categoryFutures),
      offerFuture,
    ]);

    final List<VendorCategoryModel?> categoryResults =
        results[0] as List<VendorCategoryModel?>;
    final List<OfferModel> offers = results[1] as List<OfferModel>;

    // Filter out null results
    final List<VendorCategoryModel> validCategories =
        categoryResults.whereType<VendorCategoryModel>().toList();

    // Batch all setState calls into one
    if (mounted) {
      setState(() {
        vendorCateoryModel.addAll(validCategories);
        tabController =
            TabController(length: vendorCateoryModel.length + 2, vsync: this);
        offerList = offers;
      });
    }
  }

  @override
  void dispose() {
    _stopVisitorTracking();
    scrollController.dispose();
    _searchDebounceTimer?.cancel();
    searchController.dispose();
    tabController!.dispose();

    super.dispose();
  }

  List<int> getVisibleItemsIndex() {
    Rect? rect = RectGetter.getRectFromKey(listViewKey);

    List<int> items = [];

    if (rect == null) return items;

    itemKeys.forEach((index, key) {
      Rect? itemRect = RectGetter.getRectFromKey(key);

      if (itemRect == null) return;

      if (itemRect.top > rect.bottom) return;

      if (itemRect.bottom < rect.top) return;

      items.add(index);
    });

    return items;
  }

  void onCollapsed(bool value) {
    if (this.isCollapsed == value) return;

    setState(() => this.isCollapsed = value);
  }

  bool onScrollNotification(ScrollNotification notification) {
    if (pauseRectGetterIndex) return true;

    int lastTabIndex = tabController!.length - 1;

    List<int> visibleItems = getVisibleItemsIndex();

    if (visibleItems.isEmpty) return false;

    // If we're at the last section and it's visible, select the last tab
    bool reachLastTabIndex =
        visibleItems.length <= 2 && visibleItems.last == lastTabIndex;

    if (reachLastTabIndex) {
      if (tabController!.index != lastTabIndex) {
        tabController!.animateTo(lastTabIndex);
      }
    } else if (visibleItems.isNotEmpty) {
      // Calculate which section is most visible
      int mostVisibleIndex = visibleItems.first;

      // If multiple sections are visible, prefer the first one
      // This ensures the tab switches as soon as a new section becomes visible
      if (tabController!.index != mostVisibleIndex) {
        tabController!.animateTo(mostVisibleIndex);
      }
    }

    return false;
  }

  void animateAndScrollTo(int index) {
    pauseRectGetterIndex = true;

    tabController!.animateTo(index);

    scrollController
        .scrollToIndex(index, preferPosition: AutoScrollPosition.begin)
        .then((value) => pauseRectGetterIndex = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(COLOR_PRIMARY)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.vendorModel.title,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Color(COLOR_PRIMARY) : Colors.grey.shade700,
            ),
            onPressed: _handleToggleFavorite,
          ),
        ],
      ),
      body: tabController == null
          ? const Center(child: CircularProgressIndicator())
          : RectGetter(
              key: listViewKey,
              child: NotificationListener<ScrollNotification>(
                child: buildSliverScrollView(),
                onNotification: onScrollNotification,
              ),
            ),
      bottomNavigationBar: priceTemp > 0
          ? Container(
              padding: const EdgeInsets.only(
                  left: 20, right: 20, bottom: 20, top: 20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade400))),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Item Total:" +
                          " " +
                          amountShow(amount: priceTemp.toString()),
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16.0,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  SizedBox(
                    height: 40.0,
                    child: CommonElevatedButton(
                      onButtonPressed: () {
                        pushAndRemoveUntil(
                          context,
                          ContainerScreen(
                            user: MyAppState.currentUser,
                            currentWidget: CartScreen(),
                            appBarTitle: 'Your Cart',
                          ),
                          false,
                        );
                      },
                      custom: Row(
                        spacing: 4.0,
                        children: [
                          CommonImage(
                            path: Assets.icShoppingCart,
                            height: 18.0,
                            width: 18.0,
                          ),
                          Text(
                            "View Cart",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.0,
                              fontWeight: FontWeight.w600,
                              fontFamily: "Poppinsm",
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget buildSliverScrollView() {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // buildAppBar(),
        SliverPersistentHeader(
          delegate: VendorHeaderDelegate(
              context: context,
              vendorModel: widget.vendorModel,
              expandedHeight: expandedHeight,
              isOpen: isOpen,
              hideCollapsedAppBar: true,
              onViewPhotos: () => push(
                  context, RestaurantPhotos(vendorModel: widget.vendorModel)),
              searchController: searchController,
              onSearchChanged: (query) {
                filterProducts(query);
              },
              viewingNow: _viewingNow,
              visitorsThisWeek: _visitorsThisWeek),
          pinned: true,
        ),
        if (widget.showReorderBanner)
          SliverToBoxAdapter(
            child: _buildReorderBanner(),
          ),
        if (_shouldShowLowPerfWarning())
          SliverToBoxAdapter(
            child: _buildLowPerfWarningBanner(),
          ),
        if (searchQuery.isEmpty)
          SliverAppBar(
            automaticallyImplyLeading: false,
            pinned: false,
            floating: true,
            toolbarHeight: 48,
            backgroundColor: Colors.white,
            flexibleSpace: Align(
              alignment: Alignment.bottomCenter,
              child: TabBar(
                isScrollable: true,
                controller: tabController,
                indicatorPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                indicatorColor: CustomColors.primary,
                labelStyle: const TextStyle(
                  color: CustomColors.primary,
                  fontSize: 16.0,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: TextStyle(
                  color: Colors.black.withValues(alpha: 0.60),
                  fontSize: 14.0,
                  fontWeight: FontWeight.w400,
                ),
                indicatorWeight: 3.0,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          size: 16,
                          color: CustomColors.primary,
                        ),
                        const SizedBox(width: 4),
                        const Text("Popular"),
                      ],
                    ),
                  ),
                  ...vendorCateoryModel.map((e) => Tab(text: e.title)),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2,
                          size: 16,
                          color: CustomColors.primary,
                        ),
                        const SizedBox(width: 4),
                        const Text("Bundles"),
                      ],
                    ),
                  ),
                ],
                onTap: animateAndScrollTo,
              ),
            ),
          ),
        buildBody(),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    cartDatabase = Provider.of<CartDatabase>(context);
    updatePrice();
    super.didChangeDependencies();
  }

  // SliverAppBar buildAppBar() {
  //   return FAppBar(
  //     vendorModel: widget.vendorModel,
  //     vendorCateoryModel: vendorCateoryModel,
  //     isOpen: isOpen,
  //     context: context,
  //     scrollController: scrollController,
  //     expandedHeight: expandedHeight,
  //     collapsedHeight: collapsedHeight,
  //     isCollapsed: isCollapsed,
  //     onCollapsed: onCollapsed,
  //     tabController: tabController!,
  //     offerList: offerList,
  //     onTap: (index) => animateAndScrollTo(index),
  //   );
  // }

  SliverList buildBody() {
    if (searchQuery.isNotEmpty) {
      // Show unified search results
      if (filteredProducts.isEmpty) {
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: CustomColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Search Results (0)",
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "No results found",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Try searching with different keywords",
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: 2,
          ),
        );
      }
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: CustomColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Search Results (${filteredProducts.length})",
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }
            return buildSearchResultItem(filteredProducts[index - 1]);
          },
          childCount: filteredProducts.length + 1,
        ),
      );
    } else {
      // Show normal category-based view (Popular + categories + Bundles)
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == 0) {
              return buildPopularSection();
            } else if (index <= vendorCateoryModel.length) {
              return buildCategoryItem(index - 1);
            } else {
              return buildBundlesSection();
            }
          },
          childCount: vendorCateoryModel.length + 2,
        ),
      );
    }
  }

  Widget buildBundlesSection() {
    final bundleIndex = vendorCateoryModel.length + 1;
    itemKeys[bundleIndex] = RectGetter.createGlobalKey();
    return RectGetter(
      key: itemKeys[bundleIndex],
      child: AutoScrollTag(
        key: ValueKey(bundleIndex),
        index: bundleIndex,
        controller: scrollController,
        child: StreamBuilder<List<BundleModel>>(
          stream: BundleService.getActiveBundlesStream(
            restaurantId: widget.vendorModel.id,
            limit: 20,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    snapshot.hasError ? 'Failed to load bundles' : 'No bundles',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              );
            }
            final bundles = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.inventory_2,
                        size: 20,
                        color: CustomColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Bundles",
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bundles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final bundle = bundles[index];
                      return BundleCard(
                        bundle: bundle,
                        onAddToCart: () => _addBundleToCart(context, bundle),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _addBundleToCart(BuildContext context, BundleModel bundle) async {
    final cartDb = Provider.of<CartDatabase>(context, listen: false);
    final products = await cartDb.allCartProducts;
    if (products.isNotEmpty &&
        products.first.vendorID != bundle.restaurantId) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Different restaurant'),
          content: const Text(
            'Your cart has items from another restaurant. '
            'Clear cart and add this bundle?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear and Add'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await cartDb.deleteAllProducts();
    }
    final itemsWithPhotos = await BundleService.itemsWithPhotos(
      bundle.restaurantId,
      bundle.items,
    );
    await cartDb.addBundleToCart(
      bundleId: bundle.bundleId,
      bundleName: bundle.name,
      vendorID: bundle.restaurantId,
      bundlePrice: bundle.bundlePrice,
      items: itemsWithPhotos,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${bundle.name} added to cart')),
      );
    }
  }

  Widget buildSearchResultItem(ProductModel product) {
    return datarow(product);
  }

  Widget buildCategoryItem(int index) {
    itemKeys[index] = RectGetter.createGlobalKey();

    VendorCategoryModel category = vendorCateoryModel[index];

    return RectGetter(
      key: itemKeys[index],
      child: AutoScrollTag(
        key: ValueKey(index),
        index: index,
        controller: scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            productModel.isEmpty
                ? Container()
                : index == 0
                    ? buildVeg(false, false) // veg, nonveg parameters (unused)
                    : Container(),
            _buildSectionTileHeader(category),
            _buildFoodTileList(context, category),
          ],
        ),
      ),
    );
  }

  Widget buildPopularSection() {
    // Get the 9 most ordered foods (for now, we'll take the first 9 products)
    List<ProductModel> popularProducts = productModel.take(10).toList();

    // Add key for the Popular section (index 0)
    itemKeys[0] = RectGetter.createGlobalKey();

    return RectGetter(
      key: itemKeys[0],
      child: AutoScrollTag(
        key: ValueKey(0),
        index: 0,
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 20,
                    color: CustomColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "Popular",
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.75,
                  crossAxisSpacing: 6.0,
                  mainAxisSpacing: 6.0,
                ),
                itemCount: popularProducts.length,
                itemBuilder: (context, index) {
                  return buildPopularFoodItem(popularProducts[index]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildPopularFoodItem(ProductModel product) {
    return GestureDetector(
      onTap: () {
        push(
          context,
          ProductDetailsScreen(
            productModel: product,
            vendorModel: widget.vendorModel,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.1,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8.0)),
                  child: CommonNetworkImage(
                    imageUrl: getImageVAlidUrl(product.photo),
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: AddIconButton(
                    productModel: product,
                    size: 30.0,
                    margin: EdgeInsets.zero,
                    onCartUpdated: updatePrice,
                    isRestaurantOpen: isOpen,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${amountShow(amount: product.price.toString())}",
                  style: TextStyle(
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
    );
  }

  Widget _buildSectionTileHeader(VendorCategoryModel category) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Text(
        category.title.toString(),
        style: const TextStyle(
            color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  var isAnother = 0;

  // Veg/Non-veg variables removed

  Widget _buildFoodTileList(
      BuildContext context, VendorCategoryModel category) {
    // Pre-filter products by category - O(m) instead of O(n*m)
    final categoryProducts = productModel
        .where((product) => product.categoryID == category.id)
        .toList();

    if (categoryProducts.isEmpty) {
      return showEmptyState("No Food are available.", context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categoryProducts.length,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            return buildRow(
              categoryProducts[index],
              false, // veg parameter (unused)
              false, // nonveg parameter (unused)
              categoryProducts[index].categoryID,
              (index == (categoryProducts.length - 1)),
            );
          },
          separatorBuilder: (context, index) {
            return SizedBox(
              height: 0,
              child: Divider(
                color: CustomColors.lightGray300,
                thickness: 0.5,
              ),
            );
          },
        ),
      ],
    );
  }

  buildRow(ProductModel productModel, veg, nonveg, inx, bool index) {
    // Simplified - show all products without veg/non-veg filtering
    isAnother++;
    return datarow(productModel);
  }

  late CartDatabase cartDatabase;

  late List<CartProduct> cartProducts = [];

  double priceTemp = 0.0;

  datarow(ProductModel productModel) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {},
      child: CommonElevatedButton(
        backgroundColor: Colors.transparent,
        borderRadius: BorderRadius.zero,
        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
        onButtonPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => ProductDetailsScreen(
                    productModel: productModel,
                    vendorModel: widget.vendorModel,
                  )));
        },
        custom: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                productModel.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontFamily: "Poppinssb",
                    fontWeight: FontWeight.w600,
                    color: Colors.black),
              ),
              const SizedBox(height: 5),
              Row(
                children: <Widget>[
                  productModel.disPrice == "" || productModel.disPrice == "0"
                      ? Expanded(
                          child: Text(
                            "${amountShow(amount: productModel.price.toString())}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: CustomColors.primary,
                                fontSize: 16.0,
                                fontWeight: FontWeight.w600),
                          ),
                        )
                      : Row(
                          children: [
                            Text(
                              "${amountShow(amount: productModel.disPrice.toString())}",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(COLOR_PRIMARY),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              "${amountShow(amount: productModel.price.toString())}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  decoration: TextDecoration.lineThrough),
                            ),
                          ],
                        ),
                ],
              ),
              if (productModel.description.isNotEmpty)
                const SizedBox(height: 5),
              if (productModel.description.isNotEmpty)
                Text(
                  productModel.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w400),
                ),
              if (productModel.reviewsCount != 0) const SizedBox(height: 5),
              if (productModel.reviewsCount != 0)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                            (productModel.reviewsSum /
                                    productModel.reviewsCount)
                                .toStringAsFixed(1),
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
            ],
          )),
          const SizedBox(width: 10.0),
          Stack(
            alignment: Alignment.topLeft,
            clipBehavior: Clip.none,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                clipBehavior: Clip.none,
                children: [
                  CommonNetworkImage(
                    height: 120,
                    width: 120,
                    imageUrl: getImageVAlidUrl(productModel.photo),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  AddIconButton(
                    productModel: productModel,
                    size: 30.0,
                    onCartUpdated: updatePrice,
                    isRestaurantOpen: isOpen,
                  )
                ],
              ),
              // Veg/Non-veg indicator removed
            ],
          ),
        ]),
      ),
    );
  }

  // Veg/Non-veg switches removed

  buildVeg(veg, nonveg) {
    // Veg/Non-veg options removed - return empty container
    return Container();
  }

  bool isOpen = false;

  statusCheck() {
    final now = new DateTime.now();

    var day = DateFormat('EEEE', 'en_US').format(now);

    var date = DateFormat('dd-MM-yyyy').format(now);

    widget.vendorModel.workingHours.forEach((element) {
      print("===>");

      print(element);

      if (day == element.day.toString()) {
        print("---->1" + element.day.toString());

        if (element.timeslot!.isNotEmpty) {
          element.timeslot!.forEach((element) {
            print("===>2");

            print(element);

            var start = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + element.from.toString());

            var end = DateFormat("dd-MM-yyyy HH:mm")
                .parse(date + " " + element.to.toString());

            if (isCurrentDateInRange(start, end)) {
              print("===>1");

              setState(() {
                isOpen = true;

                print("===>");

                print(isOpen);
              });
            }
          });
        }
      }
    });
  }

  bool isCurrentDateInRange(DateTime startDate, DateTime endDate) {
    print(startDate);

    print(endDate);

    final currentDate = DateTime.now();

    print(currentDate);

    return currentDate.isAfter(startDate) && currentDate.isBefore(endDate);
  }

  void updatePrice() {
    List<CartProduct> cartProducts = [];

    Future.delayed(const Duration(milliseconds: 500), () {
      cartProducts.clear();

      cartDatabase.allCartProducts.then((value) {
        priceTemp = 0;

        cartProducts.addAll(value);

        for (int i = 0; i < cartProducts.length; i++) {
          CartProduct e = cartProducts[i];

          if (e.extras_price != null &&
              e.extras_price != "" &&
              double.parse(e.extras_price!) != 0) {
            priceTemp += double.parse(e.extras_price!) * e.quantity;
          }

          priceTemp += double.parse(e.price) * e.quantity;
        }

        setState(() {});
      });
    });
  }
}
