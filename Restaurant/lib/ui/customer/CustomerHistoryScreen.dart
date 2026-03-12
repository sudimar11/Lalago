import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/ordersScreen/OrderDetailsScreen.dart';
import 'package:foodie_restaurant/utils/analytics_helper.dart';

class CustomerHistoryScreen extends StatefulWidget {
  final User customer;
  final String vendorID;

  const CustomerHistoryScreen({
    Key? key,
    required this.customer,
    required this.vendorID,
  }) : super(key: key);

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  String _statusFilter = 'All';
  List<OrderModel> _orders = [];
  bool _loading = true;
  double? _totalSpent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await FireStoreUtils.getCustomerOrders(
        widget.customer.userID,
        widget.vendorID,
      );
      double total = 0.0;
      for (final o in orders) {
        total += await AnalyticsHelper.calculateOrderNetTotal(o);
      }
      if (mounted) {
        setState(() {
          _orders = orders;
          _totalSpent = total;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _orders = [];
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<OrderModel> get _filteredOrders {
    if (_statusFilter == 'All') return _orders;
    return _orders.where((o) => o.status == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode(context);
    final list = _filteredOrders;

    return Scaffold(
      backgroundColor:
          dark ? Color(DARK_VIEWBG_COLOR) : const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: dark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.customer.fullName(),
          style: TextStyle(
            color: dark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Unable to load orders',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: dark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadOrders,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildHeader(dark),
                      ),
                      SliverToBoxAdapter(
                        child: _buildStatusChips(dark),
                      ),
                      if (list.isEmpty)
                        SliverFillRemaining(
                          child: showEmptyState(
                            'No Orders',
                            _statusFilter == 'All'
                                ? 'This customer has no orders yet'
                                : 'No orders with status $_statusFilter',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.all(20),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final order = list[index];
                                return _buildOrderCard(context, order, dark);
                              },
                              childCount: list.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeader(bool dark) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: dark ? Color(DARK_CARD_BG_COLOR) : Colors.grey.shade50,
      child: Row(
        children: [
          if (widget.customer.profilePictureURL.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: CachedNetworkImage(
                imageUrl: widget.customer.profilePictureURL,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _placeholderAvatar(),
              ),
            )
          else
            _placeholderAvatar(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.customer.fullName(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: dark ? Colors.white : Colors.black,
                  ),
                ),
                if (widget.customer.phoneNumber.isNotEmpty)
                  Text(
                    widget.customer.phoneNumber,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _metricChip(
                      dark,
                      '${_orders.length}',
                      'Orders',
                    ),
                    const SizedBox(width: 12),
                    _metricChip(
                      dark,
                      _totalSpent != null
                          ? '\₱${_totalSpent!.toStringAsFixed(2)}'
                          : '-',
                      'Total Spent',
                    ),
                    const SizedBox(width: 12),
                    _metricChip(
                      dark,
                      _orders.isNotEmpty && _totalSpent != null
                          ? '\₱${(_totalSpent! / _orders.length).toStringAsFixed(2)}'
                          : '-',
                      'Avg Order',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderAvatar() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Color(COLOR_PRIMARY).withOpacity(0.2),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Icon(
        Icons.person,
        size: 32,
        color: Color(COLOR_PRIMARY),
      ),
    );
  }

  Widget _metricChip(bool dark, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(COLOR_PRIMARY),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChips(bool dark) {
    final statuses = ['All', 'Order Completed', 'Order Placed', 'Order Rejected'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: statuses.map((s) {
          final selected = _statusFilter == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(s),
              selected: selected,
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => _statusFilter = s);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    OrderModel order,
    bool dark,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      color: dark ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => push(context, OrderDetailsScreen(orderModel: order)),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order #${order.id.length >= 8 ? order.id.substring(0, 8) : order.id}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white : Colors.black,
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(order.status),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      order.status,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('MMM d, yyyy • h:mm a').format(
                  order.createdAt.toDate(),
                ),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${order.products.length} item(s)',
                style: TextStyle(
                  fontSize: 14,
                  color: dark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              FutureBuilder<double>(
                future: AnalyticsHelper.calculateOrderNetTotal(order),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '\₱${(snap.data ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(COLOR_PRIMARY),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Order Completed':
      case 'Order Delivered':
        return Colors.green;
      case 'Order Rejected':
        return Colors.red;
      case 'Order Placed':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
