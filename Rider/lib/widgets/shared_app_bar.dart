import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/rider_preset_location_service.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/widgets/hours_online_widget.dart';
import 'package:foodie_driver/widgets/outside_service_area_timer_widget.dart';
import 'package:foodie_driver/ui/profile/IncentiveScreen.dart';
import 'package:foodie_driver/ui/communication/unified_communication_hub_screen.dart';
import 'package:foodie_driver/ui/ordersScreen/OrderHistoryScreen.dart';
import 'package:foodie_driver/services/unified_inbox_service.dart';

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
  final VoidCallback? onWorkAreaTap;

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
    this.onWorkAreaTap,
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
              _buildWorkAreaIndicator(context),
              _buildAttendanceChip(context),
              // Outside service area timer (when outside) or hours online
              if (isOutsideServiceArea && firstOutsideAt != null)
                OutsideServiceAreaTimerWidget(
                  firstOutsideAt: firstOutsideAt!,
                  penaltyThresholdMinutes: outsidePenaltyThresholdMinutes,
                )
              else
                HoursOnlineWidget(user: user),
              StreamBuilder<int>(
                stream: UnifiedInboxService.getTotalUnreadCountStream(
                  user.userID,
                ),
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const UnifiedCommunicationHubScreen(),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.chat_bubble_outline,
                          color: isDarkMode(context)
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                      if (unread > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
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

  Widget _buildWorkAreaIndicator(BuildContext context) {
    final hasValid = RiderPresetLocationService.hasValidWorkArea(user);
    final color = hasValid ? Colors.green : Colors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: InkWell(
        onTap: onWorkAreaTap,
        borderRadius: BorderRadius.circular(20),
        child: Tooltip(
          message: hasValid ? 'Work area selected' : 'No work area selected',
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDarkMode(context) ? Colors.white24 : Colors.black26,
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceChip(BuildContext context) {
    final isOnline = user.isOnline == true;

    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;
    final bool enabled;

    if (!isOnline) {
      bgColor = Colors.green;
      fgColor = Colors.white;
      icon = Icons.login;
      label = 'Online';
      enabled = true;
    } else {
      bgColor = Colors.blue;
      fgColor = Colors.white;
      icon = Icons.logout;
      label = 'Offline';
      enabled = true;
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
