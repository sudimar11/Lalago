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

  static const _tableColumnWidths = <int, FlexColumnWidth>{
    0: FlexColumnWidth(0.8),
    1: FlexColumnWidth(2.5),
    2: FlexColumnWidth(1.8),
    3: FlexColumnWidth(2.0),
    4: FlexColumnWidth(1.2),
  };

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Transmit Requests', style: theme.titleLarge),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _TransmitFilterBar(
            value: _filterStatus,
            onChanged: (v) => setState(() => _filterStatus = v),
          ),
          const _TransmitPageHeader(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _TransmitTableHeader(columnWidths: _tableColumnWidths),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(USERS)
                    .where('role', isEqualTo: USER_ROLE_DRIVER)
                    .snapshots(),
                builder: (context, snapshot) {
                  return RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: _buildTransmitListBody(
                      context,
                      snapshot,
                      theme,
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

  Widget _buildTransmitListBody(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot> snapshot,
    TextTheme theme,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 320,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (snapshot.hasError) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 320,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  SelectableText.rich(
                    TextSpan(
                      text: 'Error loading requests: ${snapshot.error}',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.red,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final requests = _parseTransmitRequests(snapshot.data, _filterStatus);
    if (requests.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 320,
            child: Center(
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
                    style: theme.bodyLarge?.copyWith(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final request = requests[index];
          return _TransmitRequestRow(
            request: request,
            index: index,
            formatDate: _formatDate,
            columnWidths: _tableColumnWidths,
          );
        },
      ),
    );
  }

  List<TransmitRequest> _parseTransmitRequests(
    QuerySnapshot? data,
    String filterStatus,
  ) {
    final List<TransmitRequest> requests = [];
    for (var doc in data?.docs ?? []) {
      final docData = doc.data() as Map<String, dynamic>;
      final transmitRequests =
          docData['transmitRequests'] as List<dynamic>? ?? [];

      for (var requestData in transmitRequests) {
        if (requestData is Map<String, dynamic>) {
          final status = requestData['status'] as String? ?? '';
          final type = requestData['type'] as String? ?? '';

          if (type == 'credit_wallet_transmit') {
            if (filterStatus == 'all' ||
                (filterStatus == 'pending' && status == 'pending') ||
                (filterStatus == 'confirmed' && status == 'confirmed')) {
              requests.add(TransmitRequest(
                userId: doc.id,
                requestId: requestData['id'] as String? ?? '',
                driverName:
                    '${docData['firstName'] ?? ''} ${docData['lastName'] ?? ''}'
                        .trim(),
                amount:
                    (requestData['amount'] as num?)?.toDouble() ?? 0.0,
                status: status,
                createdAt: requestData['createdAt'] as Timestamp?,
                confirmedAt: requestData['confirmedAt'] as Timestamp?,
              ));
            }
          }
        }
      }
    }
    requests.sort((a, b) {
      final aDate = a.createdAt ?? Timestamp.now();
      final bDate = b.createdAt ?? Timestamp.now();
      return bDate.compareTo(aDate);
    });
    return requests;
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

class _TransmitFilterBar extends StatelessWidget {
  const _TransmitFilterBar({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: _FilterButton(
              label: 'All',
              isSelected: value == 'all',
              onTap: () => onChanged('all'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FilterButton(
              label: 'Pending',
              isSelected: value == 'pending',
              onTap: () => onChanged('pending'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _FilterButton(
              label: 'Confirmed',
              isSelected: value == 'confirmed',
              onTap: () => onChanged('confirmed'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransmitPageHeader extends StatelessWidget {
  const _TransmitPageHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: const Icon(Icons.send, color: Colors.blue, size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Transmit Requests',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Credit wallet transmit requests',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransmitTableHeader extends StatelessWidget {
  const _TransmitTableHeader({required this.columnWidths});

  final Map<int, FlexColumnWidth> columnWidths;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Table(
        columnWidths: columnWidths,
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
    );
  }
}

class _TransmitRequestRow extends StatelessWidget {
  const _TransmitRequestRow({
    required this.request,
    required this.index,
    required this.formatDate,
    required this.columnWidths,
  });

  final TransmitRequest request;
  final int index;
  final String Function(Timestamp?) formatDate;
  final Map<int, FlexColumnWidth> columnWidths;

  @override
  Widget build(BuildContext context) {
    final statusText =
        request.status == 'confirmed' ? 'Confirmed' : 'Pending';
    final statusColor =
        request.status == 'confirmed' ? Colors.green : Colors.orange;

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
        columnWidths: columnWidths,
        children: [
          TableRow(
            children: [
              _DataCell('${index + 1}'),
              _DataCell(request.driverName),
              _DataCell('₱${request.amount.toStringAsFixed(2)}'),
              _DataCell(formatDate(request.createdAt)),
              _DataCell(statusText, color: statusColor),
            ],
          ),
        ],
      ),
    );
  }
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

