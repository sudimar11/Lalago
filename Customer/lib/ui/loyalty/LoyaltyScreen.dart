import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/LoyaltyData.dart';
import 'package:foodie_customer/services/loyalty_service.dart';
import 'package:foodie_customer/ui/loyalty/widgets/benefit_card.dart';
import 'package:foodie_customer/ui/loyalty/widgets/progress_bar_with_indicator.dart';
import 'package:foodie_customer/ui/loyalty/widgets/tier_badge.dart';
import 'package:foodie_customer/ui/loyalty/widgets/token_counter.dart';
import 'package:foodie_customer/widget/shimmer_widgets.dart';
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
        leading: BackButton(color: Colors.white),
        title: const Text('Loyalty Program'),
        backgroundColor: Color(COLOR_PRIMARY),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: LoyaltyService.getLoyaltyConfigStream(),
        builder: (context, configSnap) {
          if (configSnap.connectionState == ConnectionState.waiting) {
            return _buildLoadingShimmer();
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
                return _buildLoadingShimmer();
              }

              final loyalty = loyaltySnap.data;
              final currentTier = loyalty?.currentTier ?? 'bronze';
              final tokensThisCycle = loyalty?.tokensThisCycle ?? 0;
              final nextTierName =
                  LoyaltyService.getNextTierName(tokensThisCycle, config);
              final minTokensForNextTier =
                  LoyaltyService.getMinTokensForNextTier(
                      tokensThisCycle, config);
              final progress =
                  LoyaltyService.getProgressToNextTier(tokensThisCycle, config);
              final tokensNeeded = minTokensForNextTier != null
                  ? (minTokensForNextTier - tokensThisCycle).clamp(0, 999)
                  : 0;
              final currentBenefits =
                  _getBenefitsForTier(currentTier, config);
              final nextBenefits =
                  LoyaltyService.getNextTierBenefits(tokensThisCycle, config);

              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildHeaderCard(
                            currentTier, tokensThisCycle, loyalty),
                        const SizedBox(height: 16),
                        _buildProgressCard(
                          progress: progress,
                          tokensThisCycle: tokensThisCycle,
                          minTokensForNextTier: minTokensForNextTier,
                          nextTierName: nextTierName,
                          tokensNeeded: tokensNeeded,
                        ),
                        const SizedBox(height: 24),
                        _buildBenefitsSection(
                            loyalty, config, currentBenefits, nextBenefits,
                            nextTierName: nextTierName),
                        const SizedBox(height: 16),
                        _buildHistorySection(loyalty),
                        const SizedBox(height: 8),
                        _buildLifetimeFooter(loyalty),
                      ]),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return ShimmerWidgets.baseShimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              height: 24,
              width: 120,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.9,
              children: List.generate(
                4,
                (_) => Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    String currentTier,
    int tokensThisCycle,
    LoyaltyData? loyalty,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            TierBadge(tier: currentTier),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TokenCounter(tokens: tokensThisCycle),
                  const SizedBox(height: 4),
                  Text(
                    _formatQuarter(loyalty),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard({
    required double progress,
    required int tokensThisCycle,
    required int? minTokensForNextTier,
    required String? nextTierName,
    required int tokensNeeded,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return ProgressBarWithIndicator(
              progress: value,
              tokensCurrent: tokensThisCycle,
              tokensForNextTier: minTokensForNextTier ?? tokensThisCycle,
              nextTierName: nextTierName,
              tokensNeeded: tokensNeeded,
            );
          },
        ),
      ),
    );
  }

  Widget _buildBenefitsSection(
    LoyaltyData? loyalty,
    Map<String, dynamic> config,
    List<Map<String, dynamic>> currentBenefits,
    List<Map<String, dynamic>> nextBenefits, {
    String? nextTierName,
  }) {
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
        if (currentBenefits.isEmpty)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Earn more tokens to unlock benefits at higher tiers.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ),
          )
        else
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.9,
            children: currentBenefits
                .map(
                  (b) => BenefitCard(
                    benefit: b,
                    isUnlocked: true,
                    isClaimed: _isBenefitClaimed(_benefitToRewardId(b), loyalty),
                    onClaim: () => _onClaimTap(_benefitToRewardId(b)),
                  ),
                )
                .toList(),
          ),
        if (nextTierName != null && nextBenefits.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Unlock at ${nextTierName[0].toUpperCase() + nextTierName.substring(1)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.9,
            children: nextBenefits
                .map(
                  (b) => BenefitCard(
                    benefit: b,
                    isUnlocked: false,
                    isClaimed: false,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildLifetimeFooter(LoyaltyData? loyalty) {
    if (loyalty == null) return const SizedBox.shrink();
    return Center(
      child: Text(
        'Lifetime tokens: ${loyalty.lifetimeTokens}',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  String _formatQuarter(LoyaltyData? data) {
    if (data == null ||
        data.cycleStartDate == null ||
        data.cycleEndDate == null) {
      return data?.currentCycle ?? '';
    }
    final start =
        DateFormat('MMM d').format(data.cycleStartDate!.toDate());
    final end =
        DateFormat('MMM d, yyyy').format(data.cycleEndDate!.toDate());
    return '${data.currentCycle} • $start – $end';
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
