import 'package:flutter/material.dart';

import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/SubstitutionRequestModel.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/services/pautos_substitution_service.dart';

class PautosSubstitutionsScreen extends StatelessWidget {
  final String orderId;

  const PautosSubstitutionsScreen({
    Key? key,
    required this.orderId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Substitutions'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<SubstitutionRequestModel>>(
        stream: PautosSubstitutionService.getSubstitutionRequestsStream(
          orderId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          final subs = snapshot.data ?? [];
          if (subs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No substitution requests.',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDarkMode(context)
                        ? Colors.white70
                        : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: subs.length,
            itemBuilder: (context, i) {
              final s = subs[i];
              return _SubstitutionCard(
                request: s,
                onApprove: s.isPending
                    ? () => _approve(context, s.id)
                    : null,
                onReject: s.isPending
                    ? () => _reject(context, s.id)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _approve(BuildContext context, String requestId) async {
    final ok = await PautosSubstitutionService.approveSubstitutionRequest(
      orderId,
      requestId,
    );
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Substitution approved'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to approve'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _reject(BuildContext context, String requestId) async {
    final ok = await PautosSubstitutionService.rejectSubstitutionRequest(
      orderId,
      requestId,
    );
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Substitution rejected'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to reject'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _SubstitutionCard extends StatelessWidget {
  final SubstitutionRequestModel request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _SubstitutionCard({
    required this.request,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = request.isPending
        ? Colors.orange
        : request.isApproved
            ? Colors.green
            : Colors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? const Color(DarkContainerColor)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode(context)
              ? Colors.grey.shade700
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${request.originalItem} → ${request.proposedItem}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDarkMode(context)
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${amountShow(amount: request.proposedPrice.toString())} • '
            '${request.status}',
            style: TextStyle(
              fontSize: 14,
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onReject != null)
                  TextButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                const SizedBox(width: 8),
                if (onApprove != null)
                  ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(COLOR_ACCENT),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Approve'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
