import 'package:flutter/material.dart';

class CommonElevatedButton extends StatelessWidget {
  final VoidCallback? onButtonPressed;
  final String? text;
  final Color? backgroundColor;
  final Color? fontColor;
  final double? fontSize;
  final FontWeight? fontWeight;
  final BorderRadius? borderRadius;
  final BorderSide? borderSide;
  final Widget? custom;
  final double? height;
  final double? width;

  const CommonElevatedButton({
    Key? key,
    this.onButtonPressed,
    this.text,
    this.backgroundColor,
    this.fontColor,
    this.fontSize,
    this.fontWeight,
    this.borderRadius,
    this.borderSide,
    this.custom,
    this.height,
    this.width,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget buttonChild = custom ??
        (text != null
            ? Text(
                text!,
                style: TextStyle(
                  color: fontColor ?? Colors.white,
                  fontSize: fontSize ?? 16.0,
                  fontWeight: fontWeight ?? FontWeight.w600,
                ),
              )
            : const SizedBox.shrink());

    Widget button = ElevatedButton(
      onPressed: onButtonPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? Theme.of(context).primaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? BorderRadius.circular(8.0),
          side: borderSide ?? BorderSide.none,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 24.0),
        elevation: borderSide != null ? 0 : 2,
      ),
      child: buttonChild,
    );

    if (height != null || width != null) {
      return SizedBox(
        height: height,
        width: width,
        child: button,
      );
    }

    return button;
  }
}
