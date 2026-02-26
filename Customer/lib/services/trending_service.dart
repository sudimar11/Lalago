import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';

/// Trending restaurants by order count in last 24 hours.
class TrendingService {
  static Stream<List<VendorModel>> getTrendingRestaurants() {
    final last24 = DateTime.now().subtract(const Duration(hours: 24));
    final startTs = Timestamp.fromDate(last24);

    return FirebaseFirestore.instance
        .collection(ORDERS)
        .where('createdAt', isGreaterThanOrEqualTo: startTs)
        .limit(500)
        .snapshots()
        .asyncMap((snapshot) async {
      final Map<String, int> counts = {};
      for (final doc in snapshot.docs) {
        final vid = doc.get('vendorID')?.toString() ?? '';
        if (vid.isEmpty) continue;
        counts[vid] = (counts[vid] ?? 0) + 1;
      }

      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topIds = sorted.take(10).map((e) => e.key).toList();

      final List<VendorModel> vendors = [];
      for (final id in topIds) {
        final v = await FireStoreUtils.getVendor(id);
        if (v != null) vendors.add(v);
      }
      return vendors;
    });
  }
}
