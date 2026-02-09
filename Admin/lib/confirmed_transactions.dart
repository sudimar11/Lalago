import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class ConfirmedTransactionsPage extends StatefulWidget {
  const ConfirmedTransactionsPage({super.key});

  @override
  State<ConfirmedTransactionsPage> createState() =>
      _ConfirmedTransactionsPageState();
}

class _ConfirmedTransactionsPageState
    extends State<ConfirmedTransactionsPage> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Confirm Remittance'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black,
                    Colors.black.withOpacity(0.8),
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
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Confirmed Transactions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Completed remittances',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Date Filter
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Filter by Date:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedDate = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.green[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedDate == null
                                  ? 'Select Date'
                                  : _formatDisplayDate(_selectedDate!),
                              style: TextStyle(
                                color: _selectedDate == null
                                    ? Colors.grey[600]
                                    : Colors.black87,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_selectedDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      color: Colors.red,
                      onPressed: () {
                        setState(() {
                          _selectedDate = null;
                        });
                      },
                      tooltip: 'Clear filter',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Total Amount Summary
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection(USERS)
                  .where('role', isEqualTo: USER_ROLE_DRIVER)
                  .snapshots(),
              builder: (context, snapshot) {
                double totalAmount = 0.0;
                int transactionCount = 0;

                if (snapshot.hasData) {
                  for (var doc in snapshot.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final transmitRequests =
                        data['transmitRequests'] as List<dynamic>? ?? [];

                    for (var requestData in transmitRequests) {
                      if (requestData is Map<String, dynamic>) {
                        final status = requestData['status'] as String? ?? '';
                        final type = requestData['type'] as String? ?? '';

                        if (status == 'confirmed' &&
                            type == 'credit_wallet_transmit') {
                          final confirmedAt =
                              requestData['confirmedAt'] as Timestamp?;

                          // Apply date filter if selected
                          if (_selectedDate != null) {
                            if (confirmedAt == null) continue;
                            final confirmedDate = confirmedAt.toDate();
                            if (confirmedDate.year != _selectedDate!.year ||
                                confirmedDate.month != _selectedDate!.month ||
                                confirmedDate.day != _selectedDate!.day) {
                              continue;
                            }
                          }

                          final amount =
                              (requestData['amount'] as num?)?.toDouble() ?? 0.0;
                          totalAmount += amount;
                          transactionCount++;
                        }
                      }
                    }
                  }
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedDate == null
                                ? 'Total Confirmed Transactions'
                                : 'Total for Selected Date',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$transactionCount transaction${transactionCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Total Amount',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₱${totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Table Header
            Container(
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Table(
                columnWidths: {
                  0: const FlexColumnWidth(0.8), // No.
                  1: const FlexColumnWidth(2.5), // Driver Name
                  2: const FlexColumnWidth(1.8), // Amount
                  3: const FlexColumnWidth(2.0), // Request Date
                  4: const FlexColumnWidth(2.0), // Confirmed Date
                  5: const FlexColumnWidth(1.2), // Status
                },
                children: const [
                  TableRow(
                    children: [
                      _HeaderCell('No.'),
                      _HeaderCell('Driver Name'),
                      _HeaderCell('Amount'),
                      _HeaderCell('Request Date'),
                      _HeaderCell('Confirmed Date'),
                      _HeaderCell('Status'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Confirmed Transactions List
            Expanded(
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
                            'Error loading transactions: ${snapshot.error}',
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

                  // Collect all confirmed remittance requests
                  final List<ConfirmedTransaction> transactions = [];
                  for (var doc in snapshot.data?.docs ?? []) {
                    final data = doc.data() as Map<String, dynamic>;
                    final transmitRequests =
                        data['transmitRequests'] as List<dynamic>? ?? [];

                    for (var requestData in transmitRequests) {
                      if (requestData is Map<String, dynamic>) {
                        final status = requestData['status'] as String? ?? '';
                        final type =
                            requestData['type'] as String? ?? '';

                        if (status == 'confirmed' &&
                            type == 'credit_wallet_transmit') {
                          transactions.add(ConfirmedTransaction(
                            userId: doc.id,
                            requestId: requestData['id'] as String? ?? '',
                            driverName:
                                '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                    .trim(),
                            amount: (requestData['amount'] as num?)
                                    ?.toDouble() ??
                                0.0,
                            createdAt: requestData['createdAt'] as Timestamp?,
                            confirmedAt:
                                requestData['confirmedAt'] as Timestamp?,
                          ));
                        }
                      }
                    }
                  }

                  // Filter by date if selected
                  List<ConfirmedTransaction> filteredTransactions = transactions;
                  if (_selectedDate != null) {
                    filteredTransactions = transactions.where((transaction) {
                      if (transaction.confirmedAt == null) return false;
                      final confirmedDate = transaction.confirmedAt!.toDate();
                      return confirmedDate.year == _selectedDate!.year &&
                          confirmedDate.month == _selectedDate!.month &&
                          confirmedDate.day == _selectedDate!.day;
                    }).toList();
                  }

                  // Sort by confirmed date (newest first)
                  filteredTransactions.sort((a, b) {
                    if (a.confirmedAt == null && b.confirmedAt == null) {
                      return 0;
                    }
                    if (a.confirmedAt == null) return 1;
                    if (b.confirmedAt == null) return -1;
                    return b.confirmedAt!.compareTo(a.confirmedAt!);
                  });

                  if (filteredTransactions.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _selectedDate == null
                                ? 'No confirmed transactions'
                                : 'No transactions found for selected date',
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
                        color: Colors.green.withOpacity(0.2),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      itemCount: filteredTransactions.length,
                      itemBuilder: (context, index) {
                        final transaction = filteredTransactions[index];

                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.green.withOpacity(0.1),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Table(
                            columnWidths: {
                              0: const FlexColumnWidth(0.8), // No.
                              1: const FlexColumnWidth(2.5), // Driver Name
                              2: const FlexColumnWidth(1.8), // Amount
                              3: const FlexColumnWidth(2.0), // Request Date
                              4: const FlexColumnWidth(2.0), // Confirmed Date
                              5: const FlexColumnWidth(1.2), // Status
                            },
                            children: [
                              TableRow(
                                children: [
                                  _DataCell('${index + 1}'),
                                  _DataCell(transaction.driverName),
                                  _DataCell(
                                    '₱${transaction.amount.toStringAsFixed(2)}',
                                  ),
                                  _DataCell(_formatDate(transaction.createdAt)),
                                  _DataCell(
                                    _formatDate(transaction.confirmedAt),
                                  ),
                                  _DataCell(
                                    'Confirmed',
                                    color: Colors.green,
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
          ],
        ),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class ConfirmedTransaction {
  final String userId;
  final String requestId;
  final String driverName;
  final double amount;
  final Timestamp? createdAt;
  final Timestamp? confirmedAt;

  ConfirmedTransaction({
    required this.userId,
    required this.requestId,
    required this.driverName,
    required this.amount,
    this.createdAt,
    this.confirmedAt,
  });
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

