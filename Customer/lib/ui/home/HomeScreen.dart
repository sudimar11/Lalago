import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:clipboard/clipboard.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:foodie_customer/AppGlobal.dart';

import 'package:foodie_customer/constants.dart';

import 'package:foodie_customer/main.dart';

import 'package:foodie_customer/model/AddressModel.dart';

import 'package:foodie_customer/model/BannerModel.dart';

import 'package:foodie_customer/model/FavouriteModel.dart';

import 'package:foodie_customer/model/ProductModel.dart';

import 'package:foodie_customer/model/User.dart';

import 'package:foodie_customer/model/VendorCategoryModel.dart';

import 'package:foodie_customer/model/VendorModel.dart';

import 'package:foodie_customer/model/offer_model.dart';

import 'package:foodie_customer/model/OrderModel.dart';

import 'package:foodie_customer/model/story_model.dart';

import 'package:foodie_customer/services/FirebaseHelper.dart';

import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';

import 'package:foodie_customer/services/coupon_service.dart';

import 'package:foodie_customer/services/localDatabase.dart';

import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/categoryDetailsScreen/CategoryDetailsScreen.dart';

import 'package:foodie_customer/ui/cuisinesScreen/CuisinesScreen.dart';

import 'package:foodie_customer/ui/deliveryAddressScreen/DeliveryAddressScreen.dart';

import 'package:foodie_customer/ui/home/view_all_category_product_screen.dart';

import 'package:foodie_customer/ui/home/view_all_new_arrival_restaurant_screen.dart';
import 'package:foodie_customer/ui/home/view_all_offer_screen.dart';
import 'package:foodie_customer/ui/promos/PromosScreen.dart';

import 'package:foodie_customer/ui/home/view_all_popular_food_near_by_screen.dart';

import 'package:foodie_customer/ui/home/view_all_popular_restaurant_screen.dart';

import 'package:foodie_customer/ui/home/view_all_restaurant.dart';
import 'package:foodie_customer/ui/home/view_all_sulit_foods_screen.dart';
import 'package:foodie_customer/ui/home/favourite_restaurant.dart';
import 'package:foodie_customer/ui/chat_screen/inbox_driver_screen.dart';
import 'package:foodie_customer/ui/home/sections/top_restaurants_section.dart';
import 'package:foodie_customer/ui/home/sections/category_restaurants_section.dart';
import 'package:foodie_customer/ui/home/sections/all_restaurants_section.dart';
import 'package:foodie_customer/ui/home/sections/new_arrival_card.dart';
import 'package:foodie_customer/ui/home/sections/populars_card.dart';
import 'package:foodie_customer/ui/home/sections/meal_for_one_section.dart';
import 'package:foodie_customer/ui/home/sections/nearby_restaurants_section.dart';
import 'package:foodie_customer/ui/home/sections/new_restaurants_section.dart';
import 'package:foodie_customer/ui/home/sections/categories_horizontal_section.dart';
import 'package:foodie_customer/ui/home/sections/home_nearby_foods_section.dart';
import 'package:foodie_customer/ui/home/sections/home_popular_today_section.dart';
import 'package:foodie_customer/ui/home/sections/home_header_section.dart';
import 'package:foodie_customer/ui/home/sections/banner_section.dart';

import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';

import 'package:foodie_customer/ui/searchScreen/SearchScreen.dart';

import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';

import 'package:foodie_customer/widget/permission_dialog.dart';
import 'package:foodie_customer/widget/product_status_badge.dart';
import 'package:foodie_customer/widget/category_card.dart';
import 'package:foodie_customer/widget/recommended_section.dart';

import 'package:geocoding/geocoding.dart';

import 'package:geolocator/geolocator.dart';

import 'package:location/location.dart' as loc;

import 'package:location/location.dart';

import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:story_view/story_view.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:google_maps_place_picker_mb/google_maps_place_picker.dart';
import 'package:foodie_customer/ui/home/food_varieties.dart';
import 'package:foodie_customer/ui/home/home_content_stack.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
import 'package:foodie_customer/widget/lazy_loading_widget.dart';
import 'package:foodie_customer/ui/home/more_stories_screen.dart';
import 'package:foodie_customer/ui/dialogs/PostCompletionDialog.dart';
import 'package:foodie_customer/userPrefrence.dart';

class HomeScreen extends StatefulWidget {
  final User? user;

