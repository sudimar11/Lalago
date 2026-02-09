import 'package:flutter/material.dart';
import 'package:foodie_driver/services/voucher_reward_service.dart';
import 'package:foodie_driver/model/VoucherRule.dart';
import 'package:foodie_driver/constants.dart';

class VoucherRewardWidget extends StatefulWidget {
  final String driverId;
  final bool isDarkMode;

  const VoucherRewardWidget({
    Key? key,
    required this.driverId,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  State<VoucherRewardWidget> createState() => _VoucherRewardWidgetState();
}

class _VoucherRewardWidgetState extends State<VoucherRewardWidget> {
  Map<String, dynamic>? voucherSummary;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVoucherSummary();
  }

  Future<void> _loadVoucherSummary() async {
    try {
      final summary =
          await VoucherRewardService.getVoucherSummary(widget.driverId);
      if (mounted) {
        setState(() {
          voucherSummary = summary;
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading voucher summary: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDarkMode ? Color(DARK_VIEWBG_COLOR) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                widget.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(COLOR_PRIMARY)),
            ),
            const SizedBox(width: 16),
            Text(
              'Loading voucher information...',
              style: TextStyle(
                color: widget.isDarkMode ? Colors.white : Colors.black,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (voucherSummary == null) {
      return const SizedBox.shrink();
    }

    final isActive = voucherSummary!['active'] ?? false;
    final deliveryCount = voucherSummary!['deliveryCount'] ?? 0;
    final attendanceWindow = voucherSummary!['attendanceWindow'] ?? 6;
    final currentVoucherAmount = voucherSummary!['currentVoucherAmount'] ?? 0.0;
    final qualifiesForVoucher = voucherSummary!['qualifiesForVoucher'] ?? false;
    final nextVoucherRule = voucherSummary!['nextVoucherRule'] as VoucherRule?;

    if (!isActive) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDarkMode ? Color(DARK_VIEWBG_COLOR) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                widget.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Voucher reward system is currently inactive',
                style: TextStyle(
                  color: widget.isDarkMode
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? Color(DARK_VIEWBG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: qualifiesForVoucher
              ? Colors.green.shade300
              : widget.isDarkMode
                  ? Colors.grey.shade700
                  : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                qualifiesForVoucher
                    ? Icons.card_giftcard
                    : Icons.local_shipping,
                color:
                    qualifiesForVoucher ? Colors.green : Color(COLOR_PRIMARY),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Voucher Rewards',
                  style: TextStyle(
                    color: widget.isDarkMode ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (qualifiesForVoucher)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'QUALIFIED',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Delivery count
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.delivery_dining, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Completed Deliveries: $deliveryCount in $attendanceWindow days',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Voucher information
          if (qualifiesForVoucher) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.card_giftcard, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'You qualify for ₱${currentVoucherAmount.toStringAsFixed(0)} voucher!',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (nextVoucherRule != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.trending_up, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Next Reward',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Complete ${nextVoucherRule.minDeliveries} deliveries to earn ₱${nextVoucherRule.voucherAmount.toStringAsFixed(0)} voucher',
                    style: TextStyle(
                      color: Colors.orange.shade600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: deliveryCount / nextVoucherRule.minDeliveries,
                    backgroundColor: Colors.orange.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No voucher rules available',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Contact admin to set up voucher reward system',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Create sample rules button (only show if no rules available)
              if (!isActive ||
                  (voucherSummary != null &&
                      voucherSummary!['nextVoucherRule'] == null &&
                      !qualifiesForVoucher))
                TextButton.icon(
                  onPressed: () async {
                    setState(() {
                      isLoading = true;
                    });
                    try {
                      await VoucherRewardService
                          .createSampleVoucherRulesDocument();
                      _loadVoucherSummary();
                    } catch (e) {
                      print('❌ Error creating sample rules: $e');
                      setState(() {
                        isLoading = false;
                      });
                    }
                  },
                  icon: Icon(
                    Icons.add_circle_outline,
                    size: 16,
                    color: Colors.blue,
                  ),
                  label: Text(
                    'Create Sample Rules',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                SizedBox.shrink(),

              // Refresh button
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    isLoading = true;
                  });
                  _loadVoucherSummary();
                },
                icon: Icon(
                  Icons.refresh,
                  size: 16,
                  color: Color(COLOR_PRIMARY),
                ),
                label: Text(
                  'Refresh',
                  style: TextStyle(
                    color: Color(COLOR_PRIMARY),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
