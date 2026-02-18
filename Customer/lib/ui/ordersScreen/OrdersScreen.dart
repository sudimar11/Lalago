// ignore_for_file: must_be_immutable

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:provider/provider.dart';

class OrdersScreen extends StatefulWidget {
  bool? isAnimation = true;

  OrdersScreen({super.key, this.isAnimation});
  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Stream<List<OrderModel>> ordersFuture;
  FireStoreUtils _fireStoreUtils = FireStoreUtils();
  List<OrderModel> ordersList = [];
  late CartDatabase cartDatabase;

  void _initializeStream() {
    if (MyAppState.currentUser == null) {
      print('❌ OrdersScreen: currentUser is null! Cannot initialize stream.');
      return;
    }

    if (MyAppState.currentUser!.userID.isEmpty) {
      print('❌ OrdersScreen: userID is empty! Cannot initialize stream.');
      return;
    }

    print('✅ OrdersScreen: Initializing order stream');
    ordersFuture = _fireStoreUtils.getOrders(MyAppState.currentUser!.userID);
  }

  @override
  void initState() {
    super.initState();
    print(
        '🔍 OrdersScreen: Initializing with userID: ${MyAppState.currentUser?.userID}');
    print('🔍 OrdersScreen: Current user: ${MyAppState.currentUser?.toJson()}');

    // Additional validation
    if (MyAppState.currentUser == null) {
      print('❌ OrdersScreen: currentUser is null!');
      return;
    }

    if (MyAppState.currentUser!.userID.isEmpty) {
      print('❌ OrdersScreen: userID is empty!');
      return;
    }

    print('✅ OrdersScreen: User validation passed, starting order stream');
    _initializeStream();

    // Test Firestore connection
    _testFirestoreConnection();

    //Future.delayed(const Duration(seconds: 7), () {
    //  setState(() {
    //    widget.isAnimation = false;
    //  });
    //});
  }

  void _testFirestoreConnection() async {
    try {
      print('🔍 Testing Firestore connection...');
      print('🔍 Using collection: $ORDERS');
      final FirebaseFirestore firestore = FireStoreUtils.firestore;
      final testQuery = await firestore
          .collection(ORDERS)
          .where('authorID', isEqualTo: MyAppState.currentUser!.userID)
          .limit(1)
          .get();
      print(
          '✅ Firestore connection test successful. Found ${testQuery.docs.length} documents');
      if (testQuery.docs.isNotEmpty) {
        print('📄 Sample document: ${testQuery.docs.first.data()}');
      }

      // Also test without filters to see if there are any orders at all
      final allOrdersQuery = await firestore.collection(ORDERS).limit(5).get();
      print(
          '🔍 Total orders in collection (first 5): ${allOrdersQuery.docs.length}');
      for (var doc in allOrdersQuery.docs) {
        final data = doc.data();
        print(
            '📄 Order ${doc.id}: authorID=${data['authorID']}, status=${data['status']}, createdAt=${data['createdAt']}');
      }
    } catch (e) {
      print('❌ Firestore connection test failed: $e');
    }
  }

  @override
  void didChangeDependencies() {
    cartDatabase = Provider.of<CartDatabase>(context, listen: false);
    super.didChangeDependencies();

    // Reinitialize stream when coming back from another screen
    // This prevents black screen when navigating back from OrderDetailsScreen
    if (MyAppState.currentUser != null &&
        MyAppState.currentUser!.userID.isNotEmpty) {
      _initializeStream();
    }
  }

