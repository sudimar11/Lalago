class PopularSearchItem {
  final String query;
  final int count;
  final String? type; // 'restaurant', 'food', or 'mixed'

  PopularSearchItem({
    required this.query,
    required this.count,
    this.type,
  });

  Map<String, dynamic> toJson() => {
        'query': query,
        'count': count,
        'type': type,
      };

  factory PopularSearchItem.fromJson(Map<String, dynamic> json) =>
      PopularSearchItem(
        query: json['query'] ?? '',
        count: json['count'] ?? 0,
        type: json['type'],
      );

  factory PopularSearchItem.fromFirestore(Map<String, dynamic> data) =>
      PopularSearchItem(
        query: data['query'] ?? '',
        count: data['count'] ?? 0,
        type: data['type'],
      );
}
