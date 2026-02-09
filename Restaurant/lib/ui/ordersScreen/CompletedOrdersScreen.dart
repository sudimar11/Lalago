import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/CurrencyModel.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/ordersScreen/OrderDetailsScreen.dart';

class CompletedOrdersScreen extends StatefulWidget {
  @override
  _CompletedOrdersScreenState createState() => _CompletedOrdersScreenState();
}

class _CompletedOrdersScreenState extends State<CompletedOrdersScreen> {
  FireStoreUtils _fireStoreUtils = FireStoreUtils();
  late Stream<List<OrderModel>> completedOrdersStream;
  bool isLoading = true;
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    initializeData();
  }

  Future<void> initializeData() async {
    await setCurrency();

    final vendorID = MyAppState.currentUser?.vendorID;
    if (vendorID == null) {
      return;
    }

    // Get completed orders for the selected date
    completedOrdersStream = _fireStoreUtils
        .watchCompletedOrdersForDate(vendorID, selectedDate)
        .asBroadcastStream();

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> setCurrency() async {
    currencyModel = await FireStoreUtils().getCurrency() ??
        CurrencyModel(
          id: "",
          code: "USD",
          decimal: 2,
          isactive: true,
          name: "US Dollar",
          symbol: "\$",
          symbolatright: false,
        );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Color(COLOR_PRIMARY),
              onPrimary: Colors.white,
              onSurface: isDarkMode(context) ? Colors.white : Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
        isLoading = true;
      });
      await initializeData();
    }
  }

  @override
  void dispose() {
    _fireStoreUtils.closeOrdersStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Color(0XFFFFFFFF),
      appBar: AppBar(
        backgroundColor:
            isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        elevation: 0,
        title: StreamBuilder<List<OrderModel>>(
          stream: completedOrdersStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                !snapshot.hasData) {
              return Text(
                'Loading...',
                style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              );
            }

            final orders = snapshot.data!;
            final totalOrders = orders.length;

            return FutureBuilder<double>(
              future: _calculateTotalAmount(orders),
              builder: (context, amountSnapshot) {
                if (amountSnapshot.connectionState == ConnectionState.waiting) {
                  return Text(
                    '$totalOrders Orders',
                    style: TextStyle(
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }

                final totalAmount = amountSnapshot.data ?? 0.0;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalOrders Orders',
                      style: TextStyle(
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '₱${totalAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Color(COLOR_PRIMARY),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.calendar_today,
              color: isDarkMode(context) ? Colors.white : Colors.black,
            ),
            onPressed: () => _selectDate(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Date selector
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: isDarkMode(context)
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.grey.shade50,
              border: Border(
                bottom: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: Color(COLOR_PRIMARY),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Orders for: '.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MMM d, yyyy').format(selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _selectDate(context),
                  child: Text(
                    'Change Date'.tr(),
                    style: TextStyle(
                      color: Color(COLOR_PRIMARY),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Orders list
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : StreamBuilder<List<OrderModel>>(
                    stream: completedOrdersStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError) {
                        return Center(
                            child: Text(
                                'Error loading completed orders. Please try again.'));
                      }

                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: showEmptyState(
                            'No Completed Orders'.tr(),
                            'No completed orders found'.tr(),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: ClampingScrollPhysics(),
                        itemCount: snapshot.data!.length,
                        padding: const EdgeInsets.all(20),
                        itemBuilder: (context, index) {
                          final orderModel = snapshot.data![index];

                          return InkWell(
                            onTap: () {
                              push(
                                context,
                                OrderDetailsScreen(orderModel: orderModel),
                              );
                            },
                            child: buildOrderItem(
                              orderModel,
                              index,
                              index != 0 ? snapshot.data![index - 1] : null,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget buildOrderItem(
    OrderModel orderModel,
    int index,
    OrderModel? prevModel,
  ) {
    // Format the date for the current and previous order
    String date = DateFormat('MMM d yyyy').format(
      DateTime.fromMillisecondsSinceEpoch(
        orderModel.createdAt.millisecondsSinceEpoch,
      ),
    );

    String date2 = prevModel != null
        ? DateFormat('MMM d yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(
              prevModel.createdAt.millisecondsSinceEpoch,
            ),
          )
        : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show date header if it's the first item or a different date than the previous
        if (index == 0 || (index != 0 && prevModel != null && date != date2))
          Container(
            height: 40.0,
            margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: isDarkMode(context)
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              date,
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Poppinsm',
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
          ),

        // The actual order card
        InkWell(
          onTap: () {
            push(context, OrderDetailsScreen(orderModel: orderModel));
          },
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            elevation: 3,
            color:
                isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: buildOrderContent(orderModel),
          ),
        ),
      ],
    );
  }

  Widget buildOrderContent(OrderModel orderModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer & Delivery Info
          Row(
            children: [
              // Product image (first product)
              Container(
                width: 60,
                height: 60,
                margin: const EdgeInsets.only(right: 12.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(orderModel.products.first.photo),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              // Customer name & address
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${orderModel.author.firstName} ${orderModel.author.lastName}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orderModel.takeAway == true
                          ? 'Takeaway'.tr()
                          : 'Deliver to: ${orderModel.address.getFullAddress()}'
                              .tr(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Order Total (with commission deduction)
          FutureBuilder<double>(
            future: calculateTotalAndDeductCommission(orderModel),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Order Total',
                    style: TextStyle(color: Colors.grey),
                  ),
                  trailing: CircularProgressIndicator(),
                );
              } else if (snapshot.hasError || !snapshot.hasData) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Order Total',
                    style: TextStyle(color: Colors.grey),
                  ),
                  trailing: Text(
                    'Error',
                    style: TextStyle(color: Colors.red),
                  ),
                );
              } else {
                double netTotal = snapshot.data ?? 0.0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Order Total',
                    style: TextStyle(color: Colors.grey),
                  ),
                  trailing: Text(
                    '\₱${netTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Color(COLOR_PRIMARY),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
            },
          ),

          // Rider Information
          buildRiderInfo(orderModel),

          const Divider(height: 24),

          // Order Status
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Status'.tr(), style: TextStyle(color: Colors.grey)),
            subtitle: Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(orderModel.status),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getStatusText(orderModel.status),
                style: TextStyle(
                  color: _getStatusTextColor(orderModel.status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          // Remarks (if any)
          if (orderModel.notes != null && orderModel.notes!.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Remarks'.tr(), style: TextStyle(color: Colors.grey)),
              subtitle: Text(
                orderModel.notes!,
                style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildRiderInfo(OrderModel orderModel) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection("restaurant_orders")
          .doc(orderModel.id)
          .get(),
      builder:
          (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delivery_dining,
              color: Color(COLOR_PRIMARY),
              size: 20,
            ),
            title: Text(
              'Rider'.tr(),
              style: TextStyle(color: Colors.grey),
            ),
            subtitle: Text(
              'Loading rider info...'.tr(),
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        if (snapshot.hasError) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delivery_dining,
              color: Colors.grey,
              size: 20,
            ),
            title: Text(
              'Rider'.tr(),
              style: TextStyle(color: Colors.grey),
            ),
            subtitle: Text(
              'Error fetching order data',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        if (!snapshot.hasData || !(snapshot.data?.exists ?? false)) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delivery_dining,
              color: Colors.grey,
              size: 20,
            ),
            title: Text(
              'Rider'.tr(),
              style: TextStyle(color: Colors.grey),
            ),
            subtitle: Text(
              'No order data found',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final orderData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final String? driverID = orderData['driverID'] as String?;

        if (driverID == null) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.delivery_dining,
              color: Colors.grey,
              size: 20,
            ),
            title: Text(
              'Rider'.tr(),
              style: TextStyle(color: Colors.grey),
            ),
            subtitle: Text(
              'No rider assigned',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return FutureBuilder<Map<String, String?>>(
          future: fetchDriverDetails(driverID),
          builder: (BuildContext context,
              AsyncSnapshot<Map<String, String?>> riderSnapshot) {
            if (riderSnapshot.connectionState == ConnectionState.waiting) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delivery_dining,
                  color: Color(COLOR_PRIMARY),
                  size: 20,
                ),
                title: Text(
                  'Rider'.tr(),
                  style: TextStyle(color: Colors.grey),
                ),
                subtitle: Text(
                  'Loading rider info...'.tr(),
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            if (riderSnapshot.hasError || !riderSnapshot.hasData) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delivery_dining,
                  color: Colors.grey,
                  size: 20,
                ),
                title: Text(
                  'Rider'.tr(),
                  style: TextStyle(color: Colors.grey),
                ),
                subtitle: Text(
                  'Rider info unavailable',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            final riderDetails = riderSnapshot.data!;
            final riderName = riderDetails["driverName"] ?? "Unknown Rider";

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delivery_dining,
                color: Color(COLOR_PRIMARY),
                size: 20,
              ),
              title: Text(
                'Rider'.tr(),
                style: TextStyle(color: Colors.grey),
              ),
              subtitle: Text(
                riderName,
                style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<double> calculateTotalAndDeductCommission(
      OrderModel orderModel) async {
    double total = 0.0;

    // Step 1: Calculate total for all products
    try {
      for (final element in orderModel.products) {
        // Add extrasPrice if available
        if (element.extrasPrice != null &&
            element.extrasPrice!.isNotEmpty &&
            double.tryParse(element.extrasPrice!) != null) {
          total += element.quantity * double.parse(element.extrasPrice!);
        }
        // Add base price
        total += element.quantity * double.parse(element.price);
      }
    } catch (e) {
      print('Error calculating product total: $e');
    }

    // Step 2: Apply discounts (if any)
    final discount =
        double.tryParse(orderModel.discount?.toString() ?? '0.0') ?? 0.0;
    final specialDiscount = double.tryParse(
            orderModel.specialDiscount?['special_discount']?.toString() ??
                '0.0') ??
        0.0;

    final totalAfterDiscount = total - discount - specialDiscount;

    // Count total number of items
    final totalQty = orderModel.products.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    // Step 3: Deduct admin commission
    double adminComm = 0.0;
    try {
      final commissionType = orderModel.adminCommissionType;
      final commissionValue = orderModel.adminCommission;

      if (commissionType != null && commissionValue != null) {
        if (commissionType == 'Percent') {
          adminComm =
              (totalAfterDiscount * double.parse(commissionValue)) / 100;
        } else if (commissionType == 'Fixed') {
          // charge fixed fee per item
          adminComm = double.parse(commissionValue) * totalQty;
        }
      }
    } catch (e) {
      print('Error calculating admin commission: $e');
    }

    // Step 4: Calculate the final net total
    final netTotal = totalAfterDiscount - adminComm;

    return netTotal;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "In Transit":
        return Colors.blue.shade100;
      case ORDER_STATUS_COMPLETED:
        return Colors.green.shade100;
      case "Order Shipped":
        return Colors.orange.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case "In Transit":
        return "In Transit".tr();
      case ORDER_STATUS_COMPLETED:
        return "Completed".tr();
      case "Order Shipped":
        return "Shipped".tr();
      default:
        return status;
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status) {
      case "In Transit":
        return Colors.blue.shade800;
      case ORDER_STATUS_COMPLETED:
        return Colors.green.shade800;
      case "Order Shipped":
        return Colors.orange.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  Future<double> _calculateTotalAmount(List<OrderModel> orders) async {
    double totalAmount = 0.0;

    for (final order in orders) {
      try {
        final orderTotal = await calculateTotalAndDeductCommission(order);
        totalAmount += orderTotal;
      } catch (e) {
        print('Error calculating total for order ${order.id}: $e');
        // Continue with other orders even if one fails
      }
    }

    return totalAmount;
  }
}

Future<Map<String, String?>> fetchDriverDetails(String driverID) async {
  try {
    final driverDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(driverID)
        .get();

    if (driverDoc.exists) {
      final driverData = driverDoc.data();
      final driverName =
          "${driverData?['firstName'] ?? 'Unknown'} ${driverData?['lastName'] ?? ''}";
      final driverPhone = driverData?['phoneNumber'] ?? 'No phone number';
      final driverPhoto = driverData?['profilePictureURL'] ?? '';

      return {
        "driverName": driverName,
        "driverPhone": driverPhone,
        "driverPhoto": driverPhoto,
      };
    } else {
      return {
        "driverName": "Driver not found",
        "driverPhone": null,
        "driverPhoto": null,
      };
    }
  } catch (e) {
    return {"driverName": "Error", "driverPhone": null, "driverPhoto": null};
  }
}
