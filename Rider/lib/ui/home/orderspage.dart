import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:foodie_driver/ui/home/customermap.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/ui/home/orderdetails.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:foodie_driver/services/audio_service.dart';
import 'package:foodie_driver/services/order_service.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';
import 'package:lalago_shared/order_status.dart';

class OrderPage extends StatefulWidget {
  const OrderPage({Key? key}) : super(key: key);

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> newOrders = [];
  List<Map<String, dynamic>> activeOrders = [];
  bool isLoading = true;
  final Map<String, String> selectedStatuses = {};

  // Caches for computed values
  final Map<String, double> _distanceCache = {};
  final Map<String, double> _totalItemPriceCache = {};
  final Map<String, Map<String, dynamic>> _discountCache = {};

  String username = "Loading...";
  String userID = "";

  @override
  void initState() {
    super.initState();
    fetchUserDetails();
    fetchOrders();
  }

  Future<void> fetchUserDetails() async {
    try {
      // Replace 'currentUserId' with your method to get the logged-in user's ID
      final currentUserId = "LOGGED_IN_USER_ID"; // Example placeholder

      final userSnapshot =
          await _firestore.collection('users').doc(currentUserId).get();

      if (userSnapshot.exists) {
        final userData = userSnapshot.data();
        setState(() {
          username = userData?['username'] ?? 'Unknown User';
          userID = userSnapshot.id;
        });
      }
    } catch (e) {
      log("Error fetching user details: $e");
      setState(() {
        username = "Error";
        userID = "";
      });
    }
  }

