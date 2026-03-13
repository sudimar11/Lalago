import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';

IconData _getBenefitIcon(String type) {
  switch (type) {
    case 'free_delivery':
      return Icons.local_shipping;
    case 'wallet_credit':
      return Icons.account_balance_wallet;
    case 'badge':
      return Icons.emoji_events;
    default:
      return Icons.card_giftcard;
  }
}

class BenefitCard extends StatelessWidget {
  final Map<String, dynamic> benefit;
  final bool isUnlocked;
  final bool isClaimed;
  final VoidCallback? onClaim;

  const BenefitCard({
    Key? key,
    required this.benefit,
    this.isUnlocked = true,
    this.isClaimed = false,
    this.onClaim,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = benefit['type']?.toString() ?? '';
    final desc = benefit['description']?.toString() ?? '';
    final showClaim = isUnlocked && !isClaimed && type != 'badge';

    return Card(
      elevation: isUnlocked ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isUnlocked ? null : Colors.grey.shade100,
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getBenefitIcon(type),
                color: theme.brightness == Brightness.dark
                    ? theme.colorScheme.primary
                    : Color(COLOR_PRIMARY),
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                desc,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (benefit['amount'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '₱${benefit['amount']}',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 13,
                    ),
                  ),
                ),
              if (showClaim && onClaim != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onClaim,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(COLOR_PRIMARY),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Claim'),
                    ),
                  ),
                )
              else if (isClaimed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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
                ),
            ],
          ),
        ),
      ),
    );
  }
}
