import 'package:flutter/material.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/ui/ordersScreen/OrdersScreen.dart';
import 'package:provider/provider.dart';

class OrderNavigationHelper {
  static void navigateToOrderSuccess(
    BuildContext context,
    OrderModel placedOrder,
  ) {
    Provider.of<CartDatabase>(context, listen: false).deleteAllProducts();
    pushAndRemoveUntil(
      context,
      ContainerScreen(
        user: MyAppState.currentUser!,
        currentWidget: OrdersScreen(isAnimation: true),
        appBarTitle: 'Orders',
      ),
      false,
    );
    push(context, OrderDetailsScreen(orderModel: placedOrder));
  }
}
