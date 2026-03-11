import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/CurrencyModel.dart';
import 'package:foodie_customer/model/TaxModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/utils/performance_logger.dart';

const _keyTheme = 'app_config_theme';
const _keyCurrency = 'app_config_currency';
const _keyTax = 'app_config_tax';
const _keyReferral = 'app_config_referral';
const _keyCountry = 'app_config_country';
const _keyCachedAt = 'app_config_at';
const _ttlMs = 24 * 60 * 60 * 1000; // 24 hours

/// Loads theme, currency, tax, payment configs, and referral in the background.
/// Uses SharedPreferences cache for instant load on subsequent launches.
class AppConfigurationService {
  AppConfigurationService._();

  static bool _isStale(int? cachedAtMs) {
    if (cachedAtMs == null) return true;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
    return age > _ttlMs;
  }

  static Future<bool> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_keyCachedAt);
      if (_isStale(at)) return false;

      final theme = prefs.getString(_keyTheme);
      if (theme != null && theme.isNotEmpty) {
        homePageThem = theme;
      }

      final currencyJson = prefs.getString(_keyCurrency);
      if (currencyJson != null && currencyJson.isNotEmpty) {
        try {
          final map = Map<String, dynamic>.from(
            jsonDecode(currencyJson) as Map,
          );
          currencyModel = CurrencyModel.fromJson(map);
        } catch (_) {}
      }

      final taxJson = prefs.getString(_keyTax);
      if (taxJson != null && taxJson.isNotEmpty) {
        try {
          final list = jsonDecode(taxJson) as List<dynamic>;
          taxList = list
              .map((e) => TaxModel.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        } catch (_) {}
      }

      final referral = prefs.getString(_keyReferral);
      if (referral != null) referralAmount = referral;

      final cachedCountry = prefs.getString(_keyCountry);
      if (cachedCountry != null) country = cachedCountry;

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppConfig] Cache read error: $e');
      return false;
    }
  }

  static Future<void> _persistToCache({
    required String theme,
    required String? currencyJson,
    required String? taxJson,
    required String referral,
    required String country,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyTheme, theme);
      if (currencyJson != null) await prefs.setString(_keyCurrency, currencyJson);
      if (taxJson != null) await prefs.setString(_keyTax, taxJson);
      await prefs.setString(_keyReferral, referral);
      await prefs.setString(_keyCountry, country);
      await prefs.setInt(_keyCachedAt, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      if (kDebugMode) debugPrint('[AppConfig] Cache write error: $e');
    }
  }

  /// Load config: from cache first, then Firestore in background if needed.
  static Future<void> loadAsync({bool forceRefresh = false}) async {
    final stopwatch = Stopwatch()..start();

    if (!forceRefresh && await _loadFromCache()) {
      if (kDebugMode) {
        PerformanceLogger.logPhase(
            'config_loaded', stopwatch.elapsedMilliseconds,
            extra: {'source': 'cache'});
      }
      return;
    }

    try {
      // Payment helpers also write to UserPreference; call them.
      await Future.wait([
        _fetchTheme(),
        FireStoreUtils().getCurrency().then((value) {
          if (value != null) {
            currencyModel = value;
          } else {
            currencyModel = CurrencyModel(
              id: '',
              code: 'USD',
              decimal: 2,
              isactive: true,
              name: 'US Dollar',
              symbol: r'$',
              symbolatright: false,
            );
          }
        }),
        Future(() async {
          await FireStoreUtils.getPaypalSettingData();
        }),
        Future(() async {
          await FireStoreUtils.getPaytmSettingData();
        }),
        Future(() async {
          FireStoreUtils.getWalletSettingData();
        }),
        Future(() async {
          try {
            await FireStoreUtils.getReferralAmount();
          } catch (_) {}
        }),
      ]);

      // Geocoding with timeout (uses global country for getTaxList)
      if (MyAppState.selectedPosition.location != null) {
        try {
          final loc = MyAppState.selectedPosition.location!;
          final placeMarks = await placemarkFromCoordinates(
            loc.latitude,
            loc.longitude,
          ).timeout(const Duration(seconds: 5));
          if (placeMarks.isNotEmpty) {
            country = placeMarks.first.country ?? '';
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[AppConfig] Geocoding error: $e');
        }
      }

      final tax = await FireStoreUtils().getTaxList();
      if (tax != null) taxList = tax;

      // Persist to cache
      await _persistToCache(
        theme: homePageThem ?? 'theme_1',
        currencyJson:
            currencyModel != null ? _encodeCurrency(currencyModel!) : null,
        taxJson: taxList != null && taxList!.isNotEmpty
            ? _encodeTaxList(taxList!)
            : null,
        referral: referralAmount,
        country: country ?? '',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AppConfig] Load error: $e');
      // Keep existing cached/global values; do not overwrite with null
    } finally {
      stopwatch.stop();
      if (kDebugMode) {
        PerformanceLogger.logPhase(
            'config_loaded', stopwatch.elapsedMilliseconds,
            extra: {'source': 'network'});
      }
    }
  }

  static Future<void> _fetchTheme() async {
    final snap = await FirebaseFirestore.instance
        .collection(Setting)
        .doc('home_page_theme')
        .get();
    final theme = snap.data()?['theme'] ?? 'theme_1';
    homePageThem = theme;
  }

  static String _encodeCurrency(CurrencyModel c) {
    return jsonEncode(c.toJson());
  }

  static String _encodeTaxList(List<TaxModel> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }
}
