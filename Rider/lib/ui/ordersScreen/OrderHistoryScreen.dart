import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/ui/chat_screen/chat_screen.dart';
import 'package:intl/intl.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({Key? key}) : super(key: key);

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  DateTime _selectedDate = DateTime.now();

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Stream<QuerySnapshot> _getOrdersStream() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      // Return an empty stream
      return Stream<QuerySnapshot>.empty();
    }

    final firestore = FirebaseFirestore.instance;

    // Query all orders for the driver
    // Date filtering will be done in the builder
    return firestore
        .collection('restaurant_orders')
        .where('driverID', isEqualTo: currentUserId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  List<QueryDocumentSnapshot> _filterOrdersByDate(QuerySnapshot snapshot) {
    final startOfDay = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      0,
      0,
      0,
    );
    final startOfTomorrow = startOfDay.add(const Duration(days: 1));

    return snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final deliveredAt = data['deliveredAt'] as Timestamp?;
      final createdAt = data['createdAt'] as Timestamp?;

      // Use deliveredAt if available, otherwise fall back to createdAt
      final timestamp = deliveredAt ?? createdAt;
      if (timestamp == null) return false;

      final orderDate = timestamp.toDate();
      return orderDate
              .isAfter(startOfDay.subtract(const Duration(seconds: 1))) &&
          orderDate.isBefore(startOfTomorrow);
    }).toList();
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

  double _calculateTotal(Map<String, dynamic> order) {
    // Calculate items total
    final products = order['products'] as List<dynamic>? ?? [];
    double itemsTotal = 0.0;
    for (var product in products) {
      final quantity = (product['quantity'] ?? 0) as num;
      final price = double.tryParse(product['price']?.toString() ?? '0') ?? 0.0;
      itemsTotal += quantity * price;
    }

    // Get delivery charge
    final deliveryCharge =
        double.tryParse(order['deliveryCharge']?.toString() ?? '0') ?? 0.0;

    // Get discount breakdown and customer total
    final discountBreakdown =
        _getDiscountBreakdown(order, itemsTotal, deliveryCharge);
    final double customerTotal = discountBreakdown['customerTotal'] as double;

    // Add tip (tip is separate from customer payment)
    final tipValue =
        order['tip_amount']?.toString() ?? order['tipValue']?.toString() ?? '0';
    final tipAmount = double.tryParse(tipValue) ?? 0.0;

    // Return customer total + tip (for display purposes)
    return customerTotal + tipAmount;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'order placed':
        return Colors.orange;
      case 'order accepted':
      case 'driver accepted':
        return Colors.blue;
      case 'order shipped':
      case 'in transit':
      case 'driver on the way':
        return Colors.purple;
      case 'order completed':
      case 'delivered':
        return Colors.green;
      case 'order cancelled':
      case 'cancelled':
      case 'driver rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusDisplayText(String status) {
    switch (status.toLowerCase()) {
      case 'order placed':
        return 'Placed';
      case 'order accepted':
        return 'Accepted';
      case 'driver accepted':
        return 'Accepted';
      case 'order shipped':
        return 'Shipped';
      case 'in transit':
        return 'In Transit';
      case 'driver on the way':
        return 'On the Way';
      case 'order completed':
        return 'Completed';
      case 'delivered':
        return 'Delivered';
      case 'order cancelled':
        return 'Cancelled';
      case 'cancelled':
        return 'Cancelled';
      case 'driver rejected':
        return 'Rejected';
      default:
        return status.toUpperCase();
    }
  }

  /// Check if chat is enabled for the given order status
  bool _isChatEnabled(String status) {
    final statusLower = status.toLowerCase();
    return statusLower == 'order accepted' ||
        statusLower == 'driver accepted' ||
        statusLower == 'driver pending' ||
        statusLower == 'order shipped' ||
        statusLower == 'in transit' ||
        statusLower == 'order completed' ||
        statusLower == 'delivered';
  }

  /// Open chat screen for the order
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

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] ?? '';
    final author = order['author'] as Map<String, dynamic>? ?? {};
    final address = order['address'] as Map<String, dynamic>? ?? {};
    final vendor = order['vendor'] as Map<String, dynamic>? ?? {};
    final products = order['products'] as List<dynamic>? ?? [];
    final status = order['status']?.toString() ?? 'Unknown';
    final deliveredAt = order['deliveredAt'] as Timestamp?;
    final createdAt = order['createdAt'] as Timestamp?;
    final orderDate = deliveredAt ?? createdAt;
    final total = _calculateTotal(order);

    final customerName =
        '${author['firstName'] ?? ''} ${author['lastName'] ?? ''}'.trim();
    final restaurantName = vendor['title']?.toString() ?? 'Unknown Restaurant';
    final customerAddress = address['address']?.toString() ?? '';
    final addressAs = address['addressAs']?.toString() ?? '';
    final landmark = address['landmark']?.toString() ?? '';

    // Calculate tip information
    final tipValueStr =
        order['tip_amount']?.toString() ?? order['tipValue']?.toString() ?? '';
    final tipAmount = double.tryParse(tipValueStr) ?? 0.0;
    final hasTip = tipValueStr.isNotEmpty &&
        tipValueStr != '0' &&
        tipValueStr != '0.0' &&
        tipAmount > 0.0;
    final tipDisplayText = hasTip ? amountShow(amount: tipValueStr) : 'None';
    final tipColor = hasTip ? Colors.green : Colors.grey[600]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 3,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            )
          ],
          color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with order info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          orderId.length > 8
                              ? 'Order #${orderId.substring(0, 8)}...'
                              : 'Order #$orderId',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusDisplayText(status),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (orderDate != null)
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM dd, yyyy • hh:mm a')
                              .format(orderDate.toDate()),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Restaurant name
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.restaurant,
                    size: 16,
                    color: Color(COLOR_PRIMARY),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Restaurant: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      restaurantName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Customer info
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer name
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 16,
                        color: Color(COLOR_PRIMARY),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Customer: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color:
                              isDarkMode(context) ? Colors.white : Colors.black,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          customerName.isEmpty ? 'N/A' : customerName,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                      ),
                      if (_isChatEnabled(status))
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: () => _openChat(orderId, author),
                            icon: const Icon(Icons.chat, size: 20),
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Customer address
                  if (customerAddress.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 16,
                          color: Color(COLOR_PRIMARY),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Address: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDarkMode(context)
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (addressAs.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Color(COLOR_PRIMARY)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    addressAs,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(COLOR_PRIMARY),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              Text(
                                customerAddress,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                              if (landmark.isNotEmpty)
                                Text(
                                  'Landmark: $landmark',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Order items
            if (products.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDarkMode(context)
                      ? Colors.grey.shade900
                      : Colors.grey.shade50,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Items (${products.length}):',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...products.map((product) {
                      final name = product['name']?.toString() ?? 'Unknown';
                      final quantity = product['quantity'] ?? 0;
                      final price = double.tryParse(
                              product['price']?.toString() ?? '0') ??
                          0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          '• $name x$quantity - ${amountShow(amount: (quantity * price).toString())}',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDarkMode(context)
                                ? Colors.grey[300]
                                : Colors.black87,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),

            // Tip information
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates,
                        size: 16,
                        color: Color(COLOR_PRIMARY),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tip:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color:
                              isDarkMode(context) ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    tipDisplayText,
                    style: TextStyle(
                      fontSize: 14,
                      color: tipColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Total amount
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Amount:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                    ),
                  ),
                  Text(
                    amountShow(amount: total.toString()),
                    style: TextStyle(
                      color: Color(COLOR_PRIMARY),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Order History'),
        backgroundColor: isDarkMode(context)
            ? Color(DARK_VIEWBG_COLOR)
            : Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: Column(
        children: [
          // Date picker button
          Container(
            padding: const EdgeInsets.all(16),
            color: isDarkMode(context)
                ? Color(DARK_CARD_BG_COLOR)
                : Colors.grey.shade100,
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Color(COLOR_PRIMARY),
                ),
                const SizedBox(width: 8),
                Text(
                  'Date: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ),
                TextButton(
                  onPressed: _selectDate,
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(_selectedDate),
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(COLOR_PRIMARY),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _selectDate,
                  icon: Icon(
                    Icons.edit,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
              ],
            ),
          ),

          // Orders list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getOrdersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator.adaptive(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                      ),
                    ),
                  );
                }

                if (snapshot.data == null) {
                  return Center(
                    child: Text(
                      'No orders found',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode(context)
                            ? Colors.grey[300]
                            : Colors.grey[600],
                      ),
                    ),
                  );
                }
                final docs = _filterOrdersByDate(snapshot.data!);
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No orders found',
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode(context)
                                ? Colors.grey[300]
                                : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No orders for ${DateFormat('MMM dd, yyyy').format(_selectedDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode(context)
                                ? Colors.grey[400]
                                : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final orderData = doc.data() as Map<String, dynamic>;
                      orderData['id'] = doc.id;
                      return _buildOrderCard(orderData);
                    },
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
