import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;

class ActiveBuyersCacheService {
  static const String _cacheKey = 'active_buyers_this_week_count';
  static const String _cacheDateKey = 'active_buyers_this_week_cache_date';
  static const String _cacheWeekKey = 'active_buyers_this_week_week_key';

  // Get week identifier (Monday date as string)
  static String _getWeekKey() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final daysToMonday = weekday - 1;
    final mondayDate = now.subtract(Duration(days: daysToMonday));
    return mondayDate.toIso8601String().split('T')[0];
  }

  // Get cached count if still valid
  static Future<int?> getCachedCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCount = prefs.getInt(_cacheKey);
      final cacheDate = prefs.getString(_cacheDateKey);
      final cachedWeekKey = prefs.getString(_cacheWeekKey);
      final currentWeekKey = _getWeekKey();

      // Check if cache exists and is valid
      if (cachedCount != null &&
          cacheDate != null &&
          cachedWeekKey == currentWeekKey) {
        return cachedCount;
      }

      return null;
    } catch (e) {
      developer.log(
        'Error reading cached count: $e',
        name: 'ActiveBuyersCacheService',
      );
      return null;
    }
  }

  // Save count to cache
  static Future<void> saveCount(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cacheKey, count);
      await prefs.setString(_cacheDateKey, DateTime.now().toIso8601String());
      await prefs.setString(_cacheWeekKey, _getWeekKey());
    } catch (e) {
      developer.log(
        'Error saving cached count: $e',
        name: 'ActiveBuyersCacheService',
      );
    }
  }

  // Clear cache (useful when week changes)
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheDateKey);
      await prefs.remove(_cacheWeekKey);
    } catch (e) {
      developer.log(
        'Error clearing cache: $e',
        name: 'ActiveBuyersCacheService',
      );
    }
  }

  // Calculate active buyers count from Firestore
  static Future<int> calculateCount({
    required DateTime startOfWeek,
    required DateTime endOfWeek,
  }) async {
    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfWeek))
          .limit(1000) // Limit to prevent memory issues
          .get();

      final Set<String> uniqueCustomerIds = {};

      for (final orderDoc in snapshot.docs) {
        final data = orderDoc.data();

        if (data == null || data is! Map<String, dynamic>) {
          continue;
        }

        final author = data['author'];
        Map<String, dynamic>? authorMap;

        if (author is Map) {
          authorMap = Map<String, dynamic>.from(author);
        } else if (author is Map<String, dynamic>) {
          authorMap = author;
        }

        final customerId = authorMap?['id'] as String?;
        if (customerId != null && customerId.isNotEmpty) {
          uniqueCustomerIds.add(customerId);
        }
      }

      final count = uniqueCustomerIds.length;

      // Save to cache
      await saveCount(count);

      return count;
    } catch (e) {
      developer.log(
        'Error calculating active buyers count: $e',
        name: 'ActiveBuyersCacheService',
        error: e,
      );
      rethrow;
    }
  }
}

