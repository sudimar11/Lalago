import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/notification_service.dart';
import 'package:foodie_driver/services/order_service.dart';
import 'package:foodie_driver/utils/geo_utils.dart';
import 'package:foodie_driver/ui/home/customermap.dart';
import 'package:foodie_driver/widgets/replacement_search_dialog.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/ui/chat_screen/chat_screen.dart';
import 'package:foodie_driver/ui/chat_screen/admin_driver_chat_screen.dart';
import 'package:foodie_driver/services/order_chat_service.dart';
import 'package:foodie_driver/services/chat_read_service.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/utils/order_ready_time_helper.dart';
import 'package:intl/intl.dart';

/// Parsed data for a single order card (used by ListView.builder).
class _OrderCardData {
  const _OrderCardData({
    required this.index,
    required this.doc,
    required this.data,
    required this.status,
    required this.vendor,
    required this.vendorLatitude,
    required this.vendorLongitude,
    required this.author,
    required this.authorLatitude,
    required this.authorLongitude,
    required this.fullAddress,
    required this.orderedItems,
    required this.itemsTotal,
    required this.totalItemCount,
    required this.deliveryCharge,
    required this.tipAmount,
    required this.totalPayment,
    required this.notes,
    required this.estimatedTimeToPrepare,
    this.orderTime,
    this.acceptedAt,
  });

  final int index;
  final QueryDocumentSnapshot doc;
  final Map<String, dynamic> data;
  final String status;
  final Map<String, dynamic> vendor;
  final double vendorLatitude;
  final double vendorLongitude;
  final Map<String, dynamic> author;
  final double authorLatitude;
  final double authorLongitude;
  final String fullAddress;
  final List<dynamic> orderedItems;
  final double itemsTotal;
  final int totalItemCount;
  final double deliveryCharge;
  final double tipAmount;
  final double totalPayment;
  final String notes;
  final String estimatedTimeToPrepare;
  final DateTime? orderTime;
  final DateTime? acceptedAt;
}

