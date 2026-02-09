import 'dart:async';
import 'package:flutter/material.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as dev;

/// Generic lazy loading widget for restaurants
class LazyLoadingRestaurantList extends StatefulWidget {
  final String orderType;
  final Widget Function(
      List<VendorModel> restaurants, bool isLoading, bool hasMore) builder;
  final int pageSize;
  final bool loadPopularOnly;
  final ScrollController? scrollController;

  const LazyLoadingRestaurantList({
    Key? key,
    required this.orderType,
    required this.builder,
    this.pageSize = 10,
    this.loadPopularOnly = false,
    this.scrollController,
  }) : super(key: key);

  @override
  _LazyLoadingRestaurantListState createState() =>
      _LazyLoadingRestaurantListState();
}

class _LazyLoadingRestaurantListState extends State<LazyLoadingRestaurantList> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  ScrollController? _scrollController;
  bool _isUsingExternalController = false;

  List<VendorModel> _restaurants = [];
  bool _isLoading = false;
  bool _hasMore = true;
  StreamSubscription<List<VendorModel>>? _subscription;
  DocumentSnapshot? _lastDocument;

  @override
  void initState() {
    super.initState();
    dev.log('🚀 [LazyLoading] initState() called');

    // Use provided ScrollController or find one from ancestor
    _scrollController = widget.scrollController;
    _isUsingExternalController = _scrollController != null;

    if (_scrollController != null) {
      dev.log('📌 [LazyLoading] Using provided ScrollController');
      _scrollController!.addListener(_onScroll);
    } else {
      dev.log(
          '⚠️ [LazyLoading] No ScrollController provided - will try to find from context');
    }

    _loadInitialData();
  }

  @override
  void dispose() {
    if (_scrollController != null && !_isUsingExternalController) {
      _scrollController!.removeListener(_onScroll);
      _scrollController!.dispose();
    } else if (_scrollController != null && _isUsingExternalController) {
      _scrollController!.removeListener(_onScroll);
    }
    _subscription?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController == null || !_scrollController!.hasClients) {
      dev.log(
          '⏸️ [LazyLoading] _onScroll: No scroll controller or not attached');
      return;
    }

    final position = _scrollController!.position;
    dev.log(
        '📜 [LazyLoading] _onScroll called - pixels: ${position.pixels.toStringAsFixed(1)}, maxScrollExtent: ${position.maxScrollExtent.toStringAsFixed(1)}, isLoading: $_isLoading, hasMore: $_hasMore');

    if (position.maxScrollExtent > 0 && !_isLoading && _hasMore) {
      final threshold = position.maxScrollExtent - 200;
      if (position.pixels >= threshold) {
        dev.log(
            '🚀 [LazyLoading] _onScroll: Reached threshold (${threshold.toStringAsFixed(1)}), calling _loadMoreData');
        _loadMoreData();
      } else {
        dev.log(
            '⏸️ [LazyLoading] _onScroll: Not at threshold yet (${position.pixels.toStringAsFixed(1)} < ${threshold.toStringAsFixed(1)})');
      }
    } else {
      if (position.maxScrollExtent <= 0) {
        dev.log(
            '⏸️ [LazyLoading] _onScroll: Not scrollable yet (maxScrollExtent=${position.maxScrollExtent})');
      }
      if (_isLoading) {
        dev.log('⏸️ [LazyLoading] _onScroll: Already loading');
      }
      if (!_hasMore) {
        dev.log('⏸️ [LazyLoading] _onScroll: No more data');
      }
    }
  }

  void _tryToFindScrollController(BuildContext context) {
    // Try to find ScrollController from ancestor Scrollable widgets
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != null) {
      final controller = scrollable.widget.controller;
      if (controller != null && controller != _scrollController) {
        dev.log(
            '✅ [LazyLoading] Found ScrollController from ancestor Scrollable');
        _scrollController?.removeListener(_onScroll);
        _scrollController = controller;
        _scrollController!.addListener(_onScroll);
      }
    }
  }

  Future<void> _loadInitialData() async {
    dev.log(
        '🔍 [LazyLoading] _loadInitialData: Starting, isLoading=$_isLoading');
    if (_isLoading) {
      dev.log('⚠️ [LazyLoading] _loadInitialData: Already loading, skipping');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      dev.log(
          '📥 [LazyLoading] _loadInitialData: Fetching restaurants (pageSize=${widget.pageSize}, orderType=${widget.orderType}, popularOnly=${widget.loadPopularOnly})');
      // Load initial batch of restaurants
      final result = await _fireStoreUtils.getRestaurantsPaginated(
        orderType: widget.orderType,
        limit: widget.pageSize,
        lastDocument: null,
        popularOnly: widget.loadPopularOnly,
      );

      final restaurants = result['restaurants'] as List<VendorModel>;
      final lastDoc = result['lastDocument'] as DocumentSnapshot?;

      dev.log(
          '✅ [LazyLoading] _loadInitialData: Loaded ${restaurants.length} restaurants, hasMore=${restaurants.length == widget.pageSize}, lastDoc=${lastDoc != null ? "exists" : "null"}');

      if (mounted) {
        setState(() {
          _restaurants = restaurants;
          _lastDocument = lastDoc;
          _isLoading = false;
          _hasMore = restaurants.length == widget.pageSize;
        });
        dev.log(
            '📊 [LazyLoading] _loadInitialData: State updated - total restaurants=${_restaurants.length}, hasMore=$_hasMore');
      }
    } catch (e, stackTrace) {
      dev.log('❌ [LazyLoading] _loadInitialData: Error: $e',
          error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreData() async {
    dev.log(
        '🔍 [LazyLoading] _loadMoreData: Called, isLoading=$_isLoading, hasMore=$_hasMore, currentCount=${_restaurants.length}');
    if (_isLoading) {
      dev.log('⚠️ [LazyLoading] _loadMoreData: Already loading, skipping');
      return;
    }
    if (!_hasMore) {
      dev.log('⚠️ [LazyLoading] _loadMoreData: No more data to load, skipping');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      dev.log(
          '📥 [LazyLoading] _loadMoreData: Fetching more restaurants (pageSize=${widget.pageSize}, lastDoc=${_lastDocument != null ? "exists" : "null"})');
      final result = await _fireStoreUtils.getRestaurantsPaginated(
        orderType: widget.orderType,
        limit: widget.pageSize,
        lastDocument: _lastDocument,
        popularOnly: widget.loadPopularOnly,
      );

      final restaurants = result['restaurants'] as List<VendorModel>;
      final lastDoc = result['lastDocument'] as DocumentSnapshot?;

      dev.log(
          '✅ [LazyLoading] _loadMoreData: Loaded ${restaurants.length} more restaurants, hasMore=${restaurants.length == widget.pageSize}, newLastDoc=${lastDoc != null ? "exists" : "null"}');

      if (mounted) {
        setState(() {
          _restaurants.addAll(restaurants);
          _lastDocument = lastDoc;
          _isLoading = false;
          _hasMore = restaurants.length == widget.pageSize;
        });
        dev.log(
            '📊 [LazyLoading] _loadMoreData: State updated - total restaurants=${_restaurants.length}, hasMore=$_hasMore');
      }
    } catch (e, stackTrace) {
      dev.log('❌ [LazyLoading] _loadMoreData: Error: $e',
          error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    dev.log(
        '🏗️ [LazyLoading] build() called - restaurants: ${_restaurants.length}, isLoading: $_isLoading, hasMore: $_hasMore');

    // Try to find ScrollController from context if not provided
    if (_scrollController == null) {
      _tryToFindScrollController(context);
    }

    // Use both NotificationListener (for child scroll notifications) and LayoutBuilder (to detect rebuilds during scroll)
    return LayoutBuilder(
      builder: (context, constraints) {
        dev.log(
            '📐 [LazyLoading] LayoutBuilder rebuild - constraints: ${constraints.maxHeight.toStringAsFixed(1)}');
        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            dev.log(
                '📜 [LazyLoading] Notification received: ${notification.runtimeType}');
            // Only process scroll update notifications
            if (notification is ScrollUpdateNotification) {
              final metrics = notification.metrics;

              dev.log(
                  '📜 [LazyLoading] ScrollNotification: pixels=${metrics.pixels.toStringAsFixed(1)}, maxScrollExtent=${metrics.maxScrollExtent.toStringAsFixed(1)}, isLoading=$_isLoading, hasMore=$_hasMore');

              // Check if scrollable and near bottom (within 200 pixels of bottom)
              if (metrics.maxScrollExtent > 0 && !_isLoading && _hasMore) {
                final threshold = metrics.maxScrollExtent - 200;
                dev.log(
                    '📐 [LazyLoading] Threshold check: threshold=${threshold.toStringAsFixed(1)}, pixels >= threshold? ${metrics.pixels >= threshold}');

                if (metrics.pixels >= threshold) {
                  dev.log(
                      '🚀 [LazyLoading] Triggering _loadMoreData: Reached threshold (${threshold.toStringAsFixed(1)})');
                  _loadMoreData();
                } else {
                  dev.log(
                      '⏸️ [LazyLoading] Not triggering: pixels (${metrics.pixels.toStringAsFixed(1)}) < threshold (${threshold.toStringAsFixed(1)})');
                }
              } else {
                if (metrics.maxScrollExtent <= 0) {
                  dev.log(
                      '⏸️ [LazyLoading] Not scrollable: maxScrollExtent=${metrics.maxScrollExtent}');
                }
                if (_isLoading) {
                  dev.log('⏸️ [LazyLoading] Not triggering: Already loading');
                }
                if (!_hasMore) {
                  dev.log('⏸️ [LazyLoading] Not triggering: No more data');
                }
              }
            } else {
              dev.log(
                  '📜 [LazyLoading] ScrollNotification type: ${notification.runtimeType} (not ScrollUpdateNotification)');
            }
            return false;
          },
          child: widget.builder(_restaurants, _isLoading, _hasMore),
        );
      },
    );
  }
}

/// Lazy loading widget specifically for popular restaurants
class LazyLoadingPopularRestaurantList extends StatefulWidget {
  final Widget Function(
      List<VendorModel> restaurants, bool isLoading, bool hasMore) builder;
  final int pageSize;

  const LazyLoadingPopularRestaurantList({
    Key? key,
    required this.builder,
    this.pageSize = 5,
  }) : super(key: key);

  @override
  _LazyLoadingPopularRestaurantListState createState() =>
      _LazyLoadingPopularRestaurantListState();
}

class _LazyLoadingPopularRestaurantListState
    extends State<LazyLoadingPopularRestaurantList> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  final ScrollController _scrollController = ScrollController();

  List<VendorModel> _restaurants = [];
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreData();
    }
  }

  Future<void> _loadInitialData() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load popular restaurants with pagination
      final restaurants = await _fireStoreUtils.getPopularRestaurantsPaginated(
        limit: widget.pageSize,
        lastDocument: null,
      );

      if (mounted) {
        setState(() {
          _restaurants = restaurants;
          _isLoading = false;
          _hasMore = restaurants.length == widget.pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final restaurants = await _fireStoreUtils.getPopularRestaurantsPaginated(
        limit: widget.pageSize,
        lastDocument: null, // Simplified for now
      );

      if (mounted) {
        setState(() {
          _restaurants.addAll(restaurants);
          _isLoading = false;
          _hasMore = restaurants.length == widget.pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels >=
            scrollInfo.metrics.maxScrollExtent * 0.8) {
          _loadMoreData();
        }
        return false;
      },
      child: widget.builder(_restaurants, _isLoading, _hasMore),
    );
  }
}

/// Lazy loading widget for products
class LazyLoadingProductList extends StatefulWidget {
  final String? vendorId;
  final String? categoryId;
  final Widget Function(
      List<ProductModel> products, bool isLoading, bool hasMore) builder;
  final int pageSize;

  const LazyLoadingProductList({
    Key? key,
    this.vendorId,
    this.categoryId,
    required this.builder,
    this.pageSize = 20,
  }) : super(key: key);

  @override
  _LazyLoadingProductListState createState() => _LazyLoadingProductListState();
}

class _LazyLoadingProductListState extends State<LazyLoadingProductList> {
  final FireStoreUtils _fireStoreUtils = FireStoreUtils();
  final ScrollController _scrollController = ScrollController();

  List<ProductModel> _products = [];
  bool _isLoading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreData();
    }
  }

  Future<void> _loadInitialData() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      List<ProductModel> products;

      if (widget.vendorId != null) {
        products = await _fireStoreUtils.getProductsByVendorPaginated(
          vendorId: widget.vendorId!,
          limit: widget.pageSize,
          lastDocument: null,
        );
      } else if (widget.categoryId != null) {
        products = await _fireStoreUtils.getProductsByCategoryPaginated(
          categoryId: widget.categoryId!,
          limit: widget.pageSize,
          lastDocument: null,
        );
      } else {
        products = await _fireStoreUtils.getAllProductsPaginated(
          limit: widget.pageSize,
          lastDocument: null,
        );
      }

      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
          _hasMore = products.length == widget.pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      List<ProductModel> products;

      if (widget.vendorId != null) {
        products = await _fireStoreUtils.getProductsByVendorPaginated(
          vendorId: widget.vendorId!,
          limit: widget.pageSize,
          lastDocument: null, // Simplified for now
        );
      } else if (widget.categoryId != null) {
        products = await _fireStoreUtils.getProductsByCategoryPaginated(
          categoryId: widget.categoryId!,
          limit: widget.pageSize,
          lastDocument: null,
        );
      } else {
        products = await _fireStoreUtils.getAllProductsPaginated(
          limit: widget.pageSize,
          lastDocument: null,
        );
      }

      if (mounted) {
        setState(() {
          _products.addAll(products);
          _isLoading = false;
          _hasMore = products.length == widget.pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels >=
            scrollInfo.metrics.maxScrollExtent * 0.8) {
          _loadMoreData();
        }
        return false;
      },
      child: widget.builder(_products, _isLoading, _hasMore),
    );
  }
}
