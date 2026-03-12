import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/bundle_model.dart';
import 'package:foodie_customer/resources/colors.dart';

class BundleCard extends StatelessWidget {
  final BundleModel bundle;
  final VoidCallback? onAddToCart;
  final bool isUnavailable;

  const BundleCard({
    super.key,
    required this.bundle,
    this.onAddToCart,
    this.isUnavailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = bundle.imageUrl;
    final savingsText = bundle.savingsAmount >= 1
        ? 'Save ₱${bundle.savingsAmount.toStringAsFixed(0)}!'
        : (bundle.savingsPercentage >= 1
            ? '${bundle.savingsPercentage.toStringAsFixed(0)}% off'
            : null);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                height: 140,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 140,
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 140,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.restaurant, size: 48),
                ),
              ),
            )
          else
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: const Icon(Icons.inventory_2, size: 48),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            bundle.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (savingsText != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: CustomColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              savingsText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: CustomColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (bundle.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bundle.description,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    ...bundle.items.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 18,
                              color: Colors.green.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${e.productName} × ${e.quantity}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (bundle.regularPrice > bundle.bundlePrice)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              '₱${bundle.regularPrice.toStringAsFixed(2)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        Text(
                          '₱${bundle.bundlePrice.toStringAsFixed(2)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: CustomColors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (onAddToCart != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isUnavailable ? null : onAddToCart,
                          icon: const Icon(Icons.add_shopping_cart, size: 20),
                          label: Text(
                            isUnavailable ? 'Unavailable' : 'Add to Cart',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: CustomColors.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
