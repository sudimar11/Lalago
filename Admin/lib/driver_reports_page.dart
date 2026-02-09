import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/model/driver_report.dart';
import 'package:brgy/services/driver_report_service.dart';
import 'package:brgy/main.dart';
import 'package:brgy/pages/driver_report_detail_page.dart';
import 'package:intl/intl.dart';

class DriverReportsPage extends StatefulWidget {
  const DriverReportsPage({super.key});

  @override
  State<DriverReportsPage> createState() => _DriverReportsPageState();
}

class _DriverReportsPageState extends State<DriverReportsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedStatus;
  String? _selectedDriverId;
  String? _selectedOrderId;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _sortNewestFirst = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _getReportsStream() {
    if (_selectedStatus != null) {
      return DriverReportService.getDriverReportsByStatus(_selectedStatus!);
    } else if (_selectedDriverId != null) {
      return DriverReportService.getDriverReportsByDriver(_selectedDriverId!);
    } else if (_selectedOrderId != null) {
      return DriverReportService.getDriverReportsByOrder(_selectedOrderId!);
    } else if (_startDate != null && _endDate != null) {
      return DriverReportService.getDriverReportsByDateRange(
        _startDate!,
        _endDate!,
      );
    } else {
      return DriverReportService.getDriverReportsStream();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = null;
      _selectedDriverId = null;
      _selectedOrderId = null;
      _startDate = null;
      _endDate = null;
      _searchController.clear();
    });
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Color _getStatusColor(DriverReportStatus status) {
    switch (status) {
      case DriverReportStatus.pending:
        return Colors.orange;
      case DriverReportStatus.under_review:
        return Colors.blue;
      case DriverReportStatus.resolved:
        return Colors.green;
      case DriverReportStatus.dismissed:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Reports'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filters',
            onPressed: () => _showFilterDialog(),
          ),
          if (_selectedStatus != null ||
              _selectedDriverId != null ||
              _selectedOrderId != null ||
              _startDate != null ||
              _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear Filters',
              onPressed: _clearFilters,
            ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by order ID, driver ID, or complaint...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              ),
            ),
          ),

          // Status filter chips
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildStatusChip('All', null),
                const SizedBox(width: 8),
                _buildStatusChip('Pending', 'pending'),
                const SizedBox(width: 8),
                _buildStatusChip('Under Review', 'under_review'),
                const SizedBox(width: 8),
                _buildStatusChip('Resolved', 'resolved'),
                const SizedBox(width: 8),
                _buildStatusChip('Dismissed', 'dismissed'),
              ],
            ),
          ),

          // Reports list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getReportsStream(),
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
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.report_problem, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No driver reports found',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                // Parse and filter reports
                List<DriverReport> reports = [];
                for (var doc in docs) {
                  try {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['type'] == 'driver_report') {
                      final report = DriverReport.fromJson(data, doc.id);
                      reports.add(report);
                    }
                  } catch (e) {
                    print('Error parsing report ${doc.id}: $e');
                  }
                }

                // Apply search filter
                if (_query.isNotEmpty) {
                  reports = reports.where((report) {
                    return report.orderId.toLowerCase().contains(_query) ||
                        report.driverId.toLowerCase().contains(_query) ||
                        report.complaint.toLowerCase().contains(_query);
                  }).toList();
                }

                // Sort by date
                reports.sort((a, b) {
                  final aTime = a.createdAt.toDate();
                  final bTime = b.createdAt.toDate();
                  return _sortNewestFirst
                      ? bTime.compareTo(aTime)
                      : aTime.compareTo(bTime);
                });

                // Count by status
                final pendingCount =
                    reports.where((r) => r.status == DriverReportStatus.pending).length;
                final underReviewCount = reports
                    .where((r) => r.status == DriverReportStatus.under_review)
                    .length;
                final resolvedCount =
                    reports.where((r) => r.status == DriverReportStatus.resolved).length;
                final dismissedCount =
                    reports.where((r) => r.status == DriverReportStatus.dismissed).length;

                return Column(
                  children: [
                    // Summary cards
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'Total',
                              reports.length.toString(),
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryCard(
                              'Pending',
                              pendingCount.toString(),
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryCard(
                              'Resolved',
                              resolvedCount.toString(),
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Reports list
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: reports.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final report = reports[index];
                          return _buildReportCard(report);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String? status) {
    final isSelected = _selectedStatus == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedStatus = selected ? status : null;
        });
      },
      selectedColor: Colors.orange.withOpacity(0.3),
      checkmarkColor: Colors.orange,
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(DriverReport report) {
    final statusColor = _getStatusColor(report.status);
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DriverReportDetailPage(report: report),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      report.status.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormat.format(report.createdAt.toDate()),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.receipt, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Order: ${report.orderId}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.drive_eta, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Driver: ${report.driverId}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  report.complaint,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (report.adminNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.note, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      '${report.adminNotes.length} admin note(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Reports'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Date Range',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _selectDateRange,
                      child: Text(
                        _startDate != null && _endDate != null
                            ? '${DateFormat('MMM dd').format(_startDate!)} - ${DateFormat('MMM dd').format(_endDate!)}'
                            : 'Select Date Range',
                      ),
                    ),
                  ),
                  if (_startDate != null && _endDate != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _startDate = null;
                          _endDate = null;
                        });
                        Navigator.pop(context);
                        _showFilterDialog();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Sort Order',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              RadioListTile<bool>(
                title: const Text('Newest First'),
                value: true,
                groupValue: _sortNewestFirst,
                onChanged: (value) {
                  setState(() {
                    _sortNewestFirst = value ?? true;
                  });
                },
              ),
              RadioListTile<bool>(
                title: const Text('Oldest First'),
                value: false,
                groupValue: _sortNewestFirst,
                onChanged: (value) {
                  setState(() {
                    _sortNewestFirst = value ?? false;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

