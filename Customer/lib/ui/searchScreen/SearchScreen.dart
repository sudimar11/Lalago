import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/bundle_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/bundle_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/SearchHistoryService.dart';
import 'package:foodie_customer/model/PopularSearchItem.dart';
import 'package:foodie_customer/ui/bundle/bundle_card.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// Cache helper classes for optimized search performance
class CachedVendor {
  final VendorModel vendor;
  final String lowerTitle;

  CachedVendor(this.vendor) : lowerTitle = vendor.title.toLowerCase();
}

class CachedProduct {
  final ProductModel product;
  final String lowerName;

  CachedProduct(this.product) : lowerName = product.name.toLowerCase();
}

class SearchScreen extends StatefulWidget {
  final bool shouldAutoFocus;
  /// When set (e.g. from ContainerScreen tab), back uses this instead of pop.
  final VoidCallback? onBackPressed;

  const SearchScreen({
    Key? key,
    this.shouldAutoFocus = false,
    this.onBackPressed,
  }) : super(key: key);

  @override
  SearchScreenState createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  late List<VendorModel> vendorList = [];
  late List<VendorModel> vendorSearchList = [];

  late List<ProductModel> productList = [];
  late List<ProductModel> productSearchList = [];

  late List<BundleModel> bundleSearchList = [];

  // Cached lists for optimized search performance
  late List<CachedVendor> _cachedVendors = [];
  late List<CachedProduct> _cachedProducts = [];
  List<BundleModel> _cachedBundles = [];

  final FireStoreUtils fireStoreUtils = FireStoreUtils();
  final FocusNode _searchFocusNode = FocusNode(); // Add FocusNode
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;

  bool isLoadingVendors = true;
  bool isLoadingProducts = true;

  // Search history related
  List<SearchHistoryItem> searchSuggestions = [];
  bool showSuggestions = false;

  // Popular searches related
  List<PopularSearchItem> popularSearches = [];
  bool isLoadingPopularSearches = false;

