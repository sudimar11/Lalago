import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/promos/PromosScreen.dart';

class PromoCard extends StatefulWidget {
  final OfferModel coupon;
  final bool isDark;
  final double screenWidth;
  final VendorModel? vendor;
  final int? index;

  const PromoCard({
    Key? key,
    required this.coupon,
    required this.isDark,
    required this.screenWidth,
    this.vendor,
    this.index,
  }) : super(key: key);

  @override
  State<PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<PromoCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('PromoCard ${widget.coupon.offerId} CREATED');
    }
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('PromoCard ${widget.coupon.offerId} DISPOSED');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (kDebugMode) {
      debugPrint('PromoCard ${widget.coupon.offerId} REBUILT');
    }

    final coupon = widget.coupon;
    final vendor = widget.vendor;
    final isDark = widget.isDark;
    final screenWidth = widget.screenWidth;
    final cacheKeySuffix =
        coupon.offerId ?? 'promo_${widget.index ?? coupon.hashCode}';

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
            Stack(
              children: [
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
                      cacheKey: 'promo_img_$cacheKeySuffix',
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
                          cacheKey: 'promo_vendor_${vendor.id}',
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
}
