import 'package:flutter/material.dart';

extension ContextExtension on BuildContext {
  void dismissKeyboard() {
    FocusScope.of(this).unfocus();
  }

  double get screenWidth => MediaQuery.of(this).size.width;
  double get screenHeight => MediaQuery.of(this).size.height;
}
