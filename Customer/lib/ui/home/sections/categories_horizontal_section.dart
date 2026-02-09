import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/widget/category_card.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';

class CategoriesHorizontalSection extends StatelessWidget {
  final Future<List<VendorCategoryModel>> categoriesFuture;

  const CategoriesHorizontalSection({
    Key? key,
    required this.categoriesFuture,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDarkMode(context)
          ? const Color(DARK_COLOR)
          : const Color(0xffFFFFFF),
      child: FutureBuilder<List<VendorCategoryModel>>(
        future: categoriesFuture,
        initialData: const [],
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              padding: const EdgeInsets.only(
                left: 10,
                bottom: 0,
              ),
              height: 100,
              child: ShimmerWidgets.categoryListShimmer(),
            );
          }

          if ((snapshot.hasData || (snapshot.data?.isNotEmpty ?? false)) &&
              context.mounted) {
            return Container(
              padding: const EdgeInsets.only(
                left: 10,
                bottom: 0,
              ),
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount:
                    snapshot.data!.length >= 15 ? 15 : snapshot.data!.length,
                itemBuilder: (context, index) {
                  return CategoryCard(
                    model: snapshot.data![index],
                    isDineIn: false,
                  );
                },
              ),
            );
          } else {
            return showEmptyState('No Categories', context);
          }
        },
      ),
    );
  }
}
