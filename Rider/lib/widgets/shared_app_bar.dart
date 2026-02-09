import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/widgets/hours_online_widget.dart';
import 'package:foodie_driver/ui/profile/IncentiveScreen.dart';
import 'package:foodie_driver/ui/ordersScreen/OrderHistoryScreen.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final User user;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final bool showActions;

  const SharedAppBar({
    Key? key,
    required this.title,
    required this.user,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
    this.showActions = true,
  }) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      iconTheme: IconThemeData(
        color: isDarkMode(context) ? Colors.white : Colors.black,
      ),
      centerTitle: centerTitle,
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      title: Text(
        title,
        style: TextStyle(
          color: isDarkMode(context) ? Colors.white : Colors.black,
        ),
      ),
      actions: showActions
          ? [
              // Hours online
              HoursOnlineWidget(user: user),
              // Order history icon
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const OrderHistoryScreen(),
                    ),
                  );
                },
                icon: Icon(
                  Icons.receipt_long,
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
              // Incentive icon
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const IncentiveScreen(),
                    ),
                  );
                },
                icon: Icon(
                  Icons.card_giftcard,
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
            ]
          : null,
    );
  }
}
