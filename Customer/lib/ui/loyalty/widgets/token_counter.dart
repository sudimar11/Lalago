import 'package:flutter/material.dart';

class TokenCounter extends StatelessWidget {
  final int tokens;

  const TokenCounter({Key? key, required this.tokens}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, color: Colors.amber, size: 28),
        const SizedBox(width: 4),
        Text(
          '$tokens',
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'tokens',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
