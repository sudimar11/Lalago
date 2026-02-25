import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';

class DefaultLocationBanner extends StatelessWidget {
  final VoidCallback onSetLocationTap;

  const DefaultLocationBanner({
    Key? key,
    required this.onSetLocationTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Color(COLOR_PRIMARY).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(COLOR_PRIMARY).withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.location_on_outlined,
            color: Color(COLOR_PRIMARY),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Showing restaurants near $DEFAULT_ADDRESS',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set your exact location for better results',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onSetLocationTap,
            child: const Text('Set Location'),
          ),
        ],
      ),
    );
  }
}
