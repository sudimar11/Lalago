import 'package:flutter/material.dart';

// Custom ShapeBorder for curved AppBar
class CurvedAppBarShape extends ShapeBorder {
  final double curveHeight;
  final double curveRadius;

  const CurvedAppBarShape({
    this.curveHeight = 20.0,
    this.curveRadius = 15.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return getOuterPath(rect, textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();

    // Start from top-left
    path.moveTo(rect.left, rect.top);

    // Top edge (flat)
    path.lineTo(rect.right, rect.top);

    // Right edge
    path.lineTo(rect.right, rect.bottom - curveHeight);

    // Bottom-right curve (concave - curves upward)
    path.quadraticBezierTo(
      rect.right - curveRadius,
      rect.bottom - curveHeight * 0.3, // Control point curves upward
      rect.right - curveRadius * 2,
      rect.bottom - curveHeight,
    );

    // Bottom center curve (concave - curves upward toward center)
    path.quadraticBezierTo(
      rect.center.dx,
      rect.bottom -
          curveHeight * 0.8, // Control point curves significantly upward
      rect.left + curveRadius * 2,
      rect.bottom - curveHeight,
    );

    // Bottom-left curve (concave - curves upward)
    path.quadraticBezierTo(
      rect.left + curveRadius,
      rect.bottom - curveHeight * 0.3, // Control point curves upward
      rect.left,
      rect.bottom - curveHeight,
    );

    // Left edge
    path.lineTo(rect.left, rect.top);

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // This is handled by the AppBar's background
  }

  @override
  ShapeBorder scale(double t) {
    return CurvedAppBarShape(
      curveHeight: curveHeight * t,
      curveRadius: curveRadius * t,
    );
  }
}
