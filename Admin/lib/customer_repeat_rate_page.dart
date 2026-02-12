import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/services/order_stats_service.dart';

class CustomerRepeatRatePage extends StatefulWidget {
  const CustomerRepeatRatePage({super.key});

  @override
  State<CustomerRepeatRatePage> createState() => _CustomerRepeatRatePageState();
}

class _CustomerRepeatRatePageState extends State<CustomerRepeatRatePage> {
  Map<String, int>? _repeatRateData;
  bool _loading = false;
  int _progressCurrent = 0;
  int _progressTotal = 0;
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _repeatCustomers = [];
  bool _loadingCustomers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRepeatRate();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRepeatRate() async {
    setState(() {
      _loading = true;
      _progressCurrent = 0;
      _progressTotal = 0;
    });

    try {
      final service = OrderStatsService();
      final data = await service.calculateCustomerRepeatRate(
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            _progressCurrent = current;
            _progressTotal = total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _repeatRateData = data;
      });

      // Load the list of repeat customers
      _loadRepeatCustomers();
    } catch (e) {
      developer.log(
        "Error loading repeat rate: $e",
        name: "CustomerRepeatRatePage",
        error: e,
      );
      if (!mounted) return;
      setState(() {
        _repeatRateData = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadRepeatCustomers() async {
    setState(() {
      _loadingCustomers = true;
    });

    try {
      final DateTime fourteenDaysAgo =
          DateTime.now().subtract(const Duration(days: 14)).toUtc();

      // Get all active customers
      final QuerySnapshot usersSnap = await FirebaseFirestore.instance
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_CUSTOMER)
          .where('active', isEqualTo: true)
          .get();

      final List<Map<String, dynamic>> repeatCustomers = [];

      for (final userDoc in usersSnap.docs) {
        final userId = userDoc.id;
        final userData = userDoc.data() as Map<String, dynamic>?;

        if (userData == null) continue;

        // Get orders for this customer in last 14 days
        final QuerySnapshot ordersSnap = await FirebaseFirestore.instance
            .collection('restaurant_orders')
            .where('author.id', isEqualTo: userId)
            .where('createdAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(fourteenDaysAgo))
            .orderBy('createdAt')
            .get();

        if (ordersSnap.docs.length >= 2) {
          repeatCustomers.add({
            'id': userId,
            'name': userData['fullName'] ?? 'Unknown',
            'email': userData['email'] ?? 'No email',
            'orderCount': ordersSnap.docs.length,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _repeatCustomers = repeatCustomers;
      });
    } catch (e) {
      developer.log(
        "Error loading repeat customers: $e",
        name: "CustomerRepeatRatePage",
        error: e,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingCustomers = false;
      });
    }
  }

  Widget _buildSkeletonLoading() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const _SkeletonBox(
              width: 80,
              height: 80,
              borderRadius: 40,
            ),
            const SizedBox(height: 24),
            const _SkeletonBox(
              width: 200,
              height: 24,
            ),
            const SizedBox(height: 8),
            const _SkeletonBox(
              width: 150,
              height: 16,
            ),
            const SizedBox(height: 40),
            _buildCardSkeleton(),
            const SizedBox(height: 24),
            if (_progressTotal > 0)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Processing $_progressCurrent / $_progressTotal customers',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
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
      child: const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SkeletonBox(
              width: 100,
              height: 18,
            ),
            SizedBox(height: 16),
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
    final repeatCount = _repeatRateData?['repeatCount'] ?? 0;
    final totalCount = _repeatRateData?['totalCount'] ?? 0;
    final percentage = totalCount > 0
        ? ((repeatCount / totalCount) * 100).toStringAsFixed(1)
        : '0.0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Repeat Rate'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? _buildSkeletonLoading()
          : RefreshIndicator(
              onRefresh: _loadRepeatRate,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.repeat,
                      size: 80,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Customer Repeat Rate',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Customers who ordered again in last 14 days',
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
                              'Repeat Rate',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '$percentage%',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$repeatCount / $totalCount customers',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      'Repeat Customers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loadingCustomers)
                      const Center(
                        child: CircularProgressIndicator(),
                      )
                    else if (_repeatCustomers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No repeat customers in the last 14 days',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _repeatCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = _repeatCustomers[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange,
                                child: Text(
                                  customer['name']
                                      .toString()
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                customer['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(customer['email']),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${customer['orderCount']} orders',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
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
