import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/restaurant_processing.dart';

/// Service for checking restaurant open/closed status (AI chat ordering flow).
class RestaurantStatusService {
  /// Check if a restaurant is currently open.
  static Future<Map<String, dynamic>> checkRestaurantStatus(
    String vendorId,
  ) async {
    try {
      final vendorDoc = await FirebaseFirestore.instance
          .collection(VENDORS)
          .doc(vendorId)
          .get();

      if (!vendorDoc.exists) {
        return {
          'exists': false,
          'error': 'Restaurant not found',
        };
      }

      final vendorData = vendorDoc.data()!;
      final isOpen = checkRestaurantOpen(vendorData);

      final workingHours = vendorData['workingHours'] as List<dynamic>? ?? [];
      final today = DateFormat('EEEE', 'en_US').format(DateTime.now());

      String todayHours = 'Closed';
      for (final dayEntry in workingHours) {
        final d = dayEntry as Map<String, dynamic>?;
        if (d == null) continue;
        if ((d['day'] ?? '').toString() == today) {
          final timeslots = d['timeslot'] as List<dynamic>? ?? [];
          if (timeslots.isNotEmpty) {
            final first = timeslots.first as Map<String, dynamic>?;
            final from = (first?['from'] ?? '?').toString();
            final to = (first?['to'] ?? '?').toString();
            todayHours = '$from - $to';
          }
          break;
        }
      }

      return {
        'exists': true,
        'vendorId': vendorId,
        'vendorName': (vendorData['title'] ?? 'Restaurant').toString(),
        'isOpen': isOpen,
        'reststatus': vendorData['reststatus'] as bool? ?? false,
        'todayHours': todayHours,
        'workingHours': workingHours,
        'supportsScheduling': true,
      };
    } catch (e) {
      debugPrint('❌ [STATUS] Error: $e');
      return {
        'exists': false,
        'error': 'Failed to check restaurant status',
      };
    }
  }

  /// Check status and whether restaurant is closing within [closingSoonWithin].
  static Future<Map<String, dynamic>> checkRestaurantStatusWithClosingSoon(
    String vendorId, {
    Duration closingSoonWithin = const Duration(minutes: 30),
  }) async {
    final status = await checkRestaurantStatus(vendorId);
    if (status['exists'] != true) return status;

    final vendorDoc = await FirebaseFirestore.instance
        .collection(VENDORS)
        .doc(vendorId)
        .get();
    if (!vendorDoc.exists || vendorDoc.data() == null) return status;

    final vendorData = vendorDoc.data()!;
    final isOpen = status['isOpen'] as bool? ?? false;
    final minutesUntilClosing = getMinutesUntilClosing(vendorData);
    final closingSoon = isOpen &&
        minutesUntilClosing != null &&
        minutesUntilClosing <= closingSoonWithin.inMinutes &&
        minutesUntilClosing >= 0;

    status['closingSoon'] = closingSoon;
    status['minutesUntilClosing'] = minutesUntilClosing;
    dev.log('[STATUS] $vendorId: isOpen=$isOpen, '
        'closingSoon=$closingSoon, minsUntilClosing=$minutesUntilClosing');
    return status;
  }

  /// Fetch and check status for multiple vendors in parallel.
  static Future<Map<String, Map<String, dynamic>>> checkMultipleVendorsStatus(
    List<String> vendorIds,
  ) async {
    final uniqueIds = vendorIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return {};

    final futures = uniqueIds.map((id) => checkRestaurantStatus(id));
    final results = await Future.wait(futures);

    final map = <String, Map<String, dynamic>>{};
    for (var i = 0; i < uniqueIds.length; i++) {
      map[uniqueIds[i]] = results[i];
    }
    dev.log('[STATUS] Batch check: vendorIds=$uniqueIds, '
        'closed=${uniqueIds.where((id) => (map[id]!['isOpen'] as bool?) != true).toList()}');
    return map;
  }

  static String getCurrentTimeFormatted() {
    return DateFormat('h:mm a').format(DateTime.now());
  }

  static String getCurrentDay() {
    return DateFormat('EEEE', 'en_US').format(DateTime.now());
  }
}
