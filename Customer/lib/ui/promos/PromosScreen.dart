import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/coupon_service.dart';
import 'package:foodie_customer/services/helper.dart';

class PromosScreen extends StatefulWidget {
  const PromosScreen({Key? key}) : super(key: key);

  @override
  _PromosScreenState createState() => _PromosScreenState();
}

class _PromosScreenState extends State<PromosScreen> {
  List<OfferModel> _activeCoupons = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActiveCoupons();
  }

  Future<void> _loadActiveCoupons() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get vendorId from cart if available, otherwise null (shows all coupons)
      String? vendorId;
      String? userId;
      if (MyAppState.currentUser != null) {
        userId = MyAppState.currentUser!.userID;
        // For now, get all active coupons (vendor-specific filtering can be added later)
        vendorId = null;
      }

      final coupons = await CouponService.getActiveCoupons(
        vendorId,
        userId: userId,
      );
      setState(() {
        _activeCoupons = coupons;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load coupons. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode(context)
          ? const Color(DARK_COLOR)
          : const Color(0xffFFFFFF),
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        title: Text(
          'Promos',
          style: TextStyle(
              color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white,
              fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator.adaptive(
                valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SelectableText.rich(
                        TextSpan(
                          text: _error!,
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadActiveCoupons,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(COLOR_PRIMARY),
                        ),
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _activeCoupons.isEmpty
                  ? showEmptyState('No Active Promos', context)
                  : RefreshIndicator(
                      onRefresh: _loadActiveCoupons,
                      color: Color(COLOR_PRIMARY),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _activeCoupons.length,
                        itemBuilder: (context, index) {
                          return _buildCouponCard(_activeCoupons[index]);
                        },
                      ),
                    ),
    );
  }

  Widget _buildCouponCard(OfferModel coupon) {
    final discountText = _getDiscountText(coupon);
    final validityText = _getValidityText(coupon);
    final minOrderText = coupon.minOrderAmount != null
        ? 'Min. order: ${amountShow(amount: coupon.minOrderAmount!.toStringAsFixed(2))}'
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode(context)
              ? const Color(DarkContainerBorderColor)
              : Colors.grey.shade200,
          width: 1,
        ),
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
            : Colors.white,
        boxShadow: [
          if (!isDarkMode(context))
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showCouponDetails(coupon);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Coupon Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: getImageVAlidUrl(coupon.imageOffer ?? ''),
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade200,
                      ),
                      child: Icon(
                        Icons.local_offer,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    placeholder: (context, url) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade200,
                      ),
                      child: Center(
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Coupon Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        coupon.title ?? coupon.offerCode ?? 'Promo',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              isDarkMode(context) ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Short Description
                      if (coupon.shortDescription != null &&
                          coupon.shortDescription!.isNotEmpty)
                        Text(
                          coupon.shortDescription!,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode(context)
                                ? Colors.grey.shade300
                                : Colors.grey.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      // Discount Value
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          discountText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(COLOR_PRIMARY),
                          ),
                        ),
                      ),
                      // Minimum Order
                      if (minOrderText != null)
                        Text(
                          minOrderText,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode(context)
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                          ),
                        ),
                      const SizedBox(height: 4),
                      // Validity Period
                      Text(
                        validityText,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode(context)
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow Icon
                Icon(
                  Icons.chevron_right,
                  color: isDarkMode(context)
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getDiscountText(OfferModel coupon) {
    if (coupon.discount == null || coupon.discountType == null) {
      return '';
    }

    final discountValue = double.tryParse(coupon.discount!) ?? 0.0;
    final isPercentage = coupon.discountType!.toLowerCase() == 'percentage' ||
        coupon.discountType!.toLowerCase() == 'percent';

    if (isPercentage) {
      return '${discountValue.toStringAsFixed(0)}% OFF';
    } else {
      return '${amountShow(amount: discountValue.toStringAsFixed(2))} OFF';
    }
  }

  String _getValidityText(OfferModel coupon) {
    Timestamp? validUntil = coupon.validUntil ?? coupon.expireOfferDate;

    if (validUntil != null) {
      final endDate = validUntil.toDate();
      final formatter = DateFormat('MMM dd, yyyy');
      return 'Valid until ${formatter.format(endDate)}';
    }

    return 'Valid now';
  }

  void _showCouponDetails(OfferModel coupon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CouponDetailsSheet(coupon: coupon),
    );
  }
}

class _CouponDetailsSheet extends StatelessWidget {
  final OfferModel coupon;

  const _CouponDetailsSheet({required this.coupon});

  String _getDiscountText(OfferModel coupon) {
    if (coupon.discount == null || coupon.discountType == null) {
      return '';
    }

    final discountValue = double.tryParse(coupon.discount!) ?? 0.0;
    final isPercentage = coupon.discountType!.toLowerCase() == 'percentage' ||
        coupon.discountType!.toLowerCase() == 'percent';

    if (isPercentage) {
      return '${discountValue.toStringAsFixed(0)}% OFF';
    } else {
      return '${amountShow(amount: discountValue.toStringAsFixed(2))} OFF';
    }
  }

  String _getValidityText(OfferModel coupon) {
    Timestamp? validFrom = coupon.validFrom;
    Timestamp? validUntil = coupon.validUntil ?? coupon.expireOfferDate;
    final formatter = DateFormat('MMM dd, yyyy');

    if (validFrom != null && validUntil != null) {
      return '${formatter.format(validFrom.toDate())} - ${formatter.format(validUntil.toDate())}';
    } else if (validUntil != null) {
      return 'Valid until ${formatter.format(validUntil.toDate())}';
    }

    return 'Valid now';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
            : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Coupon Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Coupon Image
          if (coupon.imageOffer != null && coupon.imageOffer!.isNotEmpty)
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: getImageVAlidUrl(coupon.imageOffer!),
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    width: double.infinity,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                    ),
                    child: Icon(
                      Icons.local_offer,
                      size: 60,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Title
          Text(
            coupon.title ?? coupon.offerCode ?? 'Promo',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          // Discount
          Text(
            _getDiscountText(coupon),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(COLOR_PRIMARY),
            ),
          ),
          const SizedBox(height: 16),
          // Description
          if (coupon.descriptionOffer != null &&
              coupon.descriptionOffer!.isNotEmpty)
            Text(
              coupon.descriptionOffer!,
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade700,
              ),
            ),
          // Short Description
          if (coupon.shortDescription != null &&
              coupon.shortDescription!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                coupon.shortDescription!,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode(context)
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Minimum Order
          if (coupon.minOrderAmount != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.shopping_cart,
                    size: 16,
                    color: isDarkMode(context)
                        ? Colors.grey.shade400
                        : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Minimum order: ${amountShow(amount: coupon.minOrderAmount!.toStringAsFixed(2))}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode(context)
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          // Validity Period
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: isDarkMode(context)
                    ? Colors.grey.shade400
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                _getValidityText(coupon),
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode(context)
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Coupon Code Display
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode(context)
                        ? Colors.grey.shade800
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color(COLOR_PRIMARY),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Coupon Code',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode(context)
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        coupon.offerCode ?? '',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.copy),
                onPressed: () {
                  if (coupon.offerCode != null &&
                      coupon.offerCode!.isNotEmpty) {
                    Clipboard.setData(
                      ClipboardData(text: coupon.offerCode!),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Coupon code copied to clipboard'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Color(COLOR_PRIMARY),
                      ),
                    );
                  }
                },
                color: Color(COLOR_PRIMARY),
                tooltip: 'Copy coupon code',
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Info Text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Enter this code at checkout to apply the discount',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
