import 'package:foodie_customer/model/ProductModel.dart';

class MealForOneService {
  static const double sulitCap = 150.0; // Price cap for sulit meals (in pesos)

  /// Fetch meal for one products (sulit price)
  /// Filters products based on price cap only
  static Future<List<ProductModel>> fetchMealForOneProducts(
      List<ProductModel> allProducts) async {
    try {
      List<ProductModel> mealForOneList = [];

      for (ProductModel product in allProducts) {
        double productPrice = double.tryParse(product.price) ?? 0.0;
        if (productPrice <= sulitCap && productPrice > 0) {
          mealForOneList.add(product);
        }
      }

      // Remove duplicates and shuffle for variety
      mealForOneList = mealForOneList.toSet().toList();
      mealForOneList
          .shuffle(); // Randomize to show different products each time
      mealForOneList = mealForOneList.take(10).toList();

      return mealForOneList;
    } catch (e) {
      print('Error fetching meal for one products: $e');
      return [];
    }
  }

  /// Check if a product price is within sulit cap
  static bool isWithinSulitCap(String price) {
    double productPrice = double.tryParse(price) ?? 0.0;
    return productPrice > 0 && productPrice <= sulitCap;
  }
}

