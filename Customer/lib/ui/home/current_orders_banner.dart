import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/ordertracknew.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/userPrefrence.dart';
import 'package:foodie_customer/utils/order_status_messages.dart';
import 'package:foodie_customer/widget/order_eta_badge.dart';
import 'package:foodie_customer/widget/order_status_progress_bar.dart';
import 'package:shimmer/shimmer.dart';

class CurrentOrdersBanner extends StatefulWidget {
  const CurrentOrdersBanner({Key? key}) : super(key: key);

  @override
  State<CurrentOrdersBanner> createState() => _CurrentOrdersBannerState();
}

class _CurrentOrdersBannerState extends State<CurrentOrdersBanner> {
  bool _isActiveStatus(String status) {
    final s = status.toLowerCase();
    return !(s == 'order completed' ||
            s == 'completed' ||
            s == 'delivered' ||
            s == 'order cancelled' ||
            s == 'cancelled') ||
        (s == 'order rejected' || s == 'rejected');
  }

  bool _isFinalStatus(String status) {
    final s = status.toLowerCase();
    return s == 'order completed' ||
        s == 'completed' ||
        s == 'delivered' ||
        s == 'order cancelled' ||
        s == 'cancelled';
  }

  /// Active = status from 'Order Placed' through 'In Transit' (inclusive).
  bool _isActiveOrder(String status) {
    final s = status.toLowerCase();
    return s == ORDER_STATUS_PLACED.toLowerCase() ||
        s == 'placed' ||
        s == ORDER_STATUS_ACCEPTED.toLowerCase() ||
        s == 'accepted' ||
        (s.contains('driver') && s.contains('assigned')) ||
        s == ORDER_STATUS_DRIVER_ACCEPTED.toLowerCase() ||
        s == ORDER_STATUS_SHIPPED.toLowerCase() ||
        s == 'shipped' ||
        s == ORDER_STATUS_IN_TRANSIT.toLowerCase() ||
        s == ORDER_STATUS_DRIVER_REJECTED.toLowerCase();
  }

  bool _isOrderFromToday(OrderModel order) {
    final DateTime orderDate = order.createdAt.toDate();
    final DateTime today = DateTime.now();

    return orderDate.year == today.year &&
        orderDate.month == today.month &&
        orderDate.day == today.day;
  }

