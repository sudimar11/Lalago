import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:brgy/model/customer_feedback_entry.dart';
import 'package:brgy/pages/customer_information_page.dart';
import 'package:brgy/services/customer_feedback_service.dart';
import 'package:intl/intl.dart';

const List<String> _categories = [
  'App Experience',
  'Ordering',
  'Delivery',
  'Rider Attitude',
  'Restaurant',
  'Suggestion',
  'Other',
];

enum RatingFilter { all, low, medium, high }

class CustomerFeedbackPage extends StatefulWidget {
  const CustomerFeedbackPage({super.key});

  @override
  State<CustomerFeedbackPage> createState() => _CustomerFeedbackPageState();
}

class _CustomerFeedbackPageState extends State<CustomerFeedbackPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  RatingFilter _ratingFilter = RatingFilter.all;
  final List<CustomerFeedbackEntry> _loadedMore = [];
  DocumentSnapshot? _lastStreamDoc;
  DocumentSnapshot? _lastDocFromLoadMore;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesRatingFilter(int rating) {
    switch (_ratingFilter) {
      case RatingFilter.all:
        return true;
      case RatingFilter.low:
        return rating <= 2;
      case RatingFilter.medium:
        return rating == 3;
      case RatingFilter.high:
        return rating >= 4;
    }
  }

  List<CustomerFeedbackEntry> _filterAndSort(
    List<CustomerFeedbackEntry> streamEntries,
  ) {
    List<CustomerFeedbackEntry> combined = [
      ...streamEntries,
      ..._loadedMore,
    ];
    combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_selectedCategory != null) {
      combined = combined
          .where((e) => e.category == _selectedCategory)
          .toList();
    }
    combined =
        combined.where((e) => _matchesRatingFilter(e.rating)).toList();
    if (_searchQuery.isNotEmpty) {
      combined = combined.where((e) {
        final nameMatch =
            e.userName.toLowerCase().contains(_searchQuery);
        final commentMatch =
            e.comment.toLowerCase().contains(_searchQuery);
        final idMatch =
            e.userId.toLowerCase().contains(_searchQuery);
        return nameMatch || commentMatch || idMatch;
      }).toList();
    }
    return combined;
  }

  Future<void> _onLoadMore(DocumentSnapshot? startAfter) async {
    if (startAfter == null || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final snapshot = await CustomerFeedbackService.getNextPage(
        CustomerFeedbackService.defaultPageSize,
        startAfter,
      );
      final entries = snapshot.docs
          .map((doc) => CustomerFeedbackEntry.fromFirestore(doc))
          .toList();
      if (snapshot.docs.isNotEmpty) {
        _lastDocFromLoadMore = snapshot.docs.last;
      }
      setState(() {
        _loadedMore.addAll(entries);
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Feedback'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by comment or user name',
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
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Category:', style: TextStyle(fontSize: 12)),
                ),
                _buildCategoryChip('All', null),
                ..._categories.map((c) => _buildCategoryChip(c, c)),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Rating:', style: TextStyle(fontSize: 12)),
                ),
                _buildRatingChip('All', RatingFilter.all),
                _buildRatingChip('Low (1–2)', RatingFilter.low),
                _buildRatingChip('Medium (3)', RatingFilter.medium),
                _buildRatingChip('High (4–5)', RatingFilter.high),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: CustomerFeedbackService.getFeedbackStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error,
                          size: 64,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                      ],
                    ),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isNotEmpty &&
                    docs.last.id != _lastStreamDoc?.id) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && docs.isNotEmpty) {
                      setState(() => _lastStreamDoc = docs.last);
                    }
                  });
                }
                final streamEntries = docs
                    .map((doc) =>
                        CustomerFeedbackEntry.fromFirestore(doc))
                    .toList();
                final filtered = _filterAndSort(streamEntries);
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.feedback,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty ||
                                  _selectedCategory != null ||
                                  _ratingFilter != RatingFilter.all
                              ? 'No feedback matches filters'
                              : 'No feedback found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final canLoadMore = docs.length >=
                    CustomerFeedbackService.defaultPageSize;
                final startAfterDoc = _loadedMore.isEmpty
                    ? _lastStreamDoc
                    : _lastDocFromLoadMore;
                return Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: filtered.length + (canLoadMore ? 1 : 0),
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == filtered.length) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: _isLoadingMore
                                    ? const CircularProgressIndicator()
                                    : TextButton.icon(
                                        onPressed: () => _onLoadMore(
                                            startAfterDoc),
                                        icon: const Icon(Icons.add_circle),
                                        label: const Text('Load more'),
                                      ),
                              ),
                            );
                          }
                          final entry = filtered[index];
                          return KeyedSubtree(
                            key: ValueKey(entry.id),
                            child: _buildFeedbackCard(entry),
                          );
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

  Widget _buildCategoryChip(String label, String? value) {
    final selected = _selectedCategory == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (sel) {
          setState(() =>
              _selectedCategory = sel ? value : null);
        },
        selectedColor: Colors.orange.withOpacity(0.3),
        checkmarkColor: Colors.orange,
      ),
    );
  }

  Widget _buildRatingChip(String label, RatingFilter value) {
    final selected = _ratingFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (sel) {
          setState(() =>
              _ratingFilter = sel ? value : RatingFilter.all);
        },
        selectedColor: Colors.orange.withOpacity(0.3),
        checkmarkColor: Colors.orange,
      ),
    );
  }

  Widget _buildFeedbackCard(CustomerFeedbackEntry entry) {
    final dateFormat = DateFormat('MMM dd, yyyy HH:mm');
    final displayName = entry.userName.trim().isEmpty
        ? '—'
        : entry.userName;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (entry.isDeleted)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: const Text(
                      'Resolved',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                if (entry.isDeleted) const SizedBox(width: 8),
                const Spacer(),
                Text(
                  dateFormat.format(entry.createdAt.toDate()),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: entry.userId.isNotEmpty
                  ? () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) =>
                              CustomerInformationPage(userId: entry.userId),
                        ),
                      );
                    }
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: entry.userId.isNotEmpty
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              decoration: entry.userId.isNotEmpty
                                  ? TextDecoration.underline
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (entry.userId.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${entry.userId}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.star, size: 16, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  '${entry.rating} / 5',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.category, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  entry.category,
                  style: const TextStyle(fontSize: 14),
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
                entry.comment,
                style: const TextStyle(fontSize: 14),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
