import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class ActiveCustomersPage extends StatefulWidget {
  const ActiveCustomersPage({super.key});

  @override
  State<ActiveCustomersPage> createState() => _ActiveCustomersPageState();
}

class _ActiveCustomersPageState extends State<ActiveCustomersPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSkeletonLoading() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SkeletonBox(
              width: 80,
              height: 80,
              borderRadius: 40,
            ),
            const SizedBox(height: 24),
            _SkeletonBox(
              width: 200,
              height: 24,
            ),
            const SizedBox(height: 8),
            _SkeletonBox(
              width: 150,
              height: 16,
            ),
            const SizedBox(height: 40),
            _buildCardSkeleton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCardSkeleton() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SkeletonBox(
              width: 100,
              height: 18,
            ),
            const SizedBox(height: 16),
            _SkeletonBox(
              width: 80,
              height: 48,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Query customersQuery = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER);

    // Query for orders in last 30 days
    final DateTime thirtyDaysAgo =
        DateTime.now().subtract(const Duration(days: 30)).toUtc();
    final Query ordersLast30DaysQuery = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Customers'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: customersQuery.snapshots(),
        builder: (context, customersSnapshot) {
          if (customersSnapshot.connectionState == ConnectionState.waiting) {
            return _buildSkeletonLoading();
          }
          if (customersSnapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Failed to load customers'),
                ],
              ),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: ordersLast30DaysQuery.snapshots(),
            builder: (context, ordersSnapshot) {
              if (ordersSnapshot.connectionState == ConnectionState.waiting) {
                return _buildSkeletonLoading();
              }
              if (ordersSnapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('Failed to load orders'),
                    ],
                  ),
                );
              }

              // Get active customer IDs from orders in last 30 days
              final orders = ordersSnapshot.data?.docs ?? [];
              final Set<String> activeCustomerIds = {};
              for (final orderDoc in orders) {
                try {
                  final data = orderDoc.data();
                  if (data == null || data is! Map<String, dynamic>) continue;
                  final author = data['author'];
                  if (author == null || author is! Map<String, dynamic>)
                    continue;
                  final customerId = author['id'] as String?;
                  if (customerId != null && customerId.isNotEmpty) {
                    activeCustomerIds.add(customerId);
                  }
                } catch (e) {
                  // Skip invalid documents to prevent crashes
                  continue;
                }
              }

              final activeCount = activeCustomerIds.length;

              return Center(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person,
                        size: 80,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Active Customers',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Has order in 30 days',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'Total Count',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '$activeCount',
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double? borderRadius;

  const _SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey[300]!.withOpacity(_animation.value),
            borderRadius: BorderRadius.circular(
              widget.borderRadius ?? 8,
            ),
          ),
        );
      },
    );
  }
}

