import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/widgets/order_recovery_card.dart';
import 'package:foodie_customer/ui/home/HomeScreen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';

class OrderRecoveryScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const OrderRecoveryScreen({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Recovery'),
        backgroundColor: Color(COLOR_PRIMARY),
      ),
      body: SingleChildScrollView(
        child: OrderRecoveryCard(
          notificationData: {
            'title': data['title'] ?? 'Order Issue',
            'body': data['body'] ?? '',
            'data': data,
            'subtype': data['failureType'] ?? 'unknown',
          },
          onRecover: () => _onTryAlternatives(context),
          onDismiss: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _onTryAlternatives(BuildContext context) async {
    final alternativesStr = data['alternatives'] as String?;
    if (alternativesStr == null || alternativesStr.isEmpty) {
      _navigateToHome(context);
      return;
    }

    try {
      final alternatives = jsonDecode(alternativesStr) as Map<String, dynamic>?;
      if (alternatives == null) {
        _navigateToHome(context);
        return;
      }

      final similarRestaurants = alternatives['similarRestaurants'] as List?;
      if (similarRestaurants != null && similarRestaurants.isNotEmpty) {
        final first = similarRestaurants[0] as Map<String, dynamic>?;
        final vendorId = first?['id'] as String?;
        if (vendorId != null) {
          final vendor = await FireStoreUtils.getVendor(vendorId);
          if (vendor != null && context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ContainerScreen(
                  user: MyAppState.currentUser,
                  currentWidget: NewVendorProductsScreen(
                    vendorModel: vendor,
                    showReorderBanner: false,
                  ),
                ),
              ),
              (r) => false,
            );
            return;
          }
        }
      }

      final similarProducts = alternatives['similarProducts'] as List?;
      if (similarProducts != null && similarProducts.isNotEmpty) {
        final first = similarProducts[0] as Map<String, dynamic>?;
        final productId = first?['id'] as String?;
        final vendorId = first?['vendorId'] as String?;
        if (productId != null && vendorId != null) {
          final vendor = await FireStoreUtils.getVendor(vendorId);
          if (vendor != null) {
            final doc = await FireStoreUtils.firestore
                .collection(PRODUCTS)
                .doc(productId)
                .get();
            if (doc.exists && doc.data() != null) {
              final d = Map<String, dynamic>.from(doc.data()!);
              d['id'] = doc.id;
              final product = ProductModel.fromJson(d);
              if (context.mounted) {
                push(
                  context,
                  ProductDetailsScreen(
                    productModel: product,
                    vendorModel: vendor,
                  ),
                );
                Navigator.of(context).pop();
                return;
              }
            }
          }
        }
      }

      final sameRestaurant = alternatives['sameRestaurant'] as List?;
      if (sameRestaurant != null && sameRestaurant.isNotEmpty) {
        final first = sameRestaurant[0] as Map<String, dynamic>?;
        final vendorId = first?['vendorId'] as String?;
        if (vendorId != null) {
          final vendor = await FireStoreUtils.getVendor(vendorId);
          if (vendor != null && context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => ContainerScreen(
                  user: MyAppState.currentUser,
                  currentWidget: NewVendorProductsScreen(
                    vendorModel: vendor,
                    showReorderBanner: false,
                  ),
                ),
              ),
              (r) => false,
            );
            return;
          }
        }
      }

      _navigateToHome(context);
    } catch (_) {
      _navigateToHome(context);
    }
  }

  void _navigateToHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ContainerScreen(
          user: MyAppState.currentUser,
          currentWidget: HomeScreen(),
        ),
      ),
      (r) => false,
    );
  }
}
