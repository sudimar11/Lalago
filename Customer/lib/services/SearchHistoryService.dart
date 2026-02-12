import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryItem {
  final String query;
  final String type; // 'restaurant', 'food', or 'mixed'
  final DateTime timestamp;
  final int resultCount;

  SearchHistoryItem({
    required this.query,
    required this.type,
    required this.timestamp,
    required this.resultCount,
  });

  Map<String, dynamic> toJson() => {
        'query': query,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
        'resultCount': resultCount,
      };

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) =>
      SearchHistoryItem(
        query: json['query'],
        type: json['type'],
        timestamp: DateTime.parse(json['timestamp']),
        resultCount: json['resultCount'],
      );
}

class SearchHistoryService {
  static const String _searchHistoryKey = 'search_history';
  static const int _maxHistoryItems = 20;

  // Save search to history
  static Future<void> saveSearch({
    required String query,
    required String type,
    required int resultCount,
  }) async {
    if (query.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_searchHistoryKey) ?? [];

    // Convert to SearchHistoryItem objects
    List<SearchHistoryItem> history = historyJson
        .map((item) => SearchHistoryItem.fromJson(jsonDecode(item)))
        .toList();

    // Remove existing entry with same query and type to avoid duplicates
    history.removeWhere((item) =>
        item.query.toLowerCase() == query.toLowerCase() && item.type == type);

    // Add new search at the beginning
    history.insert(
        0,
        SearchHistoryItem(
          query: query.trim(),
          type: type,
          timestamp: DateTime.now(),
          resultCount: resultCount,
        ));

    // Limit to max items
    if (history.length > _maxHistoryItems) {
      history = history.take(_maxHistoryItems).toList();
    }

    // Save back to SharedPreferences
    final updatedHistoryJson =
        history.map((item) => jsonEncode(item.toJson())).toList();

    await prefs.setStringList(_searchHistoryKey, updatedHistoryJson);
  }

  // Get search history
  static Future<List<SearchHistoryItem>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_searchHistoryKey) ?? [];

    return historyJson
        .map((item) => SearchHistoryItem.fromJson(jsonDecode(item)))
        .toList();
  }

  // Get search history by type
  static Future<List<SearchHistoryItem>> getSearchHistoryByType(
      String type) async {
    final allHistory = await getSearchHistory();
    return allHistory.where((item) => item.type == type).toList();
  }

  // Get recent searches (all types, limited count)
  static Future<List<SearchHistoryItem>> getRecentSearches(
      {int limit = 10}) async {
    final allHistory = await getSearchHistory();
    return allHistory.take(limit).toList();
  }

  // Clear all search history
  static Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_searchHistoryKey);
  }

  // Clear search history by type
  static Future<void> clearSearchHistoryByType(String type) async {
    final allHistory = await getSearchHistory();
    final filteredHistory =
        allHistory.where((item) => item.type != type).toList();

    final prefs = await SharedPreferences.getInstance();
    final updatedHistoryJson =
        filteredHistory.map((item) => jsonEncode(item.toJson())).toList();

    await prefs.setStringList(_searchHistoryKey, updatedHistoryJson);
  }

  // Remove specific search item
  static Future<void> removeSearchItem(String query, String type) async {
    final allHistory = await getSearchHistory();
    final filteredHistory = allHistory
        .where((item) => !(item.query.toLowerCase() == query.toLowerCase() &&
            item.type == type))
        .toList();

    final prefs = await SharedPreferences.getInstance();
    final updatedHistoryJson =
        filteredHistory.map((item) => jsonEncode(item.toJson())).toList();

    await prefs.setStringList(_searchHistoryKey, updatedHistoryJson);
  }

  // Get search suggestions based on current input
  static Future<List<SearchHistoryItem>> getSearchSuggestions(
      String input) async {
    if (input.trim().isEmpty) return await getRecentSearches(limit: 8);

    final allHistory = await getSearchHistory();
    return allHistory
        .where((item) => item.query.toLowerCase().contains(input.toLowerCase()))
        .take(8)
        .toList();
  }
}
