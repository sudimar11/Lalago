import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/advertisement.dart';

class AdvertisementService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Get stream of active advertisements
  static Stream<List<Advertisement>> getActiveAdsStream() {
    log('=== START: Getting active advertisements stream ===');
    log('Collection: $ADVERTISEMENTS');
    log('Filters: is_deleted=false, is_enabled=true');

    return firestore
        .collection(ADVERTISEMENTS)
        .where('is_deleted', isEqualTo: false)
        .where('is_enabled', isEqualTo: true)
        .orderBy('priority', descending: false)
        .snapshots()
        .map((snapshot) {
      log('--- Received snapshot from Firestore ---');
      log('Total documents: ${snapshot.docs.length}');

      final now = DateTime.now();
      final ads = <Advertisement>[];
      int filteredByDate = 0;
      int filteredByNoImages = 0;
      int parseErrors = 0;

      for (int i = 0; i < snapshot.docs.length; i++) {
        final doc = snapshot.docs[i];
        log('Processing ad ${i + 1}/${snapshot.docs.length}: ${doc.id}');

        try {
          final data = doc.data();
          log('  - Title: ${data['title']}');
          log('  - Priority: ${data['priority'] ?? 0}');
          log('  - Image URLs count: ${(data['image_urls'] as List?)?.length ?? 0}');
          log('  - Is enabled: ${data['is_enabled']}');
          log('  - Is deleted: ${data['is_deleted']}');

          final ad = Advertisement.fromJson(data, doc.id);
          log('  - Advertisement parsed successfully');

          // Apply scheduling logic
          bool isActive = true;
          String filterReason = '';

          // Check start date
          if (ad.startDate != null && now.isBefore(ad.startDate!)) {
            isActive = false;
            filterReason = 'Not started yet (starts: ${ad.startDate})';
            filteredByDate++;
          }

          // Check end date
          if (ad.endDate != null && now.isAfter(ad.endDate!)) {
            isActive = false;
            filterReason = 'Expired (ended: ${ad.endDate})';
            filteredByDate++;
          }

          // Check images
          if (ad.imageUrls.isEmpty) {
            isActive = false;
            filterReason = 'No images';
            filteredByNoImages++;
          }

          if (isActive) {
            ads.add(ad);
            log('  ✅ AD ADDED to display list (Priority: ${ad.priority})');
          } else {
            log('  ❌ AD FILTERED OUT: $filterReason');
          }
        } catch (e, stackTrace) {
          parseErrors++;
          log('  ❌ ERROR parsing advertisement: $e');
          log('  StackTrace: $stackTrace');
          debugPrint('Error parsing advertisement: $e');
        }
      }

      // Sort ads by priority after filtering to ensure correct order
      ads.sort((a, b) => a.priority.compareTo(b.priority));

      log('--- SUMMARY ---');
      log('Total documents received: ${snapshot.docs.length}');
      log('Successfully added: ${ads.length}');
      log('Filtered by date: $filteredByDate');
      log('Filtered by no images: $filteredByNoImages');
      log('Parse errors: $parseErrors');
      log('Ads in priority order:');
      for (int i = 0; i < ads.length; i++) {
        log('  ${i + 1}. ${ads[i].title} (Priority: ${ads[i].priority})');
      }
      log('=== END: Active advertisements stream ===');

      return ads;
    });
  }

  // Increment impression count
  static Future<void> incrementImpression(String adId) async {
    try {
      await firestore.collection(ADVERTISEMENTS).doc(adId).update({
        'impressions': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('Error incrementing impression: $e');
      // Don't throw - analytics failures shouldn't break the UI
    }
  }

  // Increment click count
  static Future<void> incrementClick(String adId) async {
    try {
      await firestore.collection(ADVERTISEMENTS).doc(adId).update({
        'clicks': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('Error incrementing click: $e');
      // Don't throw - analytics failures shouldn't break the UI
    }
  }
}
