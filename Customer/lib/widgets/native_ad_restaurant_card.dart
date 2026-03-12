import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/ad_service.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Native ad widget styled like a restaurant card, with icon, headline, body,
/// CTA button, and Sponsored badge (included in the native template).
class NativeAdRestaurantCard extends StatefulWidget {
  final String? adUnitId;

  const NativeAdRestaurantCard({Key? key, this.adUnitId}) : super(key: key);

  @override
  State<NativeAdRestaurantCard> createState() => _NativeAdRestaurantCardState();
}

class _NativeAdRestaurantCardState extends State<NativeAdRestaurantCard> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;

  String get _adUnitId =>
      widget.adUnitId ?? AdService.instance.nativeAdUnitId;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _nativeAd = NativeAd(
      adUnitId: _adUnitId,
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: Colors.white,
        cornerRadius: 20,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: Color(COLOR_PRIMARY),
          style: NativeTemplateFontStyle.normal,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black,
          style: NativeTemplateFontStyle.bold,
          size: 16,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xff555353),
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _nativeAd == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode(context)
              ? const Color(DarkContainerBorderColor)
              : Colors.grey.shade100,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 320,
            minHeight: 90,
            maxWidth: 400,
            maxHeight: 200,
          ),
          child: AdWidget(ad: _nativeAd!),
        ),
      ),
    );
  }
}
