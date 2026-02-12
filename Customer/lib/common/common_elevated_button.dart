import 'package:flutter/material.dart';
import '../resources/colors.dart';

class CommonElevatedButton extends ElevatedButton {
  CommonElevatedButton({
    super.key,
    this.onButtonPressed,
    this.text,
    this.custom,
    this.isLoading,
    this.fontColor = Colors.white,
    this.fontWeight = FontWeight.w600,
    this.fontSize = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
    this.elevation = 8,
    this.borderSide = BorderSide.none,
    this.padding,
    this.backgroundColor = CustomColors.primary,
    this.shadowColor = Colors.transparent,
    this.overlayColor = Colors.black45,
    this.shape,
    this.fontFamily = "Poppinsr"
  })  : assert(text != null || custom != null),
        super(
    onPressed: (isLoading ?? false) ? null : onButtonPressed,
    child: (isLoading ?? false)
        ? const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: CustomColors.primary
          ),
        )
        : (text != null)
            ? Text(
                text,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: fontWeight,
                  color: fontColor,
                  fontFamily: fontFamily
                ),
              )
            : custom,
    style: ElevatedButton.styleFrom(
      shadowColor: shadowColor,
      backgroundColor:
          (isLoading ?? false) ? CustomColors.gray : backgroundColor,
      overlayColor: overlayColor,
      elevation: elevation,
      shape: shape ??
          RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: borderSide,
          ),
      padding: padding,
      disabledBackgroundColor: CustomColors.lightGray300,
    ),
  );

  final VoidCallback? onButtonPressed;
  final String? text;
  final Widget? custom;
  final bool? isLoading;
  final Color fontColor;
  final Color backgroundColor;
  final Color shadowColor;
  final Color overlayColor;
  final FontWeight fontWeight;
  final double fontSize;
  final BorderRadiusGeometry borderRadius;
  final BorderSide borderSide;
  final double elevation;
  final EdgeInsetsGeometry? padding;
  final OutlinedBorder? shape;
  final String fontFamily;
}
