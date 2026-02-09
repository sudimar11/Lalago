import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/model/customer_suggestion.dart';
import 'package:brgy/services/customer_suggestion_service.dart';
import 'package:brgy/pages/customer_suggestion_detail_page.dart';
import 'package:brgy/constants.dart';
import 'package:intl/intl.dart';

class CustomerSuggestionsPage extends StatefulWidget {
  const CustomerSuggestionsPage({super.key});

  @override
  State<CustomerSuggestionsPage> createState() =>
      _CustomerSuggestionsPageState();
}

class _CustomerSuggestionsPageState extends State<CustomerSuggestionsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedStatus;
  String? _selectedCategory;
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

  Stream<QuerySnapshot> _getSuggestionsStream() {
    if (_selectedStatus != null) {
      return CustomerSuggestionService.getSuggestionsByStatus(_selectedStatus!);
    } else if (_selectedCategory != null) {
      return CustomerSuggestionService.getSuggestionsByCategory(
        _selectedCategory!,
      );
    } else if (_startDate != null && _endDate != null) {
      return CustomerSuggestionService.getSuggestionsByDateRange(
        _startDate!,
        _endDate!,
      );
    } else {
      return CustomerSuggestionService.getSuggestionsStream();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = null;
      _selectedCategory = null;
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

  Color _getStatusColor(SuggestionStatus status) {
    switch (status) {
      case SuggestionStatus.new_:
        return Colors.orange;
      case SuggestionStatus.under_review:
        return Colors.blue;
      case SuggestionStatus.acknowledged:
        return Colors.green;
      case SuggestionStatus.archived:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Suggestions'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filters',
            onPressed: () => _showFilterDialog(),
          ),
          if (_selectedStatus != null ||
              _selectedCategory != null ||
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
                hintText: 'Search by customer name or suggestion...',
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
                _buildStatusChip('New', 'new'),
                const SizedBox(width: 8),
                _buildStatusChip('Under Review', 'under_review'),
                const SizedBox(width: 8),
                _buildStatusChip('Acknowledged', 'acknowledged'),
                const SizedBox(width: 8),
                _buildStatusChip('Archived', 'archived'),
              ],
            ),
          ),

          // Suggestions list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getSuggestionsStream(),
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
                        Icon(
                          Icons.lightbulb_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No suggestions found',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                // Parse and filter suggestions
                List<CustomerSuggestion> suggestions = [];
                for (var doc in docs) {
                  try {
                    final data = doc.data() as Map<String, dynamic>;
                    // Only process service_suggestion type documents
                    if (data['type'] == 'service_suggestion') {
                      final suggestion =
                          CustomerSuggestion.fromJson(data, doc.id);
                      suggestions.add(suggestion);
                    }
                  } catch (e) {
                    print('Error parsing suggestion ${doc.id}: $e');
                  }
                }

                // Apply search filter
                if (_query.isNotEmpty) {
                  suggestions = suggestions.where((suggestion) {
                    final nameMatch = suggestion.customerName
                        .toLowerCase()
                        .contains(_query);
                    final suggestionMatch = suggestion.suggestion
                        .toLowerCase()
                        .contains(_query);
                    final idMatch = suggestion.customerId
                        .toLowerCase()
                        .contains(_query);
                    return nameMatch || suggestionMatch || idMatch;
                  }).toList();
                }

                // Sort by date
                suggestions.sort((a, b) {
                  final aTime = a.createdAt.toDate();
                  final bTime = b.createdAt.toDate();
                  return _sortNewestFirst
                      ? bTime.compareTo(aTime)
                      : aTime.compareTo(bTime);
                });

                // Count by status
                final newCount = suggestions
                    .where((s) => s.status == SuggestionStatus.new_)
                    .length;
                final acknowledgedCount = suggestions
                    .where((s) => s.status == SuggestionStatus.acknowledged)
                    .length;

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
                              suggestions.length.toString(),
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryCard(
                              'New',
                              newCount.toString(),
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSummaryCard(
                              'Acknowledged',
                              acknowledgedCount.toString(),
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Suggestions list
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final suggestion = suggestions[index];
                          return _buildSuggestionCard(suggestion);
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

  /// Fetch customer name from Firestore
  Future<String> _fetchCustomerName(String userId) async {
    if (userId.isEmpty) return 'Unknown Customer';
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection(USERS)
          .doc(userId)
          .get();
      
      if (!userDoc.exists) {
        return 'Unknown Customer';
      }
      
      final userData = userDoc.data();
      if (userData == null) {
        return 'Unknown Customer';
      }
      
      final firstName = userData['firstName'] ?? '';
      final lastName = userData['lastName'] ?? '';
      final fullName = '$firstName $lastName'.trim();
      
      return fullName.isEmpty ? 'Unknown Customer' : fullName;
    } catch (e) {
      print('Error fetching customer name: $e');
      return 'Unknown Customer';
    }
  }

  Widget _buildSuggestionCard(CustomerSuggestion suggestion) {
    final statusColor = _getStatusColor(suggestion.status);
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
              builder: (context) =>
                  CustomerSuggestionDetailPage(suggestion: suggestion),
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
                      suggestion.status.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormat.format(suggestion.createdAt.toDate()),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: suggestion.customerName.isNotEmpty
                    ? Future.value(suggestion.customerName)
                    : _fetchCustomerName(suggestion.customerId),
                builder: (context, snapshot) {
                  String displayName;
                  if (suggestion.customerName.isNotEmpty) {
                    displayName = suggestion.customerName;
                  } else if (snapshot.connectionState == ConnectionState.waiting) {
                    displayName = 'Loading...';
                  } else if (snapshot.hasData) {
                    displayName = snapshot.data!;
                  } else {
                    displayName = 'Unknown Customer';
                  }
                  
                  return Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (suggestion.category != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.category, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        suggestion.category!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  suggestion.suggestion,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (suggestion.adminNotes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.note, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      '${suggestion.adminNotes.length} admin note(s)',
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
        title: const Text('Filter Suggestions'),
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

