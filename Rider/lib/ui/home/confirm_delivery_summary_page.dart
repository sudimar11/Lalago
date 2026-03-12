import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../model/pending_order_completion.dart';
import '../../services/connectivity_service.dart';
import '../../services/offline_transaction_service.dart';
import '../../services/background_sync_service.dart';
import '../../widgets/pending_transactions_indicator.dart';
import 'package:foodie_driver/ui/container/ContainerScreen.dart';
import '../../constants.dart';
import '../../main.dart';
import '../../services/order_service.dart';
import '../../services/performance_tier_helper.dart';

class ConfirmDeliverySummaryPage extends StatefulWidget {
  final String orderId;

  const ConfirmDeliverySummaryPage({
    Key? key,
    required this.orderId,
  }) : super(key: key);

  @override
  State<ConfirmDeliverySummaryPage> createState() =>
      _ConfirmDeliverySummaryPageState();
}

class _ConfirmDeliverySummaryPageState
    extends State<ConfirmDeliverySummaryPage> {
  double? _platformCommissionPercent;
  double? _walletAmount;
  double? _driverPerformance;
  double? _incentiveGold;
  double? _incentivePlatinum;
  double? _incentiveSilver;
  bool _isProcessing = false;
  String? _errorMessage;
  int _retryAttempt = 0;
  bool _isSavedLocally = false;

  @override
  void initState() {
    super.initState();
    _loadPerformanceCommission();
    _checkIfOrderQueued();
  }

  /// Check if order is already queued locally
  void _checkIfOrderQueued() {
    final offlineService = context.read<OfflineTransactionService>();
    if (offlineService.isOrderQueued(widget.orderId)) {
      setState(() {
        _isSavedLocally = true;
        _errorMessage = 'This order is queued for sync when online.';
      });
    }
  }

  Future<void> _loadPerformanceCommission() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null || currentUserId.isEmpty) {
        return;
      }

      final firestore = FirebaseFirestore.instance;

      // Read driver's performance value from users collection
      final userDoc =
          await firestore.collection('users').doc(currentUserId).get();
      final userData = userDoc.data();
      final rawPerf = userData?['driver_performance'];

      if (rawPerf is! num) {
        return;
      }

      final perfValue = rawPerf.toDouble();

      // Read performance percent mapping from settings/driver_performance
      final settingsDoc = await firestore
          .collection('settings')
          .doc('driver_performance')
          .get();
      final settingsData = settingsDoc.data() ?? <String, dynamic>{};

      final tier = PerformanceTierHelper.getTier(perfValue);
      final commKey = PerformanceTierHelper.commissionKey(tier);
      num? percent = settingsData[commKey] as num?;

      if (percent == null) {
        return;
      }

      final incentiveGold =
          (settingsData['incentive_gold'] as num?)?.toDouble();
      final incentiveSilver =
          (settingsData['incentive_silver'] as num?)?.toDouble();
      final incentiveBronze =
          (settingsData['incentive_bronze'] as num?)?.toDouble();

      setState(() {
        _platformCommissionPercent = percent!.toDouble();
        _walletAmount =
            (userData?['wallet_amount'] ?? 0.0 as num).toDouble();
        _driverPerformance = perfValue;
        _incentiveGold = incentiveGold;
        _incentivePlatinum = incentiveBronze;
        _incentiveSilver = incentiveSilver;
      });
    } catch (_) {
      // If commission can't be loaded, we just skip those rows
    }
  }

  double _getIncentivePerOrder() {
    if (_driverPerformance == null) return 0.0;
    final tier = PerformanceTierHelper.getTier(_driverPerformance!);
    switch (tier.name) {
      case 'Gold':
        return _incentiveGold ?? 0.0;
      case 'Silver':
        return _incentiveSilver ?? 0.0;
      case 'Bronze':
        return _incentivePlatinum ?? 0.0;
      default:
        return _incentivePlatinum ?? 0.0;
    }
  }

  /// Calculate daily incentive totals (orders count and total amount)
  Future<Map<String, dynamic>> _getDailyIncentiveTotals() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null || currentUserId.isEmpty) {
        return {'ordersCount': 0, 'totalIncentive': 0.0};
      }

      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Query today's completed orders
      final ordersSnapshot = await firestore
          .collection('restaurant_orders')
          .where('driverID', isEqualTo: currentUserId)
          .where('status', isEqualTo: 'Order Completed')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      final ordersCount = ordersSnapshot.size;
      final incentivePerOrder = _getIncentivePerOrder();
      final rawTotal = ordersCount * incentivePerOrder;

      // Return actual values (caps applied in UI logic)
      return {
        'ordersCount': ordersCount,
        'totalIncentive': rawTotal,
      };
    } catch (_) {
      return {'ordersCount': 0, 'totalIncentive': 0.0};
    }
  }

  /// Calculate incentive for current order with daily caps applied
  Future<double> _calculateOrderIncentive() async {
    final incentivePerOrder = _getIncentivePerOrder();
    if (incentivePerOrder <= 0) return 0.0;

    final dailyData = await _getDailyIncentiveTotals();
    final ordersCount = dailyData['ordersCount'] as int;
    final totalIncentive = dailyData['totalIncentive'] as double;

    // Apply caps to get actual earned incentive
    final cappedOrdersCount = ordersCount > 15 ? 15 : ordersCount;
    final cappedTotal = totalIncentive > 60.0 ? 60.0 : totalIncentive;

    // Check if we've hit the daily cap
    final isCapped = cappedOrdersCount >= 15 || cappedTotal >= 60.0;

    if (isCapped) return 0.0;

    // Check if adding this order would exceed the cap
    final newOrdersCount = cappedOrdersCount + 1;
    final newTotalIncentive = cappedTotal + incentivePerOrder;

    if (newOrdersCount > 15 || newTotalIncentive > 60.0) {
      // Calculate remaining incentive before cap
      final remainingOrders = 15 - cappedOrdersCount;
      final remainingAmount = 60.0 - cappedTotal;
      if (remainingOrders > 0 && remainingAmount > 0) {
        return incentivePerOrder < remainingAmount
            ? incentivePerOrder
            : remainingAmount;
      }
      return 0.0;
    }

    return incentivePerOrder;
  }

  /// Check if error is retryable (network/timeout issues)
  bool _isRetryableError(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('network') ||
        errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('unavailable') ||
        errorStr.contains('deadline exceeded');
  }

  /// Parse numeric value from order data key
  double _numFrom(Map<String, dynamic> data, String key) {
    final v = data[key];
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _labelForAppliedDiscountType(String type) {
    switch (type) {
      case 'first_order':
        return 'First-Order Discount';
      case 'new_user_promo':
        return 'New User Promo';
      case 'happy_hour':
        return 'Happy Hour Discount';
      case 'manual_coupon':
        return 'Coupon Discount';
      default:
        return 'Discount';
    }
  }

  /// Calculate total discount amount (single discount only, no stacking).
  /// Prefers appliedDiscountAmount when set; else uses max of legacy fields.
  double _calculateTotalDiscountAmount(Map<String, dynamic> orderData) {
    final referral =
        _numFrom(orderData, 'referralWalletAmountUsed');

    // Single-discount policy: use appliedDiscountAmount when present
    final appliedAmount = _numFrom(orderData, 'appliedDiscountAmount');
    if (appliedAmount > 0) {
      final totalDiscount = appliedAmount + referral;
      // #region agent log
      try {
        debugPrint(
            '[TotalDiscount] single discount: appliedDiscountAmount=$appliedAmount, '
            'referral=$referral, total=$totalDiscount');
        final line = jsonEncode({
          'timestamp': DateTime.now().toIso8601String(),
          'location':
              'confirm_delivery_summary_page:_calculateTotalDiscountAmount',
          'message': 'Single discount (appliedDiscountAmount)',
          'data': {
            'appliedDiscountAmount': appliedAmount,
            'referralWalletAmountUsed': referral,
            'totalDiscount': totalDiscount,
          },
          'sessionId': 'debug-session',
          'hypothesisId': 'single-discount',
        }) + '\n';
        File('/Users/sudimard/Downloads/Lalago/.cursor/debug.log')
            .writeAsStringSync(line, mode: FileMode.append);
      } catch (_) {}
      // #endregion
      return totalDiscount;
    }

    // Legacy orders: one promo only (max of sources) + referral
    final discount = _numFrom(orderData, 'discount');
    final couponAmount = _numFrom(orderData, 'couponDiscountAmount');
    final manualCoupon =
        _numFrom(orderData, 'manualCouponDiscountAmount');
    double specialSum = 0.0;
    if (orderData['specialDiscount'] is Map<String, dynamic>) {
      final sd = orderData['specialDiscount'] as Map<String, dynamic>;
      specialSum =
          _numFrom(sd, 'happy_hour_discount') + _numFrom(sd, 'special_discount');
    }
    final promoOnly = [discount, couponAmount, manualCoupon, specialSum]
        .reduce((a, b) => a > b ? a : b);
    final totalDiscount = promoOnly + referral;

    // #region agent log
    try {
      debugPrint(
          '[TotalDiscount] legacy single: promoOnly=$promoOnly, '
          'referral=$referral, total=$totalDiscount');
      final line = jsonEncode({
        'timestamp': DateTime.now().toIso8601String(),
        'location':
            'confirm_delivery_summary_page:_calculateTotalDiscountAmount',
        'message': 'Legacy single discount (max of sources)',
        'data': {
          'promoOnly': promoOnly,
          'referralWalletAmountUsed': referral,
          'totalDiscount': totalDiscount,
        },
        'sessionId': 'debug-session',
        'hypothesisId': 'single-discount-legacy',
      }) + '\n';
      File('/Users/sudimard/Downloads/Lalago/.cursor/debug.log')
          .writeAsStringSync(line, mode: FileMode.append);
    } catch (_) {}
    // #endregion

    return totalDiscount;
  }

  /// Get discount breakdown from order data for display (single discount only)
  List<Map<String, dynamic>> _getDiscountBreakdown(
    Map<String, dynamic> orderData,
  ) {
    final List<Map<String, dynamic>> discounts = [];

    // Single-discount policy: use appliedDiscountAmount when present
    final appliedAmount = _numFrom(orderData, 'appliedDiscountAmount');
    if (appliedAmount > 0) {
      final type =
          orderData['appliedDiscountType']?.toString() ?? 'Discount';
      final label = _labelForAppliedDiscountType(type);
      discounts.add({'type': type, 'label': label, 'amount': appliedAmount});
      final referral = _numFrom(orderData, 'referralWalletAmountUsed');
      if (referral > 0) {
        discounts.add({
          'type': 'Referral Wallet',
          'label': 'Referral Wallet',
          'amount': referral,
        });
      }
      return discounts;
    }

    // Legacy: Manual Coupon Discount
    if (orderData['manualCouponDiscountAmount'] != null) {
      final manualCoupon = orderData['manualCouponDiscountAmount'];
      if (manualCoupon is num) {
        final amount = manualCoupon.toDouble();
        if (amount > 0) {
          final couponCode = orderData['manualCouponCode'] ?? '';
          discounts.add({
            'type': 'Manual Coupon',
            'label': couponCode.isNotEmpty
                ? 'Coupon Discount ($couponCode)'
                : 'Coupon Discount',
            'amount': amount,
          });
        }
      } else {
        final amount = double.tryParse(manualCoupon.toString()) ?? 0.0;
        if (amount > 0) {
          final couponCode = orderData['manualCouponCode'] ?? '';
          discounts.add({
            'type': 'Manual Coupon',
            'label': couponCode.isNotEmpty
                ? 'Coupon Discount ($couponCode)'
                : 'Coupon Discount',
            'amount': amount,
          });
        }
      }
    }

    // Referral Wallet
    if (orderData['referralWalletAmountUsed'] != null) {
      final referralWallet = orderData['referralWalletAmountUsed'];
      if (referralWallet is num) {
        final amount = referralWallet.toDouble();
        if (amount > 0) {
          discounts.add({
            'type': 'Referral Wallet',
            'label': 'Referral Wallet',
            'amount': amount,
          });
        }
      } else {
        final amount = double.tryParse(referralWallet.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'Referral Wallet',
            'label': 'Referral Wallet',
            'amount': amount,
          });
        }
      }
    }

    // First-Order Discount (only if not manual coupon and couponId is FIRST_ORDER_AUTO)
    final manualCouponId = orderData['manualCouponId'];
    final couponId = orderData['couponId'];
    if (manualCouponId == null &&
        couponId == "FIRST_ORDER_AUTO" &&
        orderData['couponDiscountAmount'] != null) {
      final couponDiscount = orderData['couponDiscountAmount'];
      if (couponDiscount is num) {
        final amount = couponDiscount.toDouble();
        if (amount > 0) {
          discounts.add({
            'type': 'First-Order',
            'label': 'First-Order Discount',
            'amount': amount,
          });
        }
      } else {
        final amount = double.tryParse(couponDiscount.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'First-Order',
            'label': 'First-Order Discount',
            'amount': amount,
          });
        }
      }
    }

    // Check if there's a Happy Hour discount
    bool hasHappyHourDiscount = false;
    if (orderData['specialDiscount'] != null) {
      final specialDiscount = orderData['specialDiscount'];
      if (specialDiscount is Map<String, dynamic>) {
        if (specialDiscount['happy_hour_discount'] != null) {
          final happyHourDiscount = specialDiscount['happy_hour_discount'];
          if (happyHourDiscount is num) {
            final amount = happyHourDiscount.toDouble();
            if (amount > 0) {
              hasHappyHourDiscount = true;
              discounts.add({
                'type': 'Happy Hour',
                'label': 'Happy Hour Discount',
                'amount': amount,
              });
            }
          } else {
            final amount = double.tryParse(happyHourDiscount.toString()) ?? 0.0;
            if (amount > 0) {
              hasHappyHourDiscount = true;
              discounts.add({
                'type': 'Happy Hour',
                'label': 'Happy Hour Discount',
                'amount': amount,
              });
            }
          }
        }
        // Special discount
        if (specialDiscount['special_discount'] != null) {
          final special = specialDiscount['special_discount'];
          if (special is num) {
            final amount = special.toDouble();
            if (amount > 0) {
              discounts.add({
                'type': 'Special',
                'label': 'Special Discount',
                'amount': amount,
              });
            }
          } else {
            final amount = double.tryParse(special.toString()) ?? 0.0;
            if (amount > 0) {
              discounts.add({
                'type': 'Special',
                'label': 'Special Discount',
                'amount': amount,
              });
            }
          }
        }
      }
    }

    // Other Discount (regular coupon - only if not manual coupon, not first-order, and no happy hour discount)
    // The discount field should only be shown if there's no happy hour discount to avoid double counting
    if (manualCouponId == null &&
        couponId != "FIRST_ORDER_AUTO" &&
        !hasHappyHourDiscount &&
        orderData['discount'] != null) {
      final discount = orderData['discount'];
      if (discount is num) {
        final amount = discount.toDouble();
        if (amount > 0) {
          discounts.add({
            'type': 'Other',
            'label': 'Discount',
            'amount': amount,
          });
        }
      } else {
        final amount = double.tryParse(discount.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'Other',
            'label': 'Discount',
            'amount': amount,
          });
        }
      }
    }

    return discounts;
  }

  /// Validate amounts before transaction
  String? _validateAmounts({
    required double earning,
    required double totalCommission,
    required double totalPayment,
  }) {
    if (earning.isNaN || earning.isInfinite || earning < 0) {
      return 'Invalid earning amount: $earning';
    }
    if (totalCommission.isNaN ||
        totalCommission.isInfinite ||
        totalCommission < 0) {
      return 'Invalid commission amount: $totalCommission';
    }
    if (totalPayment.isNaN || totalPayment.isInfinite || totalPayment < 0) {
      return 'Invalid payment amount: $totalPayment';
    }
    return null;
  }

  /// Retry function with exponential backoff
  Future<T> _retryWithBackoff<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxAttempts) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts || !_isRetryableError(e)) {
          rethrow;
        }

        // Update retry attempt in UI
        if (mounted) {
          setState(() {
            _retryAttempt = attempt;
          });
        }

        // Wait before retry with exponential backoff
        await Future.delayed(delay);
        delay = Duration(milliseconds: delay.inMilliseconds * 2);
      }
    }

    throw Exception('Max retry attempts reached');
  }

  Future<void> _applyDeliveryPayout({
    required Map<String, dynamic> orderData,
    required double itemsTotal,
    required int totalItemCount,
    required double deliveryCharge,
    required double tipAmount,
    required double restaurantCommission,
    required double platformCommission,
    required double totalCommission,
    required double earning,
    required double totalEarning,
    required double totalPayment,
    required double incentive,
  }) async {
    // Reset error state
    setState(() {
      _errorMessage = null;
      _retryAttempt = 0;
      _isSavedLocally = false;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _errorMessage = 'User not logged in.';
      });
      return;
    }

    // Validate amounts before transaction
    final validationError = _validateAmounts(
      earning: earning,
      totalCommission: totalCommission,
      totalPayment: totalPayment,
    );
    if (validationError != null) {
      setState(() {
        _errorMessage = validationError;
      });
      return;
    }

    // 1. SAVE LOCALLY FIRST (before attempting network)
    final offlineService = context.read<OfflineTransactionService>();
    final connectivityService = context.read<ConnectivityService>();

    final pendingCompletion = PendingOrderCompletion(
      orderId: widget.orderId,
      earning: earning,
      totalCommission: totalCommission,
      totalPayment: totalPayment,
      incentive: incentive,
      deliveryCharge: deliveryCharge,
      tipAmount: tipAmount,
      platformCommission: platformCommission,
      restaurantCommission: restaurantCommission,
      totalEarning: totalEarning,
      totalItemCount: totalItemCount,
      itemsTotal: itemsTotal,
      orderData: {}, // Empty map to avoid Hive Timestamp serialization error
      createdAt: DateTime.now(),
    );

    try {
      await offlineService.queueCompletion(pendingCompletion);
      setState(() {
        _isSavedLocally = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save locally: $e';
        _isProcessing = false;
      });
      return;
    }

    // 2. CHECK CONNECTIVITY
    final isOnline = await connectivityService.checkConnection();
    if (!isOnline) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorMessage = '✓ Saved locally. Will sync automatically when online.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '✓ Order saved. Will sync when connection is restored.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      // Trigger background sync when online
      BackgroundSyncService.triggerImmediateSync();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => ContainerScreen()),
        (route) => false, // Remove all previous routes
      );
      return;
    }

    // 3. ATTEMPT TRANSACTION
    final uid = user.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final orderRef = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .doc(widget.orderId);

    // Calculate total discount amount
    final double totalDiscountAmount = _calculateTotalDiscountAmount(orderData);

    // Floor amounts to whole numbers
    final double flooredEarning = earning.floorToDouble();
    final double flooredCreditAmount =
        (totalCommission + earning - totalDiscountAmount).floorToDouble();

    try {
      await _retryWithBackoff(
        maxAttempts: 3,
        operation: () async {
          await FirebaseFirestore.instance.runTransaction((tx) async {
            // Idempotency check INSIDE transaction: Check order status first
            final orderSnap = await tx.get(orderRef);
            if (!orderSnap.exists) {
              throw Exception('Order not found');
            }

            final orderData = orderSnap.data() ?? <String, dynamic>{};
            final currentStatus = orderData['status'] as String?;

            // If already completed, abort transaction to prevent double-crediting
            if (currentStatus == 'Order Completed') {
              throw Exception('ORDER_ALREADY_COMPLETED');
            }

            // Calculate total discount amount from all discount fields
            final double totalDiscountAmount =
                _calculateTotalDiscountAmount(orderData);

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

            // Update user wallets: earning (delivery charge minus platform commission) and credit (totalCommission + earning - totalDiscount)
            tx.update(userRef, {
              'wallet_amount': newEarning,
              'wallet_credit': newCredit,
            });

            // Log wallet entry (earning side)
            final earningLogRef =
                FirebaseFirestore.instance.collection('wallet').doc();
            tx.set(earningLogRef, {
              'user_id': uid,
              'order_id': widget.orderId,
              'amount': flooredEarning,
              'date': Timestamp.fromDate(DateTime.now()),
              'payment_method': 'Wallet',
              'payment_status': 'success',
              'transactionUser': 'driver',
              'isTopUp': false,
              'distanceKm': 0.0,
              'items': totalItemCount,
              'subtotal': itemsTotal,
              'deliveryCharge': deliveryCharge,
              'platformCommission': platformCommission,
              'restaurantCommission': restaurantCommission,
              'totalCommission': totalCommission,
              'tip': tipAmount,
              'totalPayment': totalPayment,
              'earning': earning,
              'totalEarning': totalEarning,
              'incentive': incentive,
              'walletType': 'earning',
              'note': 'Order Delivery Earnings',
            });

            // Log wallet entry (credit side)
            final creditLogRef =
                FirebaseFirestore.instance.collection('wallet').doc();
            tx.set(creditLogRef, {
              'user_id': uid,
              'order_id': widget.orderId,
              'amount': flooredCreditAmount,
              'date': Timestamp.fromDate(DateTime.now()),
              'payment_method': 'Wallet',
              'payment_status': 'success',
              'transactionUser': 'driver',
              'isTopUp': true,
              'distanceKm': 0.0,
              'items': totalItemCount,
              'subtotal': itemsTotal,
              'deliveryCharge': deliveryCharge,
              'platformCommission': platformCommission,
              'restaurantCommission': restaurantCommission,
              'totalCommission': totalCommission,
              'tip': tipAmount,
              'totalPayment': totalPayment,
              'earning': earning,
              'totalEarning': totalEarning,
              'incentive': incentive,
              'walletType': 'credit',
              'note': 'Order Delivery Credit',
            });

            // Mark order as completed with payout details
            tx.update(orderRef, {
              'status': 'Order Completed',
              'deliveredAt': Timestamp.fromDate(DateTime.now()),
              'totalEarning': totalEarning,
              'platformCommission': platformCommission,
              'restaurantCommission': restaurantCommission,
              'totalCommission': totalCommission,
              'deliveryCharge': deliveryCharge,
              'incentive': incentive,
              // Driver earnings fields (calculated from original delivery fee)
              'originalDeliveryFee': deliveryCharge.toString(),
              'driverEarnings': earning,
              'discountAmount': totalDiscountAmount,
              'adminPromoCost': totalDiscountAmount,
            });

            // Atomically remove order from rider's array
            // within the same transaction
            tx.update(userRef, {
              'inProgressOrderID':
                  FieldValue.arrayRemove([widget.orderId]),
            });
          });
        },
      );

      // 4. REMOVE FROM QUEUE if successful
      await offlineService.removePending(widget.orderId);

      // 4b. Verify array removal and sync in-memory state
      // (primary removal already happened inside the transaction)
      final verifyDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final updatedOrders =
          verifyDoc.data()?['inProgressOrderID'] as List? ??
              [];

      if (updatedOrders.contains(widget.orderId)) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({
          'inProgressOrderID':
              FieldValue.arrayRemove([widget.orderId]),
        });
      }

      final user = MyAppState.currentUser;
      if (user != null) {
        user.inProgressOrderID = List<dynamic>.from(
          updatedOrders
              .where((id) => id != widget.orderId)
              .toList(),
        );
      }

      await OrderService.updateRiderStatus();

      // 5. Send FCM notification to customer after successful order completion
      try {
        await OrderService.sendStatusUpdateNotification(
          widget.orderId,
          'Order Completed',
        );
      } catch (e) {
        // Log but don't block UI - FCM errors are non-critical
        debugPrint('Error sending FCM notification: $e');
      }

      if (!mounted) return;
      setState(() {
        _errorMessage = null;
        _retryAttempt = 0;
        _isSavedLocally = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Delivery confirmed and payout applied.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => ContainerScreen()),
        (route) => false, // Remove all previous routes
      );
    } catch (e) {
      if (!mounted) return;

      // Handle specific error cases
      final errorStr = e.toString();
      if (errorStr.contains('ORDER_ALREADY_COMPLETED')) {
        // Remove from queue since already completed
        await offlineService.removePending(widget.orderId);
        setState(() {
          _isProcessing = false;
          _isSavedLocally = false;
          _errorMessage =
              'This order has already been completed. Wallet not updated.';
        });
        return;
      }

      final isRetryable = _isRetryableError(e);
      setState(() {
        _isProcessing = false;
        _errorMessage = isRetryable
            ? '✓ Saved locally. Will retry automatically when connection is restored.'
            : 'Failed to apply payout: $e';
      });

      // Trigger background sync for retry
      if (isRetryable) {
        BackgroundSyncService.triggerImmediateSync();
      }
    }
  }

  /// Build Order Details Section
  Widget _buildOrderDetailsSection({
    required double itemsTotal,
    required double deliveryCharge,
    required Map<String, dynamic> orderData,
  }) {
    final discountBreakdown = _getDiscountBreakdown(orderData);
    final totalDiscount = _calculateTotalDiscountAmount(orderData);

    return _SectionCard(
      title: 'Order Details',
      child: Column(
        children: [
          _SummaryRow(
            label: 'Item Price',
            value: itemsTotal,
          ),
          const SizedBox(height: 12),
          if (totalDiscount > 0) ...[
            if (discountBreakdown.length > 1) ...[
              ...discountBreakdown.map((discount) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SummaryRow(
                      label: discount['label'] as String,
                      value: -(discount['amount'] as double),
                      valueColor: Colors.green.shade700,
                    ),
                  )),
            ],
            _SummaryRow(
              label: 'Total Discount',
              value: -totalDiscount,
              valueColor: Colors.green.shade700,
            ),
            const SizedBox(height: 12),
          ],
          _SummaryRow(
            label: 'Delivery Charge',
            value: deliveryCharge,
          ),
        ],
      ),
    );
  }

  /// Build Commissions Section
  Widget _buildCommissionsSection({
    required double? platformCommission,
    required double restaurantCommission,
    required double? totalCommission,
  }) {
    if (platformCommission == null && totalCommission == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Commissions',
          child: Column(
            children: [
              if (platformCommission != null && platformCommission > 0) ...[
                _SummaryRow(
                  label: 'Platform Commission',
                  value: platformCommission,
                  valueColor: Colors.red.shade700,
                ),
                const SizedBox(height: 12),
              ],
              _SummaryRow(
                label: 'Restaurant Commission',
                value: restaurantCommission,
                valueColor: Colors.red.shade700,
              ),
              if (totalCommission != null) ...[
                const SizedBox(height: 12),
                _SummaryRow(
                  label: 'Total Commission',
                  value: totalCommission,
                  valueColor: Colors.red.shade700,
                  isBold: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build Earnings Section with prominent Total Earning display
  Widget _buildEarningsSection({
    required double earning,
    required double totalEarning,
    required double tipAmount,
    required double? incentive,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'Your Earnings',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 12),
        // Prominent Total Earning display
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color(COLOR_ACCENT).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Color(COLOR_ACCENT).withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                'Total Earning',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₱${totalEarning.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(COLOR_ACCENT),
                ),
              ),
              const SizedBox(height: 16),
              Divider(
                height: 1,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Earning',
                value: earning,
                fontSize: 14,
              ),
              if (tipAmount > 0) ...[
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Tip',
                  value: tipAmount,
                  fontSize: 14,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build Credit Wallet Section (totalCommission + earning - totalDiscount)
  Widget _buildCreditWalletSection({
    required double totalCommission,
    required double earning,
    required double totalDiscount,
  }) {
    final creditAmount =
        (totalCommission + earning - totalDiscount).floorToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Credit Wallet',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Commission + Earning − Total Discount',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Total Commission',
                value: totalCommission,
                fontSize: 14,
              ),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Earning',
                value: earning,
                fontSize: 14,
              ),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Total Discount',
                value: -totalDiscount,
                valueColor: Colors.green.shade700,
                fontSize: 14,
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Credit to wallet',
                value: creditAmount,
                valueColor: Colors.blue.shade700,
                isBold: true,
                fontSize: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build Customer Payment Section
  Widget _buildCustomerPaymentSection(double customerTotal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Customer Payment',
          child: _SummaryRow(
            label: 'Total',
            value: customerTotal,
            valueColor: Colors.green.shade700,
            isBold: true,
            fontSize: 18,
            valueFontSize: 20,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Delivery'),
      ),
      body: Column(
        children: [
          const PendingTransactionsIndicator(),
          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('restaurant_orders')
                  .doc(widget.orderId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    !snapshot.data!.exists) {
                  return const Center(
                    child: Text('Unable to load order details'),
                  );
                }

                final data = snapshot.data!.data() as Map<String, dynamic>? ??
                    <String, dynamic>{};

                final List<dynamic> orderedItems =
                    (data['products'] as List<dynamic>?) ?? <dynamic>[];

                final double itemsTotal =
                    orderedItems.fold<double>(0.0, (sum, item) {
                  final map = item as Map<String, dynamic>;
                  final double price =
                      double.tryParse(map['price']?.toString() ?? '0') ?? 0.0;
                  final int qty = (map['quantity'] as num?)?.toInt() ?? 0;
                  return sum + price * qty;
                });

                final int totalItemCount =
                    orderedItems.fold<int>(0, (sum, item) {
                  final map = item as Map<String, dynamic>;
                  final int qty = (map['quantity'] as num?)?.toInt() ?? 0;
                  return sum + qty;
                });

                final double deliveryCharge = double.tryParse(
                      data['deliveryCharge']?.toString() ?? '0',
                    ) ??
                    0.0;

                final double tipAmount = double.tryParse(
                      data['tip_amount']?.toString() ?? '0',
                    ) ??
                    0.0;

                // Calculate total discount amount
                final double totalDiscount =
                    _calculateTotalDiscountAmount(data);

                // Calculate customer total (matching refreshable_order_list.dart)
                final double customerTotal =
                    itemsTotal + deliveryCharge + tipAmount - totalDiscount;

                final double totalPayment =
                    itemsTotal + deliveryCharge + tipAmount;

                // Restaurant commission: ₱20 per item
                final double restaurantCommission =
                    (totalItemCount * 20).toDouble();

                double? platformCommission;
                double? totalCommission;

                if (_platformCommissionPercent != null) {
                  platformCommission =
                      deliveryCharge * (_platformCommissionPercent! / 100);
                  totalCommission = restaurantCommission + platformCommission;
                }

                final double effectivePlatformCommission =
                    platformCommission ?? 0.0;
                final double effectiveTotalCommission = totalCommission ??
                    (restaurantCommission + effectivePlatformCommission);

                // Earning (delivery charge minus platform commission only)
                final double earning = platformCommission != null
                    ? deliveryCharge - platformCommission
                    : deliveryCharge;

                // Total Earning = earning + tipAmount
                final double totalEarning = earning + tipAmount;

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Payment Summary',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Order Details Section
                          _buildOrderDetailsSection(
                            itemsTotal: itemsTotal,
                            deliveryCharge: deliveryCharge,
                            orderData: data,
                          ),
                          // Commissions Section
                          _buildCommissionsSection(
                            platformCommission: platformCommission,
                            restaurantCommission: restaurantCommission,
                            totalCommission: totalCommission,
                          ),
                          // Earnings Section
                          _buildEarningsSection(
                            earning: earning,
                            totalEarning: totalEarning,
                            tipAmount: tipAmount,
                            incentive: null,
                          ),
                          // Credit Wallet Section (totalCommission + earning - totalDiscount)
                          _buildCreditWalletSection(
                            totalCommission: effectiveTotalCommission,
                            earning: earning,
                            totalDiscount: totalDiscount,
                          ),
                          // Customer Payment Section
                          _buildCustomerPaymentSection(customerTotal),
                          const SizedBox(height: 24),
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _isSavedLocally
                                    ? Colors.green.shade50
                                    : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isSavedLocally
                                      ? Colors.green.shade200
                                      : Colors.red.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isSavedLocally ? Icons.info : Icons.error,
                                    color: _isSavedLocally
                                        ? Colors.green.shade700
                                        : Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _isSavedLocally
                                              ? Colors.green.shade700
                                              : Colors.red,
                                        ),
                                        children: [
                                          if (!_isSavedLocally)
                                            const TextSpan(
                                              text: 'Error: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          TextSpan(text: _errorMessage!),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isProcessing
                                  ? null
                                  : () async {
                                      // Prevent double-tap
                                      if (_isProcessing) return;

                                      try {
                                        setState(() {
                                          _isProcessing = true;
                                        });

                                        final incentive =
                                            await _calculateOrderIncentive();
                                        await _applyDeliveryPayout(
                                          orderData: data,
                                          itemsTotal: itemsTotal,
                                          totalItemCount: totalItemCount,
                                          deliveryCharge: deliveryCharge,
                                          tipAmount: tipAmount,
                                          restaurantCommission:
                                              restaurantCommission,
                                          platformCommission:
                                              effectivePlatformCommission,
                                          totalCommission:
                                              effectiveTotalCommission,
                                          earning: earning,
                                          totalEarning: totalEarning,
                                          totalPayment: totalPayment,
                                          incentive: incentive,
                                        );
                                      } catch (e) {
                                        // Error already handled in _applyDeliveryPayout
                                        if (mounted) {
                                          setState(() {
                                            _isProcessing = false;
                                          });
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isProcessing
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      _errorMessage != null ? 'Retry' : 'Done',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Section Card Widget for grouping related information
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    Key? key,
    required this.title,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.shade200,
              width: 1,
            ),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final Color? valueColor;
  final bool isBold;
  final bool isLarge;
  final double? fontSize;
  final double? valueFontSize;

  const _SummaryRow({
    Key? key,
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
    this.isLarge = false,
    this.fontSize,
    this.valueFontSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color displayColor = valueColor ?? Colors.black87;
    final double labelFontSize = fontSize ?? (isLarge ? 18.0 : 16.0);
    final double amountFontSize = valueFontSize ?? (isLarge ? 20.0 : 16.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: labelFontSize,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          '₱${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: amountFontSize,
            fontWeight: FontWeight.bold,
            color: displayColor,
          ),
        ),
      ],
    );
  }
}
