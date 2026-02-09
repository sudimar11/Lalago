import 'package:flutter/material.dart';

class CurvedAppBarClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final curveHeight = 20.0;

    // Start from top-left corner
    path.moveTo(0, 0);

    // Go to top-right corner (flat top edge)
    path.lineTo(size.width, 0);

    // Go to bottom-right corner
    path.lineTo(size.width, size.height - curveHeight);

    // Bottom-right curve (concave - curves upward)
    path.quadraticBezierTo(
      size.width * 0.8, // Control point x (80% of width)
      size.height - curveHeight * 0.3, // Control point y (curves upward)
      size.width * 0.6, // End point x (60% of width)
      size.height - curveHeight, // End point y
    );

    // Bottom center curve (concave - curves upward toward center)
    path.quadraticBezierTo(
      size.width * 0.4, // Control point x (40% of width)
      size.height - curveHeight * 0.8, // Control point y (curves significantly upward)
      size.width * 0.2, // End point x (20% of width)
      size.height - curveHeight, // End point y
    );

    // Bottom-left curve (concave - curves upward)
    path.quadraticBezierTo(
      size.width * 0.0, // Control point x (0% of width)
      size.height - curveHeight * 0.3, // Control point y (curves upward)
      0, // End point x (left edge)
      size.height - curveHeight, // End point y
    );

    // Close the path by going back to start
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

