import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/VendorCategoryModel.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/categoryDetailsScreen/CategoryDetailsScreen.dart';
import 'package:foodie_customer/ui/cuisinesScreen/CuisinesScreen.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/widget/category_card.dart';

class HomeCategoriesSection extends StatelessWidget {
  final FireStoreUtils fireStoreUtils;

  const HomeCategoriesSection({
    Key? key,
    required this.fireStoreUtils,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "Categories",
          onClick: () {
            push(
              context,
              const CuisinesScreen(
                isPageCallFromHomeScreen: true,
              ),
            );
          },
          isViewAll: false,
        ),
        Container(
          color: isDarkMode(context)
              ? const Color(DARK_COLOR)
              : const Color(0xffFFFFFF),
          child: FutureBuilder<List<VendorCategoryModel>>(
            future: fireStoreUtils.getCuisines(),
            initialData: const [],
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator.adaptive(
                    valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                  ),
                );
              }

              if (snapshot.hasData && (snapshot.data?.isNotEmpty ?? false)) {
                return Container(
                  padding: const EdgeInsets.only(left: 10),
                  height: 150,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: snapshot.data!.length >= 15
                        ? 15
                        : snapshot.data!.length,
                    itemBuilder: (context, index) {
                      return buildCategoryItem(
                        context,
                        snapshot.data![index],
                      );
                    },
                  ),
                );
              } else {
                return showEmptyState('No Categories', context);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget buildCategoryItem(
    BuildContext context,
    VendorCategoryModel model,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GestureDetector(
        onTap: () {
          push(
            context,
            CategoryDetailsScreen(
              category: model,
              isDineIn: false,
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryCard(
              model: model,
              isDineIn: false,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Text(
                  model.title.toString(),
                  style: TextStyle(
                    color: isDarkMode(context)
                        ? Colors.white
                        : const Color(0xFF000000),
                    fontFamily: "Poppinsr",
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


