import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/ui/ordersScreen/OrdersScreen.dart';
import 'package:provider/provider.dart';

class PlaceOrderScreen extends StatefulWidget {
  final OrderModel orderModel;

  const PlaceOrderScreen({Key? key, required this.orderModel})
      : super(key: key);

  @override
  _PlaceOrderScreenState createState() => _PlaceOrderScreenState();
}

class _PlaceOrderScreenState extends State<PlaceOrderScreen> {
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // Call placeOrder before the timer starts
    placeOrder().then((_) {
      timer = Timer(const Duration(seconds: 3), () => animateOut());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: BoxDecoration(
        color: isDarkMode(context) ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              'Placing Order...',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade800,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator.adaptive(
                valueColor: AlwaysStoppedAnimation(
                  Color(COLOR_PRIMARY), // Use runtime color
                ),
              ),
            ),
          ),
          Visibility(
            visible:
                true, // Always show delivery info since takeAway was removed
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 40),
                  title: Text(
                    widget.orderModel.address?.getFullAddress() ??
                        "Address not available",
                    style: TextStyle(
                      color: isDarkMode(context)
                          ? Colors.grey.shade300
                          : Colors.grey.shade800,
                      fontWeight: FontWeight.w500,
                      fontSize: 17,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  subtitle: Text('Deliver to door'),
                  leading: const Icon(
                    CupertinoIcons.checkmark_alt,
                  ),
                ),
                const Divider(indent: 40, endIndent: 40),
              ],
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 40),
            title: Text(
              'Your order, ${widget.orderModel.author.fullName()}',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade800,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            leading: const Icon(
              CupertinoIcons.checkmark_alt,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsetsDirectional.only(start: 56),
              itemCount: widget.orderModel.products.length,
              itemBuilder: (context, index) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      color: isDarkMode(context)
                          ? Colors.grey.shade700
                          : Colors.grey.shade200,
                      padding: const EdgeInsets.all(6),
                      child: Text('${index + 1}'),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        widget.orderModel.products[index].name,
                        style: TextStyle(
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> placeOrder() async {
    try {
      // Simulating order placement logic (replace this with actual implementation)
      print(
          "Order placed successfully for: ${widget.orderModel.author.fullName()}");
      // Call your Firestore or API to store the order data
    } catch (e) {
      print("Error placing order: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Order placement failed. Please try again."),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> animateOut() async {
    // Rider-first dispatch:
    // Restaurant notifications are sent by Cloud Functions *after* the rider
    // accepts (not immediately at checkout).

    if (!mounted) return;

    try {
      Provider.of<CartDatabase>(context, listen: false).deleteAllProducts();

      // Navigate to ContainerScreen with OrdersScreen first to ensure proper navigation stack
      pushAndRemoveUntil(
        context,
        ContainerScreen(
          user: MyAppState.currentUser!,
          currentWidget: OrdersScreen(isAnimation: true),
          appBarTitle: 'Orders',
        ),
        false,
      );

      // Then push OrderDetailsScreen on top so back button returns to OrdersScreen
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          push(
            context,
            OrderDetailsScreen(orderModel: widget.orderModel),
          );
        }
      });
    } catch (e) {
      print("Error during navigation or clearing cart: $e");
    }
  }
}
