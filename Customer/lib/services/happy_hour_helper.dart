import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/HappyHourConfig.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/happy_hour_service.dart';

class HappyHourHelper {
  // Cache for server time offset to avoid repeated calls
  static Duration? _serverTimeOffset;
  static DateTime? _lastServerTimeCheck;

  // Get server time (with caching to reduce Firebase calls)
  static Future<DateTime> getServerTime() async {
    try {
      // Use cached offset if available and recent (within 5 minutes)
      if (_serverTimeOffset != null && 
          _lastServerTimeCheck != null &&
          DateTime.now().difference(_lastServerTimeCheck!).inMinutes < 5) {
        return DateTime.now().add(_serverTimeOffset!);
      }

      // Get server timestamp
      final serverTimestamp = await HappyHourService.getServerTimestamp();
      final serverTime = serverTimestamp.toDate();
      final localTime = DateTime.now();
      
      // Calculate offset
      _serverTimeOffset = serverTime.difference(localTime);
      _lastServerTimeCheck = DateTime.now();
      
      return serverTime;
    } catch (e) {
      print('Error getting server time: $e');
      // Fallback to local time
      return DateTime.now();
    }
  }

  // Check if Happy Hour is currently active
  static Future<bool> isHappyHourActive(HappyHourSettings settings) async {
    if (!settings.enabled || settings.configs.isEmpty) {
      return false;
    }

    final activeConfig = await getActiveHappyHour(settings);
    return activeConfig != null;
  }

  // Get the currently active Happy Hour config
  static Future<HappyHourConfig?> getActiveHappyHour(HappyHourSettings settings) async {
    if (!settings.enabled || settings.configs.isEmpty) {
      return null;
    }

    try {
      final serverTime = await getServerTime();
      final currentDay = serverTime.weekday % 7; // 0=Sunday, 1=Monday, ..., 6=Saturday
      final currentTime = TimeOfDay.fromDateTime(serverTime);

      // Find first active config
      for (var config in settings.configs) {
        // Check if today is an active day
        if (!config.activeDays.contains(currentDay)) {
          continue;
        }

        // Parse start and end times
        final startParts = config.startTime.split(':');
        final endParts = config.endTime.split(':');
        final startTime = TimeOfDay(
          hour: int.parse(startParts[0]),
          minute: int.parse(startParts[1]),
        );
        final endTime = TimeOfDay(
          hour: int.parse(endParts[0]),
          minute: int.parse(endParts[1]),
        );

        // Check if current time is within range
        if (_isTimeInRange(currentTime, startTime, endTime)) {
          return config;
        }
      }
    } catch (e) {
      print('Error checking active Happy Hour: $e');
    }

    return null;
  }

