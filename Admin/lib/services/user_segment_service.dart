import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/constants.dart';

class UserSegmentService {
  UserSegmentService._();

  static const List<String> segments = [
    'power_user',
    'regular',
    'active',
    'new',
    'inactive',
    'churned',
  ];

  static Future<Map<String, int>> getSegmentCounts() async {
    final snap = await FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER)
        .where('active', isEqualTo: true)
        .get();
    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final raw = doc.data()['segment'] as String?;
      String seg = 'unknown';
      if (raw != null && raw.trim().isNotEmpty) {
        final normalized = raw.trim().toLowerCase();
        seg = segments.contains(normalized) ? normalized : 'unknown';
      }
      counts[seg] = (counts[seg] ?? 0) + 1;
    }
    return counts;
  }

  static Query<Map<String, dynamic>> getUsersBySegment(String segment) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER)
        .where('active', isEqualTo: true);
    if (segment != 'all') {
      query = query.where('segment', isEqualTo: segment);
    }
    return query.orderBy('engagementScore', descending: true);
  }

  static Color getSegmentColor(String segment) {
    switch (segment) {
      case 'power_user':
        return Colors.purple;
      case 'regular':
        return Colors.blue;
      case 'active':
        return Colors.green;
      case 'new':
        return Colors.orange;
      case 'inactive':
        return Colors.grey;
      case 'churned':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String getSegmentDisplayName(String segment) {
    switch (segment) {
      case 'power_user':
        return 'Power User';
      case 'regular':
        return 'Regular';
      case 'active':
        return 'Active';
      case 'new':
        return 'New';
      case 'inactive':
        return 'Inactive';
      case 'churned':
        return 'Churned';
      case 'unknown':
        return 'Unknown';
      default:
        return segment;
    }
  }

  /// Criteria used for segmentation (matches backend logic).
  static String getSegmentDescription(String segment) {
    switch (segment) {
      case 'power_user':
        return '10+ orders, last order ≤30 days ago, ≥50% notification open rate';
      case 'regular':
        return '5+ orders, last order ≤30 days ago';
      case 'active':
        return '1–4 orders, last order ≤30 days ago';
      case 'new':
        return 'No completed orders yet';
      case 'inactive':
        return 'Last order 31–90 days ago';
      case 'churned':
        return 'Last order >90 days ago';
      case 'unknown':
        return 'Segment not yet calculated';
      default:
        return '';
    }
  }
}
