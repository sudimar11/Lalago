import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for public performance metrics (badge override).
class PublicMetricsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Set or clear the badge override for a vendor.
  /// [overrideBadge] null or empty = use computed; 'hidden' = hide badge.
  Future<void> setBadgeOverride(String vendorId, String? overrideBadge) async {
    final ref = _firestore.collection('vendors').doc(vendorId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data() ?? {};
    final existing = data['publicMetrics'] as Map<String, dynamic>? ?? {};
    final updated = Map<String, dynamic>.from(existing);
    updated['overrideBadge'] = (overrideBadge == null ||
            overrideBadge.isEmpty ||
            overrideBadge.toLowerCase() == 'none')
        ? null
        : overrideBadge;

    await ref.update({'publicMetrics': updated});
  }
}
