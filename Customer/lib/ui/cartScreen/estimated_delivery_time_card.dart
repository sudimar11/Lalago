import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';

class EstimatedDeliveryTimeCard extends StatelessWidget {
  final String? deliveryTime;

  const EstimatedDeliveryTimeCard({
    Key? key,
    this.deliveryTime,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 13, top: 13, right: 13, bottom: 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDarkMode(context)
              ? const Color(DarkContainerBorderColor)
              : Colors.grey.shade100,
          width: 1,
        ),
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
            : Colors.white,
        boxShadow: [
          isDarkMode(context)
              ? const BoxShadow()
              : BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.5),
                  blurRadius: 5,
                ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              color: Color(COLOR_PRIMARY),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    'Estimated Delivery Time: ',
                    style: TextStyle(
                      fontFamily: 'Poppinsm',
                      fontSize: 14,
                      color:
                          isDarkMode(context) ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    deliveryTime ?? '30 - 45 minutes',
                    style: TextStyle(
                      fontFamily: 'Poppinsr',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(COLOR_PRIMARY),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
