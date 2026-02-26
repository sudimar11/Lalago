import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/trending_service.dart';

/// Discovery recommendations: mix of preferred cuisines, collaborative, and random.
class DiscoveryService {
  static Future<List<VendorModel>> getDiscoveryRecommendations(
    String userId,
  ) async {
    final preferredCuisines =
        await _getUserPreferredCuisines(userId);
    final newInPreferred =
        await _getNewRestaurantsInCuisines(preferredCuisines, 6);
    final collaborative =
        await _getCollaborativeRecommendations(userId, 3);
    final random = await _getRandomRestaurants(1);

    final all = [...newInPreferred, ...collaborative, ...random];
    final filtered = all.where((v) {
      final isOpen = v.reststatus == true;
      final hasRating = (v.reviewsCount ?? 0) > 0;
      return isOpen && hasRating;
    }).toList();
    filtered.shuffle(Random());
    return filtered.take(10).toList();
  }

  static String getRecommendationReason(
    VendorModel restaurant,
    String userId, {
    bool? isNew,
    bool? isTrending,
    bool? similarToFavorites,
    bool? fromPreferredCuisine,
  }) {
    if (isNew == true) return 'New in your area';
    if (isTrending == true) return 'Trending now';
    if (similarToFavorites == true) return 'Similar to your favorites';
    if (fromPreferredCuisine == true) return 'From your favorite cuisine';
    return 'Recommended for you';
  }

  static Future<List<String>> _getUserPreferredCuisines(String userId) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection(USERS).doc(userId).get();
      final prefs = doc.data()?['preferenceProfile'] as Map?;
      final cuisinePrefs = prefs?['cuisinePreferences'] as Map?;
      if (cuisinePrefs == null || cuisinePrefs.isEmpty) return [];
      return cuisinePrefs.keys.map((k) => k.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<VendorModel>> _getNewRestaurantsInCuisines(
    List<String> cuisines,
    int limit,
  ) async {
    if (cuisines.isEmpty) {
      return _getNewRestaurants(limit);
    }

    final thirtyDaysAgo =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));
    final snap = await FirebaseFirestore.instance
        .collection(VENDORS)
        .where('reststatus', isEqualTo: true)
        .where('createdAt', isGreaterThanOrEqualTo: thirtyDaysAgo)
        .limit(50)
        .get();

    final list = <VendorModel>[];
    for (final doc in snap.docs) {
      if (list.length >= limit) break;
      try {
        final data = doc.data();
        data['id'] = doc.id;
        final v = VendorModel.fromJson(data);
        final cat = v.categoryTitle.toLowerCase();
        if (cuisines.any((c) => cat.contains(c.toLowerCase()))) {
          list.add(v);
        }
      } catch (_) {}
    }
    return list;
  }

  static Future<List<VendorModel>> _getNewRestaurants(int limit) async {
    final snap = await FirebaseFirestore.instance
        .collection(VENDORS)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return VendorModel.fromJson(data);
    }).toList();
  }

  static Future<List<VendorModel>> _getCollaborativeRecommendations(
    String userId,
    int limit,
  ) async {
    try {
      final stream = TrendingService.getTrendingRestaurants();
      final list = await stream.first;
      return list.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<VendorModel>> _getRandomRestaurants(int limit) async {
    final snap = await FirebaseFirestore.instance
        .collection(VENDORS)
        .where('reststatus', isEqualTo: true)
        .limit(30)
        .get();

    if (snap.docs.isEmpty) return [];
    final shuffled = List.of(snap.docs)..shuffle(Random());
    return shuffled.take(limit).map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return VendorModel.fromJson(data);
    }).toList();
  }
}
