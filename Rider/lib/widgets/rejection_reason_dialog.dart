import 'package:flutter/material.dart';

/// Rejection reason codes stored in Firestore
const List<Map<String, String>> rejectionReasons = [
  {'code': 'too_far', 'label': 'Too far away'},
  {'code': 'wrong_direction', 'label': 'Heading wrong direction'},
  {'code': 'taking_break', 'label': 'About to take a break'},
  {'code': 'restaurant_closed', 'label': 'Restaurant closed'},
  {'code': 'emergency', 'label': "Emergency / Can't deliver"},
  {'code': 'other', 'label': 'Other'},
];

/// Shows a dialog for the rider to select a rejection reason.
/// Returns the selected reason code, or null if dismissed.
Future<String?> showRejectionReasonDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Why are you rejecting?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: rejectionReasons
              .map(
                (r) => ListTile(
                  title: Text(r['label']!),
                  onTap: () => Navigator.pop(context, r['code']),
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
