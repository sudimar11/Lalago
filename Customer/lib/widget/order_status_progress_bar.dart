import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/utils/order_status_messages.dart';

/// Reusable progress bar showing order status message, percentage, and a
/// gray bar with colored fill for the current progress.
class OrderStatusProgressBar extends StatelessWidget {
  const OrderStatusProgressBar({Key? key, required this.status})
      : super(key: key);

  final String status;

  @override
  Widget build(BuildContext context) {
    final String message = getStatusMessage(status);
    final int percentage = getProgressPercentage(status);
    final bool dark = isDarkMode(context);
    final Color textColor = dark ? Colors.white70 : const Color(0xFF666666);
    final Color grayBg = dark ? Colors.grey.shade700 : Colors.grey.shade300;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  fontSize: 12,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$percentage%',
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double width = constraints.maxWidth;
            final double fillWidth =
                (percentage / 100).clamp(0.0, 1.0) * width;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 7,
                  width: width,
                  decoration: BoxDecoration(
                    color: grayBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  height: 7,
                  width: fillWidth,
                  decoration: BoxDecoration(
                    color: Color(COLOR_PRIMARY),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
