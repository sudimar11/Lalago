import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/widget/curved_appbar_clipper.dart';

class CurvedAppBar extends StatelessWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final double height;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onActionTap;

  const CurvedAppBar({
    Key? key,
    required this.title,
    this.leading,
    this.actions,
    this.backgroundColor,
    this.height = 240.0,
    this.onLeadingTap,
    this.onActionTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final primaryColor = backgroundColor ?? Color(COLOR_PRIMARY);

    return ClipPath(
      clipper: CurvedAppBarClipper(),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primaryColor,
              primaryColor.withOpacity(0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                // Leading widget (hamburger menu)
                if (leading != null)
                  GestureDetector(
                    onTap: onLeadingTap,
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      child: leading,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onLeadingTap,
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.menu,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),

                // Title
                Expanded(
                  child: Center(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppinssb',
                      ),
                    ),
                  ),
                ),

                // Actions
                if (actions != null && actions!.isNotEmpty)
                  Row(
                    children: actions!.map((action) {
                      return GestureDetector(
                        onTap: onActionTap,
                        child: Container(
                          padding: const EdgeInsets.all(8.0),
                          child: action,
                        ),
                      );
                    }).toList(),
                  )
                else
                  GestureDetector(
                    onTap: onActionTap,
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.search,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
