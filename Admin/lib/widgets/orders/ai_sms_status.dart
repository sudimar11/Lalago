import 'package:flutter/material.dart';

class AISMSStatus extends StatelessWidget {
  final String status;
  final Map<String, dynamic> orderData;

  const AISMSStatus({
    super.key,
    required this.status,
    required this.orderData,
  });

  bool get _shouldShow {
    final s = status.toLowerCase();
    final autoAccepted = (orderData['autoAccepted'] as bool?) ?? false;

    // Show when the system is likely sending SMS:
    // - auto-accepted orders (customer + restaurant)
    // - just accepted orders (customer)
    // - driver assignment in progress (driver)
    return autoAccepted ||
        s == 'order accepted' ||
        s == 'driver pending' ||
        s == 'driver assigned';
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();

    final isAuto = (orderData['autoAccepted'] as bool?) ?? false;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: Colors.indigo.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isAuto ? 'AI auto-notifications' : 'AI notifications',
              style: TextStyle(
                color: Colors.indigo.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Sending SMS',
            style: TextStyle(
              color: Colors.indigo.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
