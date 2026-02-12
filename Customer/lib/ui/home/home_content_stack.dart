import 'package:flutter/material.dart';
import 'package:foodie_customer/ui/home/current_orders_banner.dart';
import 'package:foodie_customer/widget/happy_hour_banner.dart';

class HomeContentStack extends StatelessWidget {
  final Widget homeContent;

  const HomeContentStack({
    Key? key,
    required this.homeContent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main home content
        homeContent,

        // Happy Hour banner positioned at bottom (same position as order status banner)
        // Only one banner will show at a time as both have internal visibility logic
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: const HappyHourBanner(),
        ),

        // Order status banner positioned at bottom (takes priority when active)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: const CurrentOrdersBanner(),
        ),
      ],
    );
  }
}
