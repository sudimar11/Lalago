import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:foodie_driver/constants.dart';

/// Service that evaluates whether the rider has unremitted credit wallet
/// balance from a previous day and blocks order interaction until remitted.
/// Listens to Firestore user doc for reactive auto-dismissal when admin
/// confirms transmit.
class RemittanceEnforcementService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? _listeningUserId;

  bool _isBlockedByRemittance = false;

  /// True when rider has unremitted credit balance from a previous day
  /// and must remit before accepting orders.
  bool get isBlockedByRemittance => _isBlockedByRemittance;

  /// Start listening to user document for remittance status changes.
  /// Call when rider logs in.
  void startListening(String userId) {
    if (_listeningUserId == userId) return;
    stopListening();
    _listeningUserId = userId;

    _subscription = _firestore
        .collection(USERS)
        .doc(userId)
        .snapshots()
        .listen(_onUserSnapshot);
  }

  /// Stop listening. Call when rider logs out.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _listeningUserId = null;
    if (_isBlockedByRemittance) {
      _isBlockedByRemittance = false;
      notifyListeners();
    }
  }

  void _onUserSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!snapshot.exists || snapshot.data() == null) {
      _updateBlocked(false);
      return;
    }

    final data = snapshot.data()!;

    final overridden =
        data['creditWalletRemittanceEnforcementOverridden'];
    if (overridden == true) {
      print('[REMITTANCE] Admin override active '
          '-> not blocked');
      _updateBlocked(false);
      return;
    }

    final walletCredit =
        (data['wallet_credit'] ?? 0.0).toDouble();
    if (walletCredit <= 0) {
      print('[REMITTANCE] wallet_credit=$walletCredit '
          '(<= 0) -> not blocked');
      _updateBlocked(false);
      return;
    }

    final lastRemitDate = _getLastRemittanceDate(data);
    final now = DateTime.now();
    final yesterdayStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));

    final remittedRecently = lastRemitDate != null &&
        !lastRemitDate.isBefore(yesterdayStart);
    final blocked = !remittedRecently;

    print('[REMITTANCE] now=$now, '
        'yesterdayStart=$yesterdayStart');
    print('[REMITTANCE] wallet_credit=$walletCredit, '
        'lastRemitDate=$lastRemitDate');
    print('[REMITTANCE] remittedRecently='
        '$remittedRecently -> blocked=$blocked');

    _updateBlocked(blocked);
  }

  /// Get latest confirmedAt date from transmitRequests with type
  /// credit_wallet_transmit.
  DateTime? _getLastRemittanceDate(Map<String, dynamic> data) {
    final requests = data['transmitRequests'] as List<dynamic>?;
    if (requests == null || requests.isEmpty) return null;

    DateTime? latest;
    for (final req in requests) {
      if (req is! Map<String, dynamic>) continue;
      if (req['type'] != 'credit_wallet_transmit') continue;

      final confirmedAt = req['confirmedAt'];
      if (confirmedAt is! Timestamp) continue;

      final d = confirmedAt.toDate();
      if (latest == null || d.isAfter(latest)) {
        latest = d;
      }
    }
    return latest;
  }

  void _updateBlocked(bool blocked) {
    if (_isBlockedByRemittance != blocked) {
      _isBlockedByRemittance = blocked;
      notifyListeners();
    }
  }

  /// Evaluate block status from user document (for guards that need
  /// a one-shot check without depending on stream state).
  static Future<bool> evaluateIsBlocked(
    FirebaseFirestore firestore,
    String userId,
  ) async {
    try {
      final doc = await firestore
          .collection(USERS)
          .doc(userId)
          .get();
      if (!doc.exists || doc.data() == null) return false;

      final data = doc.data()!;

      if (data['creditWalletRemittanceEnforcementOverridden']
          == true) {
        print('[REMITTANCE-STATIC] Admin override '
            '-> not blocked');
        return false;
      }

      final walletCredit =
          (data['wallet_credit'] ?? 0.0).toDouble();
      if (walletCredit <= 0) {
        print('[REMITTANCE-STATIC] wallet_credit='
            '$walletCredit (<= 0) -> not blocked');
        return false;
      }

      final lastRemitDate =
          _getLastRemittanceDateStatic(data);
      final now = DateTime.now();
      final yesterdayStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1));

      final remittedRecently = lastRemitDate != null &&
          !lastRemitDate.isBefore(yesterdayStart);
      final blocked = !remittedRecently;

      print('[REMITTANCE-STATIC] now=$now, '
          'yesterdayStart=$yesterdayStart');
      print('[REMITTANCE-STATIC] wallet_credit='
          '$walletCredit, '
          'lastRemitDate=$lastRemitDate');
      print('[REMITTANCE-STATIC] remittedRecently='
          '$remittedRecently -> blocked=$blocked');

      return blocked;
    } catch (e) {
      print('[REMITTANCE-STATIC] Error: $e '
          '-> blocked=true');
      return true;
    }
  }

  static DateTime? _getLastRemittanceDateStatic(Map<String, dynamic> data) {
    final requests = data['transmitRequests'] as List<dynamic>?;
    if (requests == null || requests.isEmpty) return null;

    DateTime? latest;
    for (final req in requests) {
      if (req is! Map<String, dynamic>) continue;
      if (req['type'] != 'credit_wallet_transmit') continue;

      final confirmedAt = req['confirmedAt'];
      if (confirmedAt is! Timestamp) continue;

      final d = confirmedAt.toDate();
      if (latest == null || d.isAfter(latest)) {
        latest = d;
      }
    }
    return latest;
  }
}
