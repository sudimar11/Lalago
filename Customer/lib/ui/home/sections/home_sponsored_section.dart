import 'package:flutter/material.dart';
import 'package:foodie_customer/ui/home/sections/home_section_utils.dart';
import 'package:foodie_customer/widgets/native_ad_restaurant_card.dart';

class HomeSponsoredSection extends StatelessWidget {
  const HomeSponsoredSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionUtils.buildTitleRow(
          titleValue: 'Sponsored',
          isViewAll: false,
        ),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            cacheExtent: 400,
            children: const [
              NativeAdRestaurantCard(),
            ],
          ),
        ),
      ],
    );
  }
}
