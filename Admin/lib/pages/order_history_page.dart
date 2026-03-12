import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/constants.dart';
import 'package:intl/intl.dart';

class OrderHistoryPage extends StatefulWidget {
  final String? initialRiderId;

  const OrderHistoryPage({super.key, this.initialRiderId});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String? _selectedRiderId;
  String _statusFilter = 'All';
  bool _isLoading = false;
  bool _ridersLoaded = false;

  List<QueryDocumentSnapshot> _riders = [];
  List<QueryDocumentSnapshot> _orders = [];
  final Set<String> _markingComplete = {};

  static const _statusOptions = [
    'All',
    'Order Completed',
    'Order Rejected',
    'Order Placed',
    'Driver Accepted',
    'Order Shipped',
    'In Transit',
  ];

  @override
  void initState() {
    super.initState();
    _selectedRiderId = widget.initialRiderId;
    _loadRiders();
  }

  Future<void> _loadRiders() async {
    final snap = await FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_DRIVER)
        .orderBy('firstName')
        .get();
    if (!mounted) return;
    setState(() {
      _riders = snap.docs;
      _ridersLoaded = true;
    });
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);

    final startOfDay = DateTime(
      _fromDate.year,
      _fromDate.month,
      _fromDate.day,
    ).toUtc();
    final endOfDay = DateTime(
      _toDate.year,
      _toDate.month,
      _toDate.day,
      23,
      59,
      59,
    ).toUtc();

    Query query = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where(
          'createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
        )
        .orderBy('createdAt', descending: true)
        .limit(200);

    if (_selectedRiderId != null &&
        _selectedRiderId!.isNotEmpty) {
      query = FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('driverID', isEqualTo: _selectedRiderId)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo:
                Timestamp.fromDate(startOfDay),
          )
          .where(
            'createdAt',
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay),
          )
          .orderBy('createdAt', descending: true)
          .limit(200);
    }

    try {
      final snap = await query.get();
      if (!mounted) return;

      var docs = snap.docs;
      if (_statusFilter != 'All') {
        docs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status =
              (data['status'] ?? '').toString();
          return status == _statusFilter;
        }).toList();
      }

      setState(() {
        _orders = docs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load orders: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _markOrderComplete(String orderId) async {
    setState(() => _markingComplete.add(orderId));
    try {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .update({
        'status': 'Order Completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order marked as completed'),
          backgroundColor: Colors.green,
        ),
      );
      _loadOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _markingComplete.remove(orderId));
      }
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_fromDate.isAfter(_toDate)) _toDate = _fromDate;
      } else {
        _toDate = picked;
        if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
      }
    });
  }

  double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('completed') || s.contains('delivered')) {
      return Colors.green;
    } else if (s.contains('rejected') ||
        s.contains('cancelled')) {
      return Colors.red;
    } else if (s.contains('pending') ||
        s.contains('placed') ||
        s.contains('preparing')) {
      return Colors.orange;
    }
    return Colors.blue;
  }

  String _riderName(String riderId) {
    for (final doc in _riders) {
      if (doc.id == riderId) {
        final d = doc.data() as Map<String, dynamic>;
        final first = d['firstName'] ?? '';
        final last = d['lastName'] ?? '';
        final name = '$first $last'.trim();
        return name.isEmpty ? 'Rider ${riderId.substring(0, 8)}' : name;
      }
    }
    return riderId.length > 8
        ? '${riderId.substring(0, 8)}...'
        : riderId;
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM dd, yyyy');

    double grandTotal = 0;
    for (final doc in _orders) {
      final d = doc.data() as Map<String, dynamic>;
      grandTotal += _parseAmount(
        d['totalAmount'] ??
            d['grand_total'] ??
            d['vendorTotal'] ??
            d['total'] ??
            d['amount'],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order History'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildFilterBar(dateFmt),
          _buildSummaryRow(grandTotal),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _orders.isEmpty
                    ? const Center(
                        child: Text(
                          'No orders found',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _orders.length,
                          itemBuilder: (context, i) =>
                              _buildOrderCard(_orders[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(DateFormat dateFmt) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('From: ${dateFmt.format(_fromDate)}'),
              onPressed: () => _pickDate(isFrom: true),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text('To: ${dateFmt.format(_toDate)}'),
              onPressed: () => _pickDate(isFrom: false),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _selectedRiderId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Rider',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All Riders'),
                  ),
                  if (_ridersLoaded)
                    ..._riders.map((doc) {
                      final d =
                          doc.data() as Map<String, dynamic>;
                      final first = d['firstName'] ?? '';
                      final last = d['lastName'] ?? '';
                      final name = '$first $last'.trim();
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text(
                          name.isEmpty
                              ? 'Rider ${doc.id.substring(0, 6)}'
                              : name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                ],
                onChanged: (val) =>
                    setState(() => _selectedRiderId = val),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _statusFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: _statusOptions
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _statusFilter = val);
                  }
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _loadOrders,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(double grandTotal) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            '${_orders.length} orders found',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            'Total: ₱${grandTotal.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final orderId = doc.id;
    final status = (data['status'] ?? 'Unknown').toString();
    final createdAt = data['createdAt'] as Timestamp?;
    final vendor = data['vendor'] as Map<String, dynamic>?;
    final author = data['author'] as Map<String, dynamic>?;
    final products =
        data['products'] as List<dynamic>? ?? [];
    final driverId = (data['driverID'] ?? '').toString();

    final total = _parseAmount(
      data['totalAmount'] ??
          data['grand_total'] ??
          data['vendorTotal'] ??
          data['total'] ??
          data['amount'],
    );

    final restaurantName =
        vendor?['title']?.toString() ?? 'Unknown Restaurant';
    final customerFirst = author?['firstName'] ?? '';
    final customerLast = author?['lastName'] ?? '';
    final customerName =
        '$customerFirst $customerLast'.trim();

    String dateText = 'Unknown date';
    if (createdAt != null) {
      dateText = DateFormat('MMM dd, yyyy • hh:mm a')
          .format(createdAt.toDate());
    }

    final truncatedId = orderId.length > 12
        ? '${orderId.substring(0, 12)}...'
        : orderId;
    final itemCount = products.length;
    final isCompleted =
        status.toLowerCase().contains('completed');
    final isMarking = _markingComplete.contains(orderId);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: 4,
      ),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16,
        ),
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(status),
          radius: 18,
          child: const Icon(
            Icons.receipt_long,
            color: Colors.white,
            size: 18,
          ),
        ),
        title: Text(
          restaurantName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#$truncatedId',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dateText,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: _getStatusColor(status)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₱${total.toStringAsFixed(2)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        children: [
          Row(
            children: [
              const Icon(Icons.person, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Customer: ${customerName.isEmpty ? "Unknown" : customerName}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (driverId.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.drive_eta,
                  size: 14,
                  color: Colors.blue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Rider: ${_riderName(driverId)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              const Icon(
                Icons.shopping_bag,
                size: 14,
                color: Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                '$itemCount item${itemCount != 1 ? 's' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              Text(
                'Payment: ${data['payment_method'] ?? '-'}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          if (products.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.grey[300]!,
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Items:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...products.map((p) {
                    if (p is! Map<String, dynamic>) {
                      return const SizedBox.shrink();
                    }
                    final name =
                        p['name']?.toString() ?? 'Unknown';
                    final qty = p['quantity'] ?? 1;
                    final price =
                        p['price']?.toString() ?? '0';
                    return Padding(
                      padding:
                          const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius:
                                  BorderRadius.circular(3),
                            ),
                            child: Text(
                              '${qty}x',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 12,
                              ),
                              overflow:
                                  TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '₱$price',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          if (!isCompleted) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: isMarking
                    ? null
                    : () => _markOrderComplete(orderId),
                icon: isMarking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.check_circle,
                        size: 18,
                      ),
                label: Text(
                  isMarking
                      ? 'Updating...'
                      : 'Mark Complete',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
