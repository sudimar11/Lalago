import 'package:flutter/material.dart';

/// Show dialog for selecting a different driver for an order
/// Displays list of all available drivers with their status
Future<Map<String, dynamic>?> showChangeDriverDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> drivers,
  required String currentDriverId,
}) async {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => _ChangeDriverDialog(
      drivers: drivers,
      currentDriverId: currentDriverId,
    ),
  );
}

/// Dialog widget for selecting a driver
class _ChangeDriverDialog extends StatelessWidget {
  final List<Map<String, dynamic>> drivers;
  final String currentDriverId;

  const _ChangeDriverDialog({
    required this.drivers,
    required this.currentDriverId,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Driver'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: drivers.length,
          itemBuilder: (context, index) {
            final driver = drivers[index];
            final driverId = driver['id'] as String;
            final firstName = driver['firstName'] as String;
            final lastName = driver['lastName'] as String;
            final driverName = '$firstName $lastName'.trim();
            final displayName =
                driverName.isEmpty ? 'Unknown Driver' : driverName;
            final driverPhone = driver['phoneNumber'] as String;
            final isActive = driver['isActive'] as bool;
            final isCurrent = driverId == currentDriverId;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isCurrent
                    ? Colors.purple
                    : (isActive ? Colors.green : Colors.grey),
                child: Icon(
                  isCurrent
                      ? Icons.person
                      : (isActive ? Icons.check : Icons.person_off),
                  color: Colors.white,
                ),
              ),
              title: Text(
                displayName,
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (driverPhone.isNotEmpty) Text(driverPhone),
                  Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: isActive ? Colors.green : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  if (isCurrent)
                    const Text(
                      'Current Driver',
                      style: TextStyle(
                        color: Colors.purple,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              trailing: isCurrent
                  ? const Icon(Icons.check_circle, color: Colors.purple)
                  : null,
              enabled: !isCurrent,
              onTap: isCurrent
                  ? null
                  : () {
                      Navigator.of(context).pop({
                        'id': driverId,
                        'name': displayName,
                      });
                    },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
