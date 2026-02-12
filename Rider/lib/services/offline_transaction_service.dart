import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/pending_order_completion.dart';

class OfflineTransactionService extends ChangeNotifier {
  static const String _boxName = 'pending_completions';
  Box<Map>? _pendingBox;
  bool _isProcessing = false;

  bool get isProcessing => _isProcessing;
  int get pendingCount => _pendingBox?.length ?? 0;
  bool get isInitialized => _pendingBox != null;

  /// Retry Hive.initFlutter() so path_provider channel is ready (release mode).
  /// On failure after retries, keeps running without offline queue (no throw).
  Future<void> initialize() async {
    final bool isRelease = kReleaseMode;
    final int maxAttempts = isRelease ? 12 : 8;
    final int delayMs = isRelease ? 800 : 500;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await Hive.initFlutter();
        _pendingBox = await Hive.openBox<Map>(_boxName);
        if (attempt > 1) {
          debugPrint('✅ Hive initialized on attempt $attempt');
        }
        notifyListeners();
        return;
      } on PlatformException catch (e) {
        if (e.code == 'channel-error' && attempt < maxAttempts) {
          debugPrint(
            'Hive init attempt $attempt failed (channel not ready), '
            'retrying in ${delayMs}ms...',
          );
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        } else {
          debugPrint(
            'OfflineTransactionService: Hive init failed after retries. '
            'Offline queue disabled.',
          );
          notifyListeners();
          return;
        }
      }
    }
  }

  /// Save transaction locally before attempting network request
  Future<void> queueCompletion(PendingOrderCompletion completion) async {
    if (_pendingBox == null) return;

    try {
      final json = completion.toJson();
      await _pendingBox!.put(completion.orderId, json);
      notifyListeners();
      debugPrint('✅ Queued completion for order: ${completion.orderId}');
    } catch (e) {
      debugPrint('❌ Failed to queue completion: $e');
      rethrow;
    }
  }

  /// Remove from queue after successful completion
  Future<void> removePending(String orderId) async {
    if (_pendingBox == null) return;

    try {
      await _pendingBox!.delete(orderId);
      notifyListeners();
      debugPrint('✅ Removed pending completion: $orderId');
    } catch (e) {
      debugPrint('❌ Failed to remove pending: $e');
    }
  }

  /// Get all pending completions
  List<PendingOrderCompletion> getPendingCompletions() {
    if (_pendingBox == null) return [];

    return _pendingBox!.values.map((json) {
      try {
        return PendingOrderCompletion.fromJson(Map<String, dynamic>.from(json));
      } catch (e) {
        debugPrint('Error parsing pending completion: $e');
        return null;
      }
    }).whereType<PendingOrderCompletion>().toList();
  }

  /// Process all pending transactions
  Future<void> processPendingTransactions() async {
    if (_isProcessing || _pendingBox == null || _pendingBox!.isEmpty) {
      return;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      final pending = getPendingCompletions();
      debugPrint('🔄 Processing ${pending.length} pending transactions');

      for (final transaction in pending) {
        try {
          await _completeOrder(transaction);
          await removePending(transaction.orderId);
          debugPrint('✅ Successfully processed: ${transaction.orderId}');
        } catch (e) {
          debugPrint('❌ Failed to process ${transaction.orderId}: $e');

          // Update retry count
          if (transaction.retryCount < 10) {
            final updated = transaction.copyWith(
              retryCount: transaction.retryCount + 1,
            );
            await queueCompletion(updated);
          } else {
            debugPrint('⚠️ Max retries reached for: ${transaction.orderId}');
          }
        }
      }
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Complete order transaction
  Future<void> _completeOrder(PendingOrderCompletion completion) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }

    final uid = user.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final orderRef = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .doc(completion.orderId);

    final double flooredEarning = completion.earning.floorToDouble();
    final double flooredCreditAmount =
        (completion.totalCommission + completion.earning).floorToDouble();

    await FirebaseFirestore.instance.runTransaction((tx) async {
      // Idempotency check
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw Exception('Order not found');
      }

      final orderData = orderSnap.data() ?? <String, dynamic>{};
      final currentStatus = orderData['status'] as String?;

      if (currentStatus == 'Order Completed') {
        throw Exception('ORDER_ALREADY_COMPLETED');
      }

      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? <String, dynamic>{};

      final double currentEarning =
          (userData['wallet_amount'] ?? 0.0).toDouble();
      final double currentCredit =
          (userData['wallet_credit'] ?? 0.0).toDouble();

      final double newEarningRaw = currentEarning + flooredEarning;
      final double newCreditRaw = currentCredit + flooredCreditAmount;
      final double newEarning = newEarningRaw.floorToDouble();
      final double newCredit = newCreditRaw.floorToDouble();

      // Update user wallets
      tx.update(userRef, {
        'wallet_amount': newEarning,
        'wallet_credit': newCredit,
      });

      // Log wallet entry (earning side)
      final earningLogRef =
          FirebaseFirestore.instance.collection('wallet').doc();
      tx.set(earningLogRef, {
        'user_id': uid,
        'order_id': completion.orderId,
        'amount': flooredEarning,
        'date': Timestamp.fromDate(DateTime.now()),
        'payment_method': 'Wallet',
        'payment_status': 'success',
        'transactionUser': 'driver',
        'isTopUp': false,
        'distanceKm': 0.0,
        'items': completion.totalItemCount,
        'subtotal': completion.itemsTotal,
        'deliveryCharge': completion.deliveryCharge,
        'platformCommission': completion.platformCommission,
        'restaurantCommission': completion.restaurantCommission,
        'totalCommission': completion.totalCommission,
        'tip': completion.tipAmount,
        'totalPayment': completion.totalPayment,
        'earning': completion.earning,
        'totalEarning': completion.totalEarning,
        'incentive': completion.incentive,
        'walletType': 'earning',
        'note': 'Order Delivery Earnings',
      });

      // Log wallet entry (credit side)
      final creditLogRef =
          FirebaseFirestore.instance.collection('wallet').doc();
      tx.set(creditLogRef, {
        'user_id': uid,
        'order_id': completion.orderId,
        'amount': flooredCreditAmount,
        'date': Timestamp.fromDate(DateTime.now()),
        'payment_method': 'Wallet',
        'payment_status': 'success',
        'transactionUser': 'driver',
        'isTopUp': true,
        'distanceKm': 0.0,
        'items': completion.totalItemCount,
        'subtotal': completion.itemsTotal,
        'deliveryCharge': completion.deliveryCharge,
        'platformCommission': completion.platformCommission,
        'restaurantCommission': completion.restaurantCommission,
        'totalCommission': completion.totalCommission,
        'tip': completion.tipAmount,
        'totalPayment': completion.totalPayment,
        'earning': completion.earning,
        'totalEarning': completion.totalEarning,
        'incentive': completion.incentive,
        'walletType': 'credit',
        'note': 'Order Delivery Credit',
      });

      // Mark order as completed
      tx.update(orderRef, {
        'status': 'Order Completed',
        'deliveredAt': Timestamp.fromDate(DateTime.now()),
        'totalEarning': completion.totalEarning,
        'platformCommission': completion.platformCommission,
        'restaurantCommission': completion.restaurantCommission,
        'totalCommission': completion.totalCommission,
        'deliveryCharge': completion.deliveryCharge,
        'incentive': completion.incentive,
      });
    });
  }

  /// Check if order is already queued
  bool isOrderQueued(String orderId) {
    if (_pendingBox == null) return false;
    return _pendingBox!.containsKey(orderId);
  }

  @override
  void dispose() {
    _pendingBox?.close();
    super.dispose();
  }
}













