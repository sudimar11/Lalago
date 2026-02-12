import 'package:flutter/material.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/auth/AuthScreen.dart';

class AuthGuard {
  /// Shows login dialog if user is not authenticated
  /// Returns true if user is logged in, false otherwise
  static bool requiresLogin(BuildContext context, {String? message}) {
    if (MyAppState.currentUser == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Login Required'),
          content: Text(message ?? 'Please login to continue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                push(context, AuthScreen());
              },
              child: Text('Login'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }
  
  /// Returns a placeholder widget for guest users
  static Widget buildGuestPlaceholder({
    required String message,
    required VoidCallback onLoginPressed,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text(message, style: TextStyle(fontSize: 18)),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: onLoginPressed,
            child: Text('Login / Register'),
          ),
        ],
      ),
    );
  }
}