  @override
  void dispose() {
    FireStoreUtils().closeOrdersStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show guest placeholder if user is not logged in
    if (MyAppState.currentUser == null) {
      return Scaffold(
        backgroundColor:
            isDarkMode(context) ? Color(DARK_COLOR) : Color(0xffFFFFFF),
        appBar: AppBar(
          backgroundColor: Color(COLOR_PRIMARY),
          elevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            'Orders',
            style: TextStyle(
              fontFamily: "Poppinsm",
              fontSize: 18,
              color: Colors.white,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text('Login to view your orders', style: TextStyle(fontSize: 18)),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => push(context, LoginScreen()),
                child: Text('Login / Register'),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_COLOR) : Color(0xffFFFFFF),
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        elevation: 0,
        centerTitle: false, // keep it aligned to the left
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Orders',
          style: TextStyle(
            fontFamily: "Poppinsm",
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        actions: [
          StreamBuilder<List<CartProduct>>(
            stream: cartDatabase.watchProducts,
            initialData: const [],
            builder: (context, snapshot) {
              int cartCount = 0;
              if (snapshot.hasData) {
                cartCount =
                    snapshot.data!.fold(0, (sum, item) => sum + item.quantity);
              }
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.shopping_cart, color: Colors.white),
                    onPressed: () {
                      push(context, CartScreen());
                    },
                  ),
                  if (cartCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Color(COLOR_PRIMARY),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          cartCount.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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
      body: StreamBuilder<List<OrderModel>>(
        stream: ordersFuture,
        builder: (context, snapshot) {
          print(
              '🔍 OrdersScreen StreamBuilder - Connection state: ${snapshot.connectionState}');
          print(
              '🔍 OrdersScreen StreamBuilder - Has data: ${snapshot.hasData}');
          print(
              '🔍 OrdersScreen StreamBuilder - Data length: ${snapshot.data?.length ?? 0}');
          print('🔍 OrdersScreen StreamBuilder - Error: ${snapshot.error}');

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator.adaptive(
                valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
              ),
            );
          }

          if (snapshot.hasError) {
            print('❌ OrdersScreen StreamBuilder - Error: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text('Error loading orders: ${snapshot.error}'),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        ordersFuture = _fireStoreUtils
                            .getOrders(MyAppState.currentUser!.userID);
                      });
                    },
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || (snapshot.data?.isEmpty ?? true)) {
            print('📭 OrdersScreen StreamBuilder - No orders found');
            return Center(
              child: showEmptyState('No Previous Orders', context,
                  description: "Let's orders food!"),
            );
          } else {
            print(
                '✅ OrdersScreen StreamBuilder - Found ${snapshot.data!.length} orders');
            snapshot.data!.forEach((order) {
              print(
                  '📦 Order: ${order.id} - Status: ${order.status} - CreatedAt: ${order.createdAt}');
            });
            return ListView.builder(
              itemCount: snapshot.data!.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) =>
                  buildOrderItem(snapshot.data![index]),
            );
          }
        },
      ),
    );
  }

  Widget buildOrderItem(OrderModel orderModel) {
    return Container(
      margin: EdgeInsets.only(bottom: 16, left: 16, right: 16),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode(context)
              ? const Color.fromARGB(255, 126, 125, 125).withValues(alpha: 0.2)
              : const Color.fromARGB(255, 126, 125, 125).withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkMode(context)
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.grey.withValues(alpha: 0.15),
            spreadRadius: 0,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => push(
            context,
            OrderDetailsScreen(orderModel: orderModel),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with Order ID and Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ORDER ID',
                            style: TextStyle(
                              fontFamily: 'Poppinsm',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                              color: isDarkMode(context)
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '#${orderModel.id.substring(0, 8).toUpperCase()}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Colors.black87,
                              fontFamily: "Poppinssb",
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusBadge(orderModel.status),
                  ],
                ),

                SizedBox(height: 16),

                // Main content with image and details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product image with modern styling
                    Container(
                      height: 90,
                      width: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            spreadRadius: 0,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          (orderModel.products.first.photo.isNotEmpty)
                              ? orderModel.products.first.photo
                              : placeholderImage,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade200,
                              child: Icon(
                                Icons.restaurant,
                                color: Colors.grey.shade400,
                                size: 32,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    SizedBox(width: 16),

                    // Order details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Restaurant name
                          if (orderModel.vendor.title.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text(
                                orderModel.vendor.title,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode(context)
                                      ? Colors.white
                                      : Colors.black87,
                                  fontFamily: "Poppinsb",
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          // Products list
                          ...orderModel.products
                              .take(2)
                              .map((product) => Padding(
                                    padding: EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      product.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: isDarkMode(context)
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                        fontFamily: "Poppinsm",
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),

                          if (orderModel.products.length > 2)
                            Text(
                              '+${orderModel.products.length - 2} more items',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                                fontFamily: "Poppinsr",
                              ),
                            ),

                          SizedBox(height: 8),

                          // Date
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 14,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                              SizedBox(width: 4),
                              Text(
                                orderDate(orderModel.createdAt),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDarkMode(context)
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                  fontFamily: "Poppinsr",
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Footer with total and action
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode(context)
                                ? Colors.grey.shade400
                                : Colors.grey.shade600,
                            fontFamily: "Poppinsr",
                          ),
                        ),
                        SizedBox(height: 2),
                        getOrderTotalText(orderModel),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () => push(
                        context,
                        OrderDetailsScreen(orderModel: orderModel),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(COLOR_PRIMARY),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'View Details',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              fontFamily: "Poppinsm",
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color statusColor;
    Color backgroundColor;
    IconData statusIcon;

    switch (status.toLowerCase()) {
      case 'order placed':
      case 'placed':
        statusColor = Colors.blue;
        backgroundColor = Colors.blue.withValues(alpha: 0.1);
        statusIcon = Icons.receipt_long_rounded;
        break;
      case 'order accepted':
      case 'accepted':
        statusColor = Colors.green;
        backgroundColor = Colors.green.withValues(alpha: 0.1);
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      case 'order shipped':
      case 'shipped':
      case 'in transit':
        statusColor = Colors.orange;
        backgroundColor = Colors.orange.withValues(alpha: 0.1);
        statusIcon = Icons.local_shipping_rounded;
        break;
      case 'order completed':
      case 'completed':
      case 'delivered':
        statusColor = Colors.green;
        backgroundColor = Colors.green.withValues(alpha: 0.1);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'order cancelled':
      case 'cancelled':
        statusColor = Colors.red;
        backgroundColor = Colors.red.withValues(alpha: 0.1);
        statusIcon = Icons.cancel_outlined;
        break;
      case 'order rejected':
      case 'rejected':
        statusColor = Colors.red;
        backgroundColor = Colors.red.withValues(alpha: 0.1);
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.grey;
        backgroundColor = Colors.grey.withValues(alpha: 0.1);
        statusIcon = Icons.info_outline_rounded;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            size: 14,
            color: statusColor,
          ),
          SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: statusColor,
              fontFamily: "Poppinsm",
            ),
          ),
        ],
      ),
    );
  }

