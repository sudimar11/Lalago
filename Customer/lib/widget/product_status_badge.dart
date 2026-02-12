import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/services/helper.dart';

class ProductStatusBadge extends StatelessWidget {
  final ProductModel product;
  final double width;
  final double height;
  final List<ProductModel> allProducts;

  const ProductStatusBadge({
    Key? key,
    required this.product,
    required this.allProducts,
    this.width = 80,
    this.height = 80,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Check if status is "Order Rejected"
    if (product.status == "Order Rejected") {
      return _buildRecommendationGrid(context);
    }

    // Default Stack widget for normal status
    return Stack(
      children: [
        // Product Image Container
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: getImageVAlidUrl(product.photo),
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(COLOR_PRIMARY).withOpacity(0.1),
                      Color(COLOR_PRIMARY).withOpacity(0.05),
                    ],
                  ),
                ),
                child: Center(
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade200,
                ),
                child: Icon(
                  Icons.fastfood,
                  size: 30,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ),
        // "TOP SELLING" badge
        Positioned(
          top: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.green.shade400,
                  Colors.green.shade600,
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.trending_up,
                  size: 8,
                  color: Colors.white,
                ),
                const SizedBox(width: 1),
                Text(
                  'TOP',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Discount badge (if applicable)
        if (product.disPrice != "" && product.disPrice != "0")
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red.shade400,
                    Colors.red.shade600,
                  ],
                ),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                'SALE',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 6,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecommendationGrid(BuildContext context) {
    // Get 30 similar products based on search algorithm
    List<ProductModel> recommendations = _getSimilarProducts();
    
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.refresh,
                  size: 12,
                  color: Colors.red.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  'Try These Instead',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Grid of recommendations
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.0,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: recommendations.length > 30 ? 30 : recommendations.length,
              itemBuilder: (context, index) {
                final recommendedProduct = recommendations[index];
                return GestureDetector(
                  onTap: () {
                    // Handle product tap - you can add navigation logic here
                    print('Tapped on recommended product: ${recommendedProduct.name}');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl: getImageVAlidUrl(recommendedProduct.photo),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.fastfood,
                            size: 8,
                            color: Colors.grey.shade400,
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          child: Icon(
                            Icons.fastfood,
                            size: 8,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<ProductModel> _getSimilarProducts() {
    if (allProducts.isEmpty) return [];

    // Filter out the current product
    List<ProductModel> availableProducts = allProducts
        .where((p) => p.id != product.id)
        .toList();

    // Simple similarity algorithm based on:
    // 1. Same category
    // 2. Similar price range
    // 3. Same vendor (if available)
    // 4. Popular products (high reviews)

    List<ProductModel> similarProducts = [];

    // First priority: Same category
    similarProducts.addAll(availableProducts.where((p) => 
        p.categoryID == product.categoryID).toList());

    // Second priority: Same vendor
    similarProducts.addAll(availableProducts.where((p) => 
        p.vendorID == product.vendorID && !similarProducts.contains(p)).toList());

    // Third priority: Similar price range (±20%)
    double currentPrice = double.tryParse(product.price) ?? 0.0;
    if (currentPrice > 0) {
      double minPrice = currentPrice * 0.8;
      double maxPrice = currentPrice * 1.2;
      
      similarProducts.addAll(availableProducts.where((p) {
        double price = double.tryParse(p.price) ?? 0.0;
        return price >= minPrice && price <= maxPrice && !similarProducts.contains(p);
      }).toList());
    }

    // Fourth priority: Popular products (high reviews)
    similarProducts.addAll(availableProducts.where((p) {
      double rating = p.reviewsCount > 0 ? (p.reviewsSum / p.reviewsCount) : 0.0;
      return rating >= 4.0 && !similarProducts.contains(p);
    }).toList());

    // Fill remaining slots with random products
    List<ProductModel> remainingProducts = availableProducts
        .where((p) => !similarProducts.contains(p))
        .toList();
    remainingProducts.shuffle();
    similarProducts.addAll(remainingProducts);

    // Return first 30 products
    return similarProducts.take(30).toList();
  }
}
