import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:foodie_customer/model/BannerModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class BannerSection extends StatelessWidget {
  final bool isBannerLoading;
  final String? bannerErrorMessage;
  final VoidCallback? onBannerRetry;
  final bool areBannerImagesCached;
  final List<BannerModel> cachedFilteredBanners;
  final List<Widget>? cachedCarouselItems;
  final CarouselSliderController carouselController;
  final PageStorageKey carouselKey;
  final CarouselOptions carouselOptions;
  final VoidCallback onRebuildCarouselItems;
  final List<VendorModel> offerVendorList;
  final List<OfferModel> offersList;
  final Widget Function(BuildContext, VendorModel, OfferModel) buildCouponsForYouItem;

  const BannerSection({
    Key? key,
    this.isBannerLoading = false,
    this.bannerErrorMessage,
    this.onBannerRetry,
    required this.areBannerImagesCached,
    required this.cachedFilteredBanners,
    required this.cachedCarouselItems,
    required this.carouselController,
    required this.carouselKey,
    required this.carouselOptions,
    required this.onRebuildCarouselItems,
    required this.offerVendorList,
    required this.offersList,
    required this.buildCouponsForYouItem,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (bannerErrorMessage != null && onBannerRetry != null) {
      return HomeSectionUtils.sectionError(
        message: bannerErrorMessage!,
        onRetry: onBannerRetry!,
      );
    }
    if (isBannerLoading) {
      return ShimmerWidgets.bannerSkeleton();
    }
    if (offerVendorList.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(
          left: 10,
          right: 10,
          bottom: 10,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Builder(
            builder: (context) {
              // Only render carousel when images are cached
              if (!areBannerImagesCached || cachedFilteredBanners.isEmpty) {
                // Show placeholder while caching or if no banners
                return cachedFilteredBanners.isEmpty
                    ? Container(
                        width: double.infinity,
                        height: 170,
                        color: Colors.grey[200],
                        child: Image.asset(
                          'assets/slides/1.png',
                          fit: BoxFit.cover,
                        ),
                      )
                    : ShimmerWidgets.bannerSkeleton();
              }

              // Rebuild items if not cached or if banners changed
              if (cachedCarouselItems == null) {
                onRebuildCarouselItems();
              }

              if (cachedCarouselItems == null || cachedCarouselItems!.isEmpty) {
                // Fallback if no cached images available
                return Container(
                  width: double.infinity,
                  height: 170,
                  color: Colors.grey[200],
                  child: Image.asset(
                    'assets/slides/1.png',
                    fit: BoxFit.cover,
                  ),
                );
              }

              return CarouselSlider(
                key: carouselKey,
                carouselController: carouselController,
                items: cachedCarouselItems!,
                options: carouselOptions,
              );
            },
          ),
        ),
      );
    } else {
      return Container(
        width: MediaQuery.of(context).size.width,
        height: 300,
        margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
        child: ListView.builder(
          shrinkWrap: true,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          cacheExtent: 300.0,
          itemCount: offerVendorList.length >= 15 ? 15 : offerVendorList.length,
          itemBuilder: (context, index) {
            return buildCouponsForYouItem(
              context,
              offerVendorList[index],
              offersList[index],
            );
          },
        ),
      );
    }
  }
}

