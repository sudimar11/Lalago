import 'package:flutter/material.dart';

/// Show dialog for selecting order preparation time
/// Separated from business logic for better organization
Future<String?> showOrderPreparationDialog(
  BuildContext context,
  List<String> timeOptions,
) async {
  return showDialog<String>(
    context: context,
    builder: (context) => _OrderPreparationDialog(
      timeOptions: timeOptions,
    ),
  );
}

/// Dialog widget for selecting order preparation time
class _OrderPreparationDialog extends StatefulWidget {
  final List<String> timeOptions;

  const _OrderPreparationDialog({
    required this.timeOptions,
  });

  @override
  State<_OrderPreparationDialog> createState() =>
      _OrderPreparationDialogState();
}

class _OrderPreparationDialogState extends State<_OrderPreparationDialog> {
  String? selectedTime;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Accept Order'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select estimated preparation time:'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.timeOptions.map((time) {
              final isSelected = selectedTime == time;
              return ChoiceChip(
                label: Text(time),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    selectedTime = selected ? time : null;
                  });
                },
                selectedColor: Colors.green,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : null,
                ),
              );
            }).toList(),
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
            Navigator.of(context).pop(selectedTime);
          },
          child: const Text('Accept'),
        ),
      ],
    );
  }
}
