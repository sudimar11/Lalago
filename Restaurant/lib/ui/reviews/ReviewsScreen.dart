import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/ProductModel.dart';
import 'package:foodie_restaurant/model/Ratingmodel.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/utils/date_utils.dart' as app_date_utils;
import 'package:intl/intl.dart';

enum ReviewSort { newestFirst, oldestFirst, highestRating }

class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({Key? key}) : super(key: key);

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  final _fireStoreUtils = FireStoreUtils();
  int? _ratingFilter;
  DateTime _rangeStart = app_date_utils.DateUtils.startOfToday();
  DateTime _rangeEnd = app_date_utils.DateUtils.endOfThisMonth();
  String _rangeLabel = 'This Month';
  ReviewSort _sort = ReviewSort.newestFirst;

  void _selectRange(String label) {
    switch (label) {
      case 'Today':
        _rangeStart = app_date_utils.DateUtils.startOfToday();
        _rangeEnd = app_date_utils.DateUtils.endOfToday();
        break;
      case 'This Week':
        _rangeStart = app_date_utils.DateUtils.startOfThisWeek();
        _rangeEnd = app_date_utils.DateUtils.endOfThisWeek();
        break;
      case 'This Month':
        _rangeStart = app_date_utils.DateUtils.startOfThisMonth();
        _rangeEnd = app_date_utils.DateUtils.endOfThisMonth();
        break;
      default:
        return;
    }
    setState(() => _rangeLabel = label);
  }

  Future<void> _selectCustomRange() async {
    final start = await showDatePicker(
      context: context,
      initialDate: _rangeStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Color(COLOR_PRIMARY),
            onPrimary: Colors.white,
            onSurface: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (start == null || !mounted) return;

    final end = await showDatePicker(
      context: context,
      initialDate: start.isBefore(_rangeEnd) ? _rangeEnd : start,
      firstDate: start,
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: Color(COLOR_PRIMARY),
            onPrimary: Colors.white,
            onSurface: isDarkMode(context) ? Colors.white : Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (end == null || !mounted) return;
    if (end.isBefore(start)) return;

    setState(() {
      _rangeStart = DateTime(start.year, start.month, start.day);
      _rangeEnd = end.add(const Duration(days: 1));
      _rangeLabel = 'Custom';
    });
  }

  List<RatingModel> _filterAndSort(List<RatingModel> reviews) {
    var filtered = reviews.where((r) {
      if (r.status == 'hidden') return false;
      if (_ratingFilter != null) {
        final rv = (r.rating ?? 0).round();
        if (rv != _ratingFilter!) return false;
      }
      final ts = r.createdAt;
      if (ts == null) return true;
      final dt = ts.toDate();
      if (dt.isBefore(_rangeStart)) return false;
      if (dt.isAfter(_rangeEnd)) return false;
      return true;
    }).toList();

    switch (_sort) {
      case ReviewSort.newestFirst:
        filtered.sort((a, b) =>
            (b.createdAt ?? Timestamp.now()).compareTo(a.createdAt ?? Timestamp.now()));
        break;
      case ReviewSort.oldestFirst:
        filtered.sort((a, b) =>
            (a.createdAt ?? Timestamp.now()).compareTo(b.createdAt ?? Timestamp.now()));
        break;
      case ReviewSort.highestRating:
        filtered.sort((a, b) =>
            (b.rating ?? 0).compareTo(a.rating ?? 0));
        break;
    }
    return filtered;
  }

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
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || result.trim().isEmpty || !mounted) return;
    EasyLoading.show(status: 'Sending...');
    try {
      final user = MyAppState.currentUser;
      if (user == null) return;
      await _fireStoreUtils.addReviewReply(
        review.id ?? '',
        result.trim(),
        userId: user.userID,
        userType: 'restaurant',
        userName: user.fullName(),
      );
      if (mounted) {
        EasyLoading.dismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reply sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        EasyLoading.dismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _showFlagDialog(RatingModel review) async {
    final reasons = [
      'Inappropriate content',
      'Spam',
      'Fake review',
      'Other',
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
              child: const Text('Flag'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    EasyLoading.show(status: 'Flagging...');
    try {
      final user = MyAppState.currentUser;
      if (user == null) return;
      await _fireStoreUtils.flagReview(
        review.id ?? '',
        userId: user.userID,
        reason: result,
      );
      if (mounted) {
        EasyLoading.dismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Review flagged')),
        );
      }
    } catch (e) {
      if (mounted) {
        EasyLoading.dismiss();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorId = MyAppState.currentUser?.vendorID;
    if (vendorId == null || vendorId.isEmpty) {
      return Center(
        child: Text(
          'No restaurant selected',
          style: TextStyle(
            color: isDarkMode(context) ? Colors.white70 : Colors.black54,
          ),
        ),
      );
    }

    return StreamBuilder<List<RatingModel>>(
      stream: _fireStoreUtils.getReviewsByVendor(vendorId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(color: Colors.red),
            ),
          );
        }
        final reviews = snapshot.data ?? [];
        final filtered = _filterAndSort(reviews);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rating filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildChip('All', _ratingFilter == null, () {
                      setState(() => _ratingFilter = null);
                    }),
                    for (var i = 5; i >= 1; i--)
                      _buildChip('$i★', _ratingFilter == i, () {
                        setState(() => _ratingFilter = i);
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Date range
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _selectCustomRange,
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildChip('Today', _rangeLabel == 'Today',
                          () => _selectRange('Today')),
                      _buildChip('This Week', _rangeLabel == 'This Week',
                          () => _selectRange('This Week')),
                      _buildChip('This Month', _rangeLabel == 'This Month',
                          () => _selectRange('This Month')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Sort dropdown
              DropdownButton<ReviewSort>(
                value: _sort,
                items: const [
                  DropdownMenuItem(
                    value: ReviewSort.newestFirst,
                    child: Text('Newest First'),
                  ),
                  DropdownMenuItem(
                    value: ReviewSort.oldestFirst,
                    child: Text('Oldest First'),
                  ),
                  DropdownMenuItem(
                    value: ReviewSort.highestRating,
                    child: Text('Highest Rating'),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sort = v);
                },
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No reviews match filters',
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
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _ReviewCard(
                      review: filtered[index],
                      onReply: () => _showReplySheet(filtered[index]),
                      onFlag: () => _showFlagDialog(filtered[index]),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: Color(COLOR_PRIMARY).withOpacity(0.3),
        checkmarkColor: Color(COLOR_PRIMARY),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final RatingModel review;
  final VoidCallback onReply;
  final VoidCallback onFlag;

  const _ReviewCard({
    required this.review,
    required this.onReply,
    required this.onFlag,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: (review.profile != null &&
                          review.profile!.isNotEmpty)
                      ? NetworkImage(review.profile!)
                      : null,
                  child: (review.profile == null || review.profile!.isEmpty)
                      ? Icon(Icons.person, color: Color(COLOR_PRIMARY))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.uname ?? 'Anonymous',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: isDarkMode(context)
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RatingBar.builder(
                        ignoreGestures: true,
                        initialRating: review.rating ?? 0,
                        minRating: 1,
                        itemSize: 18,
                        itemCount: 5,
                        allowHalfRating: true,
                        itemBuilder: (context, _) =>
                            Icon(Icons.star, color: Color(COLOR_PRIMARY)),
                        onRatingUpdate: (_) {},
                      ),
                      const SizedBox(height: 4),
                      Text(
                        review.createdAt != null
                            ? orderDate(review.createdAt!)
                            : '',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDarkMode(context)
                              ? Colors.grey[400]
                              : Colors.grey[600],
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
                      onPressed: onReply,
                      tooltip: 'Reply',
                    ),
                    IconButton(
                      icon: const Icon(Icons.flag_outlined),
                      onPressed: onFlag,
                      tooltip: 'Flag',
                    ),
                  ],
                ),
              ],
            ),
            if (review.productId != null && review.productId!.isNotEmpty)
              FutureBuilder<ProductModel?>(
                future: FireStoreUtils().getProductByProductID(review.productId!),
                builder: (ctx, snap) {
                  if (snap.hasData && snap.data != null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Product: ${snap.data!.name}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(COLOR_PRIMARY),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                review.comment!,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode(context)
                      ? Colors.white70
                      : Colors.black87,
                ),
              ),
            ],
            if (review.photos != null && review.photos!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.photos!.length,
                  itemBuilder: (context, i) {
                    final url = review.photos![i].toString();
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          errorWidget: (_, __, ___) => const Icon(Icons.error),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (review.replies != null && review.replies!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              ...review.replies!.map((r) {
                final userType = r['userType'] as String? ?? '';
                final userName = r['userName'] as String? ?? '';
                final text = r['text'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDarkMode(context)
                          ? Colors.grey[800]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Color(COLOR_PRIMARY).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                userType.isNotEmpty
                                    ? userType[0].toUpperCase() +
                                        userType.substring(1)
                                    : 'Reply',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(COLOR_PRIMARY),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(text, style: const TextStyle(fontSize: 13)),
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
