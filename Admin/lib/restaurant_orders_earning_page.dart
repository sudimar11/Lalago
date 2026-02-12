import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RestaurantOrdersEarningPage extends StatefulWidget {
  const RestaurantOrdersEarningPage({super.key});

  @override
  State<RestaurantOrdersEarningPage> createState() =>
      _RestaurantOrdersEarningPageState();
}

class _RestaurantOrdersEarningPageState
    extends State<RestaurantOrdersEarningPage> {
  Map<String, Map<String, dynamic>>? _restaurantStats;

  Future<void> _onRefresh() async {
    setState(() {
      _restaurantStats = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  // Process all orders for today and group by restaurant (similar to top_restaurants_orders_today_page)
  Future<Map<String, Map<String, dynamic>>> _processOrdersForToday() async {
    debugPrint('[RestaurantOrders] Processing all orders for today...');

    try {
      // Get current date (start and end of day) in UTC - same as reference
      final String todayDate = DateTime.now().toIso8601String().split('T')[0];
      final DateTime startOfDay =
          DateTime.parse('$todayDate 00:00:00Z').toUtc();
      final DateTime endOfDay = DateTime.parse('$todayDate 23:59:59Z').toUtc();

      debugPrint(
        '[RestaurantOrders] TODAY\'S DATE: $todayDate - Fetching all orders for today',
      );

      // Query all orders for today - same pattern as reference
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .get()
          .timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Query timeout');
        },
      );

      debugPrint(
        '[RestaurantOrders] Found ${ordersSnapshot.docs.length} total orders for today',
      );

      // Group orders by restaurant/vendor and count items
      final Map<String, int> restaurantOrderCounts = {};
      final Map<String, int> restaurantItemCounts = {};
      final Map<String, double> restaurantCommissions = {};
      final Map<String, double> restaurantDiscounts = {};
      final Map<String, Map<String, dynamic>> restaurantInfo = {};
      final Map<String, List<Map<String, dynamic>>> restaurantOrders = {};

      for (final orderDoc in ordersSnapshot.docs) {
        try {
          final data = orderDoc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          // Filter out rejected/cancelled orders
          final status = data['status'] as String? ?? '';
          if (status == 'Order Rejected' ||
              status == 'order rejected' ||
              status == 'Driver Rejected' ||
              status == 'driver rejected') {
            debugPrint(
                '[RestaurantOrders] Skipping $status order: ${orderDoc.id}');
            continue;
          }

          final vendor = data['vendor'];
          if (vendor == null || vendor is! Map<String, dynamic>) continue;

          // Try multiple vendor ID fields to match restaurants - same as reference
          final vendorId =
              vendor['id'] as String? ?? vendor['vendorId'] as String? ?? '';
          final vendorTitle = vendor['title'] as String? ??
              vendor['authorName'] as String? ??
              '';

          String? restaurantKey;
          String restaurantName = vendorTitle;

          // Use vendor ID as primary key if available - same as reference
          if (vendorId.isNotEmpty) {
            restaurantKey = vendorId;
          } else if (vendorTitle.isNotEmpty) {
            restaurantKey = vendorTitle;
          }

          if (restaurantKey != null && restaurantKey.isNotEmpty) {
            // Count orders
            restaurantOrderCounts[restaurantKey] =
                (restaurantOrderCounts[restaurantKey] ?? 0) + 1;

            // Count items from products array
            // Based on database format: products is an array, each product has quantity (number)
            int orderItemCount = 0;
            final products = data['products'] as List<dynamic>? ?? [];
            for (final product in products) {
              if (product is! Map<String, dynamic>) continue;

              // quantity is a number in the database format
              final quantity = product['quantity'];
              int qty = 1; // default to 1 if missing

              if (quantity != null) {
                if (quantity is num) {
                  qty = quantity.toInt();
                } else if (quantity is String) {
                  qty = int.tryParse(quantity) ?? 1;
                }
              }

              orderItemCount += qty;
            }

            restaurantItemCounts[restaurantKey] =
                (restaurantItemCounts[restaurantKey] ?? 0) + orderItemCount;

            // Read commission from order data
            final adminCommission = data['adminCommission'];
            final adminCommissionType =
                data['adminCommissionType'] as String? ?? 'Fixed';

            // Parse commission value
            double commissionValue = 0.0;
            if (adminCommission != null) {
              if (adminCommission is num) {
                commissionValue = adminCommission.toDouble();
              } else if (adminCommission is String) {
                commissionValue = double.tryParse(adminCommission) ?? 0.0;
              }
            }

            // Calculate commission for this order
            double orderCommission = 0.0;
            if (commissionValue > 0) {
              if (adminCommissionType == 'Fixed') {
                // Fixed commission per item
                orderCommission = orderItemCount * commissionValue;
              } else if (adminCommissionType == 'Percent') {
                // For percentage, would need order total price
                // For now, treating as fixed per item
                orderCommission = orderItemCount * commissionValue;
              }
            }

            debugPrint(
              '[RestaurantOrders] Order ${orderDoc.id}: Commission = $commissionValue ($adminCommissionType), '
              'Items: $orderItemCount, Total: ₱${orderCommission.toStringAsFixed(2)}',
            );

            // Accumulate total commission per restaurant
            restaurantCommissions[restaurantKey] =
                (restaurantCommissions[restaurantKey] ?? 0.0) + orderCommission;

            // Extract discount/promo information
            double couponDiscount = 0.0;
            double promoDiscount = 0.0;
            String? appliedCouponId;
            String? appliedPromoId;

            final couponDiscountRaw = data['couponDiscountAmount'];
            if (couponDiscountRaw != null) {
              if (couponDiscountRaw is num) {
                couponDiscount = couponDiscountRaw.toDouble();
              } else if (couponDiscountRaw is String) {
                couponDiscount = double.tryParse(couponDiscountRaw) ?? 0.0;
              }
              appliedCouponId = data['appliedCouponId'] as String?;
            }

            final promoDiscountRaw = data['promoDiscountAmount'];
            if (promoDiscountRaw != null) {
              if (promoDiscountRaw is num) {
                promoDiscount = promoDiscountRaw.toDouble();
              } else if (promoDiscountRaw is String) {
                promoDiscount = double.tryParse(promoDiscountRaw) ?? 0.0;
              }
              appliedPromoId = data['appliedPromoId'] as String?;
            }

            final totalOrderDiscount = couponDiscount + promoDiscount;

            // Accumulate total discount per restaurant
            restaurantDiscounts[restaurantKey] =
                (restaurantDiscounts[restaurantKey] ?? 0.0) +
                    totalOrderDiscount;

            // Store individual order details
            final createdAt = data['createdAt'] as Timestamp?;

            // Extract driver ID
            final driverID =
                data['driverID'] as String? ?? 'No driver assigned';

            restaurantOrders.putIfAbsent(restaurantKey, () => []);
            restaurantOrders[restaurantKey]!.add({
              'orderId': orderDoc.id,
              'itemCount': orderItemCount,
              'timestamp': createdAt?.toDate(),
              'commission': orderCommission,
              'driverID': driverID,
              'couponDiscount': couponDiscount,
              'promoDiscount': promoDiscount,
              'totalDiscount': totalOrderDiscount,
              'appliedCouponId': appliedCouponId,
              'appliedPromoId': appliedPromoId,
            });

            debugPrint(
              '[RestaurantOrders] Order ${orderDoc.id}: $orderItemCount items '
              '(${products.length} products)',
            );

            if (!restaurantInfo.containsKey(restaurantKey)) {
              restaurantInfo[restaurantKey] = {
                'name': restaurantName,
                'vendorId': vendorId,
                'vendorTitle': vendorTitle,
              };
            }
          }
        } catch (e) {
          debugPrint(
            '[RestaurantOrders] Error processing order ${orderDoc.id}: $e',
          );
          continue;
        }
      }

      debugPrint(
        '[RestaurantOrders] Grouped into ${restaurantOrderCounts.length} restaurants',
      );

      // Convert to the format expected by the UI
      final Map<String, Map<String, dynamic>> result = {};
      for (final entry in restaurantOrderCounts.entries) {
        final info = restaurantInfo[entry.key] ?? {};
        final itemCount = restaurantItemCounts[entry.key] ?? 0;
        final orders = restaurantOrders[entry.key] ?? [];
        final totalCommission = restaurantCommissions[entry.key] ?? 0.0;
        final totalDiscount = restaurantDiscounts[entry.key] ?? 0.0;
        result[entry.key] = {
          'name': info['name'] ?? entry.key,
          'orderCount': entry.value,
          'itemCount': itemCount,
          'orders': orders,
          'totalCommission': totalCommission,
          'totalDiscount': totalDiscount,
        };

        debugPrint(
          '[RestaurantOrders] ${info['name'] ?? entry.key}: '
          '${entry.value} orders, $itemCount items, '
          'Commission: ₱${totalCommission.toStringAsFixed(2)}, '
          'Discounts: ₱${totalDiscount.toStringAsFixed(2)}',
        );
      }

      return result;
    } catch (e, stackTrace) {
      debugPrint('[RestaurantOrders] ERROR processing orders: $e');
      debugPrint('[RestaurantOrders] Stack trace: $stackTrace');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Orders Today'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _restaurantStats == null
              ? _processOrdersForToday()
              : Future.value(_restaurantStats!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Failed to load orders'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _restaurantStats = null;
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            // Use cached stats if available, otherwise use snapshot data
            final stats = _restaurantStats ?? snapshot.data ?? {};

            // Update state with results from snapshot
            if (_restaurantStats == null &&
                snapshot.hasData &&
                snapshot.data!.isNotEmpty) {
              Future.microtask(() {
                if (mounted) {
                  setState(() {
                    _restaurantStats = snapshot.data;
                  });
                }
              });
            }

            if (stats.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.restaurant, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'No orders today',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            debugPrint(
              '[RestaurantOrders] Building table with ${stats.length} restaurants',
            );

            // Convert to list and sort by order count (descending)
            final statsList = stats.entries.toList()
              ..sort((a, b) => (b.value['orderCount'] as int)
                  .compareTo(a.value['orderCount'] as int));

            debugPrint(
              '[RestaurantOrders] After sorting: ${statsList.length} entries',
            );

            // Remove duplicates (same restaurant with different keys)
            final uniqueStats = <String, Map<String, dynamic>>{};
            for (final entry in statsList) {
              final name = entry.value['name'] as String;
              if (!uniqueStats.containsKey(name)) {
                uniqueStats[name] = entry.value;
              }
            }

            debugPrint(
              '[RestaurantOrders] After removing duplicates: ${uniqueStats.length} unique restaurants',
            );

            final finalStatsList = uniqueStats.entries.toList()
              ..sort((a, b) => (b.value['orderCount'] as int)
                  .compareTo(a.value['orderCount'] as int));

            debugPrint(
              '[RestaurantOrders] Final table will show ${finalStatsList.length} rows',
            );

            // Calculate overall total commission and discounts
            double overallTotalCommission = 0.0;
            double overallTotalDiscount = 0.0;
            int totalOrders = 0;
            int totalItems = 0;
            for (final entry in finalStatsList) {
              overallTotalCommission +=
                  entry.value['totalCommission'] as double? ?? 0.0;
              overallTotalDiscount +=
                  entry.value['totalDiscount'] as double? ?? 0.0;
              totalOrders += entry.value['orderCount'] as int? ?? 0;
              totalItems += entry.value['itemCount'] as int? ?? 0;
            }

            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: finalStatsList.length + 1,
              itemBuilder: (context, index) {
                // Show summary card at index 0
                if (index == 0) {
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    color: Colors.green[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Today\'s Earnings Summary',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Column(
                                children: [
                                  const Text(
                                    'Commission',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '₱${overallTotalCommission.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              if (overallTotalDiscount > 0) ...[
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: Colors.grey[300],
                                ),
                                Column(
                                  children: [
                                    const Text(
                                      'Discounts Given',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '₱${overallTotalDiscount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '$totalOrders orders | $totalItems items',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Show restaurant items for index > 0
                final restaurantIndex = index - 1;
                final entry = finalStatsList[restaurantIndex];
                final stats = entry.value;
                final name = stats['name'] as String;
                final orderCount = stats['orderCount'] as int? ?? 0;
                final itemCount = stats['itemCount'] as int? ?? 0;
                final totalCommission =
                    stats['totalCommission'] as double? ?? 0.0;
                final totalDiscount = stats['totalDiscount'] as double? ?? 0.0;
                final orders =
                    stats['orders'] as List<Map<String, dynamic>>? ?? [];

                debugPrint(
                  '[RestaurantOrders] List item: $name - Orders: $orderCount, '
                  'Items: $itemCount, Commission: ₱${totalCommission.toStringAsFixed(2)}',
                );

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ExpansionTile(
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Orders: $orderCount | Items: $itemCount',
                            style: const TextStyle(fontSize: 13),
                          ),
                          if (totalDiscount > 0)
                            Text(
                              'Commission: ₱${totalCommission.toStringAsFixed(0)} | Discounts: ₱${totalDiscount.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13),
                            )
                          else
                            Text(
                              'Commission: ₱${totalCommission.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                        ],
                      ),
                    ),
                    children: orders.map((order) {
                      final orderId = order['orderId'] as String? ?? 'N/A';
                      final orderItemCount = order['itemCount'] as int? ?? 0;
                      final timestamp = order['timestamp'] as DateTime?;
                      final orderCommission =
                          order['commission'] as double? ?? 0.0;
                      final driverID =
                          order['driverID'] as String? ?? 'No driver';
                      final couponDiscount =
                          order['couponDiscount'] as double? ?? 0.0;
                      final promoDiscount =
                          order['promoDiscount'] as double? ?? 0.0;
                      final totalOrderDiscount =
                          order['totalDiscount'] as double? ?? 0.0;
                      final appliedCouponId =
                          order['appliedCouponId'] as String?;
                      final appliedPromoId = order['appliedPromoId'] as String?;

                      String formattedTime = 'N/A';
                      if (timestamp != null) {
                        final hour = timestamp.hour.toString().padLeft(2, '0');
                        final minute =
                            timestamp.minute.toString().padLeft(2, '0');
                        formattedTime = '$hour:$minute';
                      }

                      return ListTile(
                        dense: true,
                        title: Text(
                          orderId,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$orderItemCount items • Commission: ₱${orderCommission.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (totalOrderDiscount > 0) ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.discount,
                                    size: 12,
                                    color: Colors.orange[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Discount: ₱${totalOrderDiscount.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                  if (couponDiscount > 0 &&
                                      appliedCouponId != null)
                                    Text(
                                      ' (Coupon)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  if (promoDiscount > 0 &&
                                      appliedPromoId != null)
                                    Text(
                                      ' (Promo)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            Text(
                              'Driver: $driverID',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: Text(
                          formattedTime,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
