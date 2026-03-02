import 'package:flutter/material.dart';

/// Ash avatar widget for consistent visual branding across the app.
class AshAvatar extends StatelessWidget {
  final double radius;
  final bool showGlow;
  final VoidCallback? onTap;

  const AshAvatar({
    super.key,
    this.radius = 20,
    this.showGlow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.orange.shade400,
              Colors.orange.shade600,
            ],
          ),
          boxShadow: showGlow
              ? [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Icon(
          Icons.smart_toy,
          color: Colors.white,
          size: radius * 1.2,
        ),
      ),
    );
  }
}
