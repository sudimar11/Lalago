import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';

const _keyVendors = 'home_cached_vendors';
const _keyVendorsAt = 'home_cached_vendors_at';
const _keyCategories = 'home_cached_categories';
const _keyCategoriesAt = 'home_cached_categories_at';
const _ttlMinutes = 5;

/// Client-side cache for home screen data. TTL 5 minutes.
class HomeScreenCache {
  HomeScreenCache._();

  static bool _isStale(int? cachedAtMs) {
    if (cachedAtMs == null) return true;
    final age = DateTime.now().millisecondsSinceEpoch - cachedAtMs;
    return age > _ttlMinutes * 60 * 1000;
  }

  static Object? _convertForEncode(Object? v) {
    if (v == null) return null;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _convertForEncode(val)));
    }
    if (v is List) return v.map(_convertForEncode).toList();
    return v;
  }

  static Object? _convertForDecode(Object? v, String key) {
    if (v == null) return null;
    // Restore Timestamp from milliseconds (stored by _convertForEncode)
    if (v is int && key == 'createdAt') {
      return Timestamp.fromMillisecondsSinceEpoch(v);
    }
    if (v is Map) {
      return v.map((k, val) =>
          MapEntry(k, _convertForDecode(val, k is String ? k : '')));
    }
    if (v is List) {
      return v.map((e) => _convertForDecode(e, '')).toList();
    }
    return v;
  }

  static Future<void> cacheVendors(List<VendorModel> vendors) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = vendors.map((v) => _convertForEncode(v.toJson())).toList();
      await prefs.setString(_keyVendors, jsonEncode(list));
      await prefs.setInt(_keyVendorsAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<VendorModel>?> getCachedVendors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_keyVendorsAt);
      if (_isStale(at)) return null;
      final raw = prefs.getString(_keyVendors);
      if (raw == null) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) {
        final m = (e as Map).map((k, v) =>
            MapEntry(k as String, _convertForDecode(v, k)));
        return VendorModel.fromJson(Map<String, dynamic>.from(m));
      }).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> cacheCategories(
      List<VendorCategoryModel> categories) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = categories.map((c) => c.toJson()).toList();
      await prefs.setString(_keyCategories, jsonEncode(list));
      await prefs.setInt(
          _keyCategoriesAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<VendorCategoryModel>?> getCachedCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final at = prefs.getInt(_keyCategoriesAt);
      if (_isStale(at)) return null;
      final raw = prefs.getString(_keyCategories);
      if (raw == null) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => VendorCategoryModel.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
