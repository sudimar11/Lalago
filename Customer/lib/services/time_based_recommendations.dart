import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';

/// Time-based meal period recommendations.
class TimeBasedRecommendations {
  static String getMealPeriod() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return 'breakfast';
    if (hour >= 11 && hour < 16) return 'lunch';
    if (hour >= 16 && hour < 22) return 'dinner';
    return 'late_night';
  }

  static Map<String, List<String>> getCuisineByMealPeriod() {
    return {
      'breakfast': ['silog', 'pastries', 'coffee', 'rice', 'bread', 'breakfast'],
      'lunch': ['rice', 'bowl', 'noodles', 'value', 'soup', 'bbq', 'lunch'],
      'dinner': [
        'family',
        'grilled',
        'seafood',
        'group',
        'steak',
        'dinner',
      ],
      'late_night': [
        'fast food',
        'dessert',
        'snack',
        'pizza',
        'burger',
        'late',
      ],
    };
  }

  static Stream<List<VendorModel>> getRecommendations() {
    final mealPeriod = getMealPeriod();
    final keywords =
        getCuisineByMealPeriod()[mealPeriod] ?? ['rice', 'food'];

    return FirebaseFirestore.instance
        .collection(VENDORS)
        .where('reststatus', isEqualTo: true)
        .limit(80)
        .snapshots()
        .map((snapshot) {
      final list = <VendorModel>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          data['id'] = doc.id;
          final v = VendorModel.fromJson(data);
          if (_matchesMealPeriod(v, keywords)) {
            list.add(v);
            if (list.length >= 10) break;
          }
        } catch (_) {}
      }
      return list;
    });
  }

  static bool _matchesMealPeriod(VendorModel v, List<String> keywords) {
    final category = v.categoryTitle.toLowerCase();
    final filterStr = (v.filters).values
        .whereType<String>()
        .map((s) => s.toLowerCase())
        .join(' ');
    final desc = v.description.toLowerCase();
    final combined = '$category $filterStr $desc';

    for (final kw in keywords) {
      if (combined.contains(kw.toLowerCase())) return true;
    }
    return false;
  }
}
