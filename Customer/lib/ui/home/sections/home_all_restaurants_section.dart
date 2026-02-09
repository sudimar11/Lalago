import 'package:flutter/material.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/widget/lazy_loading_widget.dart';

class HomeAllRestaurantsSection extends StatelessWidget {
  final String orderType;

  const HomeAllRestaurantsSection({
    Key? key,
    required this.orderType,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: "All Restaurants",
          onClick: () {},
          isViewAll: true,
        ),
        LazyLoadingRestaurantList(
          orderType: orderType,
          builder: (restaurants, isLoading, hasMore) {
            return Container();
          },
        ),
      ],
    );
  }
}
