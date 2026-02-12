import 'package:foodie_customer/model/ProductModel.dart';

class MealForOneService {
  static const double sulitCap = 150.0; // Price cap for sulit meals (in pesos)

  /// Fetch meal for one products (sulit price)
  /// Filters products based on price cap and solo meal indicators
  static Future<List<ProductModel>> fetchMealForOneProducts(
      List<ProductModel> allProducts) async {
    try {
      List<ProductModel> mealForOneList = [];

      for (ProductModel product in allProducts) {
        // Check if product price is within sulit cap
        double productPrice = double.tryParse(product.price) ?? 0.0;
        if (productPrice <= sulitCap && productPrice > 0) {
          // Check for solo indicators in name, description, or tags
          String productName = product.name.toLowerCase();
          String productDesc = product.description.toLowerCase();

          // Keywords that indicate solo/individual meals
          List<String> soloKeywords = [
            'solo',
            'single',
            'individual',
            'one',
            '1',
            'personal',
            'meal',
            'combo',
            'set',
            'plate',
            'serving',
            'portion'
          ];

          bool isSoloMeal = soloKeywords.any((keyword) =>
              productName.contains(keyword) || productDesc.contains(keyword));

          // Also check if the product name suggests it's for one person
          if (isSoloMeal ||
              productName.contains('meal') ||
              productName.contains('combo')) {
            mealForOneList.add(product);
          }
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

