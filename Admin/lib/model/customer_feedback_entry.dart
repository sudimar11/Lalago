import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerFeedbackEntry {
  final String id;
  final String userId;
  final String userName;
  final int rating;
  final String category;
  final String comment;
  final Timestamp createdAt;
  final bool isDeleted;

  CustomerFeedbackEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.category,
    required this.comment,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory CustomerFeedbackEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CustomerFeedbackEntry(
      id: doc.id,
      userId: data['user_id']?.toString() ?? '',
      userName: data['user_name']?.toString() ?? '',
      rating: (data['rating'] is int)
          ? data['rating'] as int
          : (data['rating'] is num)
              ? (data['rating'] as num).toInt()
              : 0,
      category: data['category']?.toString() ?? '',
      comment: data['comment']?.toString() ?? '',
      createdAt: data['created_at'] is Timestamp
          ? data['created_at'] as Timestamp
          : Timestamp.now(),
      isDeleted: data['is_deleted'] == true,
    );
  }
}
