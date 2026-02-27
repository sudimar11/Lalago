import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/services/localDatabase.dart';

/// Handles adding products to cart and retrieving cart summary for AI tools.
class AiCartService {
  AiCartService({required this.cartDatabase});

  final CartDatabase cartDatabase;

  /// Adds a product to the cart by ID. If cart has items from another vendor,
  /// clears the cart first (matches ProductDetailsScreen behavior).
  Future<Map<String, dynamic>> addProductById(
    String productId,
    int quantity,
  ) async {
    if (productId.trim().isEmpty || quantity < 1) {
      return {'success': false, 'error': 'Invalid product or quantity'};
    }

    try {
      ProductModel? productModel = await _getProductByProductId(productId);
      if (productModel == null || productModel.id.isEmpty) {
        return {'success': false, 'error': 'Product not found or not available'};
      }

      final cartProducts = await cartDatabase.allCartProducts;

      if (cartProducts.isNotEmpty &&
          cartProducts.first.vendorID != productModel.vendorID) {
        await cartDatabase.deleteAllProducts();
      }

      for (var i = 0; i < quantity; i++) {
        cartDatabase.addProduct(
          productModel,
          cartDatabase,
          true,
        );
      }

      return {
        'success': true,
        'product': productModel.name,
        'quantity': quantity,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Returns cart items and subtotal.
  Future<Map<String, dynamic>> getCartSummary() async {
    try {
      final products = await cartDatabase.allCartProducts;
      double subtotal = 0.0;
      final items = <Map<String, dynamic>>[];

      for (final p in products) {
        final price = double.tryParse(p.price) ?? 0.0;
        final lineTotal = price * p.quantity;
        subtotal += lineTotal;
        items.add({
          'id': p.id,
          'name': p.name,
          'price': p.price,
          'quantity': p.quantity,
          'vendorID': p.vendorID,
        });
      }

      return {'items': items, 'subtotal': subtotal};
    } catch (e) {
      return {'items': <Map<String, dynamic>>[], 'subtotal': 0.0, 'error': '$e'};
    }
  }

  Future<ProductModel?> _getProductByProductId(String productId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(PRODUCTS)
          .where('id', isEqualTo: productId)
          .where('publish', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final data = Map<String, dynamic>.from(snapshot.docs.first.data());
      if (!data.containsKey('id') || data['id'] == null) {
        data['id'] = snapshot.docs.first.id;
      }
      return ProductModel.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
