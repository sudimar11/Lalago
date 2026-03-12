import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/main.dart';
import 'package:brgy/services/reviews_service.dart';
import 'package:intl/intl.dart';

class ReviewsModerationPage extends StatefulWidget {
  const ReviewsModerationPage({super.key});

  @override
  State<ReviewsModerationPage> createState() => _ReviewsModerationPageState();
}

class _ReviewsModerationPageState extends State<ReviewsModerationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedVendorId;
  String? _selectedDriverId;
  int? _ratingFilter;
  String? _statusFilter;
  List<Map<String, dynamic>> _vendors = [];
  DateTime? _dateStart;
  DateTime? _dateEnd;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadVendors();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVendors() async {
    final v = await ReviewsService.getVendors();
    if (mounted) setState(() => _vendors = v);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filterReviews(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((d) {
      final data = d.data();
      if (_selectedVendorId != null) {
        final vid = data['VendorId'] ?? data['vendorId'] ?? '';
        if (vid != _selectedVendorId) return false;
      }
      if (_selectedDriverId != null) {
        final did = data['driverId'] ?? '';
        if (did != _selectedDriverId) return false;
      }
      if (_ratingFilter != null) {
        final r = (data['rating'] as num?)?.toDouble() ?? 0;
        if (r.round() != _ratingFilter) return false;
      }
      if (_statusFilter != null && _statusFilter!.isNotEmpty) {
        final s = data['status'] ?? 'approved';
        if (s != _statusFilter) return false;
      }
      if (_dateStart != null) {
        final ts = data['createdAt'] as Timestamp?;
        if (ts == null) return false;
        if (ts.toDate().isBefore(_dateStart!)) return false;
      }
      if (_dateEnd != null) {
        final ts = data['createdAt'] as Timestamp?;
        if (ts == null) return false;
        if (ts.toDate().isAfter(_dateEnd!)) return false;
      }
      return true;
    }).toList();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _tabFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int tabIndex,
  ) {
    var filtered = _filterReviews(docs);
    switch (tabIndex) {
      case 1:
        filtered = filtered
            .where((d) =>
                (d.data()['flaggedBy'] as List?)?.isNotEmpty == true)
            .toList();
        break;
      case 2:
        filtered = filtered
            .where((d) => (d.data()['status'] ?? 'approved') == 'pending')
            .toList();
        break;
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Moderation'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          tabs: const [
            Tab(text: 'All Reviews'),
            Tab(text: 'Flagged'),
            Tab(text: 'Pending'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ReviewsService.getAllReviewsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          final analytics = _computeAnalytics(docs);

          return Column(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAnalytics(analytics),
                    const SizedBox(height: 16),
                    _buildFilters(),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildReviewList(_tabFilter(docs, 0)),
                    _buildReviewList(_tabFilter(docs, 1)),
                    _buildReviewList(_tabFilter(docs, 2)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, dynamic> _computeAnalytics(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var total = 0;
    var sum = 0.0;
    final byRating = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    final byVendor = <String, int>{};

    for (final d in docs) {
      final data = d.data();
      if ((data['status'] ?? 'approved') == 'hidden') continue;
      total++;
      final r = (data['rating'] as num?)?.toDouble() ?? 0;
      sum += r;
      byRating[(r.round().clamp(1, 5))] =
          (byRating[(r.round().clamp(1, 5))] ?? 0) + 1;
      final vid = (data['VendorId'] ?? data['vendorId'] ?? '').toString();
      if (vid.isNotEmpty) {
        byVendor[vid] = (byVendor[vid] ?? 0) + 1;
      }
    }
    return {
      'total': total,
      'avgRating': total > 0 ? sum / total : 0,
      'byRating': byRating,
      'byVendor': byVendor,
    };
  }

  Widget _buildAnalytics(Map<String, dynamic> analytics) {
    final total = analytics['total'] as int;
    final avg = (analytics['avgRating'] as num).toDouble();
    final byRating = analytics['byRating'] as Map<int, int>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Platform Analytics',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('Total Reviews', total.toString()),
                const SizedBox(width: 12),
                _statCard('Avg Rating', avg.toStringAsFixed(1)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: PieChart(
                PieChartData(
                  sections: [1, 2, 3, 4, 5]
                      .map((i) {
                        final v = (byRating[i] ?? 0).toDouble();
                        return PieChartSectionData(
                          value: v > 0 ? v : 0.01,
                          title: '$i★',
                          color: [
                            Colors.red,
                            Colors.orange,
                            Colors.amber,
                            Colors.lightGreen,
                            Colors.green
                          ][i - 1],
                        );
                      })
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            Text(value, style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            value: _selectedVendorId,
            decoration: const InputDecoration(
              labelText: 'Restaurant',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              ..._vendors.map((v) => DropdownMenuItem(
                    value: v['id'] as String?,
                    child: Text(
                      (v['title'] ?? v['id'] ?? '').toString(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: (v) => setState(() => _selectedVendorId = v),
          ),
        ),
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<int>(
            value: _ratingFilter,
            decoration: const InputDecoration(
              labelText: 'Rating',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              ...List.generate(5, (i) => DropdownMenuItem(
                    value: i + 1,
                    child: Text('${i + 1}★'),
                  )),
            ],
            onChanged: (v) => setState(() => _ratingFilter = v),
          ),
        ),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<String>(
            value: _statusFilter,
            decoration: const InputDecoration(
              labelText: 'Status',
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('All')),
              DropdownMenuItem(value: 'approved', child: Text('Approved')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'hidden', child: Text('Hidden')),
              DropdownMenuItem(value: 'flagged', child: Text('Flagged')),
            ],
            onChanged: (v) => setState(() => _statusFilter = v),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (range != null && mounted) {
              setState(() {
                _dateStart = range.start;
                _dateEnd = range.end;
              });
            }
          },
          tooltip: 'Date range',
        ),
      ],
    );
  }

  Widget _buildReviewList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.isEmpty) {
      return const Center(child: Text('No reviews match filters'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final doc = docs[i];
        return _ReviewModerationCard(
          docId: doc.id,
          data: doc.data(),
          onApprove: () => _updateStatus(doc.id, 'approved'),
          onHide: () => _updateStatus(doc.id, 'hidden'),
          onDelete: () => _deleteReview(doc.id),
          onDismissFlags: () => _dismissFlags(doc.id),
          onAdminReply: () => _showAdminReply(doc.id),
        );
      },
    );
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await ReviewsService.updateReviewStatus(id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status set to $status')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteReview(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete review'),
        content: const Text('Permanently delete this review?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ReviewsService.deleteReview(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _dismissFlags(String id) async {
    try {
      await ReviewsService.dismissReviewFlags(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flags dismissed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showAdminReply(String id) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Admin Reply'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Write your reply...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    final user = MyAppState.currentUser;
    if (user == null) return;
    try {
      await ReviewsService.addReviewReply(
        id,
        result.trim(),
        adminId: user.userID,
        adminName: user.fullName(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _ReviewModerationCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onApprove;
  final VoidCallback onHide;
  final VoidCallback onDelete;
  final VoidCallback onDismissFlags;
  final VoidCallback onAdminReply;

  const _ReviewModerationCard({
    required this.docId,
    required this.data,
    required this.onApprove,
    required this.onHide,
    required this.onDelete,
    required this.onDismissFlags,
    required this.onAdminReply,
  });

  @override
  Widget build(BuildContext context) {
    final uname = (data['uname'] ?? '').toString();
    final comment = (data['comment'] ?? '').toString();
    final rating = (data['rating'] as num?)?.toDouble() ?? 0;
    final vendorId = (data['VendorId'] ?? data['vendorId'] ?? '').toString();
    final driverId = (data['driverId'] ?? '').toString();
    final status = (data['status'] ?? 'approved').toString();
    final flaggedBy = data['flaggedBy'] as List? ?? [];
    final createdAt = data['createdAt'] as Timestamp?;
    final replies = data['replies'] as List? ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  uname.isEmpty ? 'Anonymous' : uname,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rating.toStringAsFixed(1)}★',
                  style: const TextStyle(color: Colors.orange),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status == 'flagged'
                        ? Colors.red.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (createdAt != null)
              Text(
                DateFormat('MMM dd, yyyy HH:mm').format(createdAt.toDate()),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            if (vendorId.isNotEmpty)
              Text('Restaurant: $vendorId', style: const TextStyle(fontSize: 12)),
            if (driverId.isNotEmpty)
              Text('Driver: $driverId', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text(comment),
            if (flaggedBy.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Flagged:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...flaggedBy.map((f) {
                final m = f is Map ? Map<String, dynamic>.from(f) : {};
                return Text(
                  '  ${m['userId']}: ${m['reason'] ?? ''}',
                  style: const TextStyle(fontSize: 12),
                );
              }),
            ],
            if (replies.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...replies.map((r) {
                final m = r is Map ? Map<String, dynamic>.from(r) : {};
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            m['userName'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (m['userType'] ?? 'Reply').toString(),
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      Text(m['text'] ?? ''),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: status != 'approved' ? onApprove : null,
                  child: const Text('Approve'),
                ),
                ElevatedButton(
                  onPressed: status != 'hidden' ? onHide : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  child: const Text('Hide'),
                ),
                if (flaggedBy.isNotEmpty)
                  ElevatedButton(
                    onPressed: onDismissFlags,
                    child: const Text('Dismiss Flags'),
                  ),
                ElevatedButton(
                  onPressed: onAdminReply,
                  child: const Text('Reply'),
                ),
                ElevatedButton(
                  onPressed: onDelete,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
