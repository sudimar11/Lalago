import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:brgy/services/user_segment_service.dart';

class NotificationProgressPage extends StatelessWidget {
  const NotificationProgressPage({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaign Progress'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              // StreamBuilder auto-updates; icon provides visual feedback
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notification_jobs')
            .doc(jobId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          final doc = snapshot.data;
          if (doc == null || !doc.exists) {
            return const Center(child: Text('Job not found'));
          }
          final data = doc.data() ?? {};
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, data),
                const SizedBox(height: 24),
                _buildStatusIndicator(context, data),
                const SizedBox(height: 24),
                _buildProgressBar(context, data),
                const SizedBox(height: 24),
                _buildStatsGrid(context, data),
                if (_shouldShowEta(data)) ...[
                  const SizedBox(height: 24),
                  _buildEta(context, data),
                ],
                if (_hasError(data)) ...[
                  const SizedBox(height: 24),
                  _buildErrorSection(context, data),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final payload = data['payload'] as Map<String, dynamic>? ?? {};
    final title = payload['title'] as String? ?? 'Untitled';
    final body = payload['body'] as String? ?? '';
    final kind = data['kind'] as String? ?? '';
    final segment = payload['segment'] as String? ?? 'all';
    final configName = payload['configName'] as String? ?? 'Happy Hour';

    final segmentLabel = kind == 'happy_hour' || segment == 'all'
        ? 'All Customers'
        : UserSegmentService.getSegmentDisplayName(segment);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'Target: $segmentLabel',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            if (kind == 'happy_hour') ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.local_offer, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Config: $configName',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
            if (body.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                body.length > 120 ? '${body.substring(0, 120)}...' : body,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final status = data['status'] as String? ?? 'unknown';
    IconData icon;
    Color color;
    String label;

    switch (status) {
      case 'queued':
        icon = Icons.schedule;
        color = Colors.grey;
        label = 'Queued';
        break;
      case 'scheduled':
        icon = Icons.schedule_send;
        color = Colors.blue;
        final scheduledFor = data['scheduledFor'] as Timestamp?;
        label = scheduledFor != null
            ? 'Scheduled for ${DateFormat.yMd().add_Hm().format(scheduledFor.toDate())}'
            : 'Scheduled';
        break;
      case 'in_progress':
        icon = Icons.hourglass_empty;
        color = Colors.orange;
        label = 'Sending...';
        break;
      case 'completed':
        icon = Icons.check_circle;
        color = Colors.green;
        label = 'Completed';
        break;
      case 'failed':
        icon = Icons.error;
        color = Colors.red;
        label = 'Failed';
        break;
      case 'cancelled':
        icon = Icons.cancel;
        color = Colors.amber;
        label = 'Cancelled';
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
        label = status;
    }

    return Row(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final stats = data['stats'] as Map<String, dynamic>?;
    final totalRecipients = _getInt(stats?['totalRecipients']) ??
        data['totalUsers'] as int? ??
        0;
    final percentComplete = _getNum(stats?['percentComplete']);
    double progress = 0.0;
    if (totalRecipients > 0 && percentComplete != null) {
      progress = (percentComplete / 100).clamp(0.0, 1.0);
    }

    if (totalRecipients == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  '${(progress * 100).round()}% complete',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey[300],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final stats = data['stats'] as Map<String, dynamic>?;
    final totalRecipients = _getInt(stats?['totalRecipients']) ??
        data['totalUsers'] as int? ??
        0;
    final processedCount = _getInt(stats?['processedCount']) ??
        data['processedCount'] as int? ??
        0;
    final successfulDeliveries = _getInt(stats?['successfulDeliveries']) ??
        data['sentCount'] as int? ??
        0;
    final failedDeliveries = _getInt(stats?['failedDeliveries']) ??
        data['errorCount'] as int? ??
        0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: [
        _buildStatCard(
          context,
          'Total Recipients',
          '$totalRecipients',
          Icons.people,
          Colors.blue,
        ),
        _buildStatCard(
          context,
          'Processed',
          '$processedCount',
          Icons.pending_actions,
          Colors.orange,
        ),
        _buildStatCard(
          context,
          'Successful',
          '$successfulDeliveries',
          Icons.check_circle,
          Colors.green,
        ),
        _buildStatCard(
          context,
          'Failed',
          '$failedDeliveries',
          Icons.error,
          failedDeliveries > 0 ? Colors.red : Colors.grey,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowEta(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    if (status != 'in_progress') return false;

    final stats = data['stats'] as Map<String, dynamic>?;
    final totalRecipients = _getInt(stats?['totalRecipients']) ??
        data['totalUsers'] as int? ??
        0;
    final processedCount = _getInt(stats?['processedCount']) ??
        data['processedCount'] as int? ??
        0;

    if (totalRecipients <= 0 || processedCount <= 0) return false;
    if (processedCount >= totalRecipients) return false;

    final batchStartedAt = data['batchStartedAt'];
    if (batchStartedAt == null) return false;

    return true;
  }

  Widget _buildEta(BuildContext context, Map<String, dynamic> data) {
    final stats = data['stats'] as Map<String, dynamic>?;
    final totalRecipients = _getInt(stats?['totalRecipients']) ??
        data['totalUsers'] as int? ??
        0;
    final processedCount = _getInt(stats?['processedCount']) ??
        data['processedCount'] as int? ??
        0;
    final batchStartedAt = data['batchStartedAt'] as Timestamp?;
    final lastUpdatedAt = _getTimestamp(stats?['lastUpdatedAt']) ??
        data['updatedAt'] as Timestamp?;

    final DateTime startTime;
    final DateTime endTime;

    if (batchStartedAt != null) {
      startTime = batchStartedAt.toDate();
    } else {
      return const SizedBox.shrink();
    }

    if (lastUpdatedAt != null) {
      endTime = lastUpdatedAt.toDate();
    } else {
      endTime = DateTime.now();
    }

    final elapsedSeconds = endTime.difference(startTime).inSeconds;
    if (elapsedSeconds <= 0) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Calculating time remaining...',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ),
      );
    }

    final rate = processedCount / elapsedSeconds;
    final remaining = totalRecipients - processedCount;
    final etaSeconds = rate > 0 ? (remaining / rate).round() : 0;

    String etaText;
    if (etaSeconds < 30) {
      etaText = 'Completing soon';
    } else if (etaSeconds < 60) {
      etaText = 'About 1 minute remaining';
    } else {
      final minutes = (etaSeconds / 60).round();
      etaText = 'About $minutes minutes remaining';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.timer, color: Colors.orange[700]),
            const SizedBox(width: 12),
            Text(
              etaText,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.orange[800],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasError(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    return status == 'failed';
  }

  Widget _buildErrorSection(BuildContext context, Map<String, dynamic> data) {
    final error = data['error'] as String? ?? 'Unknown error';

    return Card(
      elevation: 2,
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Colors.red[700]),
                const SizedBox(width: 8),
                Text(
                  'Error',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              error,
              style: TextStyle(
                fontSize: 13,
                color: Colors.red[900],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int? _getInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  double? _getNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return null;
  }

  Timestamp? _getTimestamp(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v;
    return null;
  }
}
