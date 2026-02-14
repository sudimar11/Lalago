import 'package:flutter/material.dart';
import 'package:foodie_customer/utils/extensions/context_extension.dart';

/// Placeholder that reserves space for Sign in with Apple while
/// [SignInWithApple.isAvailable()] is resolving. Prevents layout jump.
Widget buildAppleSignInPlaceholder(BuildContext context) {
  return SizedBox(
    height: 50.0,
    width: context.screenWidth,
  );
}
