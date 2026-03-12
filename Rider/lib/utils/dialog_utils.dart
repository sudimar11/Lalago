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

  /// Shows "Mark order as picked up?" when rider is at restaurant.
  /// Returns true if "Mark as picked up", false if "Not yet" or dismissed.
  static Future<bool> showMarkPickedUpDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
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
                    "You're at the restaurant",
                    style: TextStyle(
                      color: isDarkMode(context)
                          ? Colors.white
                          : Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'Mark order as picked up?',
              style: TextStyle(
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : Colors.grey.shade700,
                fontSize: 16,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Not yet',
                  style: TextStyle(
                    color: isDarkMode(context)
                        ? Colors.grey.shade400
                        : Colors.grey.shade700,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Mark as picked up'),
              ),
            ],
          ),
        );
      },
    );
    return result ?? false;
  }

  /// Result of far-pickup confirmation: confirmed and dontShowAgain checkbox.
  static Future<({bool confirmed, bool dontShowAgain})?>
      showConfirmPickupWhenFarDialog(
    BuildContext context, {
    required int distanceMeters,
  }) async {
    bool dontShowAgain = false;
    final result = await showDialog<(bool, bool)>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: isDarkMode(context)
                    ? Color(DARK_VIEWBG_COLOR)
                    : Colors.white,
                title: const Text('Confirm Pickup'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distanceMeters <= 0
                          ? 'Distance could not be determined. Are you sure '
                              'you want to mark this order as picked up?'
                          : 'You are still $distanceMeters meters away from the '
                              'restaurant. Are you sure you want to mark this '
                              'order as picked up?',
                      style: TextStyle(
                        color: isDarkMode(context)
                            ? Colors.grey.shade300
                            : Colors.grey.shade700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: dontShowAgain,
                      onChanged: (v) =>
                          setState(() => dontShowAgain = v ?? false),
                      title: Text(
                        "Don't show this warning again",
                        style: TextStyle(
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop((false, false)),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDarkMode(context)
                            ? Colors.grey.shade400
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop((true, dontShowAgain)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Confirm Pickup'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (result == null) return null;
    return (confirmed: result.$1, dontShowAgain: result.$2);
  }
}
