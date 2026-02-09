import 'package:cloud_firestore/cloud_firestore.dart';

class SearchAnalyticsModel {
  String id;
  String userId;
  String searchQuery;
  String searchType; // 'food', 'restaurant', or 'mixed'
  String? productId; // If searching for specific food
  String? vendorId; // If searching for specific restaurant
  int resultCount; // Number of results returned
  Timestamp timestamp;
  String? location; // User's location when searching
  String? deviceInfo; // Device/platform info

  SearchAnalyticsModel({
    required this.id,
    required this.userId,
    required this.searchQuery,
    required this.searchType,
    this.productId,
    this.vendorId,
    required this.resultCount,
    required this.timestamp,
    this.location,
    this.deviceInfo,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'searchQuery': searchQuery,
      'searchType': searchType,
      'productId': productId,
      'vendorId': vendorId,
      'resultCount': resultCount,
      'timestamp': timestamp,
      'location': location,
      'deviceInfo': deviceInfo,
    };
  }

  factory SearchAnalyticsModel.fromJson(Map<String, dynamic> json) {
    return SearchAnalyticsModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      searchQuery: json['searchQuery'] ?? '',
      searchType: json['searchType'] ?? '',
      productId: json['productId'],
      vendorId: json['vendorId'],
      resultCount: json['resultCount'] ?? 0,
      timestamp: json['timestamp'] ?? Timestamp.now(),
      location: json['location'],
      deviceInfo: json['deviceInfo'],
    );
  }
}
