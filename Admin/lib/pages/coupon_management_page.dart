import 'package:flutter/material.dart';
import 'package:brgy/services/coupon_service.dart';
import 'package:brgy/model/coupon.dart';
import 'package:brgy/pages/coupon_add_edit_page.dart';
import 'package:brgy/pages/coupon_usage_page.dart';
import 'package:intl/intl.dart';

class CouponManagementPage extends StatefulWidget {
  const CouponManagementPage({super.key});

  @override
  State<CouponManagementPage> createState() => _CouponManagementPageState();
}

class _CouponManagementPageState extends State<CouponManagementPage> {
  Future<void> _onRefresh() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _handleDelete(Coupon coupon) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Coupon'),
        content: Text('Are you sure you want to delete "${coupon.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await CouponService.deleteCoupon(coupon.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Coupon deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleToggleEnabled(Coupon coupon) async {
    try {
      await CouponService.toggleEnabled(coupon.id, !coupon.isEnabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              coupon.isEnabled
                  ? 'Coupon disabled'
                  : 'Coupon enabled',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Coupon Management'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Coupon',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CouponAddEditPage(),
                ),
              );
              if (result == true) {
                _onRefresh();
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: StreamBuilder<List<Coupon>>(
          stream: CouponService.getCouponsStream(),
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
                    Text('Error loading coupons: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _onRefresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final coupons = snapshot.data ?? [];

            if (coupons.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.local_offer, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No coupons yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to create your first coupon',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CouponAddEditPage(),
                          ),
                        );
                        if (result == true) {
                          _onRefresh();
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Create Coupon'),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: coupons.length,
              itemBuilder: (context, index) {
                final coupon = coupons[index];
                return _CouponCard(
                  coupon: coupon,
                  onEdit: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CouponAddEditPage(coupon: coupon),
                      ),
                    );
                    if (result == true) {
                      _onRefresh();
                    }
                  },
                  onToggleEnabled: () => _handleToggleEnabled(coupon),
                  onViewStats: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CouponUsagePage(coupon: coupon),
                      ),
                    );
                  },
                  onDelete: () => _handleDelete(coupon),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CouponCard extends StatelessWidget {
  final Coupon coupon;
  final VoidCallback onEdit;
  final VoidCallback onToggleEnabled;
  final VoidCallback onViewStats;
  final VoidCallback onDelete;

  const _CouponCard({
    required this.coupon,
    required this.onEdit,
    required this.onToggleEnabled,
    required this.onViewStats,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final isExpired = coupon.isExpired;
    final isNotYetActive = coupon.isNotYetActive;
    final isActive = coupon.isCurrentlyValid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              coupon.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.green
                                  : isExpired
                                      ? Colors.red
                                      : isNotYetActive
                                          ? Colors.orange
                                          : Colors.grey,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isActive
                                  ? 'Active'
                                  : isExpired
                                      ? 'Expired'
                                      : isNotYetActive
                                          ? 'Upcoming'
                                          : 'Inactive',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${coupon.code}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: coupon.isEnabled,
                  onChanged: (_) => onToggleEnabled(),
                  activeColor: Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              coupon.shortDescription,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            if (coupon.eligibilityRules != null &&
                coupon.eligibilityRules!.hasRules) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.verified_user, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Eligibility Rules',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: _buildEligibilityTooltip(),
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Colors.blue[400],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.percent, size: 16, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  coupon.discountType == 'percentage'
                      ? '${coupon.discountValue.toStringAsFixed(0)}% OFF'
                      : '₱${coupon.discountValue.toStringAsFixed(2)} OFF',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.shopping_cart, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Min: ₱${coupon.minOrderAmount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${dateFormat.format(coupon.validFrom.toDate())} - ${dateFormat.format(coupon.validTo.toDate())}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            if (coupon.maxUsagePerUser != null ||
                coupon.globalUsageLimit != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (coupon.maxUsagePerUser != null) ...[
                    Icon(Icons.person, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Max per user: ${coupon.maxUsagePerUser}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (coupon.globalUsageLimit != null) ...[
                    Icon(Icons.block, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Global limit: ${coupon.globalUsageLimit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onViewStats,
                  icon: const Icon(Icons.analytics, size: 18),
                  label: const Text('Stats'),
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(foregroundColor: Colors.orange),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildEligibilityTooltip() {
    final rules = coupon.eligibilityRules!;
    final parts = <String>[];

    if (rules.userCategories != null && rules.userCategories!.isNotEmpty) {
      parts.add('Categories: ${rules.userCategories!.join(", ")}');
    }

    if (rules.minCompletedOrders != null) {
      parts.add('Min orders: ${rules.minCompletedOrders}');
    }

    if (rules.firstTimeUserOnly == true) {
      parts.add('First-time users only');
    }

    if (rules.priorCouponUsage != null &&
        rules.priorCouponUsage!.type != 'none') {
      final usageType = rules.priorCouponUsage!.type == 'this_coupon'
          ? 'this coupon'
          : 'any coupon';
      final requirement = rules.priorCouponUsage!.allowed
          ? 'must have used'
          : 'must NOT have used';
      parts.add('Prior usage: $requirement $usageType');
    }

    if (rules.userIds != null && rules.userIds!.isNotEmpty) {
      parts.add('Whitelist: ${rules.userIds!.length} user(s)');
    }

    return parts.isEmpty ? 'No rules configured' : parts.join('\n');
  }
}

