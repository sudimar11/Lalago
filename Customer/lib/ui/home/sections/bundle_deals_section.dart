import 'package:flutter/material.dart';
import 'package:foodie_customer/model/bundle_model.dart';
import 'package:foodie_customer/services/bundle_service.dart';
import 'package:foodie_customer/ui/bundle/bundle_card.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class BundleDealsSection extends StatefulWidget {
  final Future<void> Function(BuildContext context, BundleModel bundle)?
      onAddToCart;

  const BundleDealsSection({
    super.key,
    this.onAddToCart,
  });

  @override
  State<BundleDealsSection> createState() => _BundleDealsSectionState();
}

class _BundleDealsSectionState extends State<BundleDealsSection> {
  int _streamKey = 0;

  void _onRetry() {
    final delay = Duration(seconds: 1 << _streamKey.clamp(0, 2));
    _streamKey = (_streamKey + 1).clamp(0, 3);
    Future.delayed(delay, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BundleModel>>(
      key: ValueKey(_streamKey),
      stream: BundleService.getActiveBundlesStream(limit: 20),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  height: 24,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              SizedBox(
                height: 320,
                child: ShimmerWidgets.productListShimmer(),
              ),
            ],
          );
        }
        if (snapshot.hasError) {
          return HomeSectionUtils.sectionError(
            message: 'Failed to load bundle deals',
            onRetry: _onRetry,
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
                            onAddToCart: widget.onAddToCart == null
                                ? null
                                : () => widget.onAddToCart!(context, bundle),
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
