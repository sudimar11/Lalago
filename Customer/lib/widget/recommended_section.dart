import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/widget/recommended_card.dart';

class RecommendedSection extends StatelessWidget {
  final List<ProductModel> recommendedProducts;
  final List<VendorModel> vendors;

  const RecommendedSection({
    Key? key,
    required this.recommendedProducts,
    required this.vendors,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<ProductModel> displayProducts = recommendedProducts
        .where((product) => _hasPhoto(product.photo))
        .toList();
    // #region agent log
    try {
      File('/Users/sudimard/Downloads/Lalago/.cursor/debug.log')
          .writeAsStringSync(
        '${jsonEncode({"location":"RecommendedSection.build","message":"Recommended display","data":{"recommendedProductsCount":recommendedProducts.length,"displayProductsCount":displayProducts.length,"vendorsCount":vendors.length},"hypothesisId":"E","timestamp":DateTime.now().millisecondsSinceEpoch})}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    // #endregion
    if (displayProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        // Header with icon and subtitle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(COLOR_PRIMARY).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.recommend,
                  size: 20,
                  color: Color(COLOR_PRIMARY),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommended for You',
                      style: TextStyle(
                        fontFamily: 'Poppinsb',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Based on your preferences',
                      style: TextStyle(
                        fontFamily: 'Poppinsr',
                        fontSize: 12,
                        color: isDarkMode(context)
                            ? Colors.white60
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Horizontal scroll list
        Container(
          width: MediaQuery.of(context).size.width,
          height: 220,
          margin: const EdgeInsets.fromLTRB(10, 0, 0, 10),
          child: RepaintBoundary(
            child: ListView.builder(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 300.0,
              itemCount: displayProducts.length >= 10
                  ? 10
                  : displayProducts.length,
              itemBuilder: (context, index) {
              ProductModel product = displayProducts[index];
              VendorModel? vendorModel;
              for (VendorModel vendor in vendors) {
                if (vendor.id == product.vendorID) {
                  vendorModel = vendor;
                  break;
                }
              }
              if (vendorModel == null) {
                return Container();
              }
              return RecommendedCard(
                product: product,
                vendor: vendorModel,
              );
            },
            ),
          ),
        ),
      ],
    );
  }

  bool _hasPhoto(String photo) {
    final String trimmed = photo.trim();
    return trimmed.isNotEmpty && trimmed.toLowerCase() != 'null';
  }
}
