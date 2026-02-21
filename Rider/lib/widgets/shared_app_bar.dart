import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/widgets/hours_online_widget.dart';
import 'package:foodie_driver/widgets/outside_service_area_timer_widget.dart';
import 'package:foodie_driver/ui/profile/IncentiveScreen.dart';
import 'package:foodie_driver/ui/ordersScreen/OrderHistoryScreen.dart';

class SharedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final User user;
  final bool automaticallyImplyLeading;
  final bool centerTitle;
  final bool showActions;
  final bool isOutsideServiceArea;
  final DateTime? firstOutsideAt;
  final int outsidePenaltyThresholdMinutes;
  final VoidCallback? onToggleAttendance;

  const SharedAppBar({
    Key? key,
    required this.title,
    required this.user,
    this.automaticallyImplyLeading = true,
    this.centerTitle = false,
    this.showActions = true,
    this.isOutsideServiceArea = false,
    this.firstOutsideAt,
    this.outsidePenaltyThresholdMinutes = 30,
    this.onToggleAttendance,
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
              _buildAttendanceChip(context),
              // Outside service area timer (when outside) or hours online
              if (isOutsideServiceArea && firstOutsideAt != null)
                OutsideServiceAreaTimerWidget(
                  firstOutsideAt: firstOutsideAt!,
                  penaltyThresholdMinutes: outsidePenaltyThresholdMinutes,
                )
              else
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

  Widget _buildAttendanceChip(BuildContext context) {
    final isCheckedIn = user.checkedInToday == true;
    final isCheckedOut = user.checkedOutToday == true;

    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;
    final bool enabled;

    if (!isCheckedIn) {
      bgColor = Colors.green;
      fgColor = Colors.white;
      icon = Icons.login;
      label = 'In';
      enabled = true;
    } else if (!isCheckedOut) {
      bgColor = Colors.blue;
      fgColor = Colors.white;
      icon = Icons.logout;
      label = 'Out';
      enabled = true;
    } else {
      bgColor = Colors.grey.shade400;
      fgColor = Colors.white;
      icon = Icons.check;
      label = 'Done';
      enabled = false;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: InkWell(
        onTap: enabled ? onToggleAttendance : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fgColor, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
