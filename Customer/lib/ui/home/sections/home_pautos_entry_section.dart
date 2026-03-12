import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/login/LoginScreen.dart';
import 'package:foodie_customer/ui/pautos/create_pautos_request_screen.dart';
import 'package:foodie_customer/ui/pautos/my_pautos_screen.dart';

class HomePautosEntrySection extends StatelessWidget {
  const HomePautosEntrySection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isDarkMode(context)
          ? const Color(DARK_COLOR)
          : const Color(0xffFFFFFF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: InkWell(
          onTap: () {
            if (MyAppState.currentUser == null) {
              push(context, LoginScreen());
              return;
            }
            push(context, const CreatePautosRequestScreen());
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(COLOR_PRIMARY).withOpacity(0.15),
                  Color(COLOR_PRIMARY).withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Color(COLOR_PRIMARY).withOpacity(0.4),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Color(COLOR_PRIMARY).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.shopping_bag_outlined,
                    size: 28,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PAUTOS',
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode(context)
                              ? Colors.white
                              : const Color(0xFF000000),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Describe what you need, set a budget, and a rider will shop for you',
                        style: TextStyle(
                          fontFamily: 'Poppinsr',
                          fontSize: 12,
                          color: isDarkMode(context)
                              ? Colors.white70
                              : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () {
                          if (MyAppState.currentUser == null) {
                            push(context, LoginScreen());
                            return;
                          }
                          push(context, const MyPautosScreen());
                        },
                        child: Text(
                          'My PAUTOS',
                          style: TextStyle(
                            fontFamily: 'Poppinsm',
                            fontSize: 14,
                            color: Color(COLOR_PRIMARY),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Color(COLOR_PRIMARY),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