  void _onCloseOrder() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<OrderModel>>(
      stream: FireStoreUtils()
          .getOrders(MyAppState.currentUser!.userID)
          .map((orders) {
        final activeToday = orders
            .where((o) =>
                _isActiveOrder(o.status) && _isOrderFromToday(o))
            .toList();
        return activeToday.take(5).toList();
      }),
      builder: (context, snapshot) {
        final bool isEmpty;
        final Widget content;
        final String bannerKey;

        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData ||
            (snapshot.data?.isEmpty ?? true)) {
          isEmpty = true;
          content = const SizedBox.shrink();
          bannerKey = 'empty';
        } else {
          final List<OrderModel> orders = snapshot.data!;
          final String userId = MyAppState.currentUser!.userID;
          final List<OrderModel> visibleOrders = <OrderModel>[];

          for (final order in orders) {
            if (UserPreference.isOrderBannerPermanentlyHidden(
                userId, order.id)) {
              continue;
            }
            if (_isFinalStatus(order.status)) {
              UserPreference.markOrderBannerAsPermanentlyHidden(
                  userId, order.id);
              continue;
            }
            if (UserPreference.isOrderBannerClosed(
                userId, order.id, order.status)) {
              continue;
            }
            final String statusLower = order.status.toLowerCase();
            final bool isRejected =
                statusLower == 'order rejected' || statusLower == 'rejected';
            if (isRejected &&
                UserPreference.isRejectedBannerViewed(userId, order.id)) {
              continue;
            }
            visibleOrders.add(order);
          }

          if (visibleOrders.isEmpty) {
            isEmpty = true;
            content = const SizedBox.shrink();
            bannerKey = 'empty';
          } else {
            isEmpty = false;
            content = visibleOrders.length == 1
                ? _buildSingleOrderBanner(
                    visibleOrders.first, _onCloseOrder)
                : _buildMultipleOrdersBanner(
                    visibleOrders, _onCloseOrder);
            if (visibleOrders.length == 1) {
              bannerKey = 'single_${visibleOrders.first.id}';
            } else {
              final ids = visibleOrders.map((o) => o.id).toList()..sort();
              bannerKey = 'multiple_${visibleOrders.length}_${ids.join(",")}';
            }
          }
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<String>(bannerKey),
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildSingleOrderBanner(
      OrderModel order, VoidCallback onCloseOrder) {
    return _BannerContent(
      order: order,
      hasMultipleActiveOrders: false,
      onCloseOrder: onCloseOrder,
    );
  }

  Widget _buildMultipleOrdersBanner(
      List<OrderModel> orders, VoidCallback onCloseOrder) {
    return _MultipleOrdersBannerContent(
      orders: orders,
      onCloseOrder: onCloseOrder,
    );
  }
}

class _MultipleOrdersBannerContent extends StatefulWidget {
  final List<OrderModel> orders;
  final VoidCallback? onCloseOrder;

  const _MultipleOrdersBannerContent({
    Key? key,
    required this.orders,
    this.onCloseOrder,
  }) : super(key: key);

  @override
  State<_MultipleOrdersBannerContent> createState() =>
      _MultipleOrdersBannerContentState();
}

class _MultipleOrdersBannerContentState
    extends State<_MultipleOrdersBannerContent> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.orders.length;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Order ${_currentPage + 1} of $count',
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDarkMode(context)
                    ? Colors.white70
                    : const Color(0xFF666666),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 300,
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (int index) {
                setState(() => _currentPage = index);
              },
              itemCount: count,
              itemBuilder: (BuildContext context, int index) {
                return _BannerContent(
                  order: widget.orders[index],
                  hasMultipleActiveOrders: true,
                  onCloseOrder: widget.onCloseOrder,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerContent extends StatefulWidget {
  final OrderModel order;
  final bool hasMultipleActiveOrders;
  final VoidCallback? onCloseOrder;

  const _BannerContent({
    Key? key,
    required this.order,
    this.hasMultipleActiveOrders = false,
    this.onCloseOrder,
  }) : super(key: key);

  @override
  State<_BannerContent> createState() => _BannerContentState();
}

class _BannerContentState extends State<_BannerContent> {
  Timer? _ticker;
  double _progress = 0.0; // 0..1
  bool _isLoadingReco = false;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;
  bool _isBannerClosed = false;
  bool _hasBeenTracked = false;
  bool _hasLoggedBannerShown = false;
  bool _hasLoggedBannerDismissed = false;
  bool _hasLoggedRejectedViewed = false;
  bool _hasLoggedReorderTapped = false;
  List<ProductModel> _recoProducts = [];
  final Map<String, VendorModel?> _vendorCache = {};
  final ScrollController _scrollController = ScrollController();
  int _currentBatch = 0;
  static const int _batchSize = 10;
  List<ProductModel> _allSimilarProducts = [];
  bool _hasMoreData = true;

  @override
  void initState() {
    super.initState();
    _startTicker();
    _scrollController.addListener(_onScroll);
    if ((widget.order.status.toLowerCase() == 'order rejected') ||
        (widget.order.status.toLowerCase() == 'rejected')) {
      _loadRecommendations();
      // Track when banner is fully rendered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markBannerAsViewed();
      });
    }
    // Track banner shown event
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logBannerShown();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreRecommendations();
    }
  }

  void _startTicker() {
    final int totalSeconds = _deriveTotalSecondsFromOrder();
    final DateTime start = widget.order.createdAt.toDate();
    void update() {
      if (!mounted) return;

      final int elapsed = DateTime.now().difference(start).inSeconds;
      final int elapsedClamped = elapsed.clamp(0, totalSeconds);

      // Check if status is before ORDER_STATUS_SHIPPED
      final String statusLower = widget.order.status.toLowerCase();
      final bool isBeforeShipped = !(statusLower == 'order shipped' ||
          statusLower == 'shipped' ||
          statusLower == 'in transit');

      final double newProgress = elapsedClamped / totalSeconds;

      // Stop timer if it reaches 100% and order hasn't shipped yet
      if (newProgress >= 1.0 && isBeforeShipped) {
        _ticker?.cancel();
        _ticker = null;
        setState(() {
          _progress = 1.0;
        });
        return;
      }

      setState(() {
        _progress = newProgress;
      });
    }

    update();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  Future<void> _loadRecommendations() async {
    if (_isLoadingReco || _recoProducts.isNotEmpty) return;
    setState(() {
      _isLoadingReco = true;
    });

    try {
      // Get rejected items for similarity matching
      final rejectedItems = widget.order.products;
      if (rejectedItems.isEmpty) {
        setState(() {
          _recoProducts = [];
        });
        return;
      }

      // Get the vendor ID that rejected the order (to exclude it)
      final rejectedVendorId = widget.order.vendor.id;

      // Extract keywords from rejected items for similarity matching
      final rejectedKeywords = <String>[];
      for (final item in rejectedItems) {
        // Split product name into words and add to keywords
        final words = item.name
            .toLowerCase()
            .split(RegExp(r'[^a-zA-Z0-9]'))
            .where((word) => word.length > 2)
            .toList();
        rejectedKeywords.addAll(words);
      }

      // Remove duplicates and common words
      final uniqueKeywords = rejectedKeywords
          .toSet()
          .where((word) => ![
                'the',
                'and',
                'with',
                'for',
                'from',
                'food',
                'item'
              ].contains(word))
          .toList();

      // Fetch all published products from other restaurants
      final snap = await FireStoreUtils.firestore
          .collection(PRODUCTS)
          .where('publish', isEqualTo: true)
          .get();

      final allProducts = snap.docs
          .map((d) => ProductModel.fromJson(d.data()))
          .where((p) =>
              p.vendorID != rejectedVendorId) // Exclude rejected restaurant
          .toList();

      // Score products based on similarity to rejected items
      final scoredProducts = <MapEntry<ProductModel, int>>[];

      for (final product in allProducts) {
        int score = 0;
        final productWords = product.name
            .toLowerCase()
            .split(RegExp(r'[^a-zA-Z0-9]'))
            .where((word) => word.length > 2)
            .toSet();

        // Check for keyword matches
        for (final keyword in uniqueKeywords) {
          if (productWords.contains(keyword)) {
            score += 2; // Higher weight for exact matches
          } else if (productWords.any(
              (word) => word.contains(keyword) || keyword.contains(word))) {
            score += 1; // Partial matches
          }
        }

        // Check category similarity
        for (final rejectedItem in rejectedItems) {
          if (product.categoryID == rejectedItem.category_id) {
            score += 3; // High weight for same category
          }
        }

        // Check name similarity (fuzzy matching)
        for (final rejectedItem in rejectedItems) {
          final rejectedName = rejectedItem.name.toLowerCase();
          final productName = product.name.toLowerCase();
          if (rejectedName.contains(productName) ||
              productName.contains(rejectedName)) {
            score += 4; // Highest weight for name similarity
          }
        }

        if (score > 0) {
          scoredProducts.add(MapEntry(product, score));
        }
      }

      // Sort by score (highest first) and store all similar products
      scoredProducts.sort((a, b) => b.value.compareTo(a.value));
      _allSimilarProducts = scoredProducts.map((entry) => entry.key).toList();

      // If we don't have enough similar products, fill with random products from other restaurants
      if (_allSimilarProducts.length < 30) {
        final remaining = 30 - _allSimilarProducts.length;
        final usedIds = _allSimilarProducts.map((p) => p.id).toSet();
        final randomProducts = allProducts
            .where((p) => !usedIds.contains(p.id))
            .toList()
          ..shuffle(Random());

        _allSimilarProducts.addAll(randomProducts.take(remaining));
      }

      // Load first batch
      _loadFirstBatch();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReco = false;
        });
      }
    }
  }

  double _avgRating(ProductModel p) {
    final count = p.reviewsCount == 0 ? 0 : p.reviewsCount;
    if (count == 0) return 0.0;
    final sum = p.reviewsSum.toDouble();
    final cnt = p.reviewsCount.toDouble();
    return (cnt == 0) ? 0.0 : (sum / cnt).clamp(0.0, 5.0);
  }

  String _displayPrice(ProductModel p) {
    final hasDiscount = (p.disPrice != null && p.disPrice != '0');
    final priceStr = hasDiscount ? p.disPrice! : p.price;
    return amountShow(amount: priceStr);
  }

  Future<void> _loadFirstBatch() async {
    if (_allSimilarProducts.isEmpty) return;

    final firstBatch = _allSimilarProducts.take(_batchSize).toList();
    _recoProducts = firstBatch;
    _currentBatch = 1;
    _hasMoreData = _allSimilarProducts.length > _batchSize;

    // Cache vendor information for first batch
    await _cacheVendorInfo(firstBatch);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadMoreRecommendations() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() {
      _isLoadingMore = true;
    });

    // Simulate loading delay
    await Future.delayed(const Duration(milliseconds: 500));

    final startIndex = _currentBatch * _batchSize;
    final endIndex =
        (startIndex + _batchSize).clamp(0, _allSimilarProducts.length);

    if (startIndex < _allSimilarProducts.length) {
      final newBatch = _allSimilarProducts.sublist(startIndex, endIndex);
      _recoProducts.addAll(newBatch);
      _currentBatch++;
      _hasMoreData = endIndex < _allSimilarProducts.length;

      // Cache vendor information for new batch
      await _cacheVendorInfo(newBatch);
    }

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _cacheVendorInfo(List<ProductModel> products) async {
    final vendorIds = products.map((p) => p.vendorID).toSet().toList();
    await Future.wait(vendorIds.map((vid) async {
      if (_vendorCache.containsKey(vid)) return;
      try {
        final vendor = await FireStoreUtils.getVendor(vid);
        _vendorCache[vid] = vendor;
      } catch (_) {
        _vendorCache[vid] = null;
      }
    }));
  }

  Future<void> _refreshRecommendations() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _recoProducts.clear();
      _allSimilarProducts.clear();
      _currentBatch = 0;
      _hasMoreData = true;
      _vendorCache.clear();
    });

    // Reset scroll position
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    // Reload recommendations with same algorithm
    await _loadRecommendations();

    setState(() {
      _isRefreshing = false;
    });
  }

  void _closeOrder() {
    _markBannerAsViewed();
    _logBannerDismissed();
    setState(() {
      _isBannerClosed = true;
    });

    final String? userId = MyAppState.currentUser?.userID;
    if (userId == null ||
        userId.isEmpty ||
        widget.order.id.isEmpty) return;

    UserPreference.markOrderBannerClosed(
      userId,
      widget.order.id,
      widget.order.status,
    ).then((_) => widget.onCloseOrder?.call());
  }

  void _markBannerAsViewed() {
    // Only track once per banner instance
    if (_hasBeenTracked) return;

    // Only track for rejected orders
    final String statusLower = widget.order.status.toLowerCase();
    final bool isRejected =
        statusLower == 'order rejected' || statusLower == 'rejected';
    if (!isRejected) return;

    // Get user ID and order ID
    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) return;
    if (widget.order.id.isEmpty) return;

    // Mark as tracked to prevent duplicate calls
    _hasBeenTracked = true;

    // Mark as viewed asynchronously (non-blocking)
    UserPreference.markRejectedBannerAsViewed(
        MyAppState.currentUser!.userID, widget.order.id);

    // Log rejected banner viewed event
    _logRejectedBannerViewed();
  }

  void _logBannerShown() {
    if (_hasLoggedBannerShown) return;
    _hasLoggedBannerShown = true;

    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) return;
    if (widget.order.id.isEmpty) return;

    FireStoreUtils().trackBannerEvent(
      userId: MyAppState.currentUser!.userID,
      eventType: 'banner_shown',
      orderId: widget.order.id,
      orderStatus: widget.order.status,
    );
  }

  void _logBannerDismissed() {
    if (_hasLoggedBannerDismissed) return;
    _hasLoggedBannerDismissed = true;

    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) return;
    if (widget.order.id.isEmpty) return;

    FireStoreUtils().trackBannerEvent(
      userId: MyAppState.currentUser!.userID,
      eventType: 'banner_dismissed',
      orderId: widget.order.id,
      orderStatus: widget.order.status,
    );
  }

  void _logRejectedBannerViewed() {
    if (_hasLoggedRejectedViewed) return;
    _hasLoggedRejectedViewed = true;

    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) return;
    if (widget.order.id.isEmpty) return;

    FireStoreUtils().trackBannerEvent(
      userId: MyAppState.currentUser!.userID,
      eventType: 'rejected_banner_viewed',
      orderId: widget.order.id,
      orderStatus: widget.order.status,
    );
  }

  void _logReorderCTATapped() {
    if (_hasLoggedReorderTapped) return;
    _hasLoggedReorderTapped = true;

    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) return;
    if (widget.order.id.isEmpty) return;

    FireStoreUtils().trackBannerEvent(
      userId: MyAppState.currentUser!.userID,
      eventType: 'reorder_cta_tapped',
      orderId: widget.order.id,
      orderStatus: widget.order.status,
    );
  }

  @override
  void didUpdateWidget(covariant _BannerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.status != widget.order.status) {
      // Reset close state when order status changes
      _isBannerClosed = false;

      // Restart timer if status changed (might have progressed to shipped)
      if (_ticker == null) {
        _startTicker();
      }

      if ((widget.order.status.toLowerCase() == 'order rejected') ||
          (widget.order.status.toLowerCase() == 'rejected')) {
        _loadRecommendations();
      }
    }
  }

  // Match parsing used in OrderDetailsScreen: supports "HH:mm" or minutes
  int _deriveTotalSecondsFromOrder() {
    final String raw = (widget.order.estimatedTimeToPrepare ?? '').trim();
    if (raw.isEmpty) {
      return 20 * 60; // default 20 minutes
    }

    if (raw.contains(':')) {
      final parts = raw.split(':');
      int hours = 0;
      int minutes = 0;
      if (parts.isNotEmpty) {
        hours = int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      }
      if (parts.length > 1) {
        minutes = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      }
      final int seconds = hours * 3600 + minutes * 60;
      return seconds > 0 ? seconds : 20 * 60;
    }

    final match = RegExp(r"\d+").firstMatch(raw);
    final int minutes = int.tryParse(match?.group(0) ?? '') ?? 0;
    return ((minutes > 0 ? minutes : 20) * 60).clamp(60, 24 * 60 * 60);
  }

  String _formatEstimatedPrep() {
    final String raw = (widget.order.estimatedTimeToPrepare ?? '').trim();
    if (raw.isEmpty) {
      return '20m';
    }

    if (raw.contains(':')) {
      final parts = raw.split(':');
      final int hours =
          int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final int minutes = parts.length > 1
          ? int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
          : 0;
      if (hours == 0) {
        return '${minutes > 0 ? minutes : 20}m';
      }
      return '${hours}h';
    }

    final match = RegExp(r"\d+").firstMatch(raw);
    final int minutes = int.tryParse(match?.group(0) ?? '') ?? 0;
    return '${minutes > 0 ? minutes : 20}m';
  }

  String _formatOrderTime() {
    final DateTime orderTime = widget.order.createdAt.toDate();
    final now = DateTime.now();
    final diff = now.difference(orderTime);

    if (diff.inMinutes < 1) {
      return 'Ordered just now';
    } else if (diff.inMinutes < 60) {
      return 'Ordered ${diff.inMinutes}m ago';
    } else {
      final hours = diff.inHours;
      final minutes = diff.inMinutes.remainder(60);
      if (minutes == 0) {
        return 'Ordered ${hours}h ago';
      }
      return 'Ordered ${hours}h ${minutes}m ago';
    }
  }

  bool _shouldShowTimer() {
    final String statusLower = widget.order.status.toLowerCase();
    final bool isBeforeShipped = !(statusLower == 'order shipped' ||
        statusLower == 'shipped' ||
        statusLower == 'in transit');

    // Hide timer if it has reached 100% and order hasn't shipped yet
    if (_progress >= 1.0 && isBeforeShipped) {
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    // Track banner view when user navigates away (if banner was visible)
    if (!_isBannerClosed) {
      _markBannerAsViewed();
    }
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildShimmerCard() {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(COLOR_PRIMARY).withOpacity(0.25),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Shimmer.fromColors(
              baseColor:
                  isDarkMode(context) ? Colors.grey[800]! : Colors.grey[300]!,
              highlightColor:
                  isDarkMode(context) ? Colors.grey[700]! : Colors.grey[100]!,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Restaurant name placeholder
                Shimmer.fromColors(
                  baseColor: isDarkMode(context)
                      ? Colors.grey[800]!
                      : Colors.grey[300]!,
                  highlightColor: isDarkMode(context)
                      ? Colors.grey[700]!
                      : Colors.grey[100]!,
                  child: Container(
                    height: 12,
                    width: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Product name placeholder
                Shimmer.fromColors(
                  baseColor: isDarkMode(context)
                      ? Colors.grey[800]!
                      : Colors.grey[300]!,
                  highlightColor: isDarkMode(context)
                      ? Colors.grey[700]!
                      : Colors.grey[100]!,
                  child: Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Price and rating placeholders
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Shimmer.fromColors(
                      baseColor: isDarkMode(context)
                          ? Colors.grey[800]!
                          : Colors.grey[300]!,
                      highlightColor: isDarkMode(context)
                          ? Colors.grey[700]!
                          : Colors.grey[100]!,
                      child: Container(
                        height: 13,
                        width: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    Shimmer.fromColors(
                      baseColor: isDarkMode(context)
                          ? Colors.grey[800]!
                          : Colors.grey[300]!,
                      highlightColor: isDarkMode(context)
                          ? Colors.grey[700]!
                          : Colors.grey[100]!,
                      child: Container(
                        height: 12,
                        width: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Return empty widget if banner is closed
    if (_isBannerClosed) {
      return const SizedBox.shrink();
    }

    final Color bgColor =
        isDarkMode(context) ? const Color(DarkContainerColor) : Colors.white;
    final Color borderColor = Color(COLOR_PRIMARY);
    final String productImageUrl = (widget.order.products.isNotEmpty &&
            widget.order.products.first.photo.isNotEmpty)
        ? widget.order.products.first.photo
        : '';
    final String statusLower = widget.order.status.toLowerCase();
    final bool isPlaced =
        statusLower == 'order placed' || statusLower == 'placed';
    final String restaurantName =
        widget.order.vendor.title.isNotEmpty ? widget.order.vendor.title : '';
    final bool isAccepted =
        statusLower == 'order accepted' || statusLower == 'accepted';
    final bool isDriverAssigned = statusLower.contains('driver') &&
        (statusLower.contains('assigned') || statusLower.contains('pending'));
    final bool isDriverPending = statusLower == 'driver pending';
    final bool isInTransit = statusLower == 'in transit';
    final bool isShipped =
        statusLower == 'order shipped' || statusLower == 'shipped';
    final bool isTrackable = isShipped || isInTransit;
    final bool isRejected =
        statusLower == 'order rejected' || statusLower == 'rejected';

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 2),
                    boxShadow: [
                      isDarkMode(context)
                          ? const BoxShadow()
                          : BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                    ],
                  ),
                  child: InkWell(
                    onTap: () {
                      _markBannerAsViewed();
                      push(
                        context,
                        OrderDetailsScreen(orderModel: widget.order),
                      );
                    },
                    child: Row(
                      children: [
                        if (!isRejected) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 52,
                              height: 52,
                              color: Color(COLOR_PRIMARY).withOpacity(0.08),
                              child: (isAccepted ||
                                          isDriverAssigned ||
                                          isInTransit) &&
                                      _shouldShowTimer()
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Background track (full circle, light grey)
                                        SizedBox(
                                          width: 46,
                                          height: 46,
                                          child: CircularProgressIndicator(
                                            value: 1,
                                            strokeWidth: 5,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.black12,
                                            ),
                                          ),
                                        ),
                                        // Foreground progress according to restaurant estimate
                                        SizedBox(
                                          width: 46,
                                          height: 46,
                                          child: CircularProgressIndicator(
                                            value: _progress.clamp(0.0, 1.0),
                                            strokeWidth: 5,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Color(COLOR_PRIMARY),
                                            ),
                                            backgroundColor: Colors.transparent,
                                          ),
                                        ),
                                        // Remaining minutes in center
                                        Text(
                                          _formatEstimatedPrep(),
                                          style: TextStyle(
                                            fontFamily: 'Poppinsm',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isDarkMode(context)
                                                ? Colors.white
                                                : const Color(0xFF000000),
                                          ),
                                        ),
                                      ],
                                    )
                                  : (productImageUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl:
                                              getImageVAlidUrl(productImageUrl),
                                          memCacheWidth: 200,
                                          memCacheHeight: 200,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) =>
                                              Icon(
                                            Icons.fastfood,
                                            color: Color(COLOR_PRIMARY),
                                          ),
                                        )
                                      : Icon(
                                          Icons.fastfood,
                                          color: Color(COLOR_PRIMARY),
                                        )),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isRejected) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.cancel,
                                      size: 20,
                                      color: const Color(0xFFFF5252),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Your order was rejected by the restaurant.',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Poppinsm',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: isDarkMode(context)
                                              ? const Color(0xFFFF6B6B)
                                              : const Color(0xFFFF5252),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.only(left: 28),
                                  child: Text(
                                    widget.order.rejectionReason != null &&
                                            widget.order.rejectionReason!
                                                .isNotEmpty
                                        ? 'Reason: ${widget.order.rejectionReason}'
                                        : 'Reason: Not specified by the restaurant.',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppinsm',
                                      fontSize: 12,
                                      color: isDarkMode(context)
                                          ? Colors.white70
                                          : const Color(0xFF666666),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_recoProducts.isNotEmpty ||
                                    _isLoadingReco ||
                                    _isRefreshing)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: (_recoProducts.isNotEmpty &&
                                                !_isLoadingReco &&
                                                !_isRefreshing)
                                            ? () {
                                                _logReorderCTATapped();
                                                if (_scrollController
                                                    .hasClients) {
                                                  _scrollController.animateTo(
                                                    0.0,
                                                    duration: const Duration(
                                                        milliseconds: 300),
                                                    curve: Curves.easeOut,
                                                  );
                                                }
                                              }
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(COLOR_PRIMARY),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: Text(
                                          'Reorder Similar Items',
                                          style: TextStyle(
                                            fontFamily: 'Poppinsm',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Container(
                                  height: 620,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: _isLoadingReco || _isRefreshing
                                      ? GridView.builder(
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 2,
                                            childAspectRatio: 0.78,
                                            crossAxisSpacing: 10,
                                            mainAxisSpacing: 10,
                                          ),
                                          itemCount:
                                              6, // Show 6 shimmer cards initially
                                          itemBuilder: (context, index) =>
                                              _buildShimmerCard(),
                                        )
                                      : (_recoProducts.isEmpty
                                          ? const SizedBox.shrink()
                                          : RefreshIndicator(
                                              onRefresh:
                                                  _refreshRecommendations,
                                              child: GridView.builder(
                                                controller: _scrollController,
                                                gridDelegate:
                                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  childAspectRatio: 0.78,
                                                  crossAxisSpacing: 10,
                                                  mainAxisSpacing: 10,
                                                ),
                                                itemCount: _recoProducts
                                                        .length +
                                                    (_isLoadingMore ? 2 : 0),
                                                itemBuilder: (context, index) {
                                                  if (index >=
                                                      _recoProducts.length) {
                                                    // Show shimmer cards for loading more
                                                    return _buildShimmerCard();
                                                  }
                                                  final p =
                                                      _recoProducts[index];
                                                  final vendor =
                                                      _vendorCache[p.vendorID];
                                                  final vendorName =
                                                      (vendor?.title ?? '')
                                                              .isNotEmpty
                                                          ? vendor!.title
                                                          : '';
                                                  final rating = _avgRating(p);

                                                  return GestureDetector(
                                                    onTap: () {
                                                      push(
                                                        context,
                                                        ProductDetailsScreen(
                                                          productModel: p,
                                                          vendorModel: vendor ??
                                                              VendorModel(),
                                                        ),
                                                      );
                                                    },
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: isDarkMode(
                                                                context)
                                                            ? const Color(
                                                                DarkContainerColor)
                                                            : Colors.white,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                        border: Border.all(
                                                          color: Color(
                                                                  COLOR_PRIMARY)
                                                              .withOpacity(
                                                                  0.25),
                                                          width: 1,
                                                        ),
                                                        boxShadow:
                                                            isDarkMode(context)
                                                                ? const []
                                                                : [
                                                                    BoxShadow(
                                                                      color: Colors
                                                                          .black
                                                                          .withOpacity(
                                                                              0.06),
                                                                      blurRadius:
                                                                          10,
                                                                      offset:
                                                                          const Offset(
                                                                              0,
                                                                              4),
                                                                    ),
                                                                  ],
                                                      ),
                                                      clipBehavior:
                                                          Clip.antiAlias,
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          AspectRatio(
                                                            aspectRatio:
                                                                16 / 10,
                                                            child:
                                                                CachedNetworkImage(
                                                              imageUrl:
                                                                  getImageVAlidUrl(
                                                                      p.photo),
                                                              memCacheWidth: 200,
                                                              memCacheHeight: 200,
                                                              fit: BoxFit.cover,
                                                              errorWidget: (context,
                                                                      url,
                                                                      error) =>
                                                                  Container(
                                                                color: Color(
                                                                        COLOR_PRIMARY)
                                                                    .withOpacity(
                                                                        0.06),
                                                                child: Icon(
                                                                  Icons
                                                                      .fastfood,
                                                                  color: Color(
                                                                      COLOR_PRIMARY),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 8),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        10),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                if (vendorName
                                                                    .isNotEmpty)
                                                                  Text(
                                                                    vendorName,
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                    style:
                                                                        TextStyle(
                                                                      fontFamily:
                                                                          'Poppinsm',
                                                                      fontSize:
                                                                          12,
                                                                      color: isDarkMode(
                                                                              context)
                                                                          ? Colors
                                                                              .white70
                                                                          : const Color(
                                                                              0xFF666666),
                                                                    ),
                                                                  ),
                                                                Text(
                                                                  p.name,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style:
                                                                      TextStyle(
                                                                    fontFamily:
                                                                        'Poppinsm',
                                                                    fontSize:
                                                                        14,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                    color: isDarkMode(
                                                                            context)
                                                                        ? Colors
                                                                            .white
                                                                        : const Color(
                                                                            0xFF000000),
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    height: 6),
                                                                Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .spaceBetween,
                                                                  children: [
                                                                    Text(
                                                                      _displayPrice(
                                                                          p),
                                                                      style:
                                                                          TextStyle(
                                                                        fontFamily:
                                                                            'Poppinsm',
                                                                        fontSize:
                                                                            13,
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                        color: isDarkMode(context)
                                                                            ? Colors.white
                                                                            : const Color(0xFF000000),
                                                                      ),
                                                                    ),
                                                                    Row(
                                                                      children: [
                                                                        Icon(
                                                                          Icons
                                                                              .star_rounded,
                                                                          size:
                                                                              16,
                                                                          color:
                                                                              const Color(0xFFFFB74D),
                                                                        ),
                                                                        const SizedBox(
                                                                            width:
                                                                                2),
                                                                        Text(
                                                                          rating
                                                                              .toStringAsFixed(1),
                                                                          style:
                                                                              TextStyle(
                                                                            fontFamily:
                                                                                'Poppinsm',
                                                                            fontSize:
                                                                                12,
                                                                            color: isDarkMode(context)
                                                                                ? Colors.white
                                                                                : const Color(0xFF000000),
                                                                          ),
                                                                        ),
                                                                      ],
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
                                                },
                                              ))),
                                ),
                              ] else if (isPlaced) ...[
                                Text(
                                  'We have sent your order to',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppinsm',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : const Color(0xFF000000),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  restaurantName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppinsm',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : const Color(0xFF000000),
                                  ),
                                ),
                              ] else if (isAccepted) ...[
                                Text(
                                  'Your order is on the way to',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppinsm',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : const Color(0xFF000000),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  restaurantName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppinsm',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : const Color(0xFF000000),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Estimate time for preparation of your orders',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppinsm',
                                    fontSize: 12,
                                    color: isDarkMode(context)
                                        ? Colors.white70
                                        : const Color(0xFF666666),
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  (isDriverPending
                                      ? 'Preparing your order'
                                      : isDriverAssigned
                                          ? 'Looking for delivery riders'
                                          : 'Your order is on the way'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Poppinsm',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : const Color(0xFF000000),
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              if (!isRejected) ...[
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: OrderStatusProgressBar(
                                          status: widget.order.status),
                                    ),
                                    if (isInTransit) ...[
                                      const SizedBox(width: 8),
                                      OrderETABadge(order: widget.order),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                              ],
                              if (!isRejected)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        size: 11,
                                        color: isDarkMode(context)
                                            ? Colors.white.withOpacity(0.5)
                                            : const Color(0xFF999999),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        _formatOrderTime(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Poppinsm',
                                          fontSize: 10,
                                          color: isDarkMode(context)
                                              ? Colors.white.withOpacity(0.5)
                                              : const Color(0xFF999999),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (!isRejected) ...[
                          const SizedBox(width: 8),
                          if (isTrackable)
                            TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: Color(COLOR_PRIMARY),
                                padding: EdgeInsets.only(top: 12, bottom: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    side: BorderSide(
                                        color: isDarkMode(context)
                                            ? Colors.grey.shade700
                                            : Colors.grey.shade200)),
                              ),
                              child: Text(
                                getButtonText(widget.order.status),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : Colors.white),
                              ),
                              onPressed: () async {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OrderTrackingPage(
                                        orderId: widget.order.id),
                                  ),
                                );
                              },
                            )
                          else
                            TextButton(
                              onPressed: () {
                                push(
                                  context,
                                  OrderDetailsScreen(orderModel: widget.order),
                                );
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.transparent,
                                backgroundColor: Colors.transparent,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(36, 36),
                              ),
                              child: SizedBox(
                                width: 70,
                                height: 70,
                                child: isDriverPending
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(35),
                                        child: widget.order.driver
                                                        ?.profilePictureURL !=
                                                    null &&
                                                widget
                                                    .order
                                                    .driver!
                                                    .profilePictureURL
                                                    .isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: getImageVAlidUrl(
                                                    widget.order.driver!
                                                        .profilePictureURL),
                                                memCacheWidth: 120,
                                                memCacheHeight: 120,
                                                fit: BoxFit.cover,
                                                width: 70,
                                                height: 70,
                                                errorWidget:
                                                    (context, url, error) =>
                                                        Container(
                                                  width: 70,
                                                  height: 70,
                                                  decoration: BoxDecoration(
                                                    color: Color(COLOR_PRIMARY)
                                                        .withOpacity(0.1),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    Icons.person,
                                                    size: 35,
                                                    color: Color(COLOR_PRIMARY),
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                width: 70,
                                                height: 70,
                                                decoration: BoxDecoration(
                                                  color: Color(COLOR_PRIMARY)
                                                      .withOpacity(0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.person,
                                                  size: 35,
                                                  color: Color(COLOR_PRIMARY),
                                                ),
                                              ),
                                      )
                                    : Image.asset(
                                        'assets/design.png',
                                        fit: BoxFit.contain,
                                      ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Close button in top-right corner
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _closeOrder,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDarkMode(context)
                            ? Colors.black.withOpacity(0.6)
                            : Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
