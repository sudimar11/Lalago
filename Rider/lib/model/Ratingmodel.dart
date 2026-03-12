import 'package:cloud_firestore/cloud_firestore.dart';

class RatingModel {
  String? id;
  double? rating;
  List<dynamic>? photos;
  String? comment;
  String? orderId;
  String? customerId;
  String? vendorId;
  String? productId;
  String? driverId;
  String? uname;
  String? profile;
  Map<String, dynamic>? reviewAttributes;
  Timestamp? createdAt;
  String? reviewType;
  String? status;
  List<Map<String, dynamic>>? flaggedBy;
  List<Map<String, dynamic>>? moderationHistory;
  List<Map<String, dynamic>>? replies;

  RatingModel({
    this.id = '',
    this.comment = '',
    this.photos = const [],
    this.rating = 0.0,
    this.orderId = '',
    this.vendorId = '',
    this.productId = '',
    this.driverId = '',
    this.customerId = '',
    this.uname = '',
    this.createdAt,
    this.reviewAttributes,
    this.profile = '',
    this.reviewType = 'product',
    this.status = 'approved',
    this.flaggedBy,
    this.moderationHistory,
    this.replies,
  });

  factory RatingModel.fromJson(Map<String, dynamic> parsedJson) {
    List<Map<String, dynamic>> _toMapList(dynamic v) {
      if (v == null) return [];
      if (v is List) {
        return v
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();
      }
      return [];
    }
    return RatingModel(
      comment: parsedJson['comment'] ?? '',
      photos: parsedJson['photos'] ?? [],
      rating: (parsedJson['rating'] is num)
          ? (parsedJson['rating'] as num).toDouble()
          : 0.0,
      id: parsedJson['Id'] ?? parsedJson['id'] ?? '',
      orderId: parsedJson['orderid'] ?? parsedJson['orderId'] ?? '',
      vendorId: parsedJson['VendorId'] ?? parsedJson['vendorId'] ?? '',
      productId: parsedJson['productId'] ?? '',
      driverId: parsedJson['driverId'] ?? '',
      customerId: parsedJson['CustomerId'] ?? parsedJson['customerId'] ?? '',
      uname: parsedJson['uname'] ?? '',
      reviewAttributes: parsedJson['reviewAttributes'] ?? {},
      createdAt: parsedJson['createdAt'] ?? Timestamp.now(),
      profile: parsedJson['profile'] ?? '',
      reviewType: parsedJson['reviewType'] ?? 'product',
      status: parsedJson['status'] ?? 'approved',
      flaggedBy: _toMapList(parsedJson['flaggedBy']),
      moderationHistory: _toMapList(parsedJson['moderationHistory']),
      replies: _toMapList(parsedJson['replies']),
    );
  }
}