  // Helper to check if time is in range
  static bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;

    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }

  // Calculate discount amount based on promo type
  static double calculateHappyHourDiscount({
    required HappyHourConfig config,
    required double orderSubtotal,
    double? deliveryCharge,
  }) {
    switch (config.promoType) {
      case 'fixed_amount':
        return config.promoValue;
      
      case 'percentage':
        return (orderSubtotal * config.promoValue) / 100;
      
      case 'free_delivery':
        return deliveryCharge ?? 0.0;
      
      case 'reduced_delivery':
        final delivery = deliveryCharge ?? 0.0;
        return delivery > config.promoValue ? config.promoValue : delivery;
      
      default:
        return 0.0;
    }
  }

  // Check if user is eligible for Happy Hour
  static Future<bool> isUserEligible({
    required HappyHourConfig config,
    required User? user,
  }) async {
    if (user == null) return false;

    // Check user eligibility type
    if (config.userEligibility == 'all') {
      return true;
    }

    try {
      // Check if user is new or returning
      final ordersQuery = await FirebaseFirestore.instance
          .collection(ORDERS)
          .where('authorID', isEqualTo: user.userID)
          .limit(1)
          .get();

      final isNewUser = ordersQuery.docs.isEmpty;

      if (config.userEligibility == 'new') {
        return isNewUser;
      } else if (config.userEligibility == 'returning') {
        return !isNewUser;
      }
    } catch (e) {
      print('Error checking user eligibility: $e');
      // On error, allow eligibility to prevent blocking users
      return true;
    }

    return false;
  }

  // Check if restaurant is eligible for Happy Hour
  static bool isRestaurantEligible({
    required HappyHourConfig config,
    required String restaurantId,
  }) {
    if (config.restaurantScope == 'all') {
      return true;
    }

    return config.restaurantIds.contains(restaurantId);
  }

  // Check user's usage count for the day
  static Future<int> getUserUsageCount({
    required HappyHourConfig config,
    required String userId,
  }) async {
    if (config.maxUsagePerUserPerDay == null) {
      return 0; // No limit
    }

    try {
      final serverTime = await getServerTime();
      final startOfDay = DateTime(serverTime.year, serverTime.month, serverTime.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

      final ordersQuery = await FirebaseFirestore.instance
          .collection(ORDERS)
          .where('authorID', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      int usageCount = 0;
      for (var doc in ordersQuery.docs) {
        final orderData = doc.data();
        final specialDiscount = orderData['specialDiscount'] as Map<String, dynamic>?;
        if (specialDiscount != null && 
            specialDiscount['happy_hour_config_id'] == config.id) {
          usageCount++;
        }
      }

      return usageCount;
    } catch (e) {
      print('Error checking user usage count: $e');
      return 0; // On error, allow usage
    }
  }

  // Check if user has exceeded usage limit
  static Future<bool> hasExceededUsageLimit({
    required HappyHourConfig config,
    required String userId,
  }) async {
    if (config.maxUsagePerUserPerDay == null) {
      return false; // No limit
    }

    final usageCount = await getUserUsageCount(
      config: config,
      userId: userId,
    );

    return usageCount >= config.maxUsagePerUserPerDay!;
  }

  // Get time remaining until Happy Hour ends
  static Future<Duration?> getTimeRemaining(HappyHourConfig config) async {
    try {
      final serverTime = await getServerTime();
      final endParts = config.endTime.split(':');
      final endHour = int.parse(endParts[0]);
      final endMinute = int.parse(endParts[1]);

      final endTime = DateTime(
        serverTime.year,
        serverTime.month,
        serverTime.day,
        endHour,
        endMinute,
      );

      final difference = endTime.difference(serverTime);
      return difference.isNegative ? null : difference;
    } catch (e) {
      print('Error calculating time remaining: $e');
      return null;
    }
  }

  // Validate all eligibility criteria for Happy Hour
  static Future<Map<String, dynamic>> validateHappyHourEligibility({
    required HappyHourConfig config,
    required User? user,
    required String restaurantId,
    required double orderSubtotal,
    double? deliveryCharge,
    int totalItemCount = 0,
  }) async {
    final result = <String, dynamic>{
      'eligible': false,
      'reason': '',
      'discount': 0.0,
    };

    // Check if Happy Hour is still active
    final serverTime = await getServerTime();
    final currentDay = serverTime.weekday % 7;
    final currentTime = TimeOfDay.fromDateTime(serverTime);

    if (!config.activeDays.contains(currentDay)) {
      result['reason'] = 'Happy Hour is not active today';
      return result;
    }

    final startParts = config.startTime.split(':');
    final endParts = config.endTime.split(':');
    final startTime = TimeOfDay(
      hour: int.parse(startParts[0]),
      minute: int.parse(startParts[1]),
    );
    final endTime = TimeOfDay(
      hour: int.parse(endParts[0]),
      minute: int.parse(endParts[1]),
    );

    if (!_isTimeInRange(currentTime, startTime, endTime)) {
      result['reason'] = 'Happy Hour has ended';
      return result;
    }

    // Check minimum order amount
    if (orderSubtotal < config.minOrderAmount) {
      result['reason'] = 'Minimum order amount not met';
      return result;
    }

    // Check minimum item requirement
    if (config.minItems != null && totalItemCount < config.minItems!) {
      result['reason'] = 'Minimum item requirement not met';
      result['itemsNeeded'] = config.minItems! - totalItemCount;
      return result;
    }

    // Check restaurant eligibility
    if (!isRestaurantEligible(config: config, restaurantId: restaurantId)) {
      result['reason'] = 'Restaurant not eligible for this promo';
      return result;
    }

    // Check user eligibility
    if (user == null) {
      result['reason'] = 'User not logged in';
      return result;
    }

    final userEligible = await isUserEligible(config: config, user: user);
    if (!userEligible) {
      result['reason'] = 'User not eligible for this promo';
      return result;
    }

    // Check usage limit
    final exceededLimit = await hasExceededUsageLimit(
      config: config,
      userId: user.userID,
    );
    if (exceededLimit) {
      result['reason'] = 'Daily usage limit reached';
      return result;
    }

    // All checks passed
    result['eligible'] = true;
    result['discount'] = calculateHappyHourDiscount(
      config: config,
      orderSubtotal: orderSubtotal,
      deliveryCharge: deliveryCharge,
    );

    return result;
  }
}

