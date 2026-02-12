import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';

class SharedBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool isDisabled;

  const SharedBottomNavigationBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.isDisabled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: isDisabled,
      child: Opacity(
        opacity: isDisabled ? 0.5 : 1.0,
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: currentIndex,
          onTap: isDisabled ? (_) {} : onTap,
          backgroundColor: Colors.black,
          selectedItemColor: isDisabled ? Colors.grey : Color(COLOR_PRIMARY),
          unselectedItemColor: Colors.grey,
          selectedLabelStyle: const TextStyle(fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.receipt_long),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.account_balance_wallet_sharp),
              label: 'Wallet',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.local_fire_department),
              label: 'Hotspots',
            ),
            BottomNavigationBarItem(
              icon: const Icon(CupertinoIcons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
