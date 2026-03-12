import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/forecast_service.dart';
import 'package:foodie_restaurant/utils/analytics_helper.dart';

/// Executes Restaurant Ash tools.
class AiChatToolHandler {
  AiChatToolHandler({required this.vendorId});

  final String vendorId;
  final _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'get_demand_forecast':
        return _getDemandForecast(args);
      case 'check_inventory':
        return _checkInventory();
      case 'view_driver_performance':
        return _viewDriverPerformance();
      case 'reorder_suggestions':
        return _reorderSuggestions(args);
      case 'get_sales_insights':
        return _getSalesInsights(args);
      case 'check_restaurant_status':
        return _checkRestaurantStatus();
      default:
        return {'error': 'Unknown tool: $name'};
    }
  }

  Future<Map<String, dynamic>> _getDemandForecast(
    Map<String, dynamic> args,
  ) async {
    try {
      final dateStr = (args['date'] ?? '').toString();
      DateTime date = DateTime.now();
      if (dateStr.isNotEmpty) {
        date = DateTime.tryParse(dateStr) ?? DateTime.now();
      }
      final forecast =
          await ForecastService.getDemandForecast(vendorId, date);
      if (forecast == null) {
        return {
          'message': 'No forecast available for ${date.toString().substring(0, 10)}. '
              'Forecasts are generated daily.',
        };
      }
      final hourly = forecast['hourlyPredictions'] as Map<String, dynamic>? ?? {};
      final products = forecast['productPredictions'] as Map<String, dynamic>? ?? {};
      final total = hourly.values.fold<int>(
        0,
        (s, v) => s + ((v as num?)?.toInt() ?? 0),
      );
      final topProducts = products.entries.take(5).map((e) {
        final v = e.value as Map?;
        return {
          'name': v?['productName'] ?? e.key,
          'predictedQty': v?['predictedQty'] ?? 0,
        };
      }).toList();
      return {
        'message': 'Forecast for ${date.toString().substring(0, 10)}: '
            '$total orders predicted. Peak hours: 6-8 PM.',
        'totalOrders': total,
        'hourlyPredictions': hourly,
        'topProducts': topProducts,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkInventory() async {
    try {
      final snap = await _firestore
          .collection(PRODUCTS)
          .where('vendorID', isEqualTo: vendorId)
          .where('publish', isEqualTo: true)
          .limit(50)
          .get();

      final items = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final stock = d['stockQuantity'] ?? d['stock'];
        if (stock != null) {
          items.add({
            'id': doc.id,
            'name': (d['name'] ?? '').toString(),
            'stock': stock is num ? stock.toInt() : int.tryParse(stock.toString()) ?? 0,
          });
        }
      }
      if (items.isEmpty) {
        return {
          'message': 'Inventory tracking is not configured. Add stockQuantity '
              'to products to enable inventory checks.',
        };
      }
      return {
        'message': 'Found ${items.length} products with stock data.',
        'items': items,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _viewDriverPerformance() async {
    try {
      final snap = await _firestore
          .collection('driver_performance_history')
          .where('vendorId', isEqualTo: vendorId)
          .orderBy('date', descending: true)
          .limit(14)
          .get();

      if (snap.docs.isEmpty) {
        return {
          'message': 'No driver performance data yet. Data is updated hourly.',
        };
      }
      final drivers = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        final driverId = (d['driverId'] ?? '').toString();
        if (driverId.isEmpty) continue;
        if (!drivers.containsKey(driverId)) {
          drivers[driverId] = {
            'driverId': driverId,
            'acceptanceRate': d['acceptanceRate'] ?? 0,
            'onTimePercentage': d['onTimePercentage'] ?? 0,
            'customerRating': d['customerRating'] ?? 0,
            'efficiencyScore': d['efficiencyScore'] ?? 0,
          };
        }
      }
      final list = drivers.values.toList();
      list.sort(
        (a, b) =>
            ((b['efficiencyScore'] as num?) ?? 0)
                .compareTo((a['efficiencyScore'] as num?) ?? 0),
      );
      return {
        'message': 'Found ${list.length} drivers with performance data.',
        'drivers': list.take(5).toList(),
      };
    } catch (e) {
      return {
        'message': 'Driver performance data is being collected. Check back later.',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _reorderSuggestions(
    Map<String, dynamic> args,
  ) async {
    try {
      final productId = (args['productId'] ?? '').toString();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final forecast =
          await ForecastService.getDemandForecast(vendorId, tomorrow);
      if (forecast == null) {
        return {
          'message': 'No forecast available. Reorder suggestions are based on '
              'demand forecasts generated daily.',
        };
      }
      final products =
          forecast['productPredictions'] as Map<String, dynamic>? ?? {};
      if (productId.isNotEmpty) {
        final p = products[productId] as Map?;
        if (p == null) {
          return {'message': 'Product $productId not in top forecasted items.'};
        }
        final qty = (p['predictedQty'] as num?)?.toInt() ?? 0;
        final suggestion = (qty * 1.2).ceil();
        return {
          'message': 'Suggested order quantity: $suggestion units '
              '(based on predicted demand of $qty, +20% safety stock).',
          'productId': productId,
          'predictedQty': qty,
          'suggestedOrder': suggestion,
        };
      }
      final suggestions = products.entries.take(10).map((e) {
        final v = e.value as Map?;
        final qty = (v?['predictedQty'] as num?)?.toInt() ?? 0;
        return {
          'productId': e.key,
          'productName': v?['productName'] ?? e.key,
          'predictedQty': qty,
          'suggestedOrder': (qty * 1.2).ceil(),
        };
      }).toList();
      return {
        'message': 'Top 10 reorder suggestions based on tomorrow\'s forecast.',
        'suggestions': suggestions,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _getSalesInsights(
    Map<String, dynamic> args,
  ) async {
    try {
      final period = (args['period'] ?? 'week').toString();
      final now = DateTime.now();
      DateTime start;
      switch (period.toLowerCase()) {
        case 'today':
          start = DateTime(now.year, now.month, now.day);
          break;
        case 'month':
          start = DateTime(now.year, now.month - 1, now.day);
          break;
        default:
          start = now.subtract(const Duration(days: 7));
      }
      final end = now.add(const Duration(days: 1));
      final orders = await FireStoreUtils.getOrdersInDateRange(
        vendorId,
        start,
        end,
      );
      if (orders.isEmpty) {
        return {
          'message': 'No orders in this period.',
        };
      }
      final revenue = await AnalyticsHelper.calculateTotalRevenue(orders);
      final popular =
          await AnalyticsHelper.getPopularItems(orders, limit: 5);
      final byHour = AnalyticsHelper.getOrdersByHour(orders);
      int peakHour = 0;
      int peakCount = 0;
      for (final e in byHour.entries) {
        if (e.value > peakCount) {
          peakCount = e.value;
          peakHour = e.key;
        }
      }
      return {
        'message': 'Sales insights for $period: ${orders.length} orders, '
            'revenue based on net totals. Peak hour: ${peakHour}:00.',
        'orderCount': orders.length,
        'revenue': revenue,
        'popularItems': popular,
        'peakHour': peakHour,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _checkRestaurantStatus() async {
    try {
      final doc =
          await _firestore.collection(VENDORS).doc(vendorId).get();
      if (!doc.exists || doc.data() == null) {
        return {'error': 'Restaurant not found'};
      }
      final d = doc.data()!;
      final isOpen = d['reststatus'] == true;
      final workingHours = d['workingHours'] as List? ?? [];
      return {
        'message': isOpen
            ? 'Restaurant is open and accepting orders.'
            : 'Restaurant is currently closed.',
        'isOpen': isOpen,
        'workingHours': workingHours,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
