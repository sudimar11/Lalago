import 'package:flutter/material.dart';

/// Show dialog for selecting order rejection reason
/// Separated from business logic for better organization
Future<String?> showOrderRejectionDialog(
  BuildContext context,
  List<String> rejectionReasons,
) async {
  return showDialog<String>(
    context: context,
    builder: (context) => _OrderRejectionDialog(
      rejectionReasons: rejectionReasons,
    ),
  );
}

/// Dialog widget for selecting order rejection reason
class _OrderRejectionDialog extends StatefulWidget {
  final List<String> rejectionReasons;

  const _OrderRejectionDialog({
    required this.rejectionReasons,
  });

  @override
  State<_OrderRejectionDialog> createState() => _OrderRejectionDialogState();
}

class _OrderRejectionDialogState extends State<_OrderRejectionDialog> {
  String? selectedReason;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject Order'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Please select a reason for rejecting this order:'),
          const SizedBox(height: 16),
          DropdownButton<String>(
            value: selectedReason,
            hint: const Text('Choose reason'),
            isExpanded: true,
            items: widget.rejectionReasons.map((String reason) {
              return DropdownMenuItem<String>(
                value: reason,
                child: Text(reason),
              );
            }).toList(),
            onChanged: (String? value) {
              setState(() {
                selectedReason = value;
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(selectedReason);
          },
          child: const Text('Reject Order'),
        ),
      ],
    );
  }
}
