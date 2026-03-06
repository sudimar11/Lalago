import 'dart:async';

import 'package:flutter/material.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/localDatabase.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:provider/provider.dart';

/// Service for one-click reorder from a vendor.
class ReorderService {
  static CartProduct? _validateAndTransformCartProduct(CartProduct product) {
    try {
      if (product.id.isEmpty ||
          product.name.isEmpty ||
          product.vendorID.isEmpty ||
          product.price.isEmpty) {
        return null;
      }
      String categoryId = product.category_id ?? product.id.split('~').first;
      if (categoryId.isEmpty) categoryId = product.id;

      String? extrasString;
      if (product.extras != null) {
        if (product.extras is List) {
          final extrasList =
              (product.extras as List).map((e) => e.toString()).toList();
          extrasString = extrasList.join(',');
        } else if (product.extras is String) {
          extrasString = product.extras as String;
        } else {
          extrasString = product.extras.toString();
        }
      }
      // Treat empty/meaningless extras as null to avoid displaying "\\", "null", etc
      if (extrasString != null) {
        final s = extrasString.trim();
        if (s.isEmpty ||
            s == '[]' ||
            s == 'null' ||
            s == '\\' ||
            s == r'\\') {
          extrasString = null;
        }
      }

      return CartProduct(
        id: product.id,
        category_id: categoryId,
        name: product.name,
        photo: product.photo.isNotEmpty
            ? product.photo
            : (AppGlobal.placeHolderImage ?? ''),
        price: product.price,
        discountPrice: product.discountPrice ?? '',
        vendorID: product.vendorID,
        quantity: product.quantity > 0 ? product.quantity : 1,
        extras_price: product.extras_price ?? '0.0',
        extras: extrasString,
        variant_info: product.variant_info,
        addedAt: product.addedAt,
      );
    } catch (e) {
      return null;
    }
  }

  /// Reorders the last completed order from the given vendor.
  /// Requires [context] for Provider and navigation.
  static Future<void> reorderFromVendor(
    BuildContext context,
    String vendorId,
  ) async {
    if (MyAppState.currentUser == null ||
        MyAppState.currentUser!.userID.isEmpty) {
      return;
    }

    await showProgress(context, 'Please wait', false);

    try {
      final result = await FireStoreUtils().getOrdersByStatusPaginated(
        userID: MyAppState.currentUser!.userID,
        status: ORDER_STATUS_COMPLETED,
        limit: 20,
      );

      final orders = (result['orders'] as List<OrderModel>?) ?? [];
      final vendorOrders = orders.where((o) => o.vendorID == vendorId).toList();
      final lastOrder = vendorOrders.isNotEmpty ? vendorOrders.first : null;

      await hideProgress();

      if (lastOrder == null || lastOrder.products.isEmpty) {
        if (context.mounted) {
          showAlertDialog(
            context,
            'Reorder Failed',
            'No previous order found from this restaurant.',
            true,
          );
        }
        return;
      }

      await showProgress(context, 'Please wait', false);

      int successCount = 0;
      int failCount = 0;
      final List<String> failedProducts = [];
      final cartDb = Provider.of<CartDatabase>(context, listen: false);

      try {
        await cartDb.deleteAllProducts().timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('Clear cart timed out'),
            );

        for (final CartProduct p in lastOrder.products) {
          try {
            final validated = _validateAndTransformCartProduct(p);
            if (validated != null) {
              await cartDb.reAddProduct(validated).timeout(
                    const Duration(seconds: 5),
                    onTimeout: () =>
                        throw TimeoutException('Add product timed out'),
                  );
              successCount++;
            } else {
              failCount++;
              failedProducts.add(p.name);
            }
          } catch (e) {
            failCount++;
            failedProducts.add(p.name);
          }
        }
      } finally {
        await hideProgress();
      }

      if (!context.mounted) return;

      if (successCount > 0) {
        if (failCount > 0) {
          showAlertDialog(
            context,
            'Partial Reorder',
            '$successCount product(s) added. $failCount could not be added: '
                '${failedProducts.join(', ')}',
            true,
          );
        }
        push(context, CartScreen(fromContainer: false));
      } else {
        showAlertDialog(
          context,
          'Reorder Failed',
          'Unable to add products to cart. Please try again.',
          true,
        );
      }
    } catch (e) {
      await hideProgress();
      if (context.mounted) {
        showAlertDialog(
          context,
          'Reorder Failed',
          'An error occurred. Please try again.',
          true,
        );
      }
    }
  }
}