/// A reusable widget that displays a refreshable list of orders
class RefreshableOrderList extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;
  final VoidCallback onRefresh;

  const RefreshableOrderList({
    Key? key,
    required this.docs,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<RefreshableOrderList> createState() => _RefreshableOrderListState();
}

class _RefreshableOrderListState extends State<RefreshableOrderList> {
  double? _platformCommissionPercent;
  double _fixCommissionPerItem = 0.0;
  double? _driverPerformance;
  double? _incentiveGold;
  double? _incentivePlatinum;
  double? _incentiveSilver;
  DateTime? _now;
  Timer? _timer;
  final Map<String, double> _distanceCache = <String, double>{};
  final Map<String, Future<double>> _distanceFutures = <String, Future<double>>{};
  final Map<String, double> _riderToVendorDistanceCache = <String, double>{};
  final Map<String, Future<double>> _riderToVendorDistanceFutures =
      <String, Future<double>>{};

  final NotificationService _notificationService = NotificationService();
  final Map<String, Timer> _leaveByTimers = <String, Timer>{};
  final Map<String, DateTime> _scheduledLeaveByByOrderId = <String, DateTime>{};
  final Map<String, DateTime> _notifiedLeaveByByOrderId = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _startMonitoringOrders();
    _syncLeaveByReminders();
    _loadPerformanceCommission();
    _loadAdminCommission();
  }

  @override
  void didUpdateWidget(RefreshableOrderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Start monitoring new orders when list updates
    _startMonitoringOrders();
    _syncLeaveByReminders();
  }

  void _startMonitoringOrders() {
    // Start monitoring all orders in the list for delays and status changes
    for (var doc in widget.docs) {
      final orderId = doc.id;
      OrderChatService.startMonitoringOrder(orderId);
    }
  }

  void _syncLeaveByReminders() {
    final currentOrderIds = widget.docs.map((d) => d.id).toSet();

    // Cancel reminders for orders no longer shown.
    final toRemove = _leaveByTimers.keys
        .where((orderId) => !currentOrderIds.contains(orderId))
        .toList();
    for (final orderId in toRemove) {
      _cancelLeaveByReminder(orderId);
      _scheduledLeaveByByOrderId.remove(orderId);
      _notifiedLeaveByByOrderId.remove(orderId);
    }

    // Schedule or update reminders for visible orders.
    for (final doc in widget.docs) {
      _scheduleLeaveByReminderForDoc(doc);
    }
  }

  void _cancelLeaveByReminder(String orderId) {
    _leaveByTimers.remove(orderId)?.cancel();
  }

  DateTime? _readTimestampAsDateTime(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  DateTime? _readOrderBaseTime(Map<String, dynamic> data) {
    final acceptedAt = _readTimestampAsDateTime(data['acceptedAt']);
    if (acceptedAt != null) return acceptedAt;
    final createdAt = _readTimestampAsDateTime(data['createdAt']);
    if (createdAt != null) return createdAt;
    final timestamp = _readTimestampAsDateTime(data['timestamp']);
    return timestamp;
  }

  Future<void> _scheduleLeaveByReminderForDoc(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final status = (data['status'] ?? '').toString();

    // Only relevant while the rider is waiting for the order to become ready.
    const targetStatuses = <String>{
      'Driver Pending',
      'Driver Accepted',
    };
    if (!targetStatuses.contains(status)) {
      _cancelLeaveByReminder(doc.id);
      _scheduledLeaveByByOrderId.remove(doc.id);
      return;
    }

    final vendor = (data['vendor'] ?? {}) as Map<String, dynamic>;
    final vendorTitle = (vendor['title'] ?? 'Restaurant').toString();
    final vendorLatRaw = vendor['latitude'];
    final vendorLngRaw = vendor['longitude'];
    final vendorLat = vendorLatRaw is num ? vendorLatRaw.toDouble() : 0.0;
    final vendorLng = vendorLngRaw is num ? vendorLngRaw.toDouble() : 0.0;
    if (vendorLat == 0.0 && vendorLng == 0.0) return;

    final baseTime = _readOrderBaseTime(data);
    if (baseTime == null) return;

    final prepMinutes = OrderReadyTimeHelper.parsePreparationMinutes(
      data['estimatedTimeToPrepare']?.toString(),
    );
    final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);

    double distanceKm = 0.0;
    try {
      distanceKm = await _getRiderToVendorDistance(
        doc.id,
        vendorLat,
        vendorLng,
      );
    } catch (_) {
      // If we can't calculate distance, we can't compute leave-by reliably.
      return;
    }
    final leaveBy = OrderReadyTimeHelper.getLeaveBy(readyAt, distanceKm);

    // Avoid rescheduling for tiny changes (distance jitter).
    final previouslyScheduled = _scheduledLeaveByByOrderId[doc.id];
    if (previouslyScheduled != null) {
      final drift = previouslyScheduled.difference(leaveBy).abs();
      if (drift < const Duration(minutes: 1)) {
        return;
      }
    }

    _cancelLeaveByReminder(doc.id);
    _scheduledLeaveByByOrderId[doc.id] = leaveBy;

    final now = DateTime.now();
    if (!leaveBy.isAfter(now.add(const Duration(seconds: 10)))) {
      // It's already time (or almost time) to leave.
      final lastNotified = _notifiedLeaveByByOrderId[doc.id];
      if (lastNotified == null ||
          lastNotified.difference(leaveBy).abs() >= const Duration(minutes: 1)) {
        _notifiedLeaveByByOrderId[doc.id] = leaveBy;
        await _notificationService.showNotification(
          NotificationData(
            type: NotificationType.reminder,
            title: 'Leave now for pickup',
            body: '$vendorTitle • Order is almost ready. Leave now.',
            priority: NotificationPriority.high,
            payload: {
              'type': 'leave_by',
              'orderId': doc.id,
            },
          ),
        );
      }
      return;
    }

    final delay = leaveBy.difference(now);
    _leaveByTimers[doc.id] = Timer(delay, () async {
      try {
        final latest = await FirebaseFirestore.instance
            .collection('restaurant_orders')
            .doc(doc.id)
            .get();
        final latestStatus =
            (latest.data()?['status'] ?? '').toString();
        if (!targetStatuses.contains(latestStatus)) return;

        _notifiedLeaveByByOrderId[doc.id] = leaveBy;
        await _notificationService.showNotification(
          NotificationData(
            type: NotificationType.reminder,
            title: 'Leave now for pickup',
            body: '$vendorTitle • Leave now to arrive on time.',
            priority: NotificationPriority.high,
            payload: {
              'type': 'leave_by',
              'orderId': doc.id,
            },
          ),
        );
      } catch (_) {
        // Ignore notification failures.
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final timer in _leaveByTimers.values) {
      timer.cancel();
    }
    _leaveByTimers.clear();
    for (var doc in widget.docs) {
      OrderChatService.stopListeningToOrderStatus(doc.id);
    }
    super.dispose();
  }

  Future<void> _loadPerformanceCommission() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null || currentUserId.isEmpty) {
        return;
      }

      final firestore = FirebaseFirestore.instance;

      // 1) Read driver's performance value from users collection
      final userDoc =
          await firestore.collection('users').doc(currentUserId).get();
      final userData = userDoc.data();
      final rawPerf = userData?['driver_performance'];

      if (rawPerf is! num) {
        return;
      }

      final perfValue = rawPerf.toDouble();

      // 2) Read performance percent mapping from settings/driver_performance
      final settingsDoc = await firestore
          .collection('settings')
          .doc('driver_performance')
          .get();
      final settingsData = settingsDoc.data() ?? <String, dynamic>{};

      // Determine tier and corresponding percent
      num? percent;
      if (perfValue < 75) {
        percent = settingsData['silver'] as num?;
      } else if (perfValue < 85) {
        percent = settingsData['Platinum'] as num?;
      } else {
        percent = settingsData['Gold'] as num?;
      }

      if (percent == null) {
        return;
      }

      // Load incentive values from Firestore
      final incentiveGold =
          (settingsData['incentive_gold'] as num?)?.toDouble();
      final incentivePlatinum =
          (settingsData['incentive_platinum'] as num?)?.toDouble();
      final incentiveSilver =
          (settingsData['incentive_silver'] as num?)?.toDouble();

      setState(() {
        _platformCommissionPercent = percent!.toDouble();
        _driverPerformance = perfValue;
        _incentiveGold = incentiveGold;
        _incentivePlatinum = incentivePlatinum;
        _incentiveSilver = incentiveSilver;
      });
    } catch (_) {
      // Fail silently; commission row will be hidden
    }
  }

  Future<void> _loadAdminCommission() async {
    try {
      final firestore = FirebaseFirestore.instance;
      final adminCommissionDoc =
          await firestore.collection('settings').doc('AdminCommission').get();

      if (adminCommissionDoc.exists) {
        final adminCommissionData = adminCommissionDoc.data();
        final commissionType =
            adminCommissionData?['commissionType'] ?? 'Fixed';

        if (commissionType == 'Fixed') {
          final fixCommission = double.tryParse(
                  adminCommissionData?['fix_commission']?.toString() ?? '0') ??
              0.0;
          setState(() {
            _fixCommissionPerItem = fixCommission;
          });
        }
      }
    } catch (_) {
      // Fail silently; commission will default to 0.0
    }
  }

  /// Get incentive amount per order based on driver performance tier
  double _getIncentivePerOrder() {
    if (_driverPerformance == null) return 0.0;
    if (_driverPerformance! >= 85) {
      return _incentiveGold ?? 0.0; // Gold
    } else if (_driverPerformance! >= 75) {
      return _incentivePlatinum ?? 0.0; // Platinum
    } else {
      return _incentiveSilver ?? 0.0; // Silver
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

  /// Get discount breakdown from order data (matching customer app display)
  /// Returns a map with subtotal, deliveryFee, discounts list, totalDiscount, and customerTotal
  Map<String, dynamic> _getDiscountBreakdown(
    Map<String, dynamic> orderData,
    double itemsTotal,
    double deliveryCharge,
  ) {
    final List<Map<String, dynamic>> discounts = [];
    double totalDiscount = 0.0;

    // Manual Coupon Discount
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
          totalDiscount += amount;
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
          totalDiscount += amount;
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
          totalDiscount += amount;
        }
      } else {
        final amount = double.tryParse(referralWallet.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'Referral Wallet',
            'label': 'Referral Wallet',
            'amount': amount,
          });
          totalDiscount += amount;
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
          totalDiscount += amount;
        }
      } else {
        final amount = double.tryParse(couponDiscount.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'First-Order',
            'label': 'First-Order Discount',
            'amount': amount,
          });
          totalDiscount += amount;
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
              totalDiscount += amount;
            }
          } else {
            final amount =
                double.tryParse(happyHourDiscount.toString()) ?? 0.0;
            if (amount > 0) {
              hasHappyHourDiscount = true;
              discounts.add({
                'type': 'Happy Hour',
                'label': 'Happy Hour Discount',
                'amount': amount,
              });
              totalDiscount += amount;
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
          totalDiscount += amount;
        }
      } else {
        final amount = double.tryParse(discount.toString()) ?? 0.0;
        if (amount > 0) {
          discounts.add({
            'type': 'Other',
            'label': 'Discount',
            'amount': amount,
          });
          totalDiscount += amount;
        }
      }
    }

    // Calculate subtotal (items + delivery) and customer total
    final double subtotal = itemsTotal + deliveryCharge;
    final double customerTotal = subtotal - totalDiscount;

    return {
      'subtotal': subtotal,
      'deliveryFee': deliveryCharge,
      'discounts': discounts,
      'totalDiscount': totalDiscount,
      'customerTotal': customerTotal,
    };
  }

  String _readOrderVendorIdFromData(Map<String, dynamic> data) {
    final vendorId = data['vendorID']?.toString() ?? '';
    if (vendorId.isNotEmpty) return vendorId;
    final vendor = data['vendor'] as Map<String, dynamic>? ?? {};
    return (vendor['id'] ?? vendor['vendorId'] ?? vendor['vendorID'] ?? '')
        .toString();
  }

  String _readFoodName(Map<String, dynamic> d) {
    final v = (d['name'] ?? d['title'] ?? d['product_name'] ??
        d['productName'] ?? 'Food').toString();
    return v.isEmpty ? 'Food' : v;
  }

  String _readFoodCategoryId(Map<String, dynamic> d) {
    return (d['categoryId'] ?? d['category_id'] ?? '').toString();
  }

  String _readFoodPhoto(Map<String, dynamic> d) {
    return (d['photo'] ?? d['image'] ?? d['imageUrl'] ??
        d['thumbnail'] ?? d['picture'] ?? '').toString();
  }

  String _readFoodPrice(Map<String, dynamic> d) {
    final v = (d['price'] ?? d['salePrice'] ?? d['regularPrice'] ?? '0')
        .toString();
    return v.isEmpty ? '0' : v;
  }

  String _readFoodDiscountPrice(Map<String, dynamic> d) {
    return (d['discount_price'] ?? d['discountPrice'] ?? '').toString();
  }

  Future<List<Map<String, dynamic>>> _loadVendorAvailableFoods(
      String vendorId) async {
    if (vendorId.isEmpty) return [];
    final c = FirebaseFirestore.instance.collection('vendor_products');
    final queries = [
      c.where('publish', isEqualTo: true)
          .where('vendorId', isEqualTo: vendorId).get(),
      c.where('publish', isEqualTo: true)
          .where('vendorID', isEqualTo: vendorId).get(),
      c.where('publish', isEqualTo: true)
          .where('vendor_id', isEqualTo: vendorId).get(),
    ];
    final results = await Future.wait(queries);
    final Map<String, Map<String, dynamic>> byId = {};
    for (final snapshot in results) {
      for (final doc in snapshot.docs) {
        final d = doc.data();
        byId[doc.id] = {
          'id': doc.id,
          'name': _readFoodName(d),
          'categoryId': _readFoodCategoryId(d),
          'photo': _readFoodPhoto(d),
          'price': _readFoodPrice(d),
          'discount_price': _readFoodDiscountPrice(d),
        };
      }
    }
    return byId.values.toList();
  }

  Future<void> _persistProducts(String orderId, List<dynamic> products) async {
    if (orderId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order ID missing')),
        );
      }
      return;
    }
    final list = products
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : e)
        .toList();
    try {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .update({
        'products': list,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _handleReplace(
    BuildContext context,
    Map<String, dynamic> product,
    String orderId,
    Map<String, dynamic> data,
    VoidCallback afterUpdate,
  ) async {
    final vendorId = _readOrderVendorIdFromData(data);
    final foods = await _loadVendorAvailableFoods(vendorId);
    if (foods.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No replacement available')),
        );
      }
      return;
    }
    final vendor = data['vendor'] as Map<String, dynamic>? ?? {};
    final restaurantName = vendor['title']?.toString();
    final selection = await ReplacementSearchDialog.show(
      context,
      candidates: foods,
      restaurantName: restaurantName,
    );
    if (selection == null) return;
    setState(() {
      product['id'] = selection['id']?.toString() ?? product['id'];
      product['name'] = selection['name']?.toString() ?? product['name'];
      final cid = selection['categoryId']?.toString() ?? product['categoryId'];
      if (cid.isNotEmpty) {
        product['categoryId'] = cid;
        product['category_id'] = cid;
      }
      final photo = selection['photo']?.toString() ?? '';
      if (photo.isNotEmpty) product['photo'] = photo;
      final price = selection['price']?.toString();
      if (price != null && price.isNotEmpty) product['price'] = price;
      final dp = selection['discount_price']?.toString();
      if (dp != null && dp.isNotEmpty) product['discount_price'] = dp;
    });
    await _persistProducts(orderId, data['products'] as List<dynamic>);
    afterUpdate();
  }

  Future<void> _handleRemove(
    BuildContext context,
    Map<String, dynamic> product,
    String orderId,
    Map<String, dynamic> data,
    VoidCallback afterUpdate,
  ) async {
    final products = data['products'] as List<dynamic>? ?? [];
    if (products.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot remove the last item')),
        );
      }
      return;
    }
    final itemName = product['name']?.toString() ?? 'this item';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove item?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Is "$itemName" really not available?',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(
              'Once removed, it cannot be added back to this order.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    products.remove(product);
    await _persistProducts(orderId, products);
    afterUpdate();
  }

  _OrderCardData _parseOrderDoc(int index, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final status = (data['status'] ?? 'Unknown').toString();
    final vendor = (data['vendor'] ?? {}) as Map<String, dynamic>;
    final double vendorLatitude =
        ((vendor['latitude'] ?? 0.0) as num).toDouble();
    final double vendorLongitude =
        ((vendor['longitude'] ?? 0.0) as num).toDouble();
    final author = (data['author'] ?? {}) as Map<String, dynamic>;
    final List<Map<String, dynamic>> shippingList =
        List<Map<String, dynamic>>.from(
            (author['shippingAddress'] as List<dynamic>?) ?? []);
    final Map<String, dynamic> defaultAddr = shippingList.firstWhere(
      (a) => a['isDefault'] == true,
      orElse: () => <String, dynamic>{},
    );
    final Map<String, dynamic> loc =
        (defaultAddr['location'] as Map<String, dynamic>?) ?? {};
    final double authorLatitude =
        ((loc['latitude'] ?? 0.0) as num).toDouble();
    final double authorLongitude =
        ((loc['longitude'] ?? 0.0) as num).toDouble();
    final String addressLine = (defaultAddr['address'] as String?) ?? '';
    final String landmark = (defaultAddr['landmark'] as String?) ?? '';
    final String locality = (defaultAddr['locality'] as String?) ?? '';
    final String fullAddress = [
      addressLine,
      if (landmark.isNotEmpty) landmark,
      if (locality.isNotEmpty) locality,
    ].where((e) => e.trim().isNotEmpty).join(', ');
    final List<dynamic> orderedItems =
        (data['products'] as List<dynamic>?) ?? [];
    final double itemsTotal = orderedItems.fold<double>(0.0, (sum, item) {
      final double price =
          double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      final int qty = (item['quantity'] ?? 0) as int;
      return sum + price * qty;
    });
    final int totalItemCount = orderedItems.fold<int>(0, (sum, item) {
      final int qty = (item['quantity'] ?? 0) as int;
      return sum + qty;
    });
    final double deliveryCharge =
        double.tryParse((data['deliveryCharge'] ?? '0').toString()) ?? 0.0;
    final double tipAmount =
        double.tryParse((data['tip_amount'] ?? '0').toString()) ?? 0.0;
    final double effectiveItemsTotal = orderedItems.fold<double>(0.0, (sum, item) {
      final double price =
          double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
      final int qty = (item['quantity'] ?? 0) as int;
      double effectivePrice = price - _fixCommissionPerItem;
      if (effectivePrice < 0) effectivePrice = 0;
      return sum + (effectivePrice * qty);
    });
    final double totalPayment =
        effectiveItemsTotal + deliveryCharge + tipAmount;
    final String notes = (data['notes'] ?? '').toString();
    final String estimatedTimeToPrepare =
        (data['estimatedTimeToPrepare'] ?? '').toString();
    final DateTime? orderTime = data['createdAt'] != null
        ? (data['createdAt'] as Timestamp).toDate()
        : data['timestamp'] != null
            ? (data['timestamp'] as Timestamp).toDate()
            : null;
    final DateTime? acceptedAt = data['acceptedAt'] != null &&
            data['acceptedAt'] is Timestamp
        ? (data['acceptedAt'] as Timestamp).toDate()
        : null;
    return _OrderCardData(
      index: index,
      doc: doc,
      data: data,
      status: status,
      vendor: vendor,
      vendorLatitude: vendorLatitude,
      vendorLongitude: vendorLongitude,
      author: author,
      authorLatitude: authorLatitude,
      authorLongitude: authorLongitude,
      fullAddress: fullAddress,
      orderedItems: orderedItems,
      itemsTotal: itemsTotal,
      totalItemCount: totalItemCount,
      deliveryCharge: deliveryCharge,
      tipAmount: tipAmount,
      totalPayment: totalPayment,
      notes: notes,
      estimatedTimeToPrepare: estimatedTimeToPrepare,
      orderTime: orderTime,
      acceptedAt: acceptedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTime = _now ?? DateTime.now();
    final docs = _sortDocsByLeaveByPriority(widget.docs, currentTime);
    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
        await Future.delayed(const Duration(milliseconds: 200));
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final doc = docs[index];
          final parsed = _parseOrderDoc(index, doc);
          return _buildOrderCard(
            context,
            currentTime,
            parsed,
            () {
              widget.onRefresh();
              setState(() {});
            },
          );
        },
      ),
    );
  }

  List<QueryDocumentSnapshot> _sortDocsByLeaveByPriority(
    List<QueryDocumentSnapshot> docs,
    DateTime now,
  ) {
    final indexed = docs.asMap().entries.toList();

    int groupFor(String status, bool leaveNow) {
      if (status == 'Order Shipped') return 0;
      if (leaveNow) return 1;
      if (status == 'Driver Pending' || status == 'Driver Accepted') return 2;
      return 3;
    }

    DateTime? computeReadyAt(Map<String, dynamic> data) {
      final baseTime = _readOrderBaseTime(data);
      if (baseTime == null) return null;
      final prepMinutes = OrderReadyTimeHelper.parsePreparationMinutes(
        data['estimatedTimeToPrepare']?.toString(),
      );
      return OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
    }

    DateTime? computeLeaveBy(String orderId, DateTime readyAt) {
      final distanceKm = _riderToVendorDistanceCache[orderId];
      if (distanceKm == null) return null;
      return OrderReadyTimeHelper.getLeaveBy(readyAt, distanceKm);
    }

    indexed.sort((a, b) {
      final da = a.value.data() as Map<String, dynamic>;
      final db = b.value.data() as Map<String, dynamic>;
      final sa = (da['status'] ?? '').toString();
      final sb = (db['status'] ?? '').toString();

      final readyAtA = computeReadyAt(da);
      final readyAtB = computeReadyAt(db);

      final leaveByA =
          readyAtA == null ? null : computeLeaveBy(a.value.id, readyAtA);
      final leaveByB =
          readyAtB == null ? null : computeLeaveBy(b.value.id, readyAtB);

      final leaveNowA = leaveByA != null &&
          (now.isAfter(leaveByA) || now.isAtSameMomentAs(leaveByA));
      final leaveNowB = leaveByB != null &&
          (now.isAfter(leaveByB) || now.isAtSameMomentAs(leaveByB));

      final ga = groupFor(sa, leaveNowA);
      final gb = groupFor(sb, leaveNowB);
      if (ga != gb) return ga.compareTo(gb);

      // Within the "active" group, sort by earliest leave-by (fallback to ready-at).
      final ta = (leaveByA ?? readyAtA)?.millisecondsSinceEpoch;
      final tb = (leaveByB ?? readyAtB)?.millisecondsSinceEpoch;
      if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);

      // Stable fallback.
      return a.key.compareTo(b.key);
    });

    return indexed.map((e) => e.value).toList();
  }

  Widget _buildWhenToLeaveChip({
    required String status,
    required DateTime? acceptedAt,
    required DateTime? orderTime,
    required String estimatedTimeToPrepare,
    required String docId,
    required double vendorLatitude,
    required double vendorLongitude,
    required DateTime currentTime,
  }) {
    if (status == 'Order Shipped') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              'Ready for pickup • Leave now',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
          ],
        ),
      );
    }

    final baseTime = acceptedAt ?? orderTime;
    if (baseTime == null) return const SizedBox.shrink();

    final prepMinutes =
        OrderReadyTimeHelper.parsePreparationMinutes(estimatedTimeToPrepare);
    final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
    final timeFormat = DateFormat.jm();

    return FutureBuilder<double>(
      future: _getRiderToVendorDistance(docId, vendorLatitude, vendorLongitude),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting ||
            !snap.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Ready at ~${timeFormat.format(readyAt)} • Calculating…',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          );
        }
        final distanceKm = snap.data ?? 0.0;
        final leaveBy =
            OrderReadyTimeHelper.getLeaveBy(readyAt, distanceKm);
        final now = currentTime;
        final leaveNow = now.isAfter(leaveBy) || now.isAtSameMomentAs(leaveBy);

        final String label = leaveNow
            ? 'Ready ~${timeFormat.format(readyAt)} • Leave now'
            : 'Ready ~${timeFormat.format(readyAt)} • Leave by ${timeFormat.format(leaveBy)}';

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: leaveNow ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: leaveNow ? Colors.orange.shade300 : Colors.blue.shade200,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                leaveNow ? Icons.directions_run : Icons.schedule,
                color: leaveNow ? Colors.orange.shade700 : Colors.blue.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: leaveNow
                        ? Colors.orange.shade800
                        : Colors.blue.shade800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<double> _getRiderToVendorDistance(
    String docId,
    double vendorLat,
    double vendorLng,
  ) {
    _riderToVendorDistanceFutures[docId] ??= GeoUtils.calculateDistance(
      vendorLat,
      vendorLng,
      null,
      null,
    ).then((v) {
      if (mounted) setState(() => _riderToVendorDistanceCache[docId] = v);
      return v;
    });
    return _riderToVendorDistanceFutures[docId]!;
  }

  Widget _buildDistanceOverlay(
    String docId,
    String status,
    double vendorLatitude,
    double vendorLongitude,
    double authorLatitude,
    double authorLongitude,
  ) {
    final cached = _distanceCache[docId];
    if (cached != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '${cached.toStringAsFixed(2)} km',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      );
    }
    _distanceFutures[docId] ??= (status == 'Order Shipped'
            ? GeoUtils.calculateDistance(
                vendorLatitude, vendorLongitude, null, null)
            : GeoUtils.calculateDistance(
                authorLatitude,
                authorLongitude,
                vendorLatitude,
                vendorLongitude,
              ))
        .then((v) {
      if (mounted) setState(() => _distanceCache[docId] = v);
      return v;
    });
    return FutureBuilder<double>(
      future: _distanceFutures[docId],
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final distanceKm = snap.data ?? 0.0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            '${distanceKm.toStringAsFixed(2)} km',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    DateTime currentTime,
    _OrderCardData parsed,
    VoidCallback afterUpdate,
  ) {
    final index = parsed.index;
    final doc = parsed.doc;
    final data = parsed.data;
    final status = parsed.status;
    final vendor = parsed.vendor;
    final vendorLatitude = parsed.vendorLatitude;
    final vendorLongitude = parsed.vendorLongitude;
    final author = parsed.author;
    final authorLatitude = parsed.authorLatitude;
    final authorLongitude = parsed.authorLongitude;
    final fullAddress = parsed.fullAddress;
    final orderedItems = parsed.orderedItems;
    final itemsTotal = parsed.itemsTotal;
    final totalItemCount = parsed.totalItemCount;
    final deliveryCharge = parsed.deliveryCharge;
    final tipAmount = parsed.tipAmount;
    final totalPayment = parsed.totalPayment;
    final notes = parsed.notes;
    final estimatedTimeToPrepare = parsed.estimatedTimeToPrepare;
    final orderTime = parsed.orderTime;
    final effectiveItemsTotal =
        totalPayment - deliveryCharge - tipAmount;

    return Card(
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black, width: 1)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timer and Order Number
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Timer
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer,
                              color: Colors.blue.shade700, size: 14),
                          const SizedBox(width: 4),
                          orderTime != null
                              ? Text(
                                  () {
                                    final duration =
                                        currentTime.difference(orderTime);
                                    final hours = duration.inHours;
                                    final minutes =
                                        duration.inMinutes.remainder(60);
                                    final seconds =
                                        duration.inSeconds.remainder(60);
                                    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
                                  }(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                )
                              : Text(
                                  '00:00:00',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    // Order Number
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long,
                              color: Colors.green.shade700, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Order #${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Order Date
                if (orderTime != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('MMM dd, yyyy').format(orderTime),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
                // Estimated Preparation Time
                if (estimatedTimeToPrepare.isNotEmpty &&
                    estimatedTimeToPrepare != 'null')
                  Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule,
                                color: Colors.orange.shade700, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Estimated Preparation: $estimatedTimeToPrepare minutes',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                // When to leave / Ready for pickup (Driver Pending, Driver Accepted, Order Shipped)
                if (status == 'Driver Pending' ||
                    status == 'Driver Accepted' ||
                    status == 'Order Shipped') ...[
                  const SizedBox(height: 12),
                  _buildWhenToLeaveChip(
                    status: status,
                    acceptedAt: parsed.acceptedAt,
                    orderTime: orderTime,
                    estimatedTimeToPrepare: estimatedTimeToPrepare,
                    docId: doc.id,
                    vendorLatitude: vendorLatitude,
                    vendorLongitude: vendorLongitude,
                    currentTime: currentTime,
                  ),
                ],
                const SizedBox(height: 8),
                // Map placeholder with Distance - avoids multiple SurfaceViews (BLASTBufferQueue errors)
                if (status == 'Order Shipped'
                    ? (vendorLatitude != 0.0 && vendorLongitude != 0.0)
                    : (authorLatitude != 0.0 && authorLongitude != 0.0)) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: Container(
                            color: Colors.grey.shade200,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    status == 'Order Shipped'
                                        ? Icons.store
                                        : Icons.location_on,
                                    size: 48,
                                    color: Colors.grey.shade600,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    status == 'Order Shipped'
                                        ? 'Restaurant'
                                        : 'Customer',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Distance overlay (cached per doc.id)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: _buildDistanceOverlay(
                            doc.id,
                            status,
                            vendorLatitude,
                            vendorLongitude,
                            authorLatitude,
                            authorLongitude,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                      status == 'Order Shipped'
                          ? 'Restaurant location unavailable'
                          : 'Customer location unavailable',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                ],
                // Earning, Tip, and Total Earning (shown at top before customer info)
                if (_platformCommissionPercent != null) ...[
                  Builder(
                    builder: (context) {
                      final double platformCommission =
                          deliveryCharge * (_platformCommissionPercent! / 100);
                      final double earning =
                          deliveryCharge - platformCommission;
                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Earning',
                                  style: const TextStyle(fontSize: 18)),
                              Text(
                                '₱${earning.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          if (tipAmount > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Tip',
                                    style: const TextStyle(fontSize: 16)),
                                Text('₱${tipAmount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                          if (_driverPerformance != null) ...[
                            FutureBuilder<Map<String, dynamic>>(
                              future: _getDailyIncentiveTotals(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const SizedBox.shrink();
                                }
                                final dailyData = snapshot.data ??
                                    {'ordersCount': 0, 'totalIncentive': 0.0};
                                final incentivePerOrder =
                                    _getIncentivePerOrder();

                                if (incentivePerOrder <= 0) {
                                  return const SizedBox.shrink();
                                }

                                // Get actual delivered orders count and total
                                final ordersCount =
                                    dailyData['ordersCount'] as int;
                                final totalIncentive =
                                    dailyData['totalIncentive'] as double;

                                // Apply caps to get actual earned incentive
                                final cappedOrdersCount =
                                    ordersCount > 15 ? 15 : ordersCount;
                                final cappedTotal = totalIncentive > 60.0
                                    ? 60.0
                                    : totalIncentive;

                                // Check if we've hit the daily cap
                                final isCapped = cappedOrdersCount >= 15 ||
                                    cappedTotal >= 60.0;

                                // Calculate what this order's incentive would be
                                // (Calculation kept for functionality, display hidden)
                                // ignore: unused_local_variable
                                double currentOrderIncentive = 0.0;
                                if (!isCapped) {
                                  // Check if adding this order would exceed the cap
                                  final newOrdersCount = cappedOrdersCount + 1;
                                  final newTotalIncentive =
                                      cappedTotal + incentivePerOrder;

                                  if (newOrdersCount > 15 ||
                                      newTotalIncentive > 60.0) {
                                    // Calculate remaining incentive before cap
                                    final remainingOrders =
                                        15 - cappedOrdersCount;
                                    final remainingAmount = 60.0 - cappedTotal;
                                    if (remainingOrders > 0 &&
                                        remainingAmount > 0) {
                                      currentOrderIncentive =
                                          incentivePerOrder < remainingAmount
                                              ? incentivePerOrder
                                              : remainingAmount;
                                    }
                                  } else {
                                    currentOrderIncentive = incentivePerOrder;
                                  }
                                }

                                // Hide incentive display but keep functionality
                                return const SizedBox.shrink();
                              },
                            ),
                          ],
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '₱${(earning + tipAmount).toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
                // Customer info
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  isThreeLine: true,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${author['firstName'] ?? 'N/A'} ${author['lastName'] ?? ''}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      if (author['phoneNumber'] != null)
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: () =>
                                _makePhoneCall(author['phoneNumber']),
                            icon: const Icon(Icons.phone, size: 20),
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                      if (author['phoneNumber'] != null)
                        const SizedBox(width: 8),
                      StreamBuilder<int>(
                        stream: ChatReadService.getUnreadCountStream(
                          orderId: doc.id,
                          userId:
                              FirebaseAuth.instance.currentUser?.uid ?? '',
                        ),
                        builder: (context, snapshot) {
                          final unreadCount = snapshot.data ?? 0;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () =>
                                      _openChat(doc.id, author),
                                  icon: const Icon(Icons.chat, size: 20),
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      unreadCount > 99
                                          ? '99+'
                                          : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('chat_admin_driver')
                            .doc(doc.id)
                            .snapshots(),
                        builder: (context, snapshot) {
                          final raw = snapshot.data?.data()
                                  as Map<String, dynamic>? ??
                              const {};
                          final unread = raw['unreadForDriver'];
                          final unreadCount = unread is num
                              ? unread.toInt()
                              : int.tryParse(unread?.toString() ?? '') ?? 0;

                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: const BoxDecoration(
                                  color: Colors.blueGrey,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AdminDriverChatScreen(
                                          orderId: doc.id,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.support_agent,
                                    size: 20,
                                  ),
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      unreadCount > 99
                                          ? '99+'
                                          : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (author['phoneNumber'] != null) ...[
                        Text(
                          '${author['phoneNumber']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        '$fullAddress',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(),
                // Restaurant
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.store, size: 20, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Text(
                        (vendor['title'] ?? 'N/A').toString(),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Notes
                if (notes.isNotEmpty) ...[
                  Text('Notes',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color.fromARGB(255, 10, 10, 10)
                              .withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      notes,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Color.fromARGB(255, 0, 0, 0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Order items section label
                Text(
                  'Order items',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 6),
                // Ordered Items
                ...orderedItems.map((item) {
                  if (item is! Map) return const SizedBox.shrink();
                  final itemMap = item as Map<String, dynamic>;
                  final String itemName =
                      (itemMap['name'] ?? 'Item').toString();
                  final int qty = (itemMap['quantity'] ?? 0) as int;
                  final double price =
                      double.tryParse(itemMap['price']?.toString() ?? '0') ?? 0.0;
                  double effectivePrice = price - _fixCommissionPerItem;
                  if (effectivePrice < 0) effectivePrice = 0;
                  final double totalEffective = effectivePrice * qty;
                  final orderId = doc.id;
                  final canRemove = orderedItems.length > 1;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '$itemName × $qty',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '₱${totalEffective.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Actions:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: canRemove
                                  ? () => _handleRemove(context, itemMap,
                                      orderId, data, afterUpdate)
                                  : null,
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 16),
                              label: const Text('Remove'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: () => _handleReplace(context,
                                  itemMap, orderId, data, afterUpdate),
                              icon: const Icon(Icons.swap_horiz, size: 16),
                              label: const Text('Replace'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Items total',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      Text(
                        '₱${effectiveItemsTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // Customer Payment Summary (matching customer app display)
                Builder(
                  builder: (context) {
                    // Get discount breakdown
                    final discountBreakdown =
                        _getDiscountBreakdown(data, itemsTotal, deliveryCharge);
                    final List<Map<String, dynamic>> discounts =
                        discountBreakdown['discounts'] as List<Map<String, dynamic>>;
                    final double customerTotal =
                        discountBreakdown['customerTotal'] as double;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Individual Discount Lines
                        ...discounts.map((discount) {
                          final String label = discount['label'] as String;
                          final double amount = discount['amount'] as double;
                          final String type = discount['type'] as String;
                          // Use green color for promotional discounts, red for others
                          final Color discountColor = (type == 'Manual Coupon' ||
                                  type == 'Referral Wallet' ||
                                  type == 'First-Order' ||
                                  type == 'Happy Hour')
                              ? Colors.green
                              : Colors.red;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 0, vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                      color: discountColor),
                                ),
                                Text(
                                  '(-₱${amount.toStringAsFixed(0)})',
                                  style: TextStyle(
                                      fontSize: 16, color: discountColor),
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(height: 1),
                        // Final Total
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 0, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Customer Payment',
                                style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18),
                              ),
                              Text(
                                '₱${customerTotal.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                // Accept/Reject buttons for Driver Assigned or Order Accepted status
                if (status == 'Driver Assigned' ||
                    status == 'Order Accepted') ...[
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () =>
                            OrderService.acceptOrder(data, doc.id, context),
                        icon: const Icon(Icons.check),
                        label: const Text('Accept Order'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () =>
                            OrderService.rejectOrder(data, doc.id, context),
                        icon: const Icon(Icons.close),
                        label: const Text('Reject Order'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
                // Status-specific actions shown below the card content
                if (status == 'Driver Pending') ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      CircularProgressIndicator(),
                      SizedBox(width: 12),
                      Text(
                        'Restaurant Preparing...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (orderTime != null) ...[
                    Builder(
                      builder: (context) {
                        final duration =
                            currentTime.difference(orderTime!);
                        final totalMinutes = duration.inMinutes;
                        final isReady = totalMinutes >= 5;
                        if (!isReady) return const SizedBox.shrink();
                        return Center(
                          child: ElevatedButton.icon(
                            onPressed: () =>
                                _markOrderAsShipped(doc.id, author),
                            icon: const Icon(Icons.check_circle,
                                color: Colors.white, size: 16),
                            label: const Text(
                              'Order is Ready',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
                if (status == 'Order Shipped') ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.motorcycle,
                        color: Colors.orange,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Order Ready for Pickup',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Please go to the restaurant to pick up the order',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      // One-tap pickup reduces delivery time when tapped as soon as order is ready
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _pickupOrder(doc.id, author),
                            icon: const Icon(
                              Icons.motorcycle,
                              color: Colors.white,
                              size: 16,
                            ),
                            label: const Text(
                              'Pickup Orders Now',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                          if (vendorLatitude != 0.0 || vendorLongitude != 0.0) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                FireStoreUtils.redirectMap(
                                  context: context,
                                  name: vendor['title']?.toString() ?? 'Restaurant',
                                  latitude: vendorLatitude,
                                  longLatitude: vendorLongitude,
                                );
                              },
                              icon: const Icon(Icons.directions, size: 16),
                              label: const Text('Navigate'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
                if (status == 'In Transit') ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CustomerDriverLocationPage(orderId: doc.id),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.directions_bike,
                            color: Colors.white,
                            size: 20,
                          ),
                          label: const Text(
                            'On the way',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                        if (authorLatitude != 0.0 || authorLongitude != 0.0) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              final customerName =
                                  '${author['firstName'] ?? ''} '
                                  '${author['lastName'] ?? ''}'.trim();
                              FireStoreUtils.redirectMap(
                                context: context,
                                name: customerName.isEmpty
                                    ? 'Customer'
                                    : customerName,
                                latitude: authorLatitude,
                                longLatitude: authorLongitude,
                              );
                            },
                            icon: const Icon(Icons.directions, size: 20),
                            label: const Text('Navigate'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _markOrderAsShipped(String orderId, Map<String, dynamic> author) async {
    try {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .update({
        'status': 'Order Shipped',
        'shippedAt': FieldValue.serverTimestamp(),
      });

      // Send system message
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (customerId != null) {
        await OrderChatService.sendSystemMessage(
          orderId: orderId,
          status: 'Order Shipped',
          customerId: customerId.toString(),
          customerFcmToken: customerFcmToken,
          restaurantId: currentUserId,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order marked as shipped successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark order as shipped: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _pickupOrder(String orderId, Map<String, dynamic> author) async {
    try {
      // Mark order as picked up and set status to In Transit
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .update({
        'status': 'In Transit',
        'pickedUpAt': FieldValue.serverTimestamp(),
      });

      // Send system message
      final customerId = author['id'] ?? author['customerID'];
      final customerFcmToken = author['fcmToken'] as String?;
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (customerId != null) {
        await OrderChatService.sendSystemMessage(
          orderId: orderId,
          status: 'In Transit',
          customerId: customerId.toString(),
          customerFcmToken: customerFcmToken,
          restaurantId: currentUserId,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pickup confirmed! Navigate to restaurant location.'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to confirm pickup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _makePhoneCall(dynamic phoneNumber) async {
    await launchPhoneCall(context, phoneNumber);
  }

  void _openChat(
    String orderId,
    Map<String, dynamic> author,
  ) async {
    try {
      final customerId = author['id'] ?? author['customerID'];
      if (customerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer information not available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final customerName =
          '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'.trim();
      final customerProfileImage = author['profilePictureURL'] ?? '';
      final customerFcmToken = author['fcmToken'] ?? '';

      final driver = MyAppState.currentUser;
      if (driver == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver information not available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final driverName = '${driver.firstName} ${driver.lastName}'.trim();
      final driverProfileImage = driver.profilePictureURL;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreens(
            orderId: orderId,
            customerId: customerId.toString(),
            customerName: customerName.isNotEmpty ? customerName : 'Customer',
            customerProfileImage: customerProfileImage,
            restaurantId: driver.userID,
            restaurantName: driverName.isNotEmpty ? driverName : 'Driver',
            restaurantProfileImage: driverProfileImage,
            token: customerFcmToken,
            chatType: 'Driver',
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open chat: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
