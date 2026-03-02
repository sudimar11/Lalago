import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/BookTableModel.dart';
import 'package:foodie_customer/model/offer_model.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/ai_cart_service.dart';
import 'package:foodie_customer/services/ai_product_search_service.dart';
import 'package:foodie_customer/services/vector_search_service.dart';
import 'package:foodie_customer/services/coupon_service.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/services/popularity_service.dart';
import 'package:foodie_customer/services/restaurant_status_service.dart';

/// Executes AI chat tools (order status, cart, booking, etc.).
class AiChatToolHandler {
  AiChatToolHandler({
    required this.userId,
    required this.aiCartService,
    required this.cartDatabase,
    required this.context,
  });

  final String? userId;
  final AiCartService aiCartService;
  final CartDatabase cartDatabase;
  final BuildContext context;

  final FireStoreUtils _firestoreUtils = FireStoreUtils();
  final AiProductSearchService _searchService = AiProductSearchService();
  final VectorSearchService _vectorSearchService = VectorSearchService();

  static const _authError = 'Please sign in to use this feature.';

  static String _sanitizeError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('socket') ||
        s.contains('connection') ||
        s.contains('network') ||
        s.contains('failed host lookup') ||
        s.contains('no internet')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (s.contains('timeout') || s.contains('timed out')) {
      return 'Request timed out. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<Map<String, dynamic>> executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'get_order_status':
        return _getOrderStatus(args);
      case 'get_active_orders':
        return _getActiveOrders();
      case 'add_products_to_cart':
        return _addProductsToCart(args);
      case 'check_restaurant_status':
        return _checkRestaurantStatus(args);
      case 'apply_best_coupon':
        return _applyBestCoupon();
      case 'get_cart_summary':
        return _getCartSummary();
      case 'book_table':
        return _getBookTableDetails(args);
      case 'report_issue':
        return _reportIssue(args);
      case 'get_user_membership_info':
        return _getUserMembershipInfo();
      case 'search_products':
        return _searchProducts(args);
      case 'search_restaurants':
        return _searchRestaurants(args);
      case 'get_popular_items':
        return _getPopularItems();
      case 'get_popular_items_at_restaurant':
        return _getPopularItemsAtRestaurant(args);
      case 'check_delivery_deadline':
        return _checkDeliveryDeadline(args);
      default:
        return {'error': 'Unknown tool: $name'};
    }
  }

  /// Performs the actual table booking (called after user confirms).
  Future<Map<String, dynamic>> performBookTable(
    Map<String, dynamic> args,
  ) async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    final user = MyAppState.currentUser;
    if (user == null) return {'error': _authError};

    final vendorId = (args['vendorId'] ?? '').toString();
    final dateStr = (args['date'] ?? '').toString();
    final timeStr = (args['time'] ?? '').toString();
    final totalGuests = (args['totalGuests'] ?? 2) is int
        ? args['totalGuests'] as int
        : int.tryParse((args['totalGuests'] ?? '2').toString()) ?? 2;
    final occasion = (args['occasion'] ?? '').toString();

    if (vendorId.isEmpty || dateStr.isEmpty || timeStr.isEmpty) {
      return {'error': 'Missing vendorId, date, or time'};
    }

    try {
      final vendor =
          await _firestoreUtils.getVendorByVendorID(vendorId);
      if (vendor == null || vendor.id.isEmpty) {
        return {'error': 'Restaurant not found'};
      }

      final dateTime = _parseDateTime(dateStr, timeStr);
      if (dateTime == null) {
        return {'error': 'Invalid date or time format'};
      }

      final bookModel = BookTableModel(
        authorID: userId!,
        author: user,
        vendorID: vendorId,
        vendor: vendor,
        date: Timestamp.fromDate(dateTime),
        status: ORDER_STATUS_PLACED,
        totalGuest: totalGuests,
        guestFirstName: user.firstName,
        guestLastName: user.lastName,
        guestEmail: user.email,
        guestPhone: user.phoneNumber,
        occasion: occasion.isEmpty ? null : occasion,
      );

      await _firestoreUtils.bookTable(bookModel);
      return {
        'success': true,
        'message': 'Booking confirmed!',
        'booking': {
          'bookingId': bookModel.id,
          'vendor': vendor.title,
          'date': dateStr,
          'time': timeStr,
          'guests': totalGuests,
        },
      };
    } catch (e) {
      return {'error': _sanitizeError(e)};
    }
  }

  static const _orderStatusSteps = [
    'Order Placed',
    'Order Accepted',
    'Driver Assigned',
    'Driver Accepted',
    'Order Shipped',
    'In Transit',
    'Order Completed',
  ];

  int _getCurrentStepIndex(String status) {
    final s = status.toLowerCase();
    if (s.contains('completed') || s.contains('delivered')) return 6;
    if (s == 'in transit') return 5;
    if (s.contains('shipped')) return 4;
    if (s.contains('driver') && s.contains('accepted')) return 3;
    if (s.contains('driver') && s.contains('assigned')) return 2;
    if (s.contains('accepted') && !s.contains('driver')) return 1;
    if (s.contains('placed') || s.contains('order placed')) return 0;
    if (s.contains('rejected') || s.contains('cancelled')) {
      return s.contains('driver') ? 2 : 1;
    }
    return 0;
  }

  Future<Map<String, dynamic>> _getOrderStatus(Map<String, dynamic> args) async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    final orderId = (args['orderId'] ?? '').toString();
    if (orderId.isEmpty) return {'error': 'Order ID is required'};

    try {
      final order = await FireStoreUtils.getOrderByIdOnce(orderId);
      if (order == null) return {'error': 'Order not found'};

      final currentStep = _getCurrentStepIndex(order.status);
      final eta = order.estimatedTimeToPrepare ?? '';

      return {
        'message': eta.isNotEmpty
            ? 'Your order from ${order.vendor.title} is on the way. ETA: $eta'
            : 'Your order from ${order.vendor.title} is being prepared.',
        'order': {
          'orderId': order.id,
          'status': order.status,
          'estimatedTime': eta,
          'vendor': order.vendor.title,
          'steps': _orderStatusSteps,
          'currentStep': currentStep,
        },
      };
    } catch (e) {
      return {'error': _sanitizeError(e)};
    }
  }

  Future<Map<String, dynamic>> _getActiveOrders() async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    try {
      final stream = _firestoreUtils.getOrders(userId!);
      final orders = await stream.first;
      final list = orders
          .map((o) => {
                'id': o.id,
                'status': o.status,
                'vendor': o.vendor.title,
                'total': o.totalAmount,
                'estimatedTime': o.estimatedTimeToPrepare ?? '',
                'steps': _orderStatusSteps,
                'currentStep': _getCurrentStepIndex(o.status),
              })
          .toList();
      final count = list.length;
      return {
        'message': count == 0
            ? 'You have no active orders.'
            : 'You have $count active order${count == 1 ? '' : 's'}:',
        'orders': list,
      };
    } catch (e) {
      return {
        'message': 'Could not load orders.',
        'orders': [],
        'error': _sanitizeError(e),
      };
    }
  }

  Future<Map<String, dynamic>> _addProductsToCart(
    Map<String, dynamic> args,
  ) async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    final itemsRaw = args['items'];
    if (itemsRaw == null || itemsRaw is! List) {
      return {'error': 'items must be a list of {productId, quantity}'};
    }

    // Resolve productId -> vendorID for each item
    final productToVendor = <String, String>{};
    try {
      for (final item in itemsRaw) {
        if (item is! Map) continue;
        final productId =
            (item['productId'] ?? item['product_id'] ?? '').toString();
        if (productId.isEmpty) continue;
        if (productToVendor.containsKey(productId)) continue;

        final productSnap = await FirebaseFirestore.instance
            .collection(PRODUCTS)
            .where('id', isEqualTo: productId)
            .limit(1)
            .get();

        if (productSnap.docs.isNotEmpty) {
          final vendorId = (productSnap.docs.first.data()['vendorID'] ?? '')
              .toString();
          if (vendorId.isNotEmpty) {
            productToVendor[productId] = vendorId;
          }
        }
      }

      final uniqueVendorIds =
          productToVendor.values.toSet().toList();
      if (uniqueVendorIds.isEmpty && itemsRaw.isNotEmpty) {
        return {
          'error': 'status_check_failed',
          'message': 'Could not resolve vendor for products.',
        };
      }

      if (uniqueVendorIds.isNotEmpty) {
        final statusMap = await RestaurantStatusService
            .checkMultipleVendorsStatus(uniqueVendorIds);
        final closedVendorIds = uniqueVendorIds
            .where((vid) => (statusMap[vid]?['isOpen'] as bool?) != true)
            .toList();

        log('[AI_CART] Status check: vendorIds=$uniqueVendorIds, '
            'closed=$closedVendorIds');

        if (closedVendorIds.isNotEmpty) {
          final closedRestaurants = closedVendorIds.map((vid) {
            final s = statusMap[vid];
            return {
              'vendorId': vid,
              'vendorName': (s?['vendorName'] ?? 'Restaurant').toString(),
              'todayHours': (s?['todayHours'] ?? 'Closed').toString(),
            };
          }).toList();
          final affectedProductIds = productToVendor.entries
              .where((e) => closedVendorIds.contains(e.value))
              .map((e) => e.key)
              .toList();
          final names = closedRestaurants
              .map((r) => (r['vendorName'] ?? 'Restaurant').toString())
              .join(', ');

          return {
            'error': 'cannot_add_closed',
            'message':
                'The following restaurant(s) are currently closed: $names. '
                'Please try again during operating hours.',
            'closedRestaurants': closedRestaurants,
            'affectedProductIds': affectedProductIds,
            'currentTime': RestaurantStatusService.getCurrentTimeFormatted(),
          };
        }
      }
    } catch (e, st) {
      log('[AI_CART] Status check failed: $e', stackTrace: st);
      return {
        'error': 'status_check_failed',
        'message': _sanitizeError(e),
      };
    }

    final successes = <String>[];
    final failures = <String>[];

    for (final item in itemsRaw) {
      if (item is! Map) continue;
      final productId =
          (item['productId'] ?? item['product_id'] ?? '').toString();
      final qty = item['quantity'] is int
          ? item['quantity'] as int
          : int.tryParse((item['quantity'] ?? '1').toString()) ?? 1;
      if (productId.isEmpty) continue;

      final result = await aiCartService.addProductById(productId, qty);
      if (result['success'] == true) {
        successes.add('${result['product']} x$qty');
      } else {
        failures.add('${result['product'] ?? productId}: ${result['error']}');
      }
    }

    log('[AI_CART] Add result: added=${successes.length}, failed=${failures.length}');
    return {
      'success': failures.isEmpty,
      'added': successes,
      'failed': failures,
    };
  }

  Future<Map<String, dynamic>> _checkRestaurantStatus(
    Map<String, dynamic> args,
  ) async {
    final vendorId = (args['vendorId'] ?? '').toString().trim();
    if (vendorId.isEmpty) {
      return {'error': 'vendorId is required'};
    }

    try {
      final status =
          await RestaurantStatusService.checkRestaurantStatus(vendorId);

      if (status['exists'] != true) {
        return {'error': status['error'] ?? 'Restaurant not found'};
      }

      final result = Map<String, dynamic>.from(status);
      result['currentTime'] =
          RestaurantStatusService.getCurrentTimeFormatted();
      result['currentDay'] = RestaurantStatusService.getCurrentDay();
      return result;
    } catch (e) {
      return {'error': 'Failed to check restaurant status'};
    }
  }

  Future<Map<String, dynamic>> _applyBestCoupon() async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    try {
      final summary = await aiCartService.getCartSummary();
      final items = summary['items'] as List<dynamic>? ?? [];
      final subtotal = (summary['subtotal'] ?? 0.0) is double
          ? summary['subtotal'] as double
          : double.tryParse(summary['subtotal']?.toString() ?? '0') ?? 0.0;

      if (items.isEmpty || subtotal <= 0) {
        return {
          'error': 'Cart is empty',
          'bestCoupon': null,
          'discount': 0,
        };
      }

      final vendorId = (items.first as Map)['vendorID']?.toString();
      final totalItemCount =
          items.fold<int>(0, (s, i) => s + ((i as Map)['quantity'] ?? 0) as int);

      final coupons = await CouponService.getActiveCoupons(
        vendorId?.isEmpty ?? true ? null : vendorId,
        userId: userId,
      );

      OfferModel? bestCoupon;
      double bestDiscount = 0;

      for (final coupon in coupons) {
        final validation = await CouponService.validateCoupon(
          coupon.offerCode ?? '',
          subtotal,
          userId!,
          vendorId,
          totalItemCount: totalItemCount,
        );
        if (validation['valid'] != true || validation['coupon'] == null) {
          continue;
        }
        final offer = validation['coupon'] as OfferModel;
        final discount =
            CouponService.calculateDiscountAmount(offer, subtotal);
        if (discount > bestDiscount) {
          bestDiscount = discount;
          bestCoupon = offer;
        }
      }

      if (bestCoupon == null) {
        return {
          'bestCoupon': null,
          'discount': 0,
          'message': 'No applicable coupons found for your cart',
        };
      }

      return {
        'bestCoupon': bestCoupon.offerCode ?? bestCoupon.title ?? '',
        'discount': bestDiscount,
        'message':
            'Best offer: ${bestCoupon.offerCode ?? bestCoupon.title} saves '
            '${bestDiscount.toStringAsFixed(2)}. Enter this code in Cart.',
      };
    } catch (e) {
      return {'error': _sanitizeError(e), 'bestCoupon': null, 'discount': 0};
    }
  }

  Future<Map<String, dynamic>> _getCartSummary() async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }
    return aiCartService.getCartSummary();
  }

  /// Returns booking details for confirmation dialog (does not book).
  Future<Map<String, dynamic>> _getBookTableDetails(
    Map<String, dynamic> args,
  ) async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    final vendorId = (args['vendorId'] ?? '').toString();
    if (vendorId.isEmpty) return {'error': 'vendorId is required'};

    try {
      final vendor =
          await _firestoreUtils.getVendorByVendorID(vendorId);
      if (vendor == null || vendor.id.isEmpty) {
        return {'error': 'Restaurant not found'};
      }

      return {
        'pendingConfirmation': true,
        'vendorId': vendorId,
        'vendorName': vendor.title,
        'date': args['date'] ?? '',
        'time': args['time'] ?? '',
        'totalGuests': args['totalGuests'] ?? 2,
        'occasion': args['occasion'] ?? '',
      };
    } catch (e) {
      return {'error': _sanitizeError(e)};
    }
  }

  Future<Map<String, dynamic>> _reportIssue(Map<String, dynamic> args) async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    final orderId = (args['orderId'] ?? '').toString();
    final issueTypesRaw = args['issueTypes'];
    final description = (args['description'] ?? '').toString();

    if (orderId.isEmpty) return {'error': 'orderId is required'};
    final issueTypes = issueTypesRaw is List
        ? issueTypesRaw
            .map((e) => e?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    if (issueTypes.isEmpty) {
      return {'error': 'At least one issue type is required'};
    }

    try {
      final order = await FireStoreUtils.getOrderByIdOnce(orderId);
      if (order == null) return {'error': 'Order not found'};

      final user = await FireStoreUtils.getCurrentUser(userId!);
      if (user == null) return {'error': 'User not found'};

      await FirebaseFirestore.instance.collection('support_tickets').add({
        'order_id': order.id,
        'order_total': order.totalAmount,
        'restaurant_name': order.vendor.title,
        'restaurant_id': order.vendorID,
        'order_date': order.createdAt,
        'customer_id': user.userID,
        'customer_name': user.fullName(),
        'customer_email': user.email,
        'customer_phone': user.phoneNumber,
        'issue_types': issueTypes,
        'description': description,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      return {'success': true, 'message': 'Report submitted successfully'};
    } catch (e) {
      return {'error': _sanitizeError(e)};
    }
  }

  Future<Map<String, dynamic>> _getUserMembershipInfo() async {
    if (userId == null || userId!.isEmpty) {
      return {'error': _authError};
    }

    try {
      final user = await FireStoreUtils.getCurrentUser(userId!);
      if (user == null) return {'error': 'User not found'};

      return {
        'referralCode': user.referralCode ?? '',
        'referredBy': user.referredBy ?? '',
        'referralWalletAmount': user.referralWalletAmount ?? 0,
        'walletAmount': user.walletAmount ?? 0,
        'hasCompletedFirstOrder': user.hasCompletedFirstOrder,
        'isReferralPath': user.isReferralPath,
      };
    } catch (e) {
      return {'error': _sanitizeError(e)};
    }
  }

  Future<Map<String, dynamic>> _searchProducts(Map<String, dynamic> args) async {
    final query = (args['query'] ?? '').toString();
    if (query.isEmpty) {
      return {'message': 'No search query.', 'products': []};
    }
    try {
      var products = await _vectorSearchService.searchProducts(query);
      if (products.isEmpty) {
        products = await _searchService.searchProducts(query);
      }
      return {
        'message': products.isEmpty
            ? 'No products found for "$query".'
            : 'Here are some products that match:',
        'products': products,
      };
    } catch (e) {
      return {
        'message': 'Could not search products.',
        'products': [],
        'error': _sanitizeError(e),
      };
    }
  }

  Future<Map<String, dynamic>> _searchRestaurants(
    Map<String, dynamic> args,
  ) async {
    final query = (args['query'] ?? '').toString().toLowerCase();
    if (query.isEmpty) return {'message': 'No search query.', 'restaurants': []};

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(VENDORS)
          .where('reststatus', isEqualTo: true)
          .limit(50)
          .get();

      double? userLat;
      double? userLng;
      try {
        final loc = MyAppState.selectedPosition.location;
        if (loc != null && (loc.latitude != 0 || loc.longitude != 0)) {
          userLat = loc.latitude;
          userLng = loc.longitude;
        }
      } catch (_) {}

      final restaurants = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final title = (d['title'] ?? '').toString().toLowerCase();
        final category = (d['categoryTitle'] ?? '').toString().toLowerCase();
        if (query.isNotEmpty &&
            !title.contains(query) &&
            !category.contains(query)) {
          continue;
        }
        if (restaurants.length >= 15) break;

        final photo = (d['photo'] ?? '').toString();
        final reviewsSum = (d['reviewsSum'] ?? 0) is num
            ? (d['reviewsSum'] as num).toDouble()
            : 0.0;
        final reviewsCount = (d['reviewsCount'] ?? 0) is num
            ? (d['reviewsCount'] as num).toDouble()
            : 0.0;
        final rating = reviewsCount > 0 ? reviewsSum / reviewsCount : 0.0;

        double? distance;
        if (userLat != null && userLng != null) {
          final vLat = (d['latitude'] ?? 0) is num
              ? (d['latitude'] as num).toDouble()
              : 0.0;
          final vLng = (d['longitude'] ?? 0) is num
              ? (d['longitude'] as num).toDouble()
              : 0.0;
          if (vLat != 0 || vLng != 0) {
            final meters = Geolocator.distanceBetween(
              userLat,
              userLng,
              vLat,
              vLng,
            );
            distance = meters / 1000;
          }
        }

        restaurants.add({
          'id': doc.id,
          'name': (d['title'] ?? '').toString(),
          'title': (d['title'] ?? '').toString(),
          'categoryTitle': (d['categoryTitle'] ?? '').toString(),
          'cuisine': (d['categoryTitle'] ?? '').toString(),
          'location': (d['location'] ?? '').toString(),
          'imageUrl': getImageVAlidUrl(photo),
          'rating': rating,
          if (distance != null) 'distance': (distance * 10).round() / 10,
        });
      }

      return {
        'message': restaurants.isEmpty
            ? 'No restaurants found for "$query".'
            : 'I found these restaurants near you:',
        'restaurants': restaurants,
      };
    } catch (e) {
      return {
        'message': 'Could not search restaurants.',
        'restaurants': [],
        'error': _sanitizeError(e),
      };
    }
  }

  Future<Map<String, dynamic>> _getPopularItems() async {
    try {
      final popular = await _firestoreUtils
          .getPopularProductsWithCountsForToday(limit: 15);
      return {
        'message': popular.isEmpty
            ? 'No popular items today.'
            : 'Popular today:',
        'popular': popular,
      };
    } catch (e) {
      return {
        'message': 'Could not load popular items.',
        'popular': [],
        'error': _sanitizeError(e),
      };
    }
  }

  Future<Map<String, dynamic>> _getPopularItemsAtRestaurant(
    Map<String, dynamic> args,
  ) async {
    final vendorId = (args['vendorId'] ?? '').toString().trim();
    final restaurantName = (args['restaurantName'] ?? '').toString().trim();
    final timeRange = (args['timeRange'] ?? 'week').toString();
    final limitRaw = args['limit'];
    final limit = limitRaw is int
        ? limitRaw
        : (int.tryParse(limitRaw?.toString() ?? '10') ?? 10);

    String? resolvedVendorId = vendorId.isNotEmpty ? vendorId : null;
    if (resolvedVendorId == null && restaurantName.isNotEmpty) {
      resolvedVendorId =
          await PopularityService.findVendorIdByName(restaurantName);
    }

    if (resolvedVendorId == null || resolvedVendorId.isEmpty) {
      return {
        'message': vendorId.isEmpty && restaurantName.isEmpty
            ? 'Please provide vendorId or restaurantName.'
            : 'Restaurant not found.',
        'popular': [],
      };
    }

    try {
      final popular = await PopularityService.getPopularItemsAtRestaurant(
        vendorId: resolvedVendorId,
        timeRange: timeRange,
        limit: limit,
      );
      return {
        'message': popular.isEmpty
            ? 'No popular items found for this restaurant.'
            : 'Popular at this restaurant:',
        'popular': popular,
      };
    } catch (e) {
      return {
        'message': 'Could not load popular items.',
        'popular': [],
        'error': _sanitizeError(e),
      };
    }
  }

  Future<Map<String, dynamic>> _checkDeliveryDeadline(
    Map<String, dynamic> args,
  ) async {
    final orderId = (args['orderId'] ?? '').toString();
    final deadlineStr = (args['deadlineTime'] ?? '').toString();
    if (orderId.isEmpty || deadlineStr.isEmpty) {
      return {'error': 'orderId and deadlineTime are required'};
    }

    try {
      final order = await FireStoreUtils.getOrderByIdOnce(orderId);
      if (order == null) return {'error': 'Order not found'};

      final etaStr = order.estimatedTimeToPrepare ?? '';
      final etaMinutes = int.tryParse(etaStr) ?? 0;
      final createdAt = order.createdAt.toDate();
      final estimatedArrival = createdAt.add(Duration(minutes: etaMinutes));

      final deadline = _parseTime(deadlineStr);
      if (deadline == null) {
        return {'error': 'Invalid deadline format (use e.g. 18:00)'};
      }

      final deadlineDate = DateTime(
        createdAt.year,
        createdAt.month,
        createdAt.day,
        deadline.hour,
        deadline.minute,
      );
      final canMeet = estimatedArrival.isBefore(deadlineDate) ||
          estimatedArrival.isAtSameMomentAs(deadlineDate);

      return {
        'canMeetDeadline': canMeet,
        'estimatedArrival': estimatedArrival.toIso8601String(),
        'deadline': deadlineStr,
        'status': order.status,
      };
    } catch (e) {
      return {'error': _sanitizeError(e)};
    }
  }

  DateTime? _parseDateTime(String dateStr, String timeStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return null;
    final time = _parseTime(timeStr);
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime? _parseTime(String s) {
    final trimmed = s.trim();
    final parts = trimmed.split(RegExp(r'[:\s]'));
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return DateTime(2000, 1, 1, h, m);
      }
    }
    return null;
  }
}
