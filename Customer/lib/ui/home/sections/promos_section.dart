import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/coupon_service.dart';
import 'package:foodie_customer/services/data_cache_service.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/ui/home/sections/promo_card.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

/// Self-contained promos section. Owns loading/error/data state.
class PromosSection extends StatefulWidget {
  final void Function(List<OfferModel>)? onPromosLoaded;

  const PromosSection({Key? key, this.onPromosLoaded}) : super(key: key);

  @override
  State<PromosSection> createState() => _PromosSectionState();
}

class _PromosSectionState extends State<PromosSection> {
  List<OfferModel> _activePromos = [];
  bool _isLoading = true;
  bool _isError = false;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    _loadPromos();
  }

  Future<void> _loadPromos() async {
    if (!mounted) return;
    setState(() {
      _isError = false;
      _isLoading = true;
    });

    try {
      final coupons = await CouponService.getActiveCoupons(null);
      if (kDebugMode) {
        debugPrint('[PromosSection] Loaded ${coupons.length} coupons');
      }
      if (mounted) {
        setState(() {
          _activePromos = coupons;
          _retryAttempt = 0;
          _isLoading = false;
        });
        widget.onPromosLoaded?.call(coupons);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PromosSection] Error: $e');
      if (mounted) {
        setState(() {
          _isError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _onRetry() {
    final delay = Duration(seconds: 1 << _retryAttempt.clamp(0, 2));
    _retryAttempt = (_retryAttempt + 1).clamp(0, 3);
    Future.delayed(delay, _loadPromos);
  }

  @override
  Widget build(BuildContext context) {
    if (_activePromos.isEmpty && !_isError) {
      if (_isLoading) {
        return SizedBox(
          height: 200,
          child: ShimmerWidgets.productListShimmer(),
        );
      }
      return const SizedBox.shrink();
    }

    final isDark = isDarkMode(context);
    final screenWidth = MediaQuery.of(context).size.width;

    if (_isError) {
      return HomeSectionUtils.sectionError(
        message: 'Failed to load promos',
        onRetry: _onRetry,
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 0),
          cacheExtent: 300.0,
          itemCount: _activePromos.length >= 10 ? 10 : _activePromos.length,
          itemBuilder: (context, index) {
            final coupon = _activePromos[index];
            final vendor = coupon.restaurantId != null
                ? DataCacheService.instance.getVendor(coupon.restaurantId!)
                : null;
            return PromoCard(
              key: ValueKey(coupon.offerId ?? 'promo_$index'),
              coupon: coupon,
              isDark: isDark,
              screenWidth: screenWidth,
              vendor: vendor,
              index: index,
            );
          },
        ),
      ),
    );
  }
}
