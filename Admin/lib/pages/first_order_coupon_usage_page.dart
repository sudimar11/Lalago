import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/services/first_order_coupon_service.dart';
import 'package:intl/intl.dart';

class FirstOrderCouponUsagePage extends StatefulWidget {
  const FirstOrderCouponUsagePage({super.key});

  @override
  State<FirstOrderCouponUsagePage> createState() =>
      _FirstOrderCouponUsagePageState();
}

class _FirstOrderCouponUsagePageState
    extends State<FirstOrderCouponUsagePage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('First Order Coupon Usage'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<CouponUsageStats>(
        stream: FirstOrderCouponService.getCouponUsageStatsStream(),
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
                  Text('Error loading usage statistics: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final stats = snapshot.data ??
              CouponUsageStats(
                totalUsage: 0,
                uniqueUsers: 0,
                totalDiscountCost: 0.0,
                affectedOrders: [],
                userIds: [],
              );

          // Filter orders by search query
          final filteredOrders = stats.affectedOrders.where((order) {
            if (_searchQuery.isEmpty) return true;
            final query = _searchQuery.toLowerCase();
            final orderId = (order['orderId'] ?? '').toString().toLowerCase();
            final userId = (order['userId'] ?? '').toString().toLowerCase();
            return orderId.contains(query) || userId.contains(query);
          }).toList();

          return Column(
            children: [
              // Statistics Cards
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[100],
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Total Usage',
                            value: '${stats.totalUsage}',
                            icon: Icons.receipt_long,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: 'Unique Users',
                            value: '${stats.uniqueUsers}',
                            icon: Icons.people,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StatCard(
                      title: 'Total Discount Cost',
                      value: '₱${stats.totalDiscountCost.toStringAsFixed(2)}',
                      icon: Icons.attach_money,
                      color: Colors.orange,
                      fullWidth: true,
                    ),
                  ],
                ),
              ),

              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by Order ID or User ID...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),

              // Orders List
              Expanded(
                child: filteredOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isEmpty
                                  ? Icons.receipt_long_outlined
                                  : Icons.search_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No orders found with this coupon'
                                  : 'No orders match your search',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredOrders.length,
                        itemBuilder: (context, index) {
                          final order = filteredOrders[index];
                          return _OrderCard(order: order);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool fullWidth;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
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
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  const _OrderCard({required this.order});

  DateTime? _getDate(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    }
    if (timestamp is Map) {
      try {
        final ts = Timestamp(
          timestamp['_seconds'] ?? 0,
          timestamp['_nanoseconds'] ?? 0,
        );
        return ts.toDate();
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final orderId = (order['orderId'] ?? '').toString();
    final userId = (order['userId'] ?? '').toString();
    final discountAmount = (order['discountAmount'] ?? 0.0) as double;
    final orderTotal = (order['orderTotal'] ?? 0.0) as double;
    final deliveredAt = _getDate(order['deliveredAt']);
    final createdAt = _getDate(order['createdAt']);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Order: ${orderId.length > 12 ? orderId.substring(0, 12) : orderId}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'User ID',
              value: userId.isEmpty
                  ? 'N/A'
                  : (userId.length > 20 ? '${userId.substring(0, 20)}...' : userId),
            ),
            _InfoRow(
              label: 'Discount Amount',
              value: '₱${discountAmount.toStringAsFixed(2)}',
            ),
            if (orderTotal > 0)
              _InfoRow(
                label: 'Order Total',
                value: '₱${orderTotal.toStringAsFixed(2)}',
              ),
            if (deliveredAt != null)
              _InfoRow(
                label: 'Completed',
                value: DateFormat('MMM dd, yyyy HH:mm').format(deliveredAt),
              )
            else if (createdAt != null)
              _InfoRow(
                label: 'Created',
                value: DateFormat('MMM dd, yyyy HH:mm').format(createdAt),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