  String? getPrice(OrderModel product, int index, CartProduct cartProduct) {
    /*double.parse(product.price)
        .toStringAsFixed(decimal)*/
    var subTotal;
    var price = cartProduct.extras_price == "" ||
            cartProduct.extras_price == null ||
            cartProduct.extras_price == "0.0"
        ? 0.0
        : cartProduct.extras_price;
    var tipValue = product.tipValue.toString() == "" || product.tipValue == null
        ? 0.0
        : product.tipValue.toString();
    var dCharge = product.deliveryCharge == null ||
            product.deliveryCharge.toString().isEmpty
        ? 0.0
        : double.parse(product.deliveryCharge.toString());
    var dis = product.discount.toString() == "" || product.discount == null
        ? 0.0
        : product.discount.toString();

    subTotal = double.parse(price.toString()) +
        double.parse(tipValue.toString()) +
        double.parse(dCharge.toString()) -
        double.parse(dis.toString());

    return subTotal.toString();
  }

  String? getPriceTotal(String price, int quantity) {
    double ans = double.parse(price) * double.parse(quantity.toString());
    return ans.toString();
  }

  getPriceTotalText(CartProduct s) {
    double total = 0.0;
    print("price $s");
    if (s.extras_price != null &&
        s.extras_price!.isNotEmpty &&
        double.parse(s.extras_price!) != 0.0) {
      total += s.quantity * double.parse(s.extras_price!);
    }
    total += s.quantity * double.parse(s.price);

    return Text(
      amountShow(amount: total.toString()),
      style: TextStyle(
          fontSize: 20,
          color:
              isDarkMode(context) ? Colors.grey.shade200 : Color(COLOR_PRIMARY),
          fontFamily: "Poppinsm"),
    );
  }

  Widget getOrderTotalText(OrderModel orderModel) {
    // Calculate subtotal from all products
    double subTotal = 0.0;
    orderModel.products.forEach((element) {
      try {
        if (element.extras_price != null &&
            element.extras_price!.isNotEmpty &&
            double.parse(element.extras_price!) != 0.0) {
          subTotal += element.quantity * double.parse(element.extras_price!);
        }
        subTotal += element.quantity * double.parse(element.price);
      } catch (ex) {
        print("Error calculating product price: $ex");
      }
    });

    // Calculate tip value
    double tipValue = 0.0;
    if (orderModel.tipValue != null && orderModel.tipValue!.isNotEmpty) {
      try {
        tipValue = double.parse(orderModel.tipValue!);
      } catch (ex) {
        print("Error parsing tip value: $ex");
      }
    }

    // Calculate delivery charge
    double deliveryCharge = 0.0;
    if (orderModel.deliveryCharge != null &&
        orderModel.deliveryCharge!.isNotEmpty) {
      try {
        deliveryCharge = double.parse(orderModel.deliveryCharge!);
      } catch (ex) {
        print("Error parsing delivery charge: $ex");
      }
    }

    // Calculate discount
    double discount = orderModel.discount?.toDouble() ?? 0.0;

    // Calculate special discount
    double specialDiscountAmount = 0.0;
    if (orderModel.specialDiscount != null &&
        orderModel.specialDiscount!.isNotEmpty) {
      try {
        specialDiscountAmount = double.parse(
            orderModel.specialDiscount!['special_discount'].toString());
      } catch (ex) {
        print("Error parsing special discount: $ex");
      }
    }

    // Calculate tax amount
    double taxAmount = 0.0;
    if (orderModel.taxModel != null) {
      for (var taxModel in orderModel.taxModel!) {
        try {
          if (taxModel.type == "percentage") {
            taxAmount += (subTotal - discount - specialDiscountAmount) *
                (double.parse(taxModel.tax!) / 100);
          } else {
            taxAmount += double.parse(taxModel.tax!);
          }
        } catch (ex) {
          print("Error calculating tax: $ex");
        }
      }
    }

    // Calculate final total
    double orderTotal = subTotal +
        deliveryCharge +
        tipValue +
        taxAmount -
        discount -
        specialDiscountAmount;

    return Text(
      amountShow(amount: orderTotal.toString()),
      style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDarkMode(context) ? Colors.white : Color(COLOR_PRIMARY)),
    );
  }
}