  Future<void> fetchOrders() async {
    setState(() {
      isLoading = true;
    });

    try {
      final newOrderSnapshot = await _firestore
          .collection('restaurant_orders')
          .where('status', isEqualTo: 'Order Accepted')
          .get();

      final activeOrderSnapshot = await _firestore
          .collection('restaurant_orders')
          .where('status', whereIn: [
        ORDER_STATUS_DRIVER_ACCEPTED,
        ORDER_STATUS_SHIPPED,
        ORDER_STATUS_IN_TRANSIT,
      ]).get();

      final newOrdersList = newOrderSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      final activeOrdersList = activeOrderSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      // Clear caches before recomputing
      _distanceCache.clear();
      _totalItemPriceCache.clear();
      _discountCache.clear();

      // Precompute all values for all orders
      _precomputeOrderData([...newOrdersList, ...activeOrdersList]);

      setState(() {
        newOrders = newOrdersList;
        activeOrders = activeOrdersList;
        isLoading = false;
      });
    } catch (e) {
      log("Error fetching orders: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$username ($userID)'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    child: const TabBar(
                      labelColor: Colors.blue,
                      unselectedLabelColor: Colors.grey,
                      tabs: [
                        Tab(text: "New Orders"),
                        Tab(text: "Active Orders"),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildOrderList(newOrders, "No new orders found."),
                        _buildActive(activeOrders, "No active orders found."),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildOrderList(
      List<Map<String, dynamic>> orders, String emptyMessage) {
    if (orders.isEmpty) {
      return Center(
        child: Text(emptyMessage),
      );
    }

    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];

        final vendor = order['vendor'] ?? {};
        final author = order['author'] ?? {};

        final List<dynamic> orderedItems = order['products'] ?? [];
        final orderStatus = order['status'] ?? 'Unknown Status'; // Order status
        final preparationTime = order['estimatedTimeToPrepare'] ??
            'N/A'; // Include the preparation time from the order data

        // Use cached values
        final orderId = order['id'] as String;
        final distanceToRestaurant = _distanceCache[orderId] ?? 0.0;
        final deliveryCharge =
            double.tryParse((order['deliveryCharge'] ?? '0').toString()) ?? 0.0;
        final totalItemPrice = _totalItemPriceCache[orderId] ?? 0.0;
        final discountBreakdown = _discountCache[orderId] ?? {
          'discounts': <Map<String, dynamic>>[],
          'customerTotal': totalItemPrice + deliveryCharge,
        };

        return Card(
              margin: const EdgeInsets.all(10),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order ID: ${order['id']}'),
                    Text(
                        'Customer: ${author['firstName'] ?? 'N/A'} ${author['lastName'] ?? ''}'),
                    Text('Restaurant: ${vendor['title'] ?? 'N/A'}'),
                    Text('Order Status: $orderStatus'), // Display order status
                    Text(
                        'Preparation Time: $preparationTime minutes'), // Display preparation time
                    Text(
                        'Distance: ${distanceToRestaurant.toStringAsFixed(2)} km'),
                    Text(
                        'Delivery Charge: ₱${deliveryCharge.toStringAsFixed(2)}'),
                    const Divider(),
                    Text('Ordered Items:'),
                    ...orderedItems.map((item) {
                      final itemName = item['name'] ?? 'Unknown Item';
                      final itemQuantity = item['quantity'] ?? 0;
                      final itemPrice =
                          double.tryParse(item['price'] ?? '0') ?? 0.0;
                      return Text(
                          '- $itemName (x$itemQuantity): ₱${(itemQuantity * itemPrice).toStringAsFixed(2)}');
                    }).toList(),
                    const Divider(),
                    // Customer Payment Summary (matching customer app display)
                    Builder(
                      builder: (context) {
                        // Use cached discount breakdown
                        final List<Map<String, dynamic>> discounts =
                            discountBreakdown['discounts']
                                as List<Map<String, dynamic>>;
                        final double customerTotal =
                            discountBreakdown['customerTotal'] as double;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Individual Discount Lines
                            ...discounts.map((discount) {
                              final String label = discount['label'] as String;
                              final double amount =
                                  discount['amount'] as double;
                              final String type = discount['type'] as String;
                              // Use green color for promotional discounts, red for others
                              final Color discountColor =
                                  (type == 'Manual Coupon' ||
                                          type == 'Referral Wallet' ||
                                          type == 'First-Order' ||
                                          type == 'Happy Hour')
                                      ? Colors.green
                                      : Colors.red;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 0, vertical: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16,
                                          color: discountColor),
                                    ),
                                    Text(
                                      '(-₱${amount.toStringAsFixed(2)})',
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Customer Payment',
                                    style: const TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                  Text(
                                    '₱${customerTotal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () => _acceptOrder(order),
                          child: Row(
                            children: const [
                              Icon(Icons.check, size: 18), // Accept Icon
                              SizedBox(width: 5),
                              Text('Accept Order'),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => _rejectOrder(order),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red, // Reject Button Color
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.close, size: 18), // Reject Icon
                              SizedBox(width: 5),
                              Text('Reject Order'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () => _navigateToOrderDetails(order),
                          icon: const Icon(
                            Icons.restaurant, // Icon for Restaurant Details
                            size: 24,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _navigatetocustomermap(order),
                          icon: const Icon(
                            Icons.person, // Icon for Customer Details
                            size: 24,
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
      },
    );
  }

  Widget _buildActive(List<Map<String, dynamic>> orders, String emptyMessage) {
    return orders.isEmpty
        ? Center(child: Text(emptyMessage))
        : ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];

              final vendor = order['vendor'] ?? {};
              final author = order['author'] ?? {};

              final List<dynamic> orderedItems = order['products'] ?? [];
              final preparationTime = order['estimatedTimeToPrepare'] ?? 'N/A';

              // Initialize the selected status for the order if not set
              selectedStatuses.putIfAbsent(order['id'], () => "Order Shipped");
// selectedStatuses.putIfAbsent(order['id'], () => order['status']);

              // Use cached values
              final orderId = order['id'] as String;
              final distanceToRestaurant = _distanceCache[orderId] ?? 0.0;
              final deliveryCharge =
                  double.tryParse((order['deliveryCharge'] ?? '0').toString()) ??
                      0.0;
              final totalItemPrice = _totalItemPriceCache[orderId] ?? 0.0;
              final discountBreakdown = _discountCache[orderId] ?? {
                'discounts': <Map<String, dynamic>>[],
                'customerTotal': totalItemPrice + deliveryCharge,
              };

              return Card(
                    margin: const EdgeInsets.all(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Customer: ${author['firstName'] ?? 'N/A'} ${author['lastName'] ?? ''}'),
                          Text('Restaurant: ${vendor['title'] ?? 'N/A'}'),
                          Text('Order Status: ${order['status']}'),
                          Text('Preparation Time: $preparationTime minutes'),
                          Text(
                              'Distance: ${distanceToRestaurant.toStringAsFixed(2)} km'),
                          Text(
                              'Delivery Charge: ₱${deliveryCharge.toStringAsFixed(2)}'),
                          const Divider(),
                          Text('Ordered Items:'),
                          ...orderedItems.map((item) {
                            final itemName = item['name'] ?? 'Unknown Item';
                            final itemQuantity = item['quantity'] ?? 0;
                            final itemPrice =
                                double.tryParse(item['price'] ?? '0') ?? 0.0;
                            return Text(
                                '- $itemName (x$itemQuantity): ₱${(itemQuantity * itemPrice).toStringAsFixed(2)}');
                          }).toList(),
                          const Divider(),
                          // Customer Payment Summary (matching customer app display)
                          Builder(
                            builder: (context) {
                              // Use cached discount breakdown
                              final List<Map<String, dynamic>> discounts =
                                  discountBreakdown['discounts']
                                      as List<Map<String, dynamic>>;
                              final double customerTotal =
                                  discountBreakdown['customerTotal'] as double;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Individual Discount Lines
                                  ...discounts.map((discount) {
                                    final String label =
                                        discount['label'] as String;
                                    final double amount =
                                        discount['amount'] as double;
                                    final String type =
                                        discount['type'] as String;
                                    // Use green color for promotional discounts, red for others
                                    final Color discountColor =
                                        (type == 'Manual Coupon' ||
                                                type == 'Referral Wallet' ||
                                                type == 'First-Order' ||
                                                type == 'Happy Hour')
                                            ? Colors.green
                                            : Colors.red;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 0, vertical: 4),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            label,
                                            style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                                color: discountColor),
                                          ),
                                          Text(
                                            '(-₱${amount.toStringAsFixed(2)})',
                                            style: TextStyle(
                                                fontSize: 16,
                                                color: discountColor),
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
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Customer Payment',
                                          style: const TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18),
                                        ),
                                        Text(
                                          '₱${customerTotal.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                onPressed: () => _navigateToOrderDetails(order),
                                icon: const Icon(
                                  Icons
                                      .restaurant, // Icon for Restaurant Details
                                  size: 24,
                                  color: Colors.blue,
                                ),
                                tooltip:
                                    'Restaurant Details', // Optional tooltip for accessibility
                              ),
                              IconButton(
                                onPressed: () => _navigatetocustomermap(order),
                                icon: const Icon(
                                  Icons.person, // Icon for Customer Details
                                  size: 24,
                                  color: Colors.green,
                                ),
                                tooltip:
                                    'Customer Details', // Optional tooltip for accessibility
                              ),
                            ],
                          ),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: DropdownButton<String>(
                                  value: selectedStatuses[order['id']],
                                  isExpanded: true,
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      selectedStatuses[order['id']] = newValue!;
                                    });
                                  },
                                  items: <String>[
                                    "Order Shipped",
                                    "In Transit",
                                    "Order Completed"
                                  ].map<DropdownMenuItem<String>>(
                                      (String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () async {
                                  try {
                                    final orderId = order['id'];
                                    final newStatus =
                                        selectedStatuses[orderId] ??
                                            "Order Shipped";

                                    await FirebaseFirestore.instance
                                        .collection('restaurant_orders')
                                        .doc(orderId)
                                        .update({
                                      'status': newStatus,
                                    });

                                    // Send FCM notification to customer
                                    try {
                                      await OrderService
                                          .sendStatusUpdateNotification(
                                        orderId,
                                        newStatus,
                                      );
                                    } catch (e) {
                                      // Log but don't block UI - FCM errors are non-critical
                                      debugPrint(
                                          'Error sending FCM notification: $e');
                                    }

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Status updated to $newStatus'),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('Failed to update status: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Update'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
            },
          );
  }

  void _acceptOrder(Map<String, dynamic> order) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) return;

    final blocked = await RemittanceEnforcementService.evaluateIsBlocked(
      FirebaseFirestore.instance,
      currentUserId,
    );
    if (blocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Daily remittance required. Please remit your credit wallet '
            'before accepting orders.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Update the order status to "Driver Accepted"
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(order['id'])
          .update({'status': ORDER_STATUS_DRIVER_ACCEPTED});

      // Display success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order accepted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      AudioService.instance.markOrderAsNotified(order['id'] as String);
    } catch (e) {
      // Display error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _rejectOrder(Map<String, dynamic> order) async {
    final ok = await OrderService.rejectOrderWithReason(
      context,
      order['id'] as String,
      orderData: order,
    );
    if (ok && mounted) {
      fetchOrders();
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
            final amount = double.tryParse(happyHourDiscount.toString()) ?? 0.0;
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

  /// Synchronous distance calculation when both points are available
  double _calculateDistanceSync(
      double lat1, double lon1, double lat2, double lon2) {
    try {
      final distanceInMeters = Geolocator.distanceBetween(
        lat1,
        lon1,
        lat2,
        lon2,
      );
      return distanceInMeters / 1000; // Convert meters to kilometers
    } catch (e) {
      log("Error calculating distance: $e");
      return 0.0;
    }
  }

  /// Precompute distance, totalItemPrice, and discount breakdown for all orders
  void _precomputeOrderData(List<Map<String, dynamic>> orders) {
    for (final order in orders) {
      final orderId = order['id'] as String;

      // Extract coordinates
      final vendor = order['vendor'] ?? {};
      final vendorLatitude = (vendor['latitude'] ?? 0.0) as double;
      final vendorLongitude = (vendor['longitude'] ?? 0.0) as double;

      final author = order['author'] ?? {};
      final authorLocation = author['location'] ?? {};
      final authorLatitude = (authorLocation['latitude'] ?? 0.0) as double;
      final authorLongitude = (authorLocation['longitude'] ?? 0.0) as double;

      // Calculate and cache distance
      final distance = _calculateDistanceSync(
        authorLatitude,
        authorLongitude,
        vendorLatitude,
        vendorLongitude,
      );
      _distanceCache[orderId] = distance;

      // Calculate and cache total item price
      final List<dynamic> orderedItems = order['products'] ?? [];
      final totalItemPrice = orderedItems.fold<double>(0.0, (sum, item) {
        final itemPrice = double.tryParse(item['price'] ?? '0') ?? 0.0;
        final itemQuantity = item['quantity'] ?? 0;
        return sum + (itemPrice * itemQuantity);
      });
      _totalItemPriceCache[orderId] = totalItemPrice;

      // Use stored delivery charge from order (matches Customer app)
      final deliveryCharge =
          double.tryParse((order['deliveryCharge'] ?? '0').toString()) ?? 0.0;

      // Calculate and cache discount breakdown
      final discountBreakdown =
          _getDiscountBreakdown(order, totalItemPrice, deliveryCharge);
      _discountCache[orderId] = discountBreakdown;
    }
  }

  void _navigateToOrderDetails(Map<String, dynamic> order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (BuildContext context) => OrderDetailsPage(order: order),
      ),
    );
  }

  void _navigatetocustomermap(Map<String, dynamic> order) {
    final String id = order['orderId'] as String; // extract the ID

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDriverLocationPage(orderId: id),
      ),
    );
  }
}
