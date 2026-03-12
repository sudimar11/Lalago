import 'dart:async';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:foodie_customer/services/ash_notification_history.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/reorder_service.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/home/HomeScreen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/ui/ordersScreen/OrdersScreen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/utils/notification_service.dart';
import 'package:foodie_customer/ui/chat_screen/chat_screen.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/constants.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lalago_shared/notification_action_payload.dart';

/// Handles interactive notification actions for the Customer app.
class NotificationActionHandler {
  /// Handles action from notification tap or action button.
  static Future<void> handleAction(
    BuildContext? context,
    String actionString,
    Map<String, dynamic>? payload, {
    String? userText,
  }) async {
    final parsed = parseActionString(actionString);
    final action = parsed['action'] ?? '';
    final targetId = parsed['targetId'] ??
        payload?['orderId']?.toString() ??
        payload?['vendorId']?.toString() ??
        payload?['targetId']?.toString() ??
        '';

    final notificationId = payload?['notificationId']?.toString();
    if (notificationId != null && notificationId.isNotEmpty) {
      unawaited(AshNotificationHistory.markOpened(
        notificationId,
        action: action.isNotEmpty ? action : 'tapped',
      ));
    }

    final ctx = context ?? NotificationService.navigatorKey.currentContext;
    if (ctx == null) return;

    switch (action) {
      case ACTION_REORDER:
        if (targetId.isNotEmpty) {
          await ReorderService.reorderFromVendor(ctx, targetId);
        }
        break;
      case ACTION_VIEW_ORDER:
      case 'view_order':
        if (targetId.isNotEmpty) {
          await _navigateToOrderDetails(ctx, targetId, payload);
        }
        break;
      case ACTION_CHAT_REPLY:
      case 'chat_reply':
        if (targetId.isNotEmpty) {
          NotificationService.instance.navigateToChat(payload ?? {});
        }
        break;
      case ACTION_REMIND_LATER:
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text("We'll remind you later")),
          );
        }
        break;
      default:
        if (targetId.isNotEmpty && payload?['type']?.toString()?.startsWith('ash_') == true) {
          await _handleAshAction(ctx, payload!);
        }
    }
  }

  static Future<void> _navigateToOrderDetails(
    BuildContext context,
    String orderId,
    Map<String, dynamic>? payload,
  ) async {
    final customerId = payload?['customerId']?.toString();
    if (MyAppState.currentUser != null &&
        customerId != null &&
        customerId != MyAppState.currentUser!.userID) {
      return;
    }
    final OrderModel? order = await FireStoreUtils.getOrderByIdOnce(orderId);
    if (order == null) return;
    if (!context.mounted) return;
    push(
      context,
      OrderDetailsScreen(orderModel: order, fromNotification: true),
    );
  }

  static Future<void> _handleAshAction(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final type = data['type']?.toString() ?? '';
    final vendorId = data['vendorId']?.toString();
    final productId = data['productId']?.toString();

    if (type == 'ash_reorder' && vendorId != null && vendorId.isNotEmpty) {
      final vendor = await FireStoreUtils.getVendor(vendorId);
      if (vendor != null && context.mounted) {
        pushAndRemoveUntil(
          context,
          ContainerScreen(user: MyAppState.currentUser),
          false,
        );
        final c = NotificationService.navigatorKey.currentContext;
        if (c != null && context.mounted) {
          push(
            c,
            NewVendorProductsScreen(
              vendorModel: vendor,
              showReorderBanner: true,
            ),
          );
        }
      } else if (context.mounted) {
        pushAndRemoveUntil(
          context,
          ContainerScreen(
            user: MyAppState.currentUser,
            currentWidget: OrdersScreen(isAnimation: true),
          ),
          false,
        );
      }
    } else if (type == 'ash_recommendation' && vendorId != null) {
      final vendor = await FireStoreUtils.getVendor(vendorId);
      if (vendor == null) {
        if (context.mounted) {
          pushAndRemoveUntil(
            context,
            ContainerScreen(
              user: MyAppState.currentUser,
              currentWidget: HomeScreen(user: MyAppState.currentUser),
            ),
            false,
          );
        }
        return;
      }
      if (!context.mounted) return;
      pushAndRemoveUntil(
        context,
        ContainerScreen(user: MyAppState.currentUser),
        false,
      );
      final c = NotificationService.navigatorKey.currentContext;
      if (c != null) {
        if (productId != null && productId.isNotEmpty) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection(PRODUCTS)
                .doc(productId)
                .get();
            if (doc.exists && doc.data() != null) {
              final d = Map<String, dynamic>.from(doc.data()!);
              d['id'] = doc.id;
              final product = ProductModel.fromJson(d);
              if (product.vendorID == vendorId) {
                push(c, ProductDetailsScreen(
                  productModel: product,
                  vendorModel: vendor,
                ));
                return;
              }
            }
          } catch (_) {}
        }
        push(c, NewVendorProductsScreen(vendorModel: vendor));
      }
    } else if (type == 'ash_cart' || type == 'ash_cart_urgent') {
      if (context.mounted) {
        pushAndRemoveUntil(
          context,
          ContainerScreen(
            user: MyAppState.currentUser,
            currentWidget: CartScreen(fromContainer: true),
          ),
          false,
        );
      }
    } else if (type == 'ash_hunger') {
      final mealPeriod = data['mealPeriod']?.toString();
      if (context.mounted) {
        pushAndRemoveUntil(
          context,
          ContainerScreen(
            user: MyAppState.currentUser,
            currentWidget: HomeScreen(
              user: MyAppState.currentUser,
              highlightMealPeriod: mealPeriod,
              filterByMeal: mealPeriod != null,
            ),
          ),
          false,
        );
      }
    } else if (context.mounted) {
      pushAndRemoveUntil(
        context,
        ContainerScreen(
          user: MyAppState.currentUser,
          currentWidget: HomeScreen(user: MyAppState.currentUser),
        ),
        false,
      );
    }
  }
}
