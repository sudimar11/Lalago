import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:intl/intl.dart';

class TransmitRequestsPage extends StatefulWidget {
  const TransmitRequestsPage({super.key});

  @override
  State<TransmitRequestsPage> createState() => _TransmitRequestsPageState();
}

class _TransmitRequestsPageState extends State<TransmitRequestsPage> {
  String _filterStatus = 'all'; // 'all', 'pending', 'confirmed'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transmit Requests'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Filter buttons
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: _FilterButton(
                    label: 'All',
                    isSelected: _filterStatus == 'all',
                    onTap: () => setState(() => _filterStatus = 'all'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterButton(
                    label: 'Pending',
                    isSelected: _filterStatus == 'pending',
                    onTap: () => setState(() => _filterStatus = 'pending'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterButton(
                    label: 'Confirmed',
                    isSelected: _filterStatus == 'confirmed',
                    onTap: () => setState(() => _filterStatus = 'confirmed'),
                  ),
                ),
              ],
            ),
          ),
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            margin: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade400,
                  Colors.blue.shade600,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  spreadRadius: 2,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send,
                    color: Colors.blue,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transmit Requests',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Credit wallet transmit requests',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Table Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Table(
                columnWidths: {
                  0: const FlexColumnWidth(0.8), // No.
                  1: const FlexColumnWidth(2.5), // Driver Name
                  2: const FlexColumnWidth(1.8), // Amount
                  3: const FlexColumnWidth(2.0), // Date
                  4: const FlexColumnWidth(1.2), // Status
                },
                children: const [
                  TableRow(
                    children: [
                      _HeaderCell('No.'),
                      _HeaderCell('Driver Name'),
                      _HeaderCell('Amount'),
                      _HeaderCell('Date'),
                      _HeaderCell('Status'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Transmit Requests List
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(USERS)
                    .where('role', isEqualTo: USER_ROLE_DRIVER)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading requests: ${snapshot.error}',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.red,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  // Collect all transmit requests
                  final List<TransmitRequest> requests = [];
                  for (var doc in snapshot.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final transmitRequests =
                        data['transmitRequests'] as List<dynamic>? ?? [];

                    for (var requestData in transmitRequests) {
                      if (requestData is Map<String, dynamic>) {
                        final status = requestData['status'] as String? ?? '';
                        final type = requestData['type'] as String? ?? '';

                        if (type == 'credit_wallet_transmit') {
                          // Apply filter
                          if (_filterStatus == 'all' ||
                              (_filterStatus == 'pending' &&
                                  status == 'pending') ||
                              (_filterStatus == 'confirmed' &&
                                  status == 'confirmed')) {
                            requests.add(TransmitRequest(
                              userId: doc.id,
                              requestId: requestData['id'] as String? ?? '',
                              driverName:
                                  '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                      .trim(),
                              amount:
                                  (requestData['amount'] as num?)?.toDouble() ??
                                      0.0,
                              status: status,
                              createdAt: requestData['createdAt'] as Timestamp?,
                              confirmedAt:
                                  requestData['confirmedAt'] as Timestamp?,
                            ));
                          }
                        }
                      }
                    }
                  }

                  // Sort by date (newest first)
                  requests.sort((a, b) {
                    final aDate = a.createdAt ?? Timestamp.now();
                    final bDate = b.createdAt ?? Timestamp.now();
                    return bDate.compareTo(aDate);
                  });

                  if (requests.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.send_outlined,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _filterStatus == 'all'
                                ? 'No transmit requests'
                                : 'No $_filterStatus transmit requests',
                            style: const TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.2),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      itemCount: requests.length,
                      itemBuilder: (context, index) {
                        final request = requests[index];

                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.blue.withOpacity(0.1),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Table(
                            columnWidths: {
                              0: const FlexColumnWidth(0.8), // No.
                              1: const FlexColumnWidth(2.5), // Driver Name
                              2: const FlexColumnWidth(1.8), // Amount
                              3: const FlexColumnWidth(2.0), // Date
                              4: const FlexColumnWidth(1.2), // Status
                            },
                            children: [
                              TableRow(
                                children: [
                                  _DataCell('${index + 1}'),
                                  _DataCell(request.driverName),
                                  _DataCell(
                                    '₱${request.amount.toStringAsFixed(2)}',
                                  ),
                                  _DataCell(_formatDate(request.createdAt)),
                                  _DataCell(
                                    request.status == 'confirmed'
                                        ? 'Confirmed'
                                        : 'Pending',
                                    color: request.status == 'confirmed'
                                        ? Colors.green
                                        : Colors.orange,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    final date = timestamp.toDate();
    return DateFormat('MMM dd, yyyy • hh:mm a').format(date);
  }
}

class TransmitRequest {
  final String userId;
  final String requestId;
  final String driverName;
  final double amount;
  final String status;
  final Timestamp? createdAt;
  final Timestamp? confirmedAt;

  TransmitRequest({
    required this.userId,
    required this.requestId,
    required this.driverName,
    required this.amount,
    required this.status,
    this.createdAt,
    this.confirmedAt,
  });
}

class _FilterButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;

  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Colors.black87,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final Color? color;

  const _DataCell(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text.isEmpty ? '-' : text,
        style: TextStyle(
          fontSize: 11,
          color: color ?? (text.isEmpty ? Colors.grey : Colors.black87),
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }
}

