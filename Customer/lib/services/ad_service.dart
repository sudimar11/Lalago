import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService _instance = AdService._();
  static AdService get instance => _instance;

  AdService._();

  static const String _testBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testNativeId = 'ca-app-pub-3940256099942544/2247696110';
  static const String _prodBannerId = 'ca-app-pub-4534028104040637/6000174084';
  static const String _prodNativeId =
      'ca-app-pub-4534028104040637/XXXXXXXX'; // Replace with your native ad unit

  String get bannerAdUnitId => kDebugMode ? _testBannerId : _prodBannerId;
  String get nativeAdUnitId => kDebugMode ? _testNativeId : _prodNativeId;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }
}