  // Performance optimization
  Timer? _filterDebounceTimer;
  Map<String, List<dynamic>> _searchCache = {};
  bool _isFiltering = false;
  static const int _minSearchLength = 2;
  static const int _maxResultsPerCategory = 50;
  static const int _maxSuggestions = 6;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.shouldAutoFocus) {
        _searchFocusNode.requestFocus();
      }
      _loadSearchSuggestions();
      _loadPopularSearches();
    });

    fireStoreUtils.getVendors().then((value) {
      setState(() {
        vendorList = value;
        // Build cache for optimized search performance
        _cachedVendors = value.map((v) => CachedVendor(v)).toList();
        isLoadingVendors = false;
      });
    });
    fireStoreUtils.getAllProducts().then((value) {
      setState(() {
        // only keep products that are published
        productList = value.where((p) => p.publish == true).toList();
        // Build cache for optimized search performance
        _cachedProducts = productList.map((p) => CachedProduct(p)).toList();
        isLoadingProducts = false;
      });
    });
    BundleService.getActiveBundles(limit: 100).then((value) {
      if (mounted) setState(() => _cachedBundles = value);
    });
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shouldAutoFocus && widget.shouldAutoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocusNode.requestFocus();
      });
    }
  }

  void _loadSearchSuggestions() async {
    final suggestions =
        await SearchHistoryService.getRecentSearches(limit: _maxSuggestions);
    if (mounted) {
      setState(() {
        searchSuggestions = suggestions;
        showSuggestions = _searchController.text.isEmpty;
      });
    }
  }

  void _loadSearchSuggestionsForInput(String input) async {
    final suggestions = await SearchHistoryService.getSearchSuggestions(input);
    if (mounted) {
      setState(() {
        searchSuggestions = suggestions.take(_maxSuggestions).toList();
      });
    }
  }

  void _loadPopularSearches() async {
    setState(() {
      isLoadingPopularSearches = true;
    });

    try {
      final popularData = await fireStoreUtils.getPopularSearches(
        limit: _maxSuggestions,
        daysBack: 30,
      );

      if (mounted) {
        setState(() {
          popularSearches = popularData
              .map((data) => PopularSearchItem.fromFirestore(data))
              .toList();
          isLoadingPopularSearches = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading popular searches: $e');
      if (mounted) {
        setState(() {
          isLoadingPopularSearches = false;
        });
      }
    }
  }

  Widget _buildSearchContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show loading indicator when filtering
            if (_isFiltering)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),

            // Restaurant results
            if (vendorSearchList.isNotEmpty) _buildRestaurantSection(),

            if (vendorSearchList.isNotEmpty && productSearchList.isNotEmpty)
              const SizedBox(height: 20),

            // Food results
            if (productSearchList.isNotEmpty) _buildFoodSection(),

            if (productSearchList.isNotEmpty && bundleSearchList.isNotEmpty)
              const SizedBox(height: 20),

            // Bundle results
            if (bundleSearchList.isNotEmpty) _buildBundleSection(),

            // No results message
            if (!_isFiltering &&
                _searchController.text.length >= _minSearchLength &&
                vendorSearchList.isEmpty &&
                productSearchList.isEmpty &&
                bundleSearchList.isEmpty)
              _buildNoResultsMessage(),
          ],
        ),
      ),
    );
  }

  Widget _buildRestaurantSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Restaurant",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: vendorSearchList.length,
          itemBuilder: (context, index) =>
              _buildVendorCard(vendorSearchList[index]),
        ),
      ],
    );
  }

  Widget _buildFoodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Foods",
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: productSearchList.length,
          itemBuilder: (context, index) =>
              _buildProductCard(productSearchList[index]),
        ),
      ],
    );
  }

  Widget _buildNoResultsMessage() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Try different keywords or check spelling',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsContainer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate maximum height considering keyboard
        final maxHeight = MediaQuery.of(context).viewInsets.bottom > 0
            ? MediaQuery.of(context).size.height *
                0.25 // Smaller when keyboard is up
            : MediaQuery.of(context).size.height *
                0.45; // Larger when keyboard is down

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
            ),
            child: _buildSuggestionsContent(),
          ),
        );
      },
    );
  }

  Widget _buildSuggestionsContent() {
    // Check if we have any suggestions
    final hasRecentSearches = searchSuggestions.isNotEmpty;
    final hasPopularSearches = popularSearches.isNotEmpty;
    final hasAnySuggestions = hasRecentSearches || hasPopularSearches;

    if (!hasAnySuggestions) {
      // Show minimal height with "No suggestions" message
      return Container(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No suggestions available',
            style: TextStyle(
              fontFamily: 'Poppinsm',
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Recent Searches Section
        if (hasRecentSearches) ...[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    await SearchHistoryService.clearSearchHistory();
                    _loadSearchSuggestions();
                  },
                  child: Text(
                    'Clear All',
                    style: TextStyle(
                      fontFamily: 'Poppinsm',
                      fontSize: 12,
                      color: Color(COLOR_PRIMARY),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...searchSuggestions
              .map((suggestion) => _buildSuggestionItem(suggestion))
              .toList(),
        ],

        // Popular Searches Section
        if (hasPopularSearches) ...[
          if (hasRecentSearches) const Divider(height: 1, color: Colors.grey),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.trending_up,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'Popular Searches',
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (isLoadingPopularSearches) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          ...popularSearches
              .map((popular) => _buildPopularSearchItem(popular))
              .toList(),
        ],
      ],
    );
  }

  Widget _buildPopularSearchItem(PopularSearchItem popular) {
    return GestureDetector(
      onTap: () {
        _searchController.text = popular.query;
        onSearchTextChanged(popular.query);
        setState(() {
          showSuggestions = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.trending_up,
              size: 16,
              color: Colors.orange[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                popular.query,
                style: const TextStyle(
                  fontFamily: 'Poppinsr',
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${popular.count}',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  fontSize: 10,
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionItem(SearchHistoryItem suggestion) {
    return GestureDetector(
      onTap: () {
        _searchController.text = suggestion.query;
        onSearchTextChanged(suggestion.query);
        setState(() {
          showSuggestions = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              suggestion.type == 'restaurant'
                  ? Icons.restaurant
                  : suggestion.type == 'food'
                      ? Icons.fastfood
                      : Icons.search,
              size: 16,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                suggestion.query,
                style: const TextStyle(
                  fontFamily: 'Poppinsr',
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
            Text(
              suggestion.type.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 10,
                color: suggestion.type == 'restaurant'
                    ? Colors.blue[600]
                    : suggestion.type == 'food'
                        ? Colors.orange[600]
                        : Colors.grey[600],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                await SearchHistoryService.removeSearchItem(
                    suggestion.query, suggestion.type);
                _loadSearchSuggestions();
              },
              child: Icon(
                Icons.close,
                size: 16,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveSearchQuery(String query) async {
    if (query.isEmpty) return; // Skip saving if the query is empty

    // Initialize SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Save the query with the key 'lastSearch'
    await prefs.setString('lastSearch', query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            // Search field with back button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          if (widget.onBackPressed != null) {
                            widget.onBackPressed!();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                    focusNode: _searchFocusNode,
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      onSearchTextChanged(value);
                    },
                    onTap: () {
                      setState(() {
                        showSuggestions = _searchController.text.isEmpty;
                      });
                      if (showSuggestions) {
                        _loadSearchSuggestions();
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'Search menu, restaurant or etc...',
                      contentPadding:
                          const EdgeInsets.only(left: 10, right: 10, top: 10),
                      hintStyle: const TextStyle(
                          color: Color(0XFF8A8989), fontFamily: 'Poppinsr'),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.0),
                          borderSide: BorderSide(
                              color: Color(COLOR_PRIMARY), width: 2.0)),
                      errorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.error),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  showSuggestions = true;
                                });
                                _loadSearchSuggestions();
                              },
                            )
                          : null,
                    ),
                        ),
                      ),
                    ],
                  ),
                  // Search suggestions
                  if (showSuggestions) _buildSuggestionsContainer(),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: (isLoadingVendors || isLoadingProducts)
                  ? ShimmerWidgets.searchScreenShimmer()
                  : _buildSearchContent(),
            ),
          ],
        ),
      ),
    );
  }

  void onSearchTextChanged(String text) {
    _saveSearchQuery(text);

    setState(() {
      showSuggestions = text.isEmpty;
    });

    if (text.isEmpty) {
      _clearSearchResults();
      if (showSuggestions) {
        _loadSearchSuggestions();
      }
      return;
    }

    // Load suggestions as user types
    _loadSearchSuggestionsForInput(text);

    // Only start filtering after minimum character threshold
    if (text.length < _minSearchLength) {
      _clearSearchResults();
      return;
    }

    // Debounced filtering for performance
    _filterDebounceTimer?.cancel();
    _filterDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(text);
    });
  }

  void _clearSearchResults() {
    setState(() {
      vendorSearchList.clear();
      productSearchList.clear();
      bundleSearchList.clear();
      _isFiltering = false;
    });
  }

  void _performSearch(String text) async {
    if (text.length < _minSearchLength) return;

    setState(() {
      _isFiltering = true;
    });

    // Check cache first
    final cacheKey = text.toLowerCase();
    if (_searchCache.containsKey(cacheKey)) {
      final cachedResults = _searchCache[cacheKey]!;
      setState(() {
        vendorSearchList = cachedResults[0] as List<VendorModel>;
        productSearchList = cachedResults[1] as List<ProductModel>;
        bundleSearchList =
            cachedResults.length > 2
                ? cachedResults[2] as List<BundleModel>
                : <BundleModel>[];
        _isFiltering = false;
      });
      _trackSearch(text);
      return;
    }

    // Perform filtering in background
    final results = await _filterDataInBackground(text);

    if (mounted) {
      setState(() {
        vendorSearchList = results['vendors'] as List<VendorModel>;
        productSearchList = results['products'] as List<ProductModel>;
        bundleSearchList = results['bundles'] as List<BundleModel>;
        _isFiltering = false;
      });

      // Cache the results
      _searchCache[cacheKey] = [
        vendorSearchList,
        productSearchList,
        bundleSearchList,
      ];

      // Clean old cache entries (keep only last 10 searches)
      if (_searchCache.length > 10) {
        final keys = _searchCache.keys.toList();
        for (int i = 0; i < keys.length - 10; i++) {
          _searchCache.remove(keys[i]);
        }
      }

      _trackSearch(text);
    }
  }

  Future<Map<String, List<dynamic>>> _filterDataInBackground(
      String text) async {
    final lowerText = text.toLowerCase();
    final List<VendorModel> filteredVendors = [];
    final List<ProductModel> filteredProducts = [];

    // OPTIMIZED: Use cached lowercase values - no repeated toLowerCase() calls
    // Filter vendors
    for (var cachedVendor in _cachedVendors) {
      if (cachedVendor.lowerTitle.contains(lowerText)) {
        filteredVendors.add(cachedVendor.vendor);
        if (filteredVendors.length >= _maxResultsPerCategory) break;
      }
    }

    // Filter products
    for (var cachedProduct in _cachedProducts) {
      // No need to check publish again - already filtered in initState
      if (cachedProduct.lowerName.contains(lowerText)) {
        filteredProducts.add(cachedProduct.product);
        if (filteredProducts.length >= _maxResultsPerCategory) break;
      }
    }

    // Filter bundles by name/description
    final List<BundleModel> filteredBundles = [];
    for (final b in _cachedBundles) {
      if (b.name.toLowerCase().contains(lowerText) ||
          b.description.toLowerCase().contains(lowerText)) {
        filteredBundles.add(b);
        if (filteredBundles.length >= _maxResultsPerCategory) break;
      }
    }

    return {
      'vendors': filteredVendors,
      'products': filteredProducts,
      'bundles': filteredBundles,
    };
  }

  Widget _buildBundleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Bundle Deals",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bundleSearchList.length,
          itemBuilder: (context, index) {
            final bundle = bundleSearchList[index];
            final vendor = vendorList.cast<VendorModel?>().firstWhere(
                  (v) => v?.id == bundle.restaurantId,
                  orElse: () => null,
                );
            return InkWell(
              onTap: () {
                if (vendor != null) {
                  push(
                    context,
                    NewVendorProductsScreen(vendorModel: vendor),
                  );
                }
              },
              child: BundleCard(
                bundle: bundle,
                onAddToCart: null,
              ),
            );
          },
        ),
      ],
    );
  }

  void _trackSearch(String query) async {
    if (query.trim().isEmpty) return;

    // Cancel previous timer if it exists
    _searchDebounceTimer?.cancel();

    // Set a new timer to debounce the search tracking
    _searchDebounceTimer = Timer(const Duration(milliseconds: 1000), () async {
      try {
        // Determine search type based on results
        String searchType = 'mixed';
        if (vendorSearchList.isNotEmpty && productSearchList.isEmpty) {
          searchType = 'restaurant';
        } else if (productSearchList.isNotEmpty && vendorSearchList.isEmpty) {
          searchType = 'food';
        }

        final resultCount = vendorSearchList.length + productSearchList.length;

        // Save to local search history
        await SearchHistoryService.saveSearch(
          query: query.trim(),
          type: searchType,
          resultCount: resultCount,
        );

        // Track in Firestore for analytics
        await fireStoreUtils.trackSearchQuery(
          userId: MyAppState.currentUser?.userID ?? '',
          searchQuery: query.trim(),
          searchType: searchType,
          resultCount: resultCount,
          location: MyAppState.currentUser?.location != null
              ? '${MyAppState.currentUser!.location.latitude},${MyAppState.currentUser!.location.longitude}'
              : null,
        );
      } catch (e) {
        debugPrint('Error tracking search: $e');
      }
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel(); // Cancel the debounce timer
    _filterDebounceTimer?.cancel(); // Cancel the filter debounce timer
    _searchFocusNode.dispose(); // Dispose the FocusNode
    _searchController.dispose();
    vendorSearchList.clear();
    productSearchList.clear();
    searchSuggestions.clear();
    popularSearches.clear();
    _searchCache.clear(); // Clear search cache
    super.dispose();
  }

  Widget _buildVendorCard(VendorModel vendorModel) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => push(
          context,
          NewVendorProductsScreen(
            vendorModel: vendorModel,
          )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            _buildVendorImage(vendorModel),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vendorModel.title,
                      style: TextStyle(
                        fontFamily: "Poppinsr",
                        fontSize: 16,
                        color: isDarkMode(context)
                            ? const Color(0xffFFFFFF)
                            : const Color(0xff272727),
                      ),
                    ),
                    const SizedBox(height: 3),
                    _buildVendorRating(vendorModel),
                    const SizedBox(height: 3),
                    _buildLocationRow(vendorModel.location),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildVendorImage(VendorModel vendorModel) {
    return CachedNetworkImage(
      height: MediaQuery.of(context).size.height * 0.075,
      width: MediaQuery.of(context).size.width * 0.16,
      imageUrl: getImageVAlidUrl(vendorModel.photo),
      imageBuilder: (context, imageProvider) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          image: DecorationImage(
            image: imageProvider,
            fit: BoxFit.cover,
          ),
        ),
      ),
      errorWidget: (context, url, error) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.network(
          AppGlobal.placeHolderImage!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[300],
            child: const Icon(Icons.restaurant, color: Colors.grey),
          ),
        ),
      ),
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildLocationRow(String location) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.location_on_sharp,
          color: Color(0xff9091A4),
          size: 16,
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: "Poppinsl",
              fontSize: 14,
              color: Color(0XFF555353),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVendorRating(VendorModel vendorModel) {
    final rating = vendorModel.reviewsCount != 0
        ? (vendorModel.reviewsSum / vendorModel.reviewsCount).toStringAsFixed(1)
        : '0.0';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.star,
          size: 14,
          color: Colors.amber,
        ),
        const SizedBox(width: 4),
        Text(
          rating,
          style: TextStyle(
            fontFamily: "Poppinsm",
            fontSize: 13,
            color:
                isDarkMode(context) ? Colors.white70 : const Color(0XFF555353),
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(ProductModel productModel) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {
        VendorModel? vendorModel =
            await FireStoreUtils.getVendor(productModel.vendorID);
        if (vendorModel != null) {
          push(
            context,
            ProductDetailsScreen(
              vendorModel: vendorModel,
              productModel: productModel,
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            _buildProductImage(productModel),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      productModel.name,
                      style: TextStyle(
                        fontFamily: "Poppinsr",
                        fontSize: 16,
                        color: isDarkMode(context)
                            ? const Color(0xffFFFFFF)
                            : const Color(0xff272727),
                      ),
                    ),
                    const SizedBox(height: 3),
                    _buildProductRating(productModel),
                    const SizedBox(height: 3),
                    _buildRestaurantName(productModel.vendorID),
                    const SizedBox(height: 5),
                    _buildProductPrice(productModel),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(ProductModel productModel) {
    return CachedNetworkImage(
      height: MediaQuery.of(context).size.height * 0.075,
      width: MediaQuery.of(context).size.width * 0.16,
      imageUrl: getImageVAlidUrl(productModel.photo),
      imageBuilder: (context, imageProvider) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          image: DecorationImage(
            image: imageProvider,
            fit: BoxFit.cover,
          ),
        ),
      ),
      errorWidget: (context, url, error) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.network(
          AppGlobal.placeHolderImage!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[300],
            child: const Icon(Icons.fastfood, color: Colors.grey),
          ),
        ),
      ),
      placeholder: (context, url) => Container(
        color: Colors.grey[200],
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildRestaurantName(String vendorID) {
    return FutureBuilder<VendorModel?>(
      future: FireStoreUtils.getVendor(vendorID),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text(
            'Loading restaurant...',
            style: TextStyle(
              fontFamily: "Poppinsl",
              fontSize: 14,
              color: Colors.grey,
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return const Text(
            'Restaurant not found',
            style: TextStyle(
              fontFamily: "Poppinsl",
              fontSize: 14,
              color: Colors.red,
            ),
          );
        }
        return Text(
          snapshot.data!.title,
          style: const TextStyle(
            fontFamily: "Poppinsl",
            fontSize: 14,
            color: Color(0XFF555353),
          ),
        );
      },
    );
  }

  Widget _buildProductPrice(ProductModel productModel) {
    final hasDiscount =
        productModel.disPrice != "" && productModel.disPrice != "0";

    if (!hasDiscount) {
      return Text(
        amountShow(amount: productModel.price.toString()),
        style: TextStyle(
          fontFamily: "Poppinsm",
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Color(COLOR_PRIMARY),
        ),
      );
    }

    return Row(
      children: [
        Text(
          amountShow(amount: productModel.disPrice.toString()),
          style: TextStyle(
            fontFamily: "Poppinsm",
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(COLOR_PRIMARY),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          amountShow(amount: productModel.price.toString()),
          style: const TextStyle(
            fontFamily: "Poppinsm",
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }

  Widget _buildProductRating(ProductModel productModel) {
    final rating = productModel.reviewsCount != 0
        ? (productModel.reviewsSum / productModel.reviewsCount)
            .toStringAsFixed(1)
        : '0.0';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.star,
          size: 14,
          color: Colors.amber,
        ),
        const SizedBox(width: 4),
        Text(
          rating,
          style: TextStyle(
            fontFamily: "Poppinsm",
            fontSize: 13,
            color:
                isDarkMode(context) ? Colors.white70 : const Color(0XFF555353),
          ),
        ),
      ],
    );
  }
}
