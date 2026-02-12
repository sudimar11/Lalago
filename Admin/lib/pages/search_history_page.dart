import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/services/FirebaseHelper.dart';
import 'package:intl/intl.dart';

class SearchHistoryPage extends StatefulWidget {
  const SearchHistoryPage({super.key});

  @override
  State<SearchHistoryPage> createState() => _SearchHistoryPageState();
}

class _SearchHistoryPageState extends State<SearchHistoryPage> {
  List<Map<String, dynamic>> _popularSearches = [];
  List<Map<String, dynamic>> _recentSearches = [];
  String? _selectedType;
  bool _isLoading = true;
  String? _error;

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final popular = await FireStoreUtils.getPopularSearches(
        limit: 50,
        searchType: _selectedType,
        daysBack: 30,
      );
      final recent = await FireStoreUtils.getRecentSearches(limit: 100);
      if (mounted) {
        setState(() {
          _popularSearches = popular;
          _recentSearches = recent;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search History'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SelectableText.rich(
                        TextSpan(
                          text: 'Error: $_error',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPopularSection(),
                        const SizedBox(height: 24),
                        _buildRecentSection(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildPopularSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Popular Searches',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange[800],
              ),
            ),
          ],
        ),
        const Divider(color: Colors.grey, thickness: 1),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _buildTypeChip('All', null),
            _buildTypeChip('Food', 'food'),
            _buildTypeChip('Restaurant', 'restaurant'),
            _buildTypeChip('Mixed', 'mixed'),
          ],
        ),
        const SizedBox(height: 12),
        if (_popularSearches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No search data in the last 30 days',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _popularSearches.length,
            itemBuilder: (context, index) {
              final item = _popularSearches[index];
              final query = item['query'] as String? ?? '';
              final count = item['count'] as int? ?? 0;
              return ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.orange[100],
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[800],
                    ),
                  ),
                ),
                title: Text(query.isEmpty ? '(empty)' : query),
                trailing: Text(
                  '$count',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildTypeChip(String label, String? value) {
    final selected = _selectedType == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (bool selected) {
        setState(() {
          _selectedType = selected ? value : null;
        });
        _loadData();
      },
    );
  }

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Searches (all users)',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.orange[800],
          ),
        ),
        const Divider(color: Colors.grey, thickness: 1),
        const SizedBox(height: 8),
        if (_recentSearches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No recent searches',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentSearches.length,
            itemBuilder: (context, index) {
              final item = _recentSearches[index];
              final query = item['query'] as String? ?? '';
              final ts = item['timestamp'];
              final userId = item['userId'] as String? ?? '';
              final searchType = item['searchType'] as String? ?? '';
              String timeStr = '';
              if (ts is Timestamp) {
                timeStr = DateFormat.yMd().add_Hm().format(ts.toDate());
              }
              final userIdShort = userId.length > 8
                  ? '${userId.substring(0, 8)}…'
                  : userId;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.search, size: 20, color: Colors.grey),
                title: Text(
                  query.isEmpty ? '(empty)' : query,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  '$timeStr • $userIdShort • $searchType',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              );
            },
          ),
      ],
    );
  }
}
