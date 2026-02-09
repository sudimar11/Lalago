import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';

class HomeSectionUtils {
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
