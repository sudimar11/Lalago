import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:intl/intl.dart';

/// Client-side analytics calculations for Insights dashboard.
class AnalyticsHelper {
  /// Replicates commission logic from OrdersScreen.calculateTotalAndDeductCommission.
  static Future<double> calculateOrderNetTotal(OrderModel order) async {
    double total = 0.0;

    try {
      for (final element in order.products) {
        if (element.extrasPrice != null &&
            element.extrasPrice!.isNotEmpty &&
            double.tryParse(element.extrasPrice!) != null) {
          total += element.quantity * double.parse(element.extrasPrice!);
        }
        total += element.quantity * double.parse(element.price);
      }
    } catch (e) {
      return 0.0;
    }

    final discount =
        double.tryParse(order.discount?.toString() ?? '0.0') ?? 0.0;
    final specialDiscount = double.tryParse(
            order.specialDiscount?['special_discount']?.toString() ?? '0.0') ??
        0.0;
    final totalAfterDiscount = total - discount - specialDiscount;

    final totalQty = order.products.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    double adminComm = 0.0;
    try {
      final commissionType = order.adminCommissionType;
      final commissionValue = order.adminCommission;

      if (commissionType != null && commissionValue != null) {
        if (commissionType == 'Percent') {
          adminComm =
              (totalAfterDiscount * double.parse(commissionValue)) / 100;
        } else if (commissionType == 'Fixed') {
          adminComm = double.parse(commissionValue) * totalQty;
        }
      }
    } catch (_) {}

    return totalAfterDiscount - adminComm;
  }

  static Future<double> calculateTotalRevenue(List<OrderModel> orders) async {
    double sum = 0.0;
    for (final order in orders) {
      sum += await calculateOrderNetTotal(order);
    }
    return sum;
  }

  static Future<List<Map<String, dynamic>>> getPopularItems(
    List<OrderModel> orders, {
    int limit = 5,
  }) async {
    final Map<String, Map<String, dynamic>> byId = {};

    for (final order in orders) {
      for (final product in order.products) {
        final id = product.id;
        final price = double.tryParse(product.price) ?? 0.0;
        final extras =
            double.tryParse(product.extrasPrice ?? '0') ?? 0.0;
        final lineTotal =
            product.quantity * (price + extras);

        if (byId.containsKey(id)) {
          byId[id]!['quantity'] =
              (byId[id]!['quantity'] as int) + product.quantity;
          byId[id]!['revenue'] =
              (byId[id]!['revenue'] as double) + lineTotal;
        } else {
          byId[id] = {
            'id': id,
            'name': product.name,
            'quantity': product.quantity,
            'revenue': lineTotal,
          };
        }
      }
    }

    final list = byId.values.toList();
    list.sort((a, b) => (b['quantity'] as int).compareTo(a['quantity'] as int));
    return list.take(limit).toList();
  }

  static Map<int, int> getOrdersByHour(List<OrderModel> orders) {
    final Map<int, int> byHour = {};
    for (var h = 0; h < 24; h++) {
      byHour[h] = 0;
    }
    for (final order in orders) {
      final hour = order.createdAt.toDate().hour;
      byHour[hour] = (byHour[hour] ?? 0) + 1;
    }
    return byHour;
  }

  static Map<String, int> getStatusBreakdown(List<OrderModel> orders) {
    final Map<String, int> byStatus = {};
    for (final order in orders) {
      final s = order.status;
      byStatus[s] = (byStatus[s] ?? 0) + 1;
    }
    return byStatus;
  }

  static Future<double?> calculateAveragePrepTime(
    List<OrderModel> orders,
  ) async {
    double totalMinutes = 0.0;
    int validCount = 0;

    for (final order in orders) {
      final acceptedAt = order.acceptedAt;
      final endAt = order.shippedAt ?? order.readyAt;
      if (acceptedAt == null || endAt == null) continue;

      final start = acceptedAt.toDate();
      final end = endAt.toDate();
      final minutes = end.difference(start).inMinutes;

      if (minutes >= 1 && minutes <= 120) {
        totalMinutes += minutes;
        validCount++;
      }
    }

    if (validCount == 0) return null;
    return totalMinutes / validCount;
  }

  static Map<String, int> getOrderTypeBreakdown(List<OrderModel> orders) {
    int takeaway = 0;
    int delivery = 0;
    for (final order in orders) {
      if (order.takeAway == true) {
        takeaway++;
      } else {
        delivery++;
      }
    }
    return {'Takeaway': takeaway, 'Delivery': delivery};
  }

  static Future<Map<String, double>> getRevenueByDate(
    List<OrderModel> orders,
  ) async {
    final Map<String, double> byDate = {};
    final fmt = DateFormat('yyyy-MM-dd');

    for (final order in orders) {
      final key = fmt.format(order.createdAt.toDate());
      final net = await calculateOrderNetTotal(order);
      byDate[key] = (byDate[key] ?? 0.0) + net;
    }

    return byDate;
  }
}
