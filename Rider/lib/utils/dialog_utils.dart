import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';

/// Utility class for common dialog operations
class DialogUtils {
  /// Shows an alert dialog with title, content, and OK button
  static Future<void> showAlertDialog(
    BuildContext context, {
    required String title,
    required String content,
    String buttonText = 'OK',
  }) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(buttonText),
            )
          ],
        );
      },
    );
  }

  /// Shows a snackbar with message and background color
  static void showSnackBar(
    BuildContext context, {
    required String message,
    Color backgroundColor = Colors.green,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  /// Shows restaurant arrival confirmation dialog
  /// Returns true if user confirmed, false otherwise
  static Future<bool> showRestaurantArrivalDialog(
    BuildContext context,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Prevent back button dismissal
          child: AlertDialog(
            backgroundColor: isDarkMode(context)
                ? Color(DARK_VIEWBG_COLOR)
                : Colors.white,
            title: Row(
              children: [
                Icon(
                  Icons.restaurant,
                  color: Color(COLOR_PRIMARY),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Arrival Confirmation',
                    style: TextStyle(
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'Have you arrived at the restaurant?',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade700,
                fontSize: 16,
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }
}
