import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/LoyaltyData.dart';
import 'package:foodie_customer/services/loyalty_service.dart';
import 'package:intl/intl.dart';

class LoyaltyScreen extends StatefulWidget {
  final String userId;

  const LoyaltyScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loyalty Program'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: LoyaltyService.getLoyaltyConfigStream(),
        builder: (context, configSnap) {
          if (configSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!configSnap.hasData || configSnap.data?['enabled'] != true) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Loyalty program is not available.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            );
          }

          final config = configSnap.data!;
          return StreamBuilder<LoyaltyData?>(
            stream: LoyaltyService.getLoyaltyStream(widget.userId),
            builder: (context, loyaltySnap) {
              if (loyaltySnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final loyalty = loyaltySnap.data;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTierBadge(loyalty, config),
                    const SizedBox(height: 24),
                    _buildTokenProgress(loyalty, config),
                    const SizedBox(height: 24),
                    _buildBenefitsSection(loyalty, config),
                    const SizedBox(height: 24),
                    _buildHistorySection(loyalty),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTierBadge(LoyaltyData? loyalty, Map<String, dynamic> config) {
    final tier = loyalty?.currentTier ?? 'bronze';
    final tierDisplay = tier[0].toUpperCase() + tier.substring(1);
    final color = _getTierColor(tier);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events,
            size: 64,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            tierDisplay,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Current Tier',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenProgress(LoyaltyData? loyalty, Map<String, dynamic> config) {
    final tokens = loyalty?.tokensThisCycle ?? 0;
    final tokensNeeded =
        LoyaltyService.getTokensToNextTier(tokens, config);
    final nextTier = LoyaltyService.getNextTierName(tokens, config);
    final progress =
        LoyaltyService.getProgressToNextTier(tokens, config);

    String cycleText = '';
    if (loyalty != null &&
        loyalty.currentCycle.isNotEmpty &&
        loyalty.cycleStartDate != null &&
        loyalty.cycleEndDate != null) {
      final start =
          DateFormat('MMM d').format(loyalty.cycleStartDate!.toDate());
      final end = DateFormat('MMM d, yyyy')
          .format(loyalty.cycleEndDate!.toDate());
      cycleText = '$start - $end';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${tokens} tokens',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (loyalty?.currentCycle.isNotEmpty == true)
                  Text(
                    loyalty!.currentCycle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
            if (cycleText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                cycleText,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                Color(COLOR_PRIMARY),
              ),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              tokensNeeded > 0 && nextTier != null
                  ? '$tokensNeeded more orders to reach ${nextTier[0].toUpperCase() + nextTier.substring(1)}!'
                  : 'You\'re at the top tier!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            if (loyalty != null) ...[
              const SizedBox(height: 12),
              Text(
                'Lifetime: ${loyalty.lifetimeTokens} tokens',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitsSection(
    LoyaltyData? loyalty,
    Map<String, dynamic> config,
  ) {
    final tier = loyalty?.currentTier ?? 'bronze';
    final benefits = _getBenefitsForTier(tier, config);
    if (benefits.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Benefits',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Earn more tokens to unlock benefits at higher tiers.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Benefits',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        ...benefits.map((b) => _buildBenefitCard(b, loyalty)),
      ],
    );
  }

  Widget _buildBenefitCard(
    Map<String, dynamic> benefit,
    LoyaltyData? loyalty,
  ) {
    final type = benefit['type']?.toString() ?? '';
    final desc = benefit['description']?.toString() ?? '';
    if (type == 'inherits') return const SizedBox.shrink();

    final rewardId = _benefitToRewardId(benefit);
    final isClaimed = _isBenefitClaimed(rewardId, loyalty);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _getBenefitIcon(type),
              color: Color(COLOR_PRIMARY),
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (benefit['amount'] != null)
                    Text(
                      'Amount: ₱${benefit['amount']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            if (!isClaimed && type != 'badge')
              ElevatedButton(
                onPressed: () => _onClaimTap(rewardId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Claim'),
              )
            else if (isClaimed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Claimed',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onClaimTap(String rewardId) async {
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('claimLoyaltyReward');
      final result = await callable.call({'rewardId': rewardId});
      final data = result.data as Map<String, dynamic>?;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data?['walletCredit'] != null &&
                      (data!['walletCredit'] as num) > 0
                  ? 'Reward claimed! ₱${data['walletCredit']} added to wallet.'
                  : 'Reward claimed successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('already-exists')
            ? 'You have already claimed this reward.'
            : e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: const TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isBenefitClaimed(String rewardId, LoyaltyData? loyalty) {
    if (loyalty == null) return false;
    return loyalty.rewardsClaimed.any(
      (r) => r.rewardId == rewardId && r.cycle == loyalty.currentCycle,
    );
  }

  String _benefitToRewardId(Map<String, dynamic> b) {
    final type = b['type']?.toString() ?? '';
    if (type == 'free_delivery') return 'free_delivery';
    if (type == 'wallet_credit') {
      final amt = b['amount'];
      return 'wallet_credit_${amt ?? 50}';
    }
    if (type == 'badge') return 'badge_${b['name'] ?? 'vip'}';
    return type;
  }

  IconData _getBenefitIcon(String type) {
    switch (type) {
      case 'free_delivery':
        return Icons.local_shipping;
      case 'wallet_credit':
        return Icons.account_balance_wallet;
      case 'badge':
        return Icons.verified;
      default:
        return Icons.card_giftcard;
    }
  }

  List<Map<String, dynamic>> _getBenefitsForTier(
    String tier,
    Map<String, dynamic> config,
  ) {
    final benefitsConfig = config['benefits'] as Map<String, dynamic>?;
    if (benefitsConfig == null) return [];

    final result = <Map<String, dynamic>>[];
    final list = benefitsConfig[tier] as List?;
    if (list != null) {
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          if (item['type'] == 'inherits') {
            final from = item['from']?.toString();
            if (from != null) {
              result.addAll(_getBenefitsForTier(from, config));
            }
          } else {
            result.add(item);
          }
        }
      }
    }
    return result;
  }

  Widget _buildHistorySection(LoyaltyData? loyalty) {
    final history = loyalty?.tierHistory ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tier History',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[300]),
            itemBuilder: (context, i) {
              final h = history[history.length - 1 - i];
              final tierDisplay =
                  h.tier[0].toUpperCase() + h.tier.substring(1);
              return ListTile(
                leading: Icon(
                  Icons.emoji_events,
                  color: _getTierColor(h.tier),
                  size: 28,
                ),
                title: Text(tierDisplay),
                subtitle: Text(
                  '${h.cycle} • ${DateFormat('MMM d, yyyy').format(h.achievedAt.toDate())}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'bronze':
        return Colors.brown;
      case 'silver':
        return Colors.grey;
      case 'gold':
        return Colors.amber;
      case 'diamond':
        return Colors.cyan;
      default:
        return Color(COLOR_PRIMARY);
    }
  }
}
