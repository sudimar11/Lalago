import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/services/helper.dart';

/// Shown when restaurant is auto-paused due to consecutive unaccepted orders.
class PauseScreen extends StatelessWidget {
  final String vendorId;

  const PauseScreen({Key? key, required this.vendorId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vendors')
          .doc(vendorId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            backgroundColor: isDarkMode(context)
                ? Color(DARK_VIEWBG_COLOR)
                : Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final autoPause = data['autoPause'] as Map<String, dynamic>? ?? {};
        final isPaused = autoPause['isPaused'] == true;
        final autoUnpauseAt = autoPause['autoUnpauseAt'] as Timestamp?;

        if (!isPaused) {
          return const SizedBox.shrink();
        }

        return Scaffold(
          backgroundColor: Colors.red.shade50,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 80,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Your store has been paused',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Due to multiple unaccepted orders, we\'ve temporarily '
                    'stopped sending you orders to protect customer experience.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red.shade800,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (autoUnpauseAt != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Auto-unpause at ${DateFormat('h:mm a').format(autoUnpauseAt.toDate())}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _handleGoOnline(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('GO ONLINE'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleGoOnline(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resume Receiving Orders?'),
        content: const Text(
          'Your store will start receiving orders again. '
          'Make sure you can accept incoming orders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('GO ONLINE'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('vendors')
          .doc(vendorId)
          .update({
        'autoPause': {
          'isPaused': false,
          'resumedAt': FieldValue.serverTimestamp(),
          'resumedBy': 'manual',
        },
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Store is now online'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error resuming: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
