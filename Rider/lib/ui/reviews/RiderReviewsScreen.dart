import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/Ratingmodel.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/performance_tier_helper.dart';
import 'package:intl/intl.dart';

class RiderReviewsScreen extends StatefulWidget {
  const RiderReviewsScreen({Key? key}) : super(key: key);

  @override
  State<RiderReviewsScreen> createState() => _RiderReviewsScreenState();
}

class _RiderReviewsScreenState extends State<RiderReviewsScreen> {
  bool _isLoading = false;

  Future<void> _showReplySheet(RatingModel review) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reply to review',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write your reply...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(COLOR_PRIMARY),
                ),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || result.trim().isEmpty || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = MyAppState.currentUser;
      if (user == null) return;
      await FireStoreUtils.addReviewReply(
        review.id ?? '',
        result.trim(),
        userId: user.userID,
        userType: 'rider',
        userName: user.fullName(),
      );
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _showFlagDialog(RatingModel review) async {
    const reasons = [
      'Inaccurate',
      'Abusive',
      'Not about delivery',
    ];
    String? selected;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          title: const Text('Flag review'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons
                .map((r) => RadioListTile<String>(
                      title: Text(r),
                      value: r,
                      groupValue: selected,
                      onChanged: (v) => setDialogState(() => selected = v),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(ctx, selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(COLOR_PRIMARY),
              ),
              child: const Text('Flag'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = MyAppState.currentUser;
      if (user == null) return;
      await FireStoreUtils.flagReview(
        review.id ?? '',
        userId: user.userID,
        reason: result,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review flagged')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  String _relativeTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays > 30) return DateFormat('MMM d, yyyy').format(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  List<FlSpot> _buildRatingTrend(List<RatingModel> reviews) {
    final now = DateTime.now();
    final spots = <FlSpot>[];
    final byDay = <String, List<double>>{};
    for (var d = 0; d < 30; d++) {
      final date = now.subtract(Duration(days: 29 - d));
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}'
          '-${date.day.toString().padLeft(2, '0')}';
      byDay[key] = [];
    }
    for (final r in reviews) {
      final ts = r.createdAt;
      if (ts == null) continue;
      final dt = ts.toDate();
      final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
          '-${dt.day.toString().padLeft(2, '0')}';
      if (byDay.containsKey(key)) {
        byDay[key]!.add(r.rating ?? 0);
      }
    }
    var i = 0;
    for (final key in byDay.keys.toList()..sort()) {
      final list = byDay[key]!;
      final avg = list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;
      spots.add(FlSpot(i.toDouble(), avg));
      i++;
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final driverId = MyAppState.currentUser?.userID;
    if (driverId == null || driverId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Reviews'),
          backgroundColor: Color(COLOR_PRIMARY),
        ),
        body: Center(
          child: Text(
            'Not signed in',
            style: TextStyle(
              color: isDarkMode(context) ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reviews'),
        backgroundColor: Color(COLOR_PRIMARY),
      ),
      body: Stack(
        children: [
          StreamBuilder<List<RatingModel>>(
            stream: FireStoreUtils.getReviewsByDriver(driverId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }
              final reviews = snapshot.data ?? [];
              final visible = reviews
                  .where((r) => r.status != 'hidden')
                  .toList()
                ..sort((a, b) =>
                    (b.createdAt ?? Timestamp.now())
                        .compareTo(a.createdAt ?? Timestamp.now()));

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(driverId)
                    .snapshots(),
                builder: (context, userSnap) {
                  final data = userSnap.data?.data()
                      as Map<String, dynamic>? ??
                      {};
                  final avgRating =
                      (data['average_rating'] as num?)?.toDouble();
                  final accRate =
                      (data['acceptance_rate'] as num?)?.toDouble();
                  final attScore =
                      (data['attendance_score'] as num?)?.toDouble();
                  final perf = (data['driver_performance'] as num?)?.toDouble() ??
                      75.0;
                  final tier = PerformanceTierHelper.getTier(perf);

                  return RefreshIndicator(
                    onRefresh: () async {},
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top: average rating + performance
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.amber
                                          .withValues(alpha: 0.2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        avgRating != null
                                            ? avgRating
                                                .toStringAsFixed(1)
                                            : '--',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber.shade700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        RatingBarIndicator(
                                          rating: avgRating ?? 0,
                                          itemBuilder: (_, __) =>
                                              Icon(Icons.star,
                                                  color: Colors.amber.shade600),
                                          itemCount: 5,
                                          itemSize: 18,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${reviews.length} reviews',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDarkMode(context)
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            _metricChip(
                                              'Accept',
                                              accRate != null
                                                  ? '${accRate.toStringAsFixed(0)}%'
                                                  : '--',
                                            ),
                                            const SizedBox(width: 8),
                                            _metricChip(
                                              'Attendance',
                                              attScore != null
                                                  ? '${attScore.toStringAsFixed(0)}%'
                                                  : '--',
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets
                                                  .symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: tier.color
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                tier.name,
                                                style: TextStyle(
                                                  color: tier.color,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Rating trend chart
                          if (reviews.isNotEmpty) ...[
                            Text(
                              'Rating trend (last 30 days)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode(context)
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 160,
                              child: LineChart(
                                LineChartData(
                                  gridData: FlGridData(show: false),
                                  titlesData: FlTitlesData(show: false),
                                  borderData: FlBorderData(show: false),
                                  minX: 0,
                                  maxX: 29,
                                  minY: 0,
                                  maxY: 5.5,
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: _buildRatingTrend(reviews),
                                      isCurved: true,
                                      color: Color(COLOR_PRIMARY),
                                      barWidth: 2,
                                      dotData: FlDotData(show: false),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: Color(COLOR_PRIMARY)
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                          if (reviews.isNotEmpty) ...[
                            _buildFeedbackTips(reviews),
                            const SizedBox(height: 20),
                          ],
                          Text(
                            'Reviews',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode(context)
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (visible.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  'No reviews yet',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDarkMode(context)
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                            )
                          else
                            ...visible.map((r) => _buildReviewCard(r)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedbackTips(List<RatingModel> reviews) {
    final wordCount = <String, int>{};
    for (final r in reviews) {
      final comment = (r.comment ?? '').toLowerCase();
      if (comment.isEmpty) continue;
      final words = comment
          .split(RegExp(r'\s+'))
          .map((w) => w.replaceAll(RegExp(r'[^\w]'), ''))
          .where((w) => w.length >= 3)
          .where((w) => !['the', 'and', 'for', 'was', 'are', 'you', 'your'].contains(w));
      for (final w in words) {
        wordCount[w] = (wordCount[w] ?? 0) + 1;
      }
    }
    final top = wordCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final tips = top.take(5).map((e) => e.key).toList();
    if (tips.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 20, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Text(
                  'Feedback insights',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode(context) ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Customers often mention: ${tips.join(", ")}',
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode(context) ? Colors.grey.shade300 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? Colors.grey.shade800
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          color: isDarkMode(context)
              ? Colors.grey.shade300
              : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildReviewCard(RatingModel r) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
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
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: r.profile != null && r.profile!.isNotEmpty
                      ? NetworkImage(r.profile!)
                      : null,
                  child: r.profile == null || r.profile!.isEmpty
                      ? Text(
                          (r.uname ?? '?')[0].toUpperCase(),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.uname ?? 'Customer',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: isDarkMode(context)
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      Text(
                        _relativeTime(r.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode(context)
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.reply),
                      onPressed: () => _showReplySheet(r),
                      tooltip: 'Reply',
                    ),
                    IconButton(
                      icon: const Icon(Icons.flag_outlined),
                      onPressed: () => _showFlagDialog(r),
                      tooltip: 'Flag',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            RatingBarIndicator(
              rating: r.rating ?? 0,
              itemBuilder: (_, __) =>
                  Icon(Icons.star, color: Colors.amber.shade600, size: 18),
              itemCount: 5,
              itemSize: 18,
            ),
            if ((r.comment ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                r.comment!,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode(context)
                      ? Colors.grey.shade300
                      : Colors.black87,
                ),
              ),
            ],
            if ((r.replies ?? []).isNotEmpty) ...[
              const SizedBox(height: 12),
              ...(r.replies ?? []).map((reply) {
                final text = reply['text'] as String? ?? '';
                final userName = reply['userName'] as String? ?? '';
                final userType = reply['userType'] as String? ?? '';
                if (text.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDarkMode(context)
                          ? Colors.grey.shade800
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              userType == 'rider' ? 'You' : userName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: isDarkMode(context)
                                    ? Colors.grey.shade300
                                    : Colors.grey.shade700,
                              ),
                            ),
                            if (userType == 'admin') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Admin',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDarkMode(context)
                                ? Colors.grey.shade300
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
