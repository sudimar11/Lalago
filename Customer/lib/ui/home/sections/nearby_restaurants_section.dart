import 'dart:math';

import 'package:flutter/material.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/new_arrival_card.dart';
import 'package:foodie_customer/ui/home/view_all_new_arrival_restaurant_screen.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class NearbyRestaurantsSection extends StatefulWidget {
  final Stream<List<VendorModel>> vendorsStream;
  final List<VendorModel> fallbackVendors;
  final List<ProductModel> allProducts;
  final List<String> lstFav;
  final bool Function(VendorModel) isRestaurantOpen;
  final VoidCallback onFavoriteChanged;

  const NearbyRestaurantsSection({
    Key? key,
    required this.vendorsStream,
    required this.fallbackVendors,
    required this.allProducts,
    required this.lstFav,
    required this.isRestaurantOpen,
    required this.onFavoriteChanged,
  }) : super(key: key);

  @override
  State<NearbyRestaurantsSection> createState() =>
      _NearbyRestaurantsSectionState();
}

class _NearbyRestaurantsSectionState extends State<NearbyRestaurantsSection> {
  static const int _initialCount = 2;
  static const int _loadMoreCount = 3;
  static const int _maxCount = 15;

  int _visibleCount = _initialCount;
  final ScrollController _scrollController = ScrollController();
  int _lastDisplayListLength = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _lastDisplayListLength <= 0) return;
    final pos = _scrollController.position;
    final threshold = 100.0;
    if (pos.maxScrollExtent > 0 &&
        pos.pixels >= pos.maxScrollExtent - threshold) {
      final nextCount = min(
        _visibleCount + _loadMoreCount,
        _lastDisplayListLength,
      );
      if (nextCount > _visibleCount) {
        setState(() => _visibleCount = nextCount);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "Nearby Restaurants",
          titleIcon: Icons.restaurant_rounded,
          onClick: () {
            push(
              context,
              const ViewAllNewArrivalRestaurantScreen(),
            );
          },
        ),
        StreamBuilder<List<VendorModel>>(
          stream: widget.vendorsStream,
          initialData: const [],
          builder: (context, snapshot) {
            final nearbyAll =
                (snapshot.data ?? const <VendorModel>[]).toList();
            final fallbackAll =
                List<VendorModel>.from(widget.fallbackVendors);

            if (snapshot.connectionState == ConnectionState.waiting &&
                widget.fallbackVendors.isEmpty) {
              return Container(
                width: MediaQuery.of(context).size.width,
                height: 260,
                margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
                child: ShimmerWidgets.restaurantListShimmer(),
              );
            }

            if (context.mounted) {
              // Show all nearby/fallback vendors; closed ones show "Temporarily closed" on card
              List<VendorModel> displayList = nearbyAll.isNotEmpty
                  ? List<VendorModel>.from(nearbyAll)
                  : List<VendorModel>.from(fallbackAll);
              // Sort by distance so nearest shows first
              final loc = MyAppState.selectedPosotion.location;
              if (loc != null && displayList.length > 1) {
                displayList.sort((VendorModel a, VendorModel b) {
                  final distA = Geolocator.distanceBetween(
                    loc.latitude, loc.longitude, a.latitude, a.longitude,
                  );
                  final distB = Geolocator.distanceBetween(
                    loc.latitude, loc.longitude, b.latitude, b.longitude,
                  );
                  return distA.compareTo(distB);
                });
              }
              final maxDisplay = min(
                displayList.length,
                _maxCount,
              );

              // Update cap for scroll listener (sync)
              _lastDisplayListLength = maxDisplay;

              // Reset visible count when data changes
              if (_visibleCount > maxDisplay) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _visibleCount = _initialCount);
                  }
                });
              }

              return displayList.isEmpty
                  ? showEmptyState('No Vendors', context)
                  : _NearbyRestaurantsList(
                      displayList: displayList,
                      visibleCount: _visibleCount,
                      maxDisplay: maxDisplay,
                      scrollController: _scrollController,
                      allProducts: widget.allProducts,
                      lstFav: widget.lstFav,
                      onFavoriteChanged: widget.onFavoriteChanged,
                    );
            } else {
              return showEmptyState('No Vendors', context);
            }
          },
        ),
      ],
    );
  }
}

class _NearbyRestaurantsList extends StatelessWidget {
  final List<VendorModel> displayList;
  final int visibleCount;
  final int maxDisplay;
  final ScrollController scrollController;
  final List<ProductModel> allProducts;
  final List<String> lstFav;
  final VoidCallback onFavoriteChanged;

  const _NearbyRestaurantsList({
    required this.displayList,
    required this.visibleCount,
    required this.maxDisplay,
    required this.scrollController,
    required this.allProducts,
    required this.lstFav,
    required this.onFavoriteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = min(visibleCount, maxDisplay);

    return Container(
      width: MediaQuery.of(context).size.width,
      height: 260,
      margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
      child: RepaintBoundary(
        child: ListView.builder(
          controller: scrollController,
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          cacheExtent: 400.0,
          itemCount: itemCount,
          itemBuilder: (context, index) => NewArrivalCard(
            vendorModel: displayList[index],
            allProducts: allProducts,
            lstFav: lstFav,
            onFavoriteChanged: onFavoriteChanged,
          ),
        ),
      ),
    );
  }
}