  HomeScreen({Key? key, this.user}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  //String lastSearch = '';
  late List<ProductModel> allProducts = [];
  List<ProductModel> recommendedProducts = [];
  final fireStoreUtils = FireStoreUtils();

  // Safety flag to prevent setState after navigation
  bool _isLeavingHome = false;

  /// Call this method before navigating away from HomeScreen
  void setLeavingHome() {
    _isLeavingHome = true;
  }

  @override
  void deactivate() {
    // Set flag when widget is being deactivated
    _isLeavingHome = true;
    super.deactivate();
  }

  late Future<List<ProductModel>> productsFuture;

  // final PageController _controller =
  //     PageController(viewportFraction: 0.8, keepPage: true);

  List<VendorModel> vendors = [];
  List<VendorModel> recommendedVendors = [];
  List<VendorModel> mostRatedRestaurantsFallback = [];
  List<VendorModel> nearbyFoodVendors = [];
  List<VendorModel> popularTodayVendors = [];

  List<VendorModel> validRestaurants = [];
  List<VendorModel> popularRestaurantLst = [];

  List<VendorModel> newArrivalLst = [];

  List<VendorModel> offerVendorList = [];

  List<OfferModel> offersList = [];

  Stream<List<VendorModel>>? lstAllRestaurant;

  List<ProductModel> lstNearByFood = [];
  List<ProductModel> popularTodayFoods = [];

  // Order Again section
  List<ProductModel> orderAgainProducts = [];
  bool isLoadingOrderAgain = true;
  StreamSubscription<List<OrderModel>>? orderAgainStreamSubscription;

  bool _didRunNearbyFallback = false;
  bool _didRunRecommendedFallback = false;
  bool _didLogRecommendedVendorEmpty = false;
  bool _didRunPopularTodayFallback = false;
  bool _isLoadingPopularToday = false;

  // Completion dialog tracking
  StreamSubscription<List<OrderModel>>? _completionDialogStreamSubscription;
  Set<String> _processedCompletedOrders = {};
  bool _isCompletionDialogOpen = false;
  String? _lastCompletionDialogOrderId;
  DateTime? _lastCompletionDialogAt;
  bool _isCompletionDialogListenerSetup = false;

  // Restaurant stream subscription management
  StreamSubscription<List<VendorModel>>? _restaurantStreamSubscription;
  bool _isProcessingRestaurants = false;
  Timer? _setStateDebounceTimer;
  bool _pendingStateUpdate = false;

  /// Unified state update method with intelligent debouncing
  ///
  /// [callback] - Optional callback for state updates (executed immediately)
  /// [immediate] - If true, bypasses debouncing for critical updates
  void _updateState({VoidCallback? callback, bool immediate = false}) {
    if (!mounted || _isLeavingHome) return;

    // Execute callback immediately if provided
    if (callback != null) {
      callback();
    }

    if (immediate) {
      // Cancel any pending debounced update
      _setStateDebounceTimer?.cancel();
      _pendingStateUpdate = false;
      // Trigger immediate rebuild
      setState(() {});
    } else {
      // Debounce the rebuild
      if (_pendingStateUpdate) return; // Already queued

      _pendingStateUpdate = true;
      _setStateDebounceTimer?.cancel();
      _setStateDebounceTimer = Timer(const Duration(milliseconds: 100), () {
        if (mounted && !_isLeavingHome && _pendingStateUpdate) {
          setState(() {});
          _pendingStateUpdate = false;
        }
      });
    }
  }

  Future<void> _runNearbyFoodsFallback(
    List<ProductModel> products, {
    required String trigger,
  }) async {
    if (_didRunNearbyFallback || !mounted || _isLeavingHome) return;
    _didRunNearbyFallback = true;

    final List<ProductModel> topProducts = products.take(20).toList();
    final List<Future<VendorModel?>> vendorFutures = topProducts
        .map((product) => FireStoreUtils.getVendor(product.vendorID))
        .toList();
    final List<VendorModel?> fetchedVendors = await Future.wait(vendorFutures);
    final Map<String, VendorModel> allVendorMap = {
      for (var vendor in fetchedVendors)
        if (vendor != null) vendor.id: vendor,
    };

    nearbyFoodVendors
      ..clear()
      ..addAll(allVendorMap.values);

    int fallbackVendorMissing = 0;
    int fallbackAdded = 0;
    for (var product in topProducts) {
      final vendor = allVendorMap[product.vendorID];
      if (vendor == null) {
        fallbackVendorMissing++;
        continue;
      }
      if (!lstNearByFood.contains(product)) {
        lstNearByFood.add(product);
        fallbackAdded++;
      }
    }

    _updateState();
  }

  Future<void> _updatePopularTodayProducts(
    List<ProductModel> products,
  ) async {
    if (!mounted || _isLeavingHome) return;
    final Set<String> vendorIds = products
        .map((product) => product.vendorID)
        .where((id) => id.isNotEmpty)
        .toSet();
    final List<Future<VendorModel?>> vendorFutures = vendorIds
        .map((vendorId) => FireStoreUtils.getVendor(vendorId))
        .toList();
    final List<VendorModel?> fetchedVendors = await Future.wait(vendorFutures);
    if (!mounted || _isLeavingHome) return;

    popularTodayVendors
      ..clear()
      ..addAll(fetchedVendors.whereType<VendorModel>());
    popularTodayFoods
      ..clear()
      ..addAll(products);

    _updateState();
  }

  Future<void> _runPopularTodayFallback(
    List<ProductModel> products, {
    required String trigger,
  }) async {
    if (_didRunPopularTodayFallback || !mounted || _isLeavingHome) return;
    _didRunPopularTodayFallback = true;

    final List<ProductModel> topProducts = products.take(20).toList();
    await _updatePopularTodayProducts(topProducts);
  }

  Future<void> _loadPopularToday(List<ProductModel> products) async {
    if (!mounted || _isLeavingHome) return;
    final List<String> topTodayIds =
        await fireStoreUtils.getMostOrderedProductIdsForToday();
    if (!mounted || _isLeavingHome) return;

    final Map<String, ProductModel> productMap = {
      for (var product in products) product.id: product,
    };
    final List<ProductModel> todayProducts = topTodayIds
        .map((id) => productMap[id])
        .whereType<ProductModel>()
        .toList();

    if (todayProducts.isEmpty) {
      final List<String> topYesterdayIds =
          await fireStoreUtils.getMostOrderedProductIdsForYesterday();
      if (!mounted || _isLeavingHome) return;
      final List<ProductModel> yesterdayProducts = topYesterdayIds
          .map((id) => productMap[id])
          .whereType<ProductModel>()
          .toList();
      if (yesterdayProducts.isEmpty) {
        await _runPopularTodayFallback(
          products,
          trigger: 'no_today_or_yesterday_orders',
        );
        return;
      }

      await _updatePopularTodayProducts(yesterdayProducts);
      return;
    }

    await _updatePopularTodayProducts(todayProducts);
  }

  // Promos section
  List<OfferModel> activePromos = [];
  bool isLoadingPromos = true;

  // Additional timers and subscriptions that need cleanup
  Timer? _debounceTimer;
  StreamSubscription? _connectivitySubscription;

  // ScrollController for home screen scroll detection (for lazy loading)
  final ScrollController _homeScrollController = ScrollController();

  // Cache for restaurant open/closed status to avoid expensive recalculations
  final Map<String, bool> _restaurantOpenStatusCache = {};
  String _currentCacheHourKey = '';

  // Meal for One • Sulit price section
  List<ProductModel> mealForOneProducts = [];
  bool isLoadingMealForOne = true;
  List<VendorModel> mealForOneVendors = [];
  static const double sulitCap = 150.0; // Price cap for sulit meals (in pesos)

  //Stream<List<FavouriteModel>>? lstFavourites;

  late Future<List<FavouriteModel>> lstFavourites;

  List<String> lstFav = [];

  String? name = "";

  String? selctedOrderTypeValue = "Delivery";

  bool isLocationPermissionAllowed = false;

  loc.Location location = loc.Location();

  // Database db;

  // Rotating hint variables
  List<String> rotatingHints = [
    'Nag lalawag lamay?',
    'Search Tiyulah itum',
    'May cravings ka?',
    'Search restaurant',
    'Search shawarma',
    'Search pizza',
    'Mahapdi na?',
    'Search mo way biddah'
  ];

  List<VendorCategoryModel> categoryWiseProductList = [];

  List<BannerModel> bannerTopHome = [];

  List<BannerModel> bannerMiddleHome = [];

  bool isHomeBannerLoading = true;

  bool isHomeBannerMiddleLoading = true;

  final CarouselSliderController _carouselController =
      CarouselSliderController();

  List<BannerModel> _cachedFilteredBanners = [];

  static const _carouselKey = PageStorageKey('home_banner_carousel');

  CarouselOptions? _cachedCarouselOptions;

  int _currentBannerIndex = 0;

  bool _isCarouselRestored = false;

  bool _userInteractedWithCarousel = false;

  // Cache-first image loading state
  Map<String, File> _cachedBannerFiles = {};

  bool _areBannerImagesCached = false;

  bool _isCachingBannerImages = false;

  // Cached carousel items list to prevent recreation on rebuilds
  List<Widget>? _cachedCarouselItems;

  // Build-time computation caches
  Map<String, VendorModel>? _cachedVendorMap;
  Map<String, String> _cachedRatings = {}; // vendorId -> rating string
  Map<String, String> _cachedDiscountTexts = {}; // offerId -> discount text
  Future<List<StoryModel>>? _cachedStoriesFuture;
  Map<String, Future<VendorModel>>? _cachedVendorFutures; // vendorId -> Future
  Future<List<VendorCategoryModel>>? _cachedCuisinesFuture;
  Stream<List<VendorModel>>? _cachedNewArrivalStream;
  Stream<List<VendorModel>>? _cachedNewestRestaurantsStream;

  // Cached callbacks for HomeHeaderSection
  late final VoidCallback _onSearchTap;
  late final VoidCallback _onMessageTap;
  late final VoidCallback _onFavoriteTap;

  // Cached callback for favorite changes
  late final VoidCallback _onFavoriteChanged;

  // Cached callback for Order Again section
  late final VoidCallback _onOrderAgainViewAll;

  // Cached method reference for BannerSection
  late final Widget Function(BuildContext, VendorModel?, OfferModel)
      _buildCouponsForYouItemCached;

  void _updateCachedFilteredBanners() {
    final previousLength = _cachedFilteredBanners.length;
    _cachedFilteredBanners = bannerTopHome
        .where((banner) =>
            banner.isPublish == true &&
            banner.photo != null &&
            banner.photo!.isNotEmpty)
        .toList()
      ..sort((a, b) => (a.setOrder ?? 0).compareTo(b.setOrder ?? 0));

    // Clamp index when banner list length changes
    final newLen = _cachedFilteredBanners.length;

    // Check if there are new banners that need caching
    if (newLen > 0 && _areBannerImagesCached) {
      final newBannerUrls = _cachedFilteredBanners
          .where((banner) =>
              banner.photo != null &&
              !_cachedBannerFiles.containsKey(banner.photo))
          .map((banner) => banner.photo!)
          .toList();

      if (newBannerUrls.isNotEmpty) {
        // Reset cache flag to show placeholder while new images are cached
        _areBannerImagesCached = false;
        _cachedCarouselItems = null; // Clear cached items
        // Trigger re-caching of new images (will be called from getBanner or can be called here)
        if (mounted && !_isLeavingHome) {
          _downloadAndCacheBannerImages().then((_) {
            if (mounted && !_isLeavingHome) {
              _updateState();
            }
          });
        }
      } else if (newLen != previousLength) {
        // Banner list changed but all images are already cached - rebuild items
        _rebuildCarouselItems();
      }
    } else if (newLen == 0) {
      // No banners - clear cached items
      _cachedCarouselItems = null;
    }

    if (newLen == 0) {
      _currentBannerIndex = 0;
      _areBannerImagesCached = false;
    } else if (_currentBannerIndex >= newLen) {
      _currentBannerIndex = newLen - 1;
    }

    // Only reset restore flag if length changed AND user hasn't interacted
    // Don't reset _userInteractedWithCarousel to preserve user's scroll position
    if (newLen != previousLength && !_userInteractedWithCarousel) {
      _isCarouselRestored = false;
    }

    // Only recreate CarouselOptions if the list length changed AND user hasn't interacted
    // CRITICAL: Once CarouselOptions are created, NEVER recreate them to avoid resetting the carousel
    if (_cachedFilteredBanners.length != previousLength &&
        !_userInteractedWithCarousel) {
      // Only create options if they don't exist yet (first time)
      // Once created, never recreate - let the carousel handle item changes naturally
      if (_cachedCarouselOptions == null && newLen > 0) {
        // First time loading banners - create options once
        _cachedCarouselOptions = CarouselOptions(
          height: 170,
          viewportFraction: 1.0,
          initialPage: 0,
          autoPlay: true,
          autoPlayInterval: Duration(seconds: 3),
          autoPlayAnimationDuration: Duration(milliseconds: 800),
          autoPlayCurve: Curves.easeInOut,
          enlargeCenterPage: false,
          aspectRatio: 16 / 9,
          enableInfiniteScroll: _cachedFilteredBanners.length > 1,
          pauseAutoPlayOnTouch: true,
          pauseAutoPlayOnManualNavigate: true,
          onPageChanged: _onBannerPageChanged,
        );
      }
    } else if (_cachedCarouselOptions == null) {
      // Initialize on first call (fallback if above condition didn't catch it)
      _cachedCarouselOptions = CarouselOptions(
        height: 170,
        viewportFraction: 1.0,
        initialPage: _currentBannerIndex,
        autoPlay: true,
        autoPlayInterval: Duration(seconds: 3),
        autoPlayAnimationDuration: Duration(milliseconds: 800),
        autoPlayCurve: Curves.easeInOut,
        enlargeCenterPage: false,
        aspectRatio: 16 / 9,
        enableInfiniteScroll: _cachedFilteredBanners.length > 1,
        pauseAutoPlayOnTouch: true,
        pauseAutoPlayOnManualNavigate: true,
        onPageChanged: _onBannerPageChanged,
      );
    }

    // Only restore carousel page if user hasn't interacted
    // This prevents the carousel from jumping after user swipes
    if (!_userInteractedWithCarousel) {
      _restoreCarouselPage();
    }
  }

  Future<void> _downloadAndCacheBannerImages() async {
    if (_isCachingBannerImages || _cachedFilteredBanners.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    _isCachingBannerImages = true;

    try {
      // Filter valid banners with non-null, non-empty photo URLs
      final validBanners = _cachedFilteredBanners
          .where((banner) =>
              banner.photo != null &&
              banner.photo!.isNotEmpty &&
              Uri.tryParse(banner.photo!) != null)
          .toList();

      if (validBanners.isEmpty) {
        _areBannerImagesCached = true;
        _isCachingBannerImages = false;
        return;
      }

      final cacheManager = DefaultCacheManager();

      // Download all images in parallel
      final results = await Future.wait(
        validBanners.map((banner) async {
          try {
            final imageUrl = banner.photo!;
            // getSingleFile automatically checks cache first and downloads if needed
            final file = await cacheManager.getSingleFile(imageUrl);
            return MapEntry(imageUrl, file);
          } catch (e) {
            return null;
          }
        }),
      );

      // Filter out null results (failed downloads) and build the map
      final successfulCaches =
          results.whereType<MapEntry<String, File>>().toList();

      if (!mounted) {
        _isCachingBannerImages = false;
        return;
      }

      // Update cached files map
      _cachedBannerFiles = Map.fromEntries(successfulCaches);
      _areBannerImagesCached = true;

      // Rebuild carousel items when images are cached
      _rebuildCarouselItems();
    } catch (e) {
    } finally {
      _isCachingBannerImages = false;
    }
  }

  void _rebuildCarouselItems() {
    if (_cachedFilteredBanners.isEmpty || !_areBannerImagesCached) {
      _cachedCarouselItems = null;
      return;
    }

    // Filter banners to only include those with cached files
    final bannersWithCachedFiles = _cachedFilteredBanners
        .where((banner) =>
            banner.photo != null &&
            _cachedBannerFiles.containsKey(banner.photo))
        .toList();

    if (bannersWithCachedFiles.isEmpty) {
      _cachedCarouselItems = null;
      return;
    }

    // Build carousel items once and cache them
    _cachedCarouselItems = bannersWithCachedFiles.asMap().entries.map((entry) {
      final index = entry.key;
      final banner = entry.value;
      final cachedFile = _cachedBannerFiles[banner.photo!];
      return Container(
        key: ValueKey('banner_${banner.photo}_$index'),
        width: double.infinity,
        child: SizedBox.expand(
          child: Image.file(
            cachedFile!,
            key: ValueKey('banner_image_${banner.photo}'),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return SizedBox.expand(
                child: Container(
                  color: Colors.grey[300],
                  child: Icon(Icons.image_not_supported),
                ),
              );
            },
          ),
        ),
      );
    }).toList();
  }

  void _onBannerPageChanged(int index, CarouselPageChangedReason reason) {
    if (!mounted) {
      return;
    }

    _currentBannerIndex = index;

    if (reason == CarouselPageChangedReason.manual) {
      _userInteractedWithCarousel = true;
      // Only call setState for manual interactions
      _updateState();
    }
  }

  void _restoreCarouselPage() {
    if (_isCarouselRestored) {
      return;
    }
    if (_userInteractedWithCarousel) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_userInteractedWithCarousel) {
        return; // Double check
      }
      if (_carouselController.ready) {
        _carouselController.jumpToPage(_currentBannerIndex);
        _isCarouselRestored = true;
      }
    });
  }

  CarouselOptions get _carouselOptions {
    // If cached options exist, use them to avoid resetting the carousel
    if (_cachedCarouselOptions != null) {
      return _cachedCarouselOptions!;
    }

    // Only set initialPage if user hasn't interacted
    // This prevents the carousel from resetting after user swipes
    return CarouselOptions(
      height: 170,
      viewportFraction: 1.0,
      initialPage: _currentBannerIndex,
      autoPlay: true,
      autoPlayInterval: Duration(seconds: 3),
      autoPlayAnimationDuration: Duration(milliseconds: 800),
      autoPlayCurve: Curves.easeInOut,
      enlargeCenterPage: false,
      aspectRatio: 16 / 9,
      enableInfiniteScroll: _cachedFilteredBanners.length > 1,
      pauseAutoPlayOnTouch: true,
      pauseAutoPlayOnManualNavigate: true,
      onPageChanged: _onBannerPageChanged,
    );
  }

  List<OfferModel> offerList = [];

  bool? storyEnable = false;

  @override
  void initState() {
    super.initState();

    if (FireStoreUtils.isMessagingEnabled && MyAppState.currentUser != null) {
      unawaited(FireStoreUtils.refreshFcmTokenForUser(MyAppState.currentUser!));
    }

    // Initialize cached callbacks
    _onSearchTap = () {
      push(
        context,
        const SearchScreen(shouldAutoFocus: true),
      );
    };

    _onMessageTap = () {
      if (MyAppState.currentUser == null) {
        push(context, LoginScreen());
      } else {
        push(context, InboxDriverScreen());
      }
    };

    _onFavoriteTap = () {
      if (MyAppState.currentUser == null) {
        push(context, LoginScreen());
      } else {
        push(context, FavouriteRestaurantScreen());
      }
    };

    _onFavoriteChanged = () {
      _updateState();
    };

    _onOrderAgainViewAll = () {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order Again feature coming soon!'),
          duration: Duration(seconds: 2),
        ),
      );
    };

    // Cache method reference
    _buildCouponsForYouItemCached = buildCouponsForYouItem;

    _loadInitialData();

    // Defer heavy operations until after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isLeavingHome) {
          _loadSecondaryData();
        }
      });
    });
  }

  /// Load critical data for initial render
  Future<void> _loadInitialData() async {
    // Only minimal critical data for initial render
    // Location check only (no heavy operations)
    await getLocationData();

    // Check for default address after user data is loaded
    _setDefaultAddressIfNeeded();
  }

  /// Load heavy operations that can wait
  /// Staggered sequential loading to reduce memory/GC pressure
  Future<void> _loadSecondaryData() async {
    // Phase 1: Load products first (needed for order again)
    await fetchAllProducts();
    if (!mounted || _isLeavingHome) return;

    // Phase 2: Wait 300ms, then load banners
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && !_isLeavingHome) {
      await getBanner();
    }
    if (!mounted || _isLeavingHome) return;

    // Phase 3: Wait another 300ms, then start restaurant stream
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && !_isLeavingHome) {
      await getData();
    }
    if (!mounted || _isLeavingHome) return;

    // Phase 4: Wait another 300ms, then setup completion dialog listener
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted && !_isLeavingHome) {
      _setupCompletionDialogListener();
    }

    // Phase 5: Load promos (lightweight, can run independently)
    if (mounted && !_isLeavingHome) {
      _loadActivePromos(); // Don't await - let it run independently
    }

    // Phase 6: Recommendations (depends on products)
    if (mounted && !_isLeavingHome) {
      fetchLastSearchAndUpdateRecommendations();
    }

    // Initialize cuisine future once
    _cachedCuisinesFuture = fireStoreUtils.getCuisines();

    // Initialize new arrival stream once
    _cachedNewArrivalStream =
        fireStoreUtils.getVendorsForNewArrival().asBroadcastStream();
    // Newest restaurants by createdAt for "New Restaurants" section
    _cachedNewestRestaurantsStream =
        fireStoreUtils.getNewestRestaurantsStream(limit: 15).asBroadcastStream();
    await _loadMostRatedRestaurantsFallback();


    // Initialize stories future once
    _cachedStoriesFuture = FireStoreUtils().getStory();
  }

  Future<void> _loadMostRatedRestaurantsFallback() async {
    if (!mounted || _isLeavingHome) return;
    try {
      final vendorsFallback = await fireStoreUtils.getVendors();
      vendorsFallback.sort((a, b) {
        final double ratingA =
            a.reviewsCount != 0 ? (a.reviewsSum / a.reviewsCount) : 0.0;
        final double ratingB =
            b.reviewsCount != 0 ? (b.reviewsSum / b.reviewsCount) : 0.0;
        final int ratingComparison = ratingB.compareTo(ratingA);
        if (ratingComparison != 0) return ratingComparison;
        return b.reviewsCount.compareTo(a.reviewsCount);
      });

      if (!mounted || _isLeavingHome) return;
      _updateState(callback: () {
        mostRatedRestaurantsFallback = vendorsFallback;
      });
    } catch (e) {
    }
  }


  /// Load active promos/coupons
  Future<void> _loadActivePromos() async {
    if (!mounted || _isLeavingHome) return;

    _updateState(callback: () {
      isLoadingPromos = true;
    });

    try {
      final coupons = await CouponService.getActiveCoupons(null);
      if (mounted && !_isLeavingHome) {
        _updateState(callback: () {
          activePromos = coupons;
          isLoadingPromos = false;
        });
        // Rebuild caches after promos load
        _rebuildComputationCaches();
      }
    } catch (e) {
      if (mounted && !_isLeavingHome) {
        _updateState(callback: () {
          isLoadingPromos = false;
        });
      }
    }
  }

  /// Set the default address from user's shipping addresses if available
  void _setDefaultAddressIfNeeded() {
    if (MyAppState.currentUser != null &&
        MyAppState.currentUser!.shippingAddress != null &&
        MyAppState.currentUser!.shippingAddress!.isNotEmpty) {
      // Find the default address
      AddressModel? defaultAddress;
      try {
        defaultAddress = MyAppState.currentUser!.shippingAddress!
            .firstWhere((address) => address.isDefault == true);
      } catch (e) {
        // No default address found, use first address as fallback
        defaultAddress = MyAppState.currentUser!.shippingAddress!.first;
      }

      // Only update if selectedPosotion is empty or different
      bool shouldUpdate = false;
      if (MyAppState.selectedPosotion.location == null ||
          (MyAppState.selectedPosotion.location!.latitude == 0 &&
              MyAppState.selectedPosotion.location!.longitude == 0)) {
        shouldUpdate = true;
      } else if (defaultAddress.id != null &&
          MyAppState.selectedPosotion.id != null &&
          defaultAddress.id != MyAppState.selectedPosotion.id) {
        shouldUpdate = true;
      }

      if (shouldUpdate) {
        MyAppState.selectedPosotion = defaultAddress;
        if (mounted && !_isLeavingHome) {
          _updateState();
        }
      }
    }
  }

  void _rebuildComputationCaches() {
    // Rebuild vendor map
    _cachedVendorMap = {for (var vendor in vendors) vendor.id: vendor};

    // Rebuild rating cache
    _cachedRatings.clear();
    for (var vendor in vendors) {
      _cachedRatings[vendor.id] = vendor.reviewsCount != 0
          ? '${(vendor.reviewsSum / vendor.reviewsCount).toStringAsFixed(1)}'
          : '0.0';
    }

    // Rebuild discount text cache
    _cachedDiscountTexts.clear();
    for (var promo in activePromos) {
      if (promo.offerId != null) {
        _cachedDiscountTexts[promo.offerId!] = _getPromoDiscountText(promo);
      }
    }

    // Rebuild vendor futures map for stories
    _cachedVendorFutures = {};
  }

  Future<void> _refreshHomeData() async {
    if (!mounted || _isLeavingHome) return;

    try {
      // Run independent operations in parallel
      await Future.wait<void>([
        getBanner(),
        fetchAllProducts(), // Already calls fetchOrderAgainProducts & fetchMealForOneProducts internally
        getData(),
      ]);

      // Run dependent operation after parallel fetch completes
      fetchLastSearchAndUpdateRecommendations();
    } catch (e) {
      if (mounted && !_isLeavingHome) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh data'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  getBanner() async {
    // Run all banner/category/offer fetches in parallel
    final results = await Future.wait([
      fireStoreUtils.getHomeTopBanner(),
      fireStoreUtils.getHomePageShowCategory(),
      fireStoreUtils.getHomeMiddleBanner(),
      FireStoreUtils().getPublicCoupons(),
      FirebaseFirestore.instance.collection(Setting).doc('story').get(),
    ]);

    if (!mounted || _isLeavingHome) {
      return;
    }

    // Batch all setState calls into one for better performance
    _updateState(callback: () {
      bannerTopHome = results[0] as List<BannerModel>;
      _updateCachedFilteredBanners();

      categoryWiseProductList = results[1] as List<VendorCategoryModel>;
      debugPrint(
          '📱 HomeScreen.getBanner(): categoryWiseProductList assigned ${categoryWiseProductList.length} categories');
      for (int i = 0; i < categoryWiseProductList.length; i++) {
        debugPrint(
            '  [$i] id="${categoryWiseProductList[i].id}" title="${categoryWiseProductList[i].title}"');
      }

      bannerMiddleHome = results[2] as List<BannerModel>;
      isHomeBannerMiddleLoading = false;

      offerList = results[3] as List<OfferModel>;

      final storyDoc = results[4] as DocumentSnapshot<Map<String, dynamic>>;
      storyEnable = storyDoc.data()?['isEnabled'] as bool? ?? false;
    });

    // Download and cache all banner images to disk before showing carousel
    if (mounted && !_isLeavingHome) {
      await _downloadAndCacheBannerImages();

      if (mounted && !_isLeavingHome) {
        // Only set loading to false after images are cached
        _updateState(callback: () {
          isHomeBannerLoading = false;
        });
      }
    } else {
      // If not mounted, still set loading to false to prevent stuck state
      if (mounted) {
        _updateState(callback: () {
          isHomeBannerLoading = false;
        });
      }
    }
  }

  Future<void> fetchAllProducts() async {
    List<ProductModel> products = await fireStoreUtils.fetchAllProducts();
    if (!mounted || _isLeavingHome) return;
    _updateState(callback: () {
      allProducts = products; // Populate global product list
    });
    generateRecommendations(); // Generate initial recommendations
    fetchOrderAgainProducts(); // Fetch order again products after load
    fetchMealForOneProducts(); // Fetch meal for one products after load
  }

  void fetchLastSearchAndUpdateRecommendations() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Fetch the last search term
    String lastSearch = prefs.getString('lastSearch') ?? '';

    // Filter recommendations based on the last search term
    if (!mounted || _isLeavingHome) return;
    _updateState(callback: () {
      recommendedProducts = allProducts.where((product) {
        return product.name.toLowerCase().contains(lastSearch.toLowerCase());
      }).toList();
    });
  }

  void generateRecommendations() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Fetch the last search term
    String lastSearch = prefs.getString('lastSearch') ?? '';

    // Initialize recommendations list
    List<ProductModel> recommendations = [];

    // Add products matching the last search term
    if (lastSearch.isNotEmpty) {
      recommendations.addAll(allProducts.where((product) =>
          product.name.toLowerCase().contains(lastSearch.toLowerCase())));
    }

    // Add frequently ordered products (mock logic placeholder).
    // Replace with actual user activity tracking.
    List<String> frequentOrders = [
      'product1',
      'product2',
    ]; // Example product IDs
    recommendations.addAll(
        allProducts.where((product) => frequentOrders.contains(product.id)));

    if (recommendations.isEmpty &&
        lastSearch.isEmpty &&
        !_didRunRecommendedFallback) {
      _didRunRecommendedFallback = true;
      final List<String> topTodayIds =
          await fireStoreUtils.getMostOrderedProductIdsForToday();
      final Map<String, ProductModel> productMap = {
        for (var product in allProducts) product.id: product,
      };
      recommendations = topTodayIds
          .map((id) => productMap[id])
          .whereType<ProductModel>()
          .toList();

    }

    // Final fallback: fill with all products if still empty
    if (recommendations.isEmpty && allProducts.isNotEmpty) {
      recommendations.addAll(allProducts);
      recommendations.shuffle();
    }

    final Set<String> vendorIds = recommendations
        .map((product) => product.vendorID)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (vendorIds.isNotEmpty) {
      final List<Future<VendorModel?>> vendorFutures = vendorIds
          .map((vendorId) => FireStoreUtils.getVendor(vendorId))
          .toList();
      final List<VendorModel?> fetchedVendors =
          await Future.wait(vendorFutures);
      recommendedVendors = fetchedVendors
          .whereType<VendorModel>()
          .toList();
    } else {
      recommendedVendors = [];
    }

    // Remove duplicates and limit to 30 recommendations
    recommendations = recommendations.toSet().toList();
    recommendations = recommendations.take(30).toList();

    // Update the UI with new recommendations
    if (!mounted || _isLeavingHome) return;
    _updateState(callback: () {
      recommendedProducts = recommendations;
    });

    if (recommendedProducts.isNotEmpty &&
        recommendedVendors.isEmpty &&
        !_didLogRecommendedVendorEmpty) {
      _didLogRecommendedVendorEmpty = true;
    }
  }

  // Fetch order again products from user's completed orders
  Future<void> fetchOrderAgainProducts() async {
    if (MyAppState.currentUser == null) {
      if (!mounted || _isLeavingHome) return;
      _updateState(callback: () {
        isLoadingOrderAgain = false;
      });
      return;
    }

    try {
      if (!mounted || _isLeavingHome) return;
      _updateState(callback: () {
        isLoadingOrderAgain = true;
      });

      // Cancel any existing subscription
      orderAgainStreamSubscription?.cancel();

      // Listen to the orders stream
      orderAgainStreamSubscription =
          fireStoreUtils.getOrders(MyAppState.currentUser!.userID).listen(
        (List<OrderModel> allOrders) async {
          // Safety check
          if (!mounted || _isLeavingHome) return;

          // Filter for completed orders using correct status values
          List<OrderModel> completedOrders = allOrders.where((order) {
            return order.status.toLowerCase().contains('completed') ||
                order.status.toLowerCase().contains('delivered') ||
                order.status == ORDER_STATUS_COMPLETED;
          }).toList();

          if (completedOrders.isEmpty) {
            if (!mounted || _isLeavingHome) return;
            _updateState(callback: () {
              orderAgainProducts = [];
              isLoadingOrderAgain = false;
            });
            return;
          }

          // Wait for allProducts to be loaded
          if (allProducts.isEmpty) {
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted || _isLeavingHome) return;
          }

          // Extract product IDs from completed orders
          Set<String> productIds = {};
          for (OrderModel order in completedOrders) {
            for (var product in order.products) {
              // Extract the base product ID (remove variant suffix if exists)
              String baseProductId = product.id.contains('~')
                  ? product.id.split('~').first
                  : product.id;
              productIds.add(baseProductId);
            }
          }

          // Map product IDs to ProductModels
          List<ProductModel> orderAgainList = [];
          for (String productId in productIds) {
            try {
              ProductModel? product = allProducts.firstWhere(
                (p) => p.id == productId,
                orElse: () => ProductModel(),
              );
              if (product.id.isNotEmpty) {
                orderAgainList.add(product);
              }
            } catch (e) {
              // Silently handle individual product errors
            }
          }

          // Remove duplicates and limit to 10 items
          orderAgainList = orderAgainList.toSet().toList();
          orderAgainList = orderAgainList.take(10).toList();

          if (!mounted || _isLeavingHome) return;
          _updateState(callback: () {
            orderAgainProducts = orderAgainList;
            isLoadingOrderAgain = false;
          });
        },
        onError: (error) {
          if (!mounted || _isLeavingHome) return;
          _updateState(callback: () {
            isLoadingOrderAgain = false;
          });
        },
      );
    } catch (e) {
      if (!mounted || _isLeavingHome) return;
      _updateState(callback: () {
        isLoadingOrderAgain = false;
      });
    }
  }

  // Fetch meal for one products (sulit price)
  Future<void> fetchMealForOneProducts() async {
    try {
      List<ProductModel> mealForOneList = [];

      for (ProductModel product in allProducts) {
        // Check if product price is within sulit cap
        double productPrice = double.tryParse(product.price) ?? 0.0;
        if (productPrice <= sulitCap && productPrice > 0) {
          // Check for solo indicators in name, description, or tags
          String productName = product.name.toLowerCase();
          String productDesc = product.description.toLowerCase();

          // Keywords that indicate solo/individual meals
          List<String> soloKeywords = [
            'solo',
            'single',
            'individual',
            'one',
            '1',
            'personal',
            'meal',
            'combo',
            'set',
            'plate',
            'serving',
            'portion'
          ];

          bool isSoloMeal = soloKeywords.any((keyword) =>
              productName.contains(keyword) || productDesc.contains(keyword));

          // Also check if the product name suggests it's for one person
          if (isSoloMeal ||
              productName.contains('meal') ||
              productName.contains('combo')) {
            mealForOneList.add(product);
          }
        }
      }

      // Remove duplicates and shuffle for variety
      mealForOneList = mealForOneList.toSet().toList();
      mealForOneList
          .shuffle(); // Randomize to show different products each time
      mealForOneList = mealForOneList.take(10).toList();

      final Set<String> vendorIds = mealForOneList
          .map((product) => product.vendorID)
          .where((id) => id.isNotEmpty)
          .toSet();
      if (vendorIds.isNotEmpty) {
        final List<Future<VendorModel?>> vendorFutures = vendorIds
            .map((vendorId) => FireStoreUtils.getVendor(vendorId))
            .toList();
        final List<VendorModel?> fetchedVendors =
            await Future.wait(vendorFutures);
        mealForOneVendors = fetchedVendors.whereType<VendorModel>().toList();
      } else {
        mealForOneVendors = [];
      }

      if (mealForOneList.isEmpty) {
      }

      if (!mounted || _isLeavingHome) return;
      _updateState(callback: () {
        mealForOneProducts = mealForOneList;
        isLoadingMealForOne = false;
      });
    } catch (e) {
      if (!mounted || _isLeavingHome) return;
      _updateState(callback: () {
        isLoadingMealForOne = false;
      });
    }
  }

  // Order Again card with same design as Meal for One cards
  Widget _orderAgainCard(ProductModel product, VendorModel vendor, bool isDark,
      double screenWidth) {
    return GestureDetector(
      onTap: () {
        push(
          context,
          ProductDetailsScreen(productModel: product, vendorModel: vendor),
        );
      },
      child: Container(
        width: screenWidth * 0.375,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image section with restaurant logo
            Stack(
              children: [
                // Main product image
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
                      memCacheWidth: (screenWidth * 0.4).round(),
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
                // Restaurant logo overlay
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
                // "Order Again" badge
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(COLOR_PRIMARY),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 10,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Again',
                          style: TextStyle(
                            fontFamily: 'Poppinssb',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Content section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Restaurant name and rating
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vendor.title,
                          style: TextStyle(
                            fontFamily: 'Poppinsm',
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
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
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  // Product name
                  Text(
                    product.name,
                    style: TextStyle(
                      fontFamily: 'Poppinssb',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Price and order again indicator
                  Row(
                    children: [
                      Text(
                        product.disPrice != "" && product.disPrice != "0"
                            ? "₱ ${double.parse(product.disPrice.toString()).toStringAsFixed(currencyModel!.decimal)}"
                            : "₱ ${double.parse(product.price.toString()).toStringAsFixed(currencyModel!.decimal)}",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                      if (product.disPrice != "" && product.disPrice != "0")
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            "₱ ${double.parse(product.price.toString()).toStringAsFixed(currencyModel!.decimal)}",
                            style: TextStyle(
                              fontFamily: 'Poppinsr',
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey.shade600,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history,
                              size: 10,
                              color: Colors.orange.shade600,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Ordered',
                              style: TextStyle(
                                fontFamily: 'Poppinsm',
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
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

  // Advertisement slider shown above Stories

  void _handleOrderTypeChanged(String? newValue) async {
    if (newValue == null) return;

    int cartProd = 0;

    await Provider.of<CartDatabase>(context, listen: false)
        .allCartProducts
        .then((value) {
      cartProd = value.length;
    });

    if (cartProd > 0) {
      showDialog(
        context: context,
        builder: (BuildContext context) => ShowDialogToDismiss(
          title: '',
          content: "Do you really want to change the delivery option?" +
              " Your cart will be empty",
          buttonText: 'CLOSE',
          secondaryButtonText: 'OK',
          action: () {
            Navigator.of(context).pop();

            Provider.of<CartDatabase>(context, listen: false)
                .deleteAllProducts();

            if (!mounted || _isLeavingHome) return;
            _updateState(
              callback: () {
                selctedOrderTypeValue = newValue.toString();
                saveFoodTypeValue();
                getData();
              },
              immediate: true,
            );
          },
        ),
      );
    } else {
      if (!mounted || _isLeavingHome) return;
      _updateState(
        callback: () {
          selctedOrderTypeValue = newValue.toString();
          saveFoodTypeValue();
          getData();
        },
        immediate: true,
      );
    }
  }

  void _handleLocationTap() async {
    if (MyAppState.currentUser != null) {
      await Navigator.of(context)
          .push(
              MaterialPageRoute(builder: (context) => DeliveryAddressScreen()))
          .then((value) async {
        // Refresh user data to get latest addresses
        if (MyAppState.currentUser != null) {
          var updatedUser = await FireStoreUtils.getCurrentUser(
              MyAppState.currentUser!.userID);
          if (updatedUser != null) {
            MyAppState.currentUser = updatedUser;
          }
        }

        if (value != null) {
          // Re-determine default address from updated shippingAddress list
          final resolvedDefaultAddress = MyAppState.resolveDefaultAddress(
              MyAppState.currentUser!.shippingAddress);
          if (resolvedDefaultAddress != null) {
            MyAppState.selectedPosotion = resolvedDefaultAddress;
          } else {
            // Fallback to returned address if no default found
            MyAppState.selectedPosotion = value;
          }

          if (mounted && !_isLeavingHome) {
            _updateState();
          }

          getData();
        } else {
          // If no address was selected but user might have changed default,
          // refresh to get the latest default address
          _setDefaultAddressIfNeeded();
          if (mounted && !_isLeavingHome) {
            _updateState();
          }
        }
      });
    } else {
      checkPermission(() async {
        await showProgress(context, "Please wait...", true);

        AddressModel addressModel = AddressModel();

        try {
          await Geolocator.requestPermission();

          await Geolocator.getCurrentPosition();

          await hideProgress();

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlacePicker(
                apiKey: GOOGLE_API_KEY,
                onPlacePicked: (result) async {
                  await hideProgress();

                  AddressModel addressModel = AddressModel();

                  addressModel.locality = result.formattedAddress!.toString();

                  addressModel.location = UserLocation(
                      latitude: result.geometry!.location.lat,
                      longitude: result.geometry!.location.lng);

                  MyAppState.selectedPosotion = addressModel;

                  if (!mounted || _isLeavingHome) return;
                  _updateState();

                  getData();

                  Navigator.of(context).pop();
                },
                initialPosition: LatLng(-33.8567844, 151.213108),
                useCurrentLocation: true,
                selectInitialPosition: true,
                usePinPointingSearch: true,
                usePlaceDetailSearch: true,
                zoomGesturesEnabled: true,
                zoomControlsEnabled: true,
                resizeToAvoidBottomInset:
                    false, // only works in page mode, less flickery, remove if wrong offsets
              ),
            ),
          );
        } catch (e) {
          await placemarkFromCoordinates(19.228825, 72.854118)
              .then((valuePlaceMaker) {
            Placemark placeMark = valuePlaceMaker[0];

            if (!mounted || _isLeavingHome) return;
            _updateState(
              callback: () {
                addressModel.location =
                    UserLocation(latitude: 19.228825, longitude: 72.854118);

                String currentLocation =
                    "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";

                addressModel.locality = currentLocation;
              },
            );
          });

          MyAppState.selectedPosotion = addressModel;

          await hideProgress();

          getData();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cache isDarkMode result - called 34 times, now only once per build
    final bool isDark = isDarkMode(context);
    // Cache MediaQuery size - called 12 times, now only once per build
    final screenWidth = MediaQuery.of(context).size.width;
    // Use cached vendor map instead of recreating
    final vendorMap = _cachedVendorMap ?? {};

    return Scaffold(
      backgroundColor: isDark
          ? const Color.fromARGB(255, 201, 144, 1)
          : const Color(0xffFFFFFF),
      body: isLoading == true
          ? ShimmerWidgets.homeScreenShimmer()
          : (MyAppState.selectedPosotion.location!.latitude == 0 &&
                  MyAppState.selectedPosotion.location!.longitude == 0)
              ? Center(
                  child: showEmptyState("We don't have your location.", context,
                      description:
                          "Set your location to started searching for restaurants in your area",
                      action: () async {
                    checkPermission(
                      () async {
                        await showProgress(context, "Please wait...", false);

                        AddressModel addressModel = AddressModel();

                        try {
                          LocationPermission permission =
                              await requestLocationWithDialog(context);

                          await Geolocator.getCurrentPosition();

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PlacePicker(
                                apiKey: GOOGLE_API_KEY,

                                onPlacePicked: (result) async {
                                  await hideProgress();

                                  AddressModel addressModel = AddressModel();

                                  addressModel.locality =
                                      result.formattedAddress!.toString();

                                  addressModel.location = UserLocation(
                                      latitude: result.geometry!.location.lat,
                                      longitude: result.geometry!.location.lng);

                                  MyAppState.selectedPosotion = addressModel;

                                  if (mounted && !_isLeavingHome) {
                                    _updateState();
                                  }

                                  getData();

                                  Navigator.of(context).pop();
                                },

                                initialPosition:
                                    LatLng(-33.8567844, 151.213108),

                                useCurrentLocation: true,

                                selectInitialPosition: true,

                                usePinPointingSearch: true,

                                usePlaceDetailSearch: true,

                                zoomGesturesEnabled: true,

                                zoomControlsEnabled: true,

                                resizeToAvoidBottomInset:
                                    false, // only works in page mode, less flickery, remove if wrong offsets
                              ),
                            ),
                          );
                        } catch (e) {
                          await placemarkFromCoordinates(19.228825, 72.854118)
                              .then((valuePlaceMaker) {
                            Placemark placeMark = valuePlaceMaker[0];

                            if (!mounted || _isLeavingHome) return;
                            _updateState(callback: () {
                              addressModel.location = UserLocation(
                                  latitude: 19.228825, longitude: 72.854118);

                              String currentLocation =
                                  "${placeMark.name}, ${placeMark.subLocality}, ${placeMark.locality}, ${placeMark.administrativeArea}, ${placeMark.postalCode}, ${placeMark.country}";

                              addressModel.locality = currentLocation;
                            });
                          });

                          MyAppState.selectedPosotion = addressModel;

                          await hideProgress();

                          getData();
                        }
                      },
                    );
                  }, buttonTitle: 'Select'),
                )
              : HomeContentStack(
                  homeContent: RefreshIndicator(
                    onRefresh: _refreshHomeData,
                    color: Color(COLOR_PRIMARY),
                    child: SingleChildScrollView(
                      controller: _homeScrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        color: isDark
                            ? const Color.fromARGB(255, 212, 197, 128)
                            : const Color(0xffFFFFFF),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HomeHeaderSection(
                              selctedOrderTypeValue: selctedOrderTypeValue,
                              rotatingHints: rotatingHints,
                              onOrderTypeChanged: _handleOrderTypeChanged,
                              onLocationTap: _handleLocationTap,
                              onSearchTap: _onSearchTap,
                              onMessageTap: _onMessageTap,
                              onFavoriteTap: _onFavoriteTap,
                            ),

                            // Divider above Categories section
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: isDark
                                    ? Colors.grey.shade600
                                    : Colors.grey.shade300,
                                indent: 5,
                                endIndent: 5,
                              ),
                            ),

                            // Categories section moved above First-time promo card
                            CategoriesHorizontalSection(
                              categoriesFuture: _cachedCuisinesFuture ??
                                  fireStoreUtils.getCuisines(),
                            ),

                            RepaintBoundary(
                              child: BannerSection(
                                areBannerImagesCached: _areBannerImagesCached,
                                cachedFilteredBanners: _cachedFilteredBanners,
                                cachedCarouselItems: _cachedCarouselItems,
                                carouselController: _carouselController,
                                carouselKey: _carouselKey,
                                carouselOptions: _carouselOptions,
                                onRebuildCarouselItems: _rebuildCarouselItems,
                                offerVendorList: offerVendorList,
                                offersList: offersList,
                                buildCouponsForYouItem:
                                    _buildCouponsForYouItemCached,
                              ),
                            ),

                            // Promos Section
                            if (isLoadingPromos || activePromos.isNotEmpty)
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  isLoadingPromos
                                      ? Container(
                                          width: screenWidth,
                                          height: 200,
                                          margin: const EdgeInsets.fromLTRB(
                                              0, 0, 0, 0),
                                          child: Center(
                                            child: CircularProgressIndicator
                                                .adaptive(
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                      Color(COLOR_PRIMARY)),
                                            ),
                                          ),
                                        )
                                      : RepaintBoundary(
                                          child: SizedBox(
                                            height: 200,
                                            child: ListView.builder(
                                              scrollDirection: Axis.horizontal,
                                              physics:
                                                  const BouncingScrollPhysics(),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      10, 10, 16, 0),
                                              cacheExtent: 300.0,
                                              itemCount:
                                                  activePromos.length >= 10
                                                      ? 10
                                                      : activePromos.length,
                                              itemBuilder: (context, index) {
                                                return _buildPromoCard(
                                                    context,
                                                    activePromos[index],
                                                    isDark,
                                                    screenWidth);
                                              },
                                            ),
                                          ),
                                        ),
                                ],
                              ),

                            //storyWidget(),

                            RepaintBoundary(
                              child: const FoodVarietiesRow(),
                            ),

                            RepaintBoundary(
                              child: HomePopularTodaySection(
                                popularTodayFoods: popularTodayFoods,
                                vendors: popularTodayVendors,
                              ),
                            ),

                            RepaintBoundary(
                              child: HomeNearbyFoodsSection(
                                lstNearByFood: lstNearByFood,
                                vendors: nearbyFoodVendors,
                              ),
                            ),

                            // Order Again Section (hide when no previous orders)
                            if (MyAppState.currentUser != null &&
                                !isLoadingOrderAgain &&
                                orderAgainProducts.isNotEmpty)
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  buildTitleRow(
                                    titleValue: "Order Again",
                                    onClick: _onOrderAgainViewAll,
                                  ),
                                  RepaintBoundary(
                                    child: Container(
                                      width: screenWidth,
                                      height: 220,
                                      margin: const EdgeInsets.fromLTRB(
                                          16, 0, 0, 10),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        itemCount:
                                            orderAgainProducts.length >= 10
                                                ? 10
                                                : orderAgainProducts.length,
                                        itemBuilder: (context, index) {
                                          ProductModel product =
                                              orderAgainProducts[index];
                                          // O(1) lookup instead of O(n) linear search
                                          final vendorModel =
                                              vendorMap[product.vendorID];
                                          if (vendorModel == null) {
                                            return Container();
                                          }
                                          return _orderAgainCard(product,
                                              vendorModel, isDark, screenWidth);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                            // Recommended for You Section
                            RepaintBoundary(
                              child: RecommendedSection(
                                recommendedProducts: recommendedProducts,
                                vendors: recommendedVendors.isNotEmpty
                                    ? recommendedVendors
                                    : vendors,
                              ),
                            ),

                            // Meal for One • Sulit price Section
                            RepaintBoundary(
                              child: MealForOneSection(
                                mealForOneProducts: mealForOneProducts,
                                vendors: mealForOneVendors.isNotEmpty
                                    ? mealForOneVendors
                                    : vendors,
                                allProducts: allProducts,
                                isLoadingMealForOne: isLoadingMealForOne,
                              ),
                            ),

                            RepaintBoundary(
                              child: NearbyRestaurantsSection(
                                vendorsStream: _cachedNewArrivalStream ??
                                    fireStoreUtils
                                        .getVendorsForNewArrival()
                                        .asBroadcastStream(),
                                fallbackVendors: mostRatedRestaurantsFallback,
                                allProducts: allProducts,
                                lstFav: lstFav,
                                isRestaurantOpen: isRestaurantOpen,
                                onFavoriteChanged: _onFavoriteChanged,
                              ),
                            ),

                            RepaintBoundary(
                              child: NewRestaurantsSection(
                                vendorsStream: _cachedNewestRestaurantsStream ??
                                    fireStoreUtils
                                        .getNewestRestaurantsStream(limit: 15)
                                        .asBroadcastStream(),
                                fallbackVendors: mostRatedRestaurantsFallback,
                                allProducts: allProducts,
                                lstFav: lstFav,
                                isRestaurantOpen: isRestaurantOpen,
                                onFavoriteChanged: _onFavoriteChanged,
                              ),
                            ),

                            RepaintBoundary(
                              child: TopRestaurantsSection(
                                popularRestaurantLst: popularRestaurantLst,
                                allProducts: allProducts,
                                lstFav: lstFav,
                                fallbackRestaurants:
                                    mostRatedRestaurantsFallback,
                                onFavoriteChanged: _onFavoriteChanged,
                              ),
                            ),

                            RepaintBoundary(
                              child: CategoryRestaurantsSection(
                                categoryWiseProductList:
                                    categoryWiseProductList,
                                allProducts: allProducts,
                                currencyModel: currencyModel,
                              ),
                            ),

                            RepaintBoundary(
                              child: AllRestaurantsSection(
                                offerList: offerList,
                                allProducts: allProducts,
                                currencyModel: currencyModel,
                                orderType: 'delivery',
                                pageSize: 10,
                                lstFav: lstFav,
                                scrollController: _homeScrollController,
                                onFavoriteChanged: _onFavoriteChanged,
                                isRestaurantOpen: isRestaurantOpen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  final StoryController controller = StoryController();

  Widget storyWidget() {
    // Stories are hidden - always return empty widget
    return SizedBox.shrink();

    // Cache isDarkMode for this method (dead code but optimized for future use)
    final bool isDark = isDarkMode(context);

    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stories Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
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
                  child: Icon(
                    Icons.play_circle_filled,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Stories",
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  "Tap to watch",
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Stories List
          Expanded(
            child: FutureBuilder<List<StoryModel>>(
              future: _cachedStoriesFuture,
              builder: (context, snapshot) {
                // 1) Loading state: show 3 placeholder cards
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return RepaintBoundary(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 3,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (_, i) => Container(
                        width: 140,
                        margin: const EdgeInsets.only(right: 16),
                        child: Card(
                          elevation: 8,
                          shadowColor: Colors.black.withOpacity(0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
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
                        ),
                      ),
                    ),
                  );
                }

                // 2) Error or empty: show empty state
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.video_library_outlined,
                            size: 48,
                            color:
                                isDark ? Colors.white54 : Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "No stories available",
                            style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 3) Data arrived: build your normal list
                final stories = snapshot.data!;
                return RepaintBoundary(
                  child: ListView.builder(
                    itemCount: stories.length,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final story = stories[index];
                      return Container(
                        width: 140,
                        margin: const EdgeInsets.only(right: 16),
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  MoreStories(storyList: stories, index: index),
                            ),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                  spreadRadius: 0,
                                ),
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 30,
                                  offset: const Offset(0, 16),
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                children: [
                                  // Story Image
                                  CachedNetworkImage(
                                    imageUrl: (story
                                                .videoThumbnail?.isNotEmpty ==
                                            true)
                                        ? story.videoThumbnail.toString()
                                        : '', // Empty string will trigger errorWidget
                                    memCacheWidth: 280,
                                    memCacheHeight: 280,
                                    maxWidthDiskCache: 560,
                                    maxHeightDiskCache: 560,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(COLOR_PRIMARY)
                                                .withOpacity(0.1),
                                            Color(COLOR_PRIMARY)
                                                .withOpacity(0.05),
                                          ],
                                        ),
                                      ),
                                      child: Center(
                                        child:
                                            CircularProgressIndicator.adaptive(
                                          valueColor: AlwaysStoppedAnimation(
                                              Color(COLOR_PRIMARY)),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(COLOR_PRIMARY)
                                                .withOpacity(0.1),
                                            Color(COLOR_PRIMARY)
                                                .withOpacity(0.3),
                                          ],
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.videocam,
                                        size: 40,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ),
                                  // Gradient overlay
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withOpacity(0.6),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Play button
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.2),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.play_arrow,
                                        size: 16,
                                        color: Color(COLOR_PRIMARY),
                                      ),
                                    ),
                                  ),
                                  // "NEW" badge for recent stories
                                  if (DateTime.now()
                                          .difference(story.createdAt!.toDate())
                                          .inDays <
                                      1)
                                    Positioned(
                                      top: 12,
                                      left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.red.shade400,
                                              Colors.red.shade600,
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.red.withOpacity(0.3),
                                              blurRadius: 4,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          'NEW',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Vendor name overlay
                                  FutureBuilder<VendorModel>(
                                    key: ValueKey('vendor_${story.vendorID}'),
                                    future: story.vendorID != null &&
                                            story.vendorID!
                                                .toString()
                                                .isNotEmpty
                                        ? ((_cachedVendorFutures ??=
                                                {})[story.vendorID!] ??=
                                            FireStoreUtils()
                                                .getVendorByVendorID(
                                                    story.vendorID!.toString()))
                                        : Future.value(VendorModel(
                                            title: 'Unknown Vendor')),
                                    builder: (c, snap) {
                                      if (snap.connectionState ==
                                          ConnectionState.waiting) {
                                        return const SizedBox.shrink();
                                      }
                                      if (snap.hasError || !snap.hasData) {
                                        return const SizedBox.shrink();
                                      }
                                      return Positioned(
                                        bottom: 12,
                                        left: 12,
                                        right: 12,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              snap.data!.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                                shadows: [
                                                  Shadow(
                                                    offset: Offset(0, 1),
                                                    blurRadius: 3,
                                                    color: Colors.black,
                                                  ),
                                                ],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              "Tap to watch",
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.8),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w500,
                                                shadows: [
                                                  Shadow(
                                                    offset: Offset(0, 1),
                                                    blurRadius: 2,
                                                    color: Colors.black,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget buildVendorItemData(
    BuildContext context,
    ProductModel product,
  ) {
    // Cache MediaQuery for this method
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      width: screenWidth * 0.8,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: getImageVAlidUrl(product.photo),
              height: 100,
              width: 100,
              memCacheHeight: 100,
              memCacheWidth: 100,
              imageBuilder: (context, imageProvider) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image:
                      DecorationImage(image: imageProvider, fit: BoxFit.cover),
                ),
              ),
              placeholder: (context, url) => Center(
                  child: CircularProgressIndicator.adaptive(
                valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
              )),
              errorWidget: (context, url, error) => ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CachedNetworkImage(
                  imageUrl: AppGlobal.placeHolderImage!,
                  fit: BoxFit.cover,
                ),
              ),
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  height: 10,
                ),
                Text(
                  product.name,
                  style: const TextStyle(
                    fontFamily: "Poppinsm",
                    fontSize: 18,
                    color: Color(0xff000000),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(
                  height: 10,
                ),
                Text(
                  product.description,
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: "Poppinsm",
                    fontSize: 16,
                    color: Color(0xff9091A4),
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                Text(
                  "${amountShow(amount: product.price)}",
                  style: TextStyle(
                    fontFamily: "Poppinsm",
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget popularFoodItem(
    BuildContext context,
    ProductModel product,
    VendorModel popularNearFoodVendorModel,
  ) {
    // Cache isDarkMode and MediaQuery for this method
    final bool isDark = isDarkMode(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {
        VendorModel? vendorModel =
            await FireStoreUtils.getVendor(product.vendorID);

        if (vendorModel != null) {
          push(
            context,
            ProductDetailsScreen(
              vendorModel: vendorModel,
              productModel: product,
            ),
          );
        }
      },
      child: Container(
        width: screenWidth * 0.8,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF2C2C2C),
                    const Color(0xFF1A1A1A),
                  ]
                : [
                    Colors.white,
                    const Color(0xFFF8F9FA),
                  ],
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.15),
              blurRadius: 15,
              offset: const Offset(0, 6),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.05),
              blurRadius: 30,
              offset: const Offset(0, 12),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // Product Image with badges
              ProductStatusBadge(
                product: product,
                allProducts: allProducts,
                width: 80,
                height: 80,
              ),

              const SizedBox(width: 12),
              // Product Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Product name
                    Text(
                      product.name,
                      style: TextStyle(
                        fontFamily: "Poppinsm",
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Product description
                    Text(
                      product.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: "Poppinsm",
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Restaurant name
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Color(COLOR_PRIMARY).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        popularNearFoodVendorModel.title,
                        style: TextStyle(
                          fontFamily: "Poppinsm",
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(COLOR_PRIMARY),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Price section
                    Row(
                      children: [
                        // Current price
                        Text(
                          product.disPrice == "" || product.disPrice == "0"
                              ? amountShow(amount: product.price)
                              : amountShow(amount: product.disPrice),
                          style: TextStyle(
                            fontFamily: "Poppinsm",
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(COLOR_PRIMARY),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Original price (if discounted)
                        if (product.disPrice != "" && product.disPrice != "0")
                          Text(
                            amountShow(amount: product.price),
                            style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        const Spacer(),
                        // Add to cart button
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_shopping_cart,
                                size: 12,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                'Add',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
      ),
    );
  }

  Widget buildProductItem(ProductModel product, VendorModel vendor) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {
          // Navigate to ProductDetailsScreen with required arguments
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProductDetailsScreen(
                productModel: product, // Pass product
                vendorModel: vendor, // Pass vendor
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.grey.shade200,
              width: 1,
            ),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.5),
                blurRadius: 5,
              ),
            ],
          ),
          margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: CachedNetworkImage(
                  imageUrl: product.photo,
                  width: double.infinity,
                  height: 120,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
              const SizedBox(height: 10),
              // Product Name
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              // Product Price
              Text(
                "\u20B1${product.price}", // Display price with peso sign
                style: TextStyle(
                  color: Theme.of(context)
                      .primaryColor, // Use the app's primary color
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),
              // Vendor Name
              Text(
                vendor.title,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper function to get stable random product image for vendor
  String getStableRandomProductImage(VendorModel vendor) {
    // Filter products by vendor ID
    List<ProductModel> vendorProducts =
        allProducts.where((product) => product.vendorID == vendor.id).toList();

    if (vendorProducts.isEmpty) {
      // Fallback to vendor photo if no products found
      return getImageVAlidUrl(vendor.photo);
    }

    // Use vendor title hash to get stable random index
    int index = vendor.title.hashCode.abs() % vendorProducts.length;
    return getImageVAlidUrl(vendorProducts[index].photo);
  }

  /// Setup listener for order completion to show dialog
  Future<void> _setupCompletionDialogListener() async {
    // Guard: only set up once
    if (_isCompletionDialogListenerSetup ||
        MyAppState.currentUser == null ||
        _isLeavingHome) {
      return;
    }

    _isCompletionDialogListenerSetup = true;

    // Cancel existing subscription if any
    _completionDialogStreamSubscription?.cancel();

    // Listen to orders stream
    _completionDialogStreamSubscription =
        fireStoreUtils.getOrders(MyAppState.currentUser!.userID).listen(
      (List<OrderModel> allOrders) async {
        // Early return guards - check before any async work
        if (!mounted || _isLeavingHome) return;

        // Hard guard: if dialog is already open, return immediately
        if (_isCompletionDialogOpen) return;

        // Optional cooldown: ignore triggers within 3 seconds of last dialog
        if (_lastCompletionDialogAt != null) {
          final timeSinceLastDialog =
              DateTime.now().difference(_lastCompletionDialogAt!);
          if (timeSinceLastDialog.inSeconds < 3) {
            return;
          }
        }

        // Find candidate completed order that hasn't been shown
        OrderModel? candidateOrder;
        for (final order in allOrders) {
          final isCompleted =
              order.status.toLowerCase().contains('completed') ||
                  order.status.toLowerCase().contains('delivered') ||
                  order.status == ORDER_STATUS_COMPLETED;

          if (isCompleted) {
            // Check if we've already processed this order
            if (_processedCompletedOrders.contains(order.id)) {
              continue;
            }

            // Check if dialog has already been shown for this order
            if (UserPreference.isCompletionDialogShown(
                MyAppState.currentUser!.userID, order.id)) {
              _processedCompletedOrders.add(order.id);
              continue;
            }

            // Guard: if this is the same order as last shown, skip
            if (order.id == _lastCompletionDialogOrderId) {
              continue;
            }

            // Found candidate - take first one
            candidateOrder = order;
            break;
          }
        }

        // No candidate found, exit
        if (candidateOrder == null) return;

        // Atomic flag setting - set all guards BEFORE any async operations
        _isCompletionDialogOpen = true;
        _lastCompletionDialogOrderId = candidateOrder.id;
        _lastCompletionDialogAt = DateTime.now();
        _processedCompletedOrders.add(candidateOrder.id);

        // Persist preference immediately (before showing dialog)
        await UserPreference.markCompletionDialogShown(
          MyAppState.currentUser!.userID,
          candidateOrder.id,
        );

        // Final mount/route check before showing dialog
        if (!mounted || _isLeavingHome) {
          _isCompletionDialogOpen = false;
          return;
        }

        // Check if route is still active
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
          _isCompletionDialogOpen = false;
          return;
        }

        // Show dialog with try/finally to ensure cleanup
        try {
          await PostCompletionDialog.show(context, candidateOrder);
        } catch (e) {
          debugPrint('Error showing completion dialog: $e');
        } finally {
          // Always reset the open flag, but keep _lastCompletionDialogOrderId
          // to prevent duplicates for the same order
          _isCompletionDialogOpen = false;
        }
      },
      onError: (error) {
        // Silently handle errors
      },
    );
  }

  @override
  void dispose() {
    // Set flag to prevent setState calls after dispose
    _isLeavingHome = true;

    // Cancel all streams and timers
    fireStoreUtils.closeVendorStream();
    fireStoreUtils.closeNewArrivalStream();
    orderAgainStreamSubscription?.cancel();
    _completionDialogStreamSubscription?.cancel();
    _restaurantStreamSubscription?.cancel();
    _debounceTimer?.cancel();
    _setStateDebounceTimer?.cancel();
    _pendingStateUpdate = false;
    _connectivitySubscription?.cancel();
    _homeScrollController.dispose();

    // Clear restaurant open status cache
    _restaurantOpenStatusCache.clear();

    // Clear build-time computation caches
    _cachedVendorMap?.clear();
    _cachedRatings.clear();
    _cachedDiscountTexts.clear();
    _cachedVendorFutures?.clear();

    // Reset completion dialog guard variables
    _isCompletionDialogOpen = false;
    _lastCompletionDialogOrderId = null;
    _lastCompletionDialogAt = null;

    // Cancel any other streams that might be running
    lstAllRestaurant = null;

    super.dispose();
  }

  openCouponCode(
    BuildContext context,
    OfferModel offerModel,
  ) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
              margin: const EdgeInsets.only(
                left: 40,
                right: 40,
              ),
              padding: const EdgeInsets.only(
                left: 50,
                right: 50,
              ),
              decoration: const BoxDecoration(
                  image: DecorationImage(
                      image: AssetImage("assets/images/offer_code_bg.png"))),
              child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Text(
                  offerModel.offerCode!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.9),
                ),
              )),
          GestureDetector(
            onTap: () {
              FlutterClipboard.copy(offerModel.offerCode!).then((value) {
                final SnackBar snackBar = SnackBar(
                    content: Text(
                      "Coupon code copied",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: const Color.fromARGB(250, 190, 187, 146));

                ScaffoldMessenger.of(context).showSnackBar(snackBar);

                return Navigator.pop(context);
              });
            },
            child: Container(
              margin: const EdgeInsets.only(top: 30, bottom: 30),
              child: Text(
                "COPY CODE",
                style: TextStyle(
                    color: Color(COLOR_PRIMARY),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 30),
            child: RichText(
              text: TextSpan(
                text: "Use code",
                style: const TextStyle(
                    fontSize: 16.0,
                    color: Colors.grey,
                    fontWeight: FontWeight.w700),
                children: <TextSpan>[
                  TextSpan(
                    text: offerModel.offerCode,
                    style: TextStyle(
                        color: Color(COLOR_PRIMARY),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1),
                  ),
                  TextSpan(
                    text: " & get" +
                        " ${offerModel.discountType == "Fix Price" ? "${currencyModel!.symbol}" : ""}${offerModel.discount} ${offerModel.discountType == "Percentage" ? "% off" : "off"} ",
                    style: const TextStyle(
                        fontSize: 16.0,
                        color: Colors.grey,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCouponsForYouItem(
      BuildContext context1, VendorModel? vendorModel, OfferModel offerModel) {
    // Cache isDarkMode and MediaQuery for this method
    final bool isDark = isDarkMode(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return vendorModel == null
        ? Container()
        : Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: GestureDetector(
              onTap: () {
                if (vendorModel.id.toString() ==
                    offerModel.restaurantId.toString()) {
                  push(
                    context,
                    NewVendorProductsScreen(vendorModel: vendorModel),
                  );
                } else {
                  showModalBottomSheet(
                    isScrollControlled: true,
                    isDismissible: true,
                    context: context,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    backgroundColor: Colors.transparent,
                    enableDrag: true,
                    builder: (context) => openCouponCode(context, offerModel),
                  );
                }
              },
              child: Container(
                width: screenWidth * 0.75,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            const Color(0xFF2C2C2C),
                            const Color(0xFF1A1A1A),
                          ]
                        : [
                            Colors.white,
                            const Color(0xFFF8F9FA),
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withOpacity(0.1)
                          : Colors.grey.withOpacity(0.05),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Image Container with overlay
                    Expanded(
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                            child: CachedNetworkImage(
                              imageUrl:
                                  getImageVAlidUrl(offerModel.imageOffer!),
                              memCacheWidth: (screenWidth * 0.35).round(),
                              memCacheHeight: 340,
                              maxWidthDiskCache: 800,
                              maxHeightDiskCache: 400,
                              width: double.infinity,
                              height: double.infinity,
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
                                  Icons.local_offer,
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
                                    Colors.black.withOpacity(0.4),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Discount badge
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.red.shade400,
                                    Colors.red.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                "${offerModel.discountType == "Fix Price" ? "${currencyModel!.symbol}" : ""}${offerModel.discount}${offerModel.discountType == "Percentage" ? "% OFF" : " OFF"}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          // "OFFER" badge
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.purple.shade400,
                                    Colors.purple.shade600,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.purple.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_offer,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'OFFER',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Content section
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Restaurant name or offer title
                          vendorModel.id.toString() ==
                                  offerModel.restaurantId.toString()
                              ? Text(
                                  vendorModel.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                )
                              : Text(
                                  "Foodie's Offer",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                          const SizedBox(height: 8),
                          // Location or offer description
                          vendorModel.id.toString() ==
                                  offerModel.restaurantId.toString()
                              ? Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: Color(COLOR_PRIMARY)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.location_on,
                                        size: 16,
                                        color: Color(COLOR_PRIMARY),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        vendorModel.location,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: "Poppinsm",
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  "Apply Offer",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: "Poppinsm",
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                  ),
                                ),
                          const SizedBox(height: 12),
                          // Bottom row with coupon code and additional info
                          Row(
                            children: [
                              // Coupon code
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    FlutterClipboard.copy(offerModel.offerCode!)
                                        .then((value) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Coupon code copied!",
                                            style:
                                                TextStyle(color: Colors.white),
                                          ),
                                          backgroundColor: Color(COLOR_PRIMARY),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color:
                                          Color(COLOR_PRIMARY).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Color(COLOR_PRIMARY)
                                            .withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.copy,
                                          size: 16,
                                          color: Color(COLOR_PRIMARY),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          offerModel.offerCode!,
                                          style: TextStyle(
                                            fontFamily: "Poppinsm",
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(COLOR_PRIMARY),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Additional info (rating for restaurant offers)
                              vendorModel.id.toString() ==
                                      offerModel.restaurantId.toString()
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.1)
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.star,
                                            size: 16,
                                            color: Color(COLOR_PRIMARY),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _cachedRatings[vendorModel.id] ??
                                                '0.0',
                                            style: TextStyle(
                                              fontFamily: "Poppinsm",
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.flash_on,
                                            size: 14,
                                            color: Colors.purple.shade600,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Limited Time',
                                            style: TextStyle(
                                              fontFamily: "Poppinsm",
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.purple.shade600,
                                            ),
                                          ),
                                        ],
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
            ),
          );
  }

  Widget _buildPromoCard(BuildContext context, OfferModel coupon, bool isDark,
      double screenWidth) {
    final discountText = coupon.offerId != null
        ? (_cachedDiscountTexts[coupon.offerId!] ?? '')
        : '';

    // Look up vendor if restaurantId is available
    VendorModel? vendor;
    if (coupon.restaurantId != null && _cachedVendorMap != null) {
      vendor = _cachedVendorMap![coupon.restaurantId];
    }

    return GestureDetector(
      onTap: () {
        push(context, PromosScreen());
      },
      child: Container(
        width: screenWidth * 0.32,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section with restaurant logo
            Stack(
              children: [
                // Main promo image
                Container(
                  height: 170,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(DarkContainerBorderColor)
                          : Colors.grey.shade200,
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: getImageVAlidUrl(coupon.imageOffer ?? ''),
                      memCacheWidth: (screenWidth * 0.35).round(),
                      memCacheHeight: 340,
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
                          Icons.local_offer,
                          color: Colors.grey.shade400,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
                // Restaurant logo overlay (only if vendor is found)
                if (vendor != null)
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
                          memCacheWidth: 48,
                          memCacheHeight: 48,
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
            // Restaurant name (only if vendor is found)
            if (vendor != null) ...[
              const SizedBox(height: 8),
              Text(
                vendor.title,
                style: TextStyle(
                  fontFamily: "Poppinsm",
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getPromoDiscountText(OfferModel coupon) {
    if (coupon.discount == null || coupon.discountType == null) {
      return '';
    }

    final discountValue = double.tryParse(coupon.discount!) ?? 0.0;
    final isPercentage = coupon.discountType!.toLowerCase() == 'percentage' ||
        coupon.discountType!.toLowerCase() == 'percent';

    if (isPercentage) {
      return '${discountValue.toStringAsFixed(0)}% OFF';
    } else {
      // Using "PHP" instead of peso sign for better font compatibility
      return 'PHP ${discountValue.toStringAsFixed(2)} OFF';
    }
  }

  String _getPromoValidityText(OfferModel coupon) {
    Timestamp? validUntil = coupon.validUntil ?? coupon.expireOfferDate;

    if (validUntil != null) {
      final endDate = validUntil.toDate();
      final formatter = DateFormat('MMM dd, yyyy');
      return 'Valid until ${formatter.format(endDate)}';
    }

    return 'Valid now';
  }

  Widget buildVendorItem(VendorModel vendorModel) {
    // Cache isDarkMode and MediaQuery for this method
    final bool isDark = isDarkMode(context);
    final screenWidth = MediaQuery.of(context).size.width;
    bool restaurantIsOpen = isRestaurantOpen(vendorModel);

    return GestureDetector(
      onTap: () => push(
        context,
        NewVendorProductsScreen(vendorModel: vendorModel),
      ),
      child: Container(
        height: 120,
        width: screenWidth,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isDark
                  ? const Color(DarkContainerBorderColor)
                  : Colors.grey.shade100,
              width: 1),
          color: isDark ? const Color(DarkContainerColor) : Colors.white,
          boxShadow: [
            isDark
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
                Expanded(
                    child: CachedNetworkImage(
                  imageUrl: getImageVAlidUrl(vendorModel.photo),
                  memCacheWidth: screenWidth.toInt(),
                  memCacheHeight: 120,
                  imageBuilder: (context, imageProvider) => Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      image: DecorationImage(
                          image: imageProvider, fit: BoxFit.cover),
                    ),
                  ),
                  placeholder: (context, url) => Center(
                      child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                  )),
                  errorWidget: (context, url, error) => ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: AppGlobal.placeHolderImage!,
                        fit: BoxFit.cover,
                      )),
                  fit: BoxFit.cover,
                )),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(vendorModel.title,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: "Poppinsm",
                        letterSpacing: 0.5,
                        color: Color(0xff000000),
                      )),
                  subtitle: Row(
                    children: [
                      ImageIcon(
                        AssetImage('assets/images/location3x.png'),
                        size: 15,
                        color: Color(COLOR_PRIMARY),
                      ),
                      SizedBox(
                        width: 200,
                        child: Text(vendorModel.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: "Poppinsm",
                              letterSpacing: 0.5,
                              color: Color(0xff555353),
                            )),
                      ),
                    ],
                  ),
                  trailing: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 20,
                              color: Color(COLOR_PRIMARY),
                            ),
                            const SizedBox(width: 3),
                            Text(_cachedRatings[vendorModel.id] ?? '0.0',
                                style: const TextStyle(
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5,
                                  color: Color(0xff000000),
                                )),
                            const SizedBox(width: 3),
                            Text(
                                '(${vendorModel.reviewsCount.toStringAsFixed(1)})',
                                style: const TextStyle(
                                  fontFamily: "Poppinsm",
                                  letterSpacing: 0.5,
                                  color: Color(0xff666666),
                                )),
                          ],
                        ),
                      ],
                    ),
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
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Temporarily Closed',
                            style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700,
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
                                color: Colors.red.shade700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Check if restaurant is currently open (cached for performance)
  /// Cache is invalidated every hour to stay current
  bool isRestaurantOpen(VendorModel vendorModel) {
    final now = DateTime.now();
    final hourKey = '${now.year}-${now.month}-${now.day}-${now.hour}';

    // Only update cache outside of build phase
    bool cacheValid = _currentCacheHourKey == hourKey;
    if (!cacheValid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _restaurantOpenStatusCache.clear();
          _currentCacheHourKey = hourKey;
        }
      });
    }

    // Return cached result if available and cache is valid for current hour
    if (cacheValid && _restaurantOpenStatusCache.containsKey(vendorModel.id)) {
      return _restaurantOpenStatusCache[vendorModel.id]!;
    }

    // Cache write guarded - compute and return immediately, cache asynchronously
    final isOpen = _computeRestaurantOpenStatus(vendorModel);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _restaurantOpenStatusCache[vendorModel.id] = isOpen;
      }
    });
    return isOpen; // Return immediately, cache asynchronously
  }

  /// Internal method to compute restaurant open status (called once per restaurant per hour)
  bool _computeRestaurantOpenStatus(VendorModel vendorModel) {
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

  Future<void> saveFoodTypeValue() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    sp.setString('foodType', selctedOrderTypeValue!);
  }

  Future<void> getFoodType() async {
    SharedPreferences sp = await SharedPreferences.getInstance();

    if (mounted && !_isLeavingHome) {
      _updateState(callback: () {
        selctedOrderTypeValue =
            sp.getString("foodType") == "" || sp.getString("foodType") == null
                ? "Delivery"
                : sp.getString("foodType");
      });
    }

    if (selctedOrderTypeValue == "Takeaway") {
      productsFuture = fireStoreUtils.getAllTakeAWayProducts();
    } else {
      productsFuture = fireStoreUtils.getAllDelevryProducts();
    }
  }

  bool isLoading = true;

  getLocationData() async {
    // Lightweight location check - only verify permissions
    // Don't call getData() here to avoid starting heavy streams immediately
    try {
      // Just check if location is available, don't start restaurant stream yet
      if (MyAppState.selectedPosotion.location == null ||
          (MyAppState.selectedPosotion.location!.latitude == 0 &&
              MyAppState.selectedPosotion.location!.longitude == 0)) {
        // Location not set, check permissions but don't load data yet
        await getPermission();
      }
    } catch (e) {
      // If there's an error, just check permissions without loading data
      await getPermission();
    }
  }

  getPermission() async {
    if (!mounted || _isLeavingHome) return;
    _updateState(callback: () {
      isLoading = false;
    });

    PermissionStatus _permissionGranted = await location.hasPermission();

    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await location.requestPermission();
      // Don't call getData() here - it will be called in deferred secondary data
    }

    if (!mounted || _isLeavingHome) return;
    _updateState(callback: () {
      isLoading = false;
    });
  }

  Future<void> getData() async {
    await getFoodType();
    productsFuture.then((value) async {
      if (!mounted || _isLeavingHome) return;
      if (!_isLoadingPopularToday && popularTodayFoods.isEmpty) {
        _isLoadingPopularToday = true;
        try {
          await _loadPopularToday(value);
        } finally {
          _isLoadingPopularToday = false;
        }
      } else {
      }
    }).catchError((_) {});

    lstNearByFood.clear();
    popularTodayFoods.clear();
    popularTodayVendors.clear();
    _didRunPopularTodayFallback = false;

    fireStoreUtils.getRestaurantNearBy().whenComplete(() {
      lstAllRestaurant = fireStoreUtils.getAllRestaurants().asBroadcastStream();

      // Cancel existing subscription before creating new one
      _restaurantStreamSubscription?.cancel();
      _isProcessingRestaurants = false;

      if (MyAppState.currentUser != null) {
        // Fetch latest user data to get updated addresses
        FireStoreUtils.getCurrentUser(MyAppState.currentUser!.userID)
            .then((updatedUser) {
          if (updatedUser != null) {
            MyAppState.currentUser = updatedUser;
            // Set default address if needed
            _setDefaultAddressIfNeeded();
          }
        });

        lstFavourites = fireStoreUtils
            .getFavouriteRestaurant(MyAppState.currentUser!.userID);

        lstFavourites.then((event) {
          lstFav.clear();

          for (int a = 0; a < event.length; a++) {
            lstFav.add(event[a].restaurantId!);
          }
        });

        name = toBeginningOfSentenceCase(widget.user!.firstName);
      }

      _restaurantStreamSubscription = lstAllRestaurant?.listen(
        (event) {
          // Skip if already processing or disposed
          if (_isProcessingRestaurants || !mounted || _isLeavingHome) return;
          _isProcessingRestaurants = true;

          try {
            vendors
              ..clear()
              ..addAll(event);

            nearbyFoodVendors
              ..clear()
              ..addAll(event);

            allstoreList
              ..clear()
              ..addAll(event);

            // Rebuild caches after vendors update
            _rebuildComputationCaches();

            productsFuture.then((value) async {
              // Safety check: don't process if widget is disposed
              if (!mounted || _isLeavingHome) return;

              if (!_isLoadingPopularToday && popularTodayFoods.isEmpty) {
                _isLoadingPopularToday = true;
                try {
                  await _loadPopularToday(value);
                } finally {
                  _isLoadingPopularToday = false;
                }
              } else {
              }

              // Create a map of vendor ID to vendor for quick lookup
              Map<String, VendorModel> vendorMap = {};
              for (var vendor in event) {
                vendorMap[vendor.id] = vendor;
              }

              // Process each product and check if its restaurant is open
              for (var product in value.take(20)) {
                VendorModel? vendor = vendorMap[product.vendorID];

                if (vendor == null) {
                  continue;
                }

                bool isOpen = isRestaurantOpen(vendor);

                // Only add products from open restaurants
                if (isOpen && !lstNearByFood.contains(product)) {
                  lstNearByFood.add(product);
                }
              }

              if (lstNearByFood.isEmpty) {
                await _runNearbyFoodsFallback(
                  value,
                  trigger: 'nearby_stream',
                );
              } else {
                _updateState();
              }
            }).catchError((error) {
              // Silently handle errors to prevent crashes
            });

            // Process restaurants in isolate to prevent UI freezes
            final List<Map<String, dynamic>> restaurantMaps =
                event.map((vendor) => vendor.toJson()).toList();

            compute(filterAndSortRestaurantsForHome, restaurantMaps)
                .then((processedMaps) {
              // Safety check: don't process if widget is disposed
              if (!mounted || _isLeavingHome) return;

              try {
                // Convert back to VendorModel objects
                final List<VendorModel> processedRestaurants = processedMaps
                    .map((map) => VendorModel.fromJson(map))
                    .toList();

                // Assign the sorted list to popularRestaurantLst
                popularRestaurantLst = processedRestaurants;

                // Debounced setState
                _updateState();
              } catch (e) {
                // Fallback to synchronous processing on error
                validRestaurants =
                    event.where((vendor) => isRestaurantOpen(vendor)).toList();
                validRestaurants.sort((a, b) {
                  final double reviewsSumA = a.reviewsSum.toDouble();
                  final double reviewsSumB = b.reviewsSum.toDouble();
                  final num reviewsCountA = a.reviewsCount;
                  final num reviewsCountB = b.reviewsCount;
                  final double ratingA =
                      reviewsCountA != 0 ? (reviewsSumA / reviewsCountA) : 0.0;
                  final double ratingB =
                      reviewsCountB != 0 ? (reviewsSumB / reviewsCountB) : 0.0;
                  final int ratingComparison = ratingB.compareTo(ratingA);
                  if (ratingComparison == 0) {
                    return reviewsCountB.compareTo(reviewsCountA);
                  }
                  return ratingComparison;
                });
                popularRestaurantLst = validRestaurants;
                _updateState();
              }
            }).catchError((error) {
              // Fallback to synchronous processing on isolate error
              if (!mounted || _isLeavingHome) return;
              try {
                validRestaurants =
                    event.where((vendor) => isRestaurantOpen(vendor)).toList();
                validRestaurants.sort((a, b) {
                  final double reviewsSumA = a.reviewsSum.toDouble();
                  final double reviewsSumB = b.reviewsSum.toDouble();
                  final num reviewsCountA = a.reviewsCount;
                  final num reviewsCountB = b.reviewsCount;
                  final double ratingA =
                      reviewsCountA != 0 ? (reviewsSumA / reviewsCountA) : 0.0;
                  final double ratingB =
                      reviewsCountB != 0 ? (reviewsSumB / reviewsCountB) : 0.0;
                  final int ratingComparison = ratingB.compareTo(ratingA);
                  if (ratingComparison == 0) {
                    return reviewsCountB.compareTo(reviewsCountA);
                  }
                  return ratingComparison;
                });
                popularRestaurantLst = validRestaurants;
                _updateState();
              } catch (e) {
                // If everything fails, just use the original list
                popularRestaurantLst = event;
                _updateState();
              }
            });
          } finally {
            _isProcessingRestaurants = false;
          }
        },
        onDone: () {
          productsFuture.then((value) async {
            if (!mounted || _isLeavingHome) return;
            if (lstNearByFood.isEmpty) {
              await _runNearbyFoodsFallback(
                value,
                trigger: 'stream_done',
              );
            }
          }).catchError((error) {});
        },
        onError: (error) {
          // Handle stream errors gracefully
          _isProcessingRestaurants = false;
        },
      );
    });

    if (!mounted || _isLeavingHome) return;
    _updateState(callback: () {
      isLoading = false;
    });
  }

  List<StoryModel> storyList = [];

  void checkPermission(Function() onTap) async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      SnackBar snack = SnackBar(
        content: const Text(
          'You have to allow location permission to use your location',
          style: TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black,
      );

      ScaffoldMessenger.of(context).showSnackBar(snack);
    } else if (permission == LocationPermission.deniedForever) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return PermissionDialog();
        },
      );
    } else {
      onTap();
    }
  }
}

// ignore: camel_case_types

class buildTitleRow extends StatelessWidget {
  final String titleValue;
  final Function? onClick;
  final bool? isViewAll;
  final IconData? titleIcon;

  const buildTitleRow({
    Key? key,
    required this.titleValue,
    this.onClick,
    this.isViewAll = false,
    this.titleIcon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Cache isDarkMode for this widget
    final bool isDark = isDarkMode(context);

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2D2D2D),
                  const Color(0xFF1A1A1A),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFFFFFFFF),
                  const Color(0xFFF8F9FA),
                ],
              ),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (titleIcon != null) ...[
                    Icon(
                      titleIcon,
                      color: isDark ? Colors.white : const Color(0xFF000000),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(titleValue,
                      style: TextStyle(
                          color:
                              isDark ? Colors.white : const Color(0xFF000000),
                          fontFamily: "Poppinsm",
                          fontSize: 18)),
                ],
              ),
              isViewAll!
                  ? Container()
                  : GestureDetector(
                      onTap: () {
                        onClick!.call();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: isDark ? Colors.white : Colors.black,
                          size: 16,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
