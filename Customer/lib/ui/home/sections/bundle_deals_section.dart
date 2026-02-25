import 'package:flutter/material.dart';
import 'package:foodie_customer/model/bundle_model.dart';
import 'package:foodie_customer/services/bundle_service.dart';
import 'package:foodie_customer/ui/bundle/bundle_card.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class BundleDealsSection extends StatelessWidget {
  final Future<void> Function(BuildContext context, BundleModel bundle)?
      onAddToCart;

  const BundleDealsSection({
    super.key,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BundleModel>>(
      stream: BundleService.getActiveBundlesStream(limit: 20),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 320,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ShimmerWidgets.productListShimmer(),
            ),
          );
        }
        if (snapshot.hasError) {
          return HomeSectionUtils.sectionError(
            message: 'Failed to load bundle deals',
            onRetry: () {},
          );
        }
        final bundles = snapshot.data ?? [];
        if (bundles.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Bundle Deals',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SizedBox(
              height: 320,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 0, 16, 16),
                itemCount: bundles.length,
                itemBuilder: (context, index) {
                  final bundle = bundles[index];
                  return SizedBox(
                    width: 220,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: ClipRect(
                        child: SizedBox(
                          height: 318,
                          child: BundleCard(
                            bundle: bundle,
                            onAddToCart: onAddToCart == null
                                ? null
                                : () => onAddToCart!(context, bundle),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
