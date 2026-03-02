import 'package:flutter/material.dart';

/// Overlay widget shown during async notification actions.
class NotificationActionLoading extends StatelessWidget {
  final String action;
  final String targetName;

  const NotificationActionLoading({
    super.key,
    required this.action,
    this.targetName = '',
  });

  @override
  Widget build(BuildContext context) {
    String message;
    switch (action) {
      case 'accept_order':
        message = targetName.isNotEmpty
            ? 'Accepting order from $targetName...'
            : 'Accepting order...';
        break;
      case 'decline_order':
        message = 'Declining order...';
        break;
      case 'reorder':
        message = targetName.isNotEmpty
            ? 'Adding $targetName to cart...'
            : 'Adding to cart...';
        break;
      case 'chat_reply':
        message = 'Sending reply...';
        break;
      case 'view_order':
        message = 'Opening order...';
        break;
      default:
        message = 'Processing your request...';
    }

    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
