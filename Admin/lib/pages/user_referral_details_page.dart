import 'package:flutter/material.dart';
import 'package:brgy/services/referral_service.dart';
import 'package:brgy/widgets/referral_wallet_adjustment_dialog.dart';
import 'package:intl/intl.dart';

class UserReferralDetailsPage extends StatefulWidget {
  final String userId;

  const UserReferralDetailsPage({required this.userId, super.key});

  @override
  State<UserReferralDetailsPage> createState() =>
      _UserReferralDetailsPageState();
}

class _UserReferralDetailsPageState extends State<UserReferralDetailsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Referral Details'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: FutureBuilder<UserReferralStats>(
        future: ReferralService.getUserReferralStats(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error loading details: ${snapshot.error}'),
                ],
              ),
            );
          }

          final stats = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wallet Summary Card
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_wallet,
                                color: Colors.orange, size: 32),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Referral Wallet Summary',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final result = await showDialog(
                                  context: context,
                                  builder: (context) =>
                                      ReferralWalletAdjustmentDialog(
                                    userId: widget.userId,
                                    currentBalance: stats.referralWalletBalance,
                                  ),
                                );
                                if (result == true) {
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.edit),
                              label: const Text('Adjust'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SummaryRow(
                          label: 'Current Balance',
                          value: '₱${stats.referralWalletBalance.toStringAsFixed(2)}',
                          isHighlight: true,
                        ),
                        _SummaryRow(
                          label: 'Total Earned',
                          value: '₱${stats.totalEarned.toStringAsFixed(2)}',
                        ),
                        _SummaryRow(
                          label: 'Total Used',
                          value: '₱${stats.totalUsed.toStringAsFixed(2)}',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Referrer Relationships
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Referrals Made (as Referrer)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (stats.referrerRelationships.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                'No referrals made',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ...stats.referrerRelationships.map((rel) =>
                              _RelationshipItem(relationship: rel)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Referred Relationships
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Referred By',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (stats.referredRelationships.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                'Not referred by anyone',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        else
                          ...stats.referredRelationships.map((rel) =>
                              _RelationshipItem(relationship: rel)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Adjustment History
                FutureBuilder<List<WalletAdjustment>>(
                  future: ReferralService.getWalletAdjustments(widget.userId),
                  builder: (context, adjSnapshot) {
                    if (adjSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }

                    final adjustments = adjSnapshot.data ?? [];

                    return Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Adjustment History',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (adjustments.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    'No adjustments made',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              )
                            else
                              ...adjustments.map((adj) =>
                                  _AdjustmentItem(adjustment: adj)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isHighlight;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isHighlight ? Colors.green : Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelationshipItem extends StatelessWidget {
  final ReferralRelationship relationship;

  const _RelationshipItem({required this.relationship});

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(relationship.status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  relationship.status.toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(relationship.status),
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              const Spacer(),
              if (relationship.creditedAmount > 0)
                Text(
                  '₱${relationship.creditedAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Code: ${relationship.referralCode}',
            style: const TextStyle(fontSize: 12),
          ),
          if (relationship.triggeringOrderId != null)
            Text(
              'Order: ${relationship.triggeringOrderId}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          Text(
            'Created: ${DateFormat('MMM dd, yyyy').format(relationship.createdAt.toDate())}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _AdjustmentItem extends StatelessWidget {
  final WalletAdjustment adjustment;

  const _AdjustmentItem({required this.adjustment});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                adjustment.adjustmentType == 'add'
                    ? Icons.add_circle
                    : Icons.remove_circle,
                color: adjustment.adjustmentType == 'add'
                    ? Colors.green
                    : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                adjustment.adjustmentType == 'add'
                    ? 'Added'
                    : 'Deducted',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: adjustment.adjustmentType == 'add'
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              const Spacer(),
              Text(
                '₱${adjustment.amount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Reason: ${adjustment.reason}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            'By: ${adjustment.adminName}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            'Balance: ₱${adjustment.previousBalance.toStringAsFixed(2)} → ₱${adjustment.newBalance.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            DateFormat('MMM dd, yyyy HH:mm')
                .format(adjustment.createdAt.toDate()),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

