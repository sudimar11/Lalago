import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
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
  bool _syncing = false;
  String? _syncMessage;

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

  Future<void> _runMigration() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    const batchSize = 200;
    var totalProcessed = 0;
    var skip = 0;
    var batchNum = 1;
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
          'runUserSegmentMigration',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        );

    try {
      var hasMore = true;

      while (hasMore && mounted) {
        setState(() => _syncMessage = 'Syncing batch $batchNum...');

        final result = await callable.call(<String, dynamic>{
          'max': batchSize,
          'skip': skip,
        });

        final data = result.data as Map<String, dynamic>? ?? {};

        if (data['success'] != true) {
          if (mounted) {
            setState(() {
              _syncing = false;
              _syncMessage = 'Error: ${data['error'] ?? 'Unknown'}';
            });
          }
          return;
        }

        final processed = (data['processed'] as num?)?.toInt() ?? 0;
        totalProcessed += processed;
        final hint = data['hint'] as String?;

        if (hint != null && processed >= batchSize) {
          skip = (data['nextSkip'] as num?)?.toInt() ?? skip + processed;
          batchNum++;
        } else {
          hasMore = false;
        }
      }

      if (mounted) {
        setState(() {
          _syncing = false;
          _syncMessage = 'Synced $totalProcessed users';
        });
        await _loadSegmentCounts();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncMessage = totalProcessed > 0
              ? 'Partial: $totalProcessed synced. Error: ${e.message}'
              : 'Error: ${e.message}';
        });
        if (totalProcessed > 0) await _loadSegmentCounts();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncMessage = totalProcessed > 0
              ? 'Partial: $totalProcessed synced. Error: $e'
              : 'Error: $e';
        });
        if (totalProcessed > 0) await _loadSegmentCounts();
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
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: _syncing ? null : _runMigration,
            tooltip: 'Sync segments (run migration)',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSegmentCounts,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final total = _segmentCounts.values.fold<int>(0, (sum, c) => sum + c);
    final segmentRows = <Widget>[
      if (_syncMessage != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _syncMessage!,
            style: TextStyle(
              color: _syncMessage!.startsWith('Error')
                  ? Colors.red[700]
                  : Colors.green[700],
              fontSize: 13,
            ),
          ),
        ),
      _buildTotalCard(total),
      const SizedBox(height: 16),
      ...UserSegmentService.segments.map((segment) {
        final count = _segmentCounts[segment] ?? 0;
        final pct =
            total > 0 ? ((count / total) * 100).toStringAsFixed(1) : '0.0';
        return _buildSegmentCard(segment, count, total, pct);
      }),
      if ((_segmentCounts['unknown'] ?? 0) > 0) ...[
        _buildSegmentCard(
          'unknown',
          _segmentCounts['unknown']!,
          total,
          total > 0
              ? ((_segmentCounts['unknown']! / total) * 100).toStringAsFixed(1)
              : '0.0',
        ),
      ],
    ];
    return ListView(
      key: ValueKey('segments_total_$total'),
      padding: const EdgeInsets.all(16),
      children: segmentRows,
    );
  }

  Widget _buildTotalCard(int total) {
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

  Widget _buildSegmentCard(
    String segment,
    int count,
    int total,
    String percentage,
  ) {
    return Card(
      key: ValueKey('seg_$segment'),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$percentage% of users',
              key: ValueKey('pct_${segment}_$percentage'),
            ),
            const SizedBox(height: 2),
            Text(
              UserSegmentService.getSegmentDescription(segment),
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
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
