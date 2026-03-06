import 'package:flutter/material.dart';
import 'package:brgy/customers_page.dart';
import 'package:brgy/services/user_segment_service.dart';

class UserSegmentsPage extends StatefulWidget {
  const UserSegmentsPage({super.key});

  @override
  State<UserSegmentsPage> createState() => _UserSegmentsPageState();
}

class _UserSegmentsPageState extends State<UserSegmentsPage> {
  Map<String, int> _segmentCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSegmentCounts();
  }

  Future<void> _loadSegmentCounts() async {
    setState(() => _loading = true);
    try {
      final counts = await UserSegmentService.getSegmentCounts();
      if (mounted) {
        setState(() {
          _segmentCounts = counts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Segments'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSegmentCounts,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTotalCard(),
                const SizedBox(height: 16),
                ...UserSegmentService.segments.map(
                  (segment) => _buildSegmentCard(
                    segment,
                    _segmentCounts[segment] ?? 0,
                  ),
                ),
                if (_segmentCounts['unknown'] != null &&
                    (_segmentCounts['unknown'] ?? 0) > 0)
                  _buildSegmentCard(
                    'unknown',
                    _segmentCounts['unknown']!,
                  ),
              ],
            ),
    );
  }

  Widget _buildTotalCard() {
    final total = _segmentCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.people, size: 40, color: Colors.blue[700]),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Active Customers',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  '$total',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentCard(String segment, int count) {
    final total = _segmentCounts.values.fold<int>(
      0,
      (sum, c) => sum + c,
    );
    final percentage = total > 0
        ? ((count / total) * 100).toStringAsFixed(1)
        : '0.0';
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: UserSegmentService.getSegmentColor(segment),
          ),
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        title: Text(
          UserSegmentService.getSegmentDisplayName(segment),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('$percentage% of users'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CustomersPage(initialSegment: segment),
            ),
          );
        },
      ),
    );
  }
}
