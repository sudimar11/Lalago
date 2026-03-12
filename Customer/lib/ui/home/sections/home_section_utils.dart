import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';

/// Per-section error widget with message and tap-to-retry.
class SectionErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const SectionErrorWidget({
    Key? key,
    required this.message,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDarkMode(context)
              ? Colors.grey.shade800
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 32,
              color: isDarkMode(context)
                  ? Colors.white70
                  : Colors.grey.shade700,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode(context)
                    ? Colors.white70
                    : Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to retry',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(COLOR_PRIMARY),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeSectionUtils {
  static Widget sectionError({
    required String message,
    required VoidCallback onRetry,
  }) {
    return SectionErrorWidget(message: message, onRetry: onRetry);
  }

  static Widget buildTitleRow({
    required String titleValue,
    Function? onClick,
    bool isViewAll = false,
    IconData? titleIcon,
  }) {
    return Builder(
      builder: (context) {
        return Container(
          color: isDarkMode(context)
              ? const Color(DARK_COLOR)
              : const Color(0xffFFFFFF),
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (titleIcon != null) ...[
                        Icon(
                          titleIcon,
                          color: Color(COLOR_PRIMARY),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        titleValue,
                        style: TextStyle(
                          color: isDarkMode(context)
                              ? Colors.white
                              : const Color(0xFF000000),
                          fontFamily: "Poppinsm",
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  isViewAll
                      ? Container()
                      : GestureDetector(
                          onTap: () {
                            onClick?.call();
                          },
                          child: Text(
                            'View All',
                            style: TextStyle(
                              color: Color(COLOR_PRIMARY),
                              fontFamily: "Poppinsm",
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
