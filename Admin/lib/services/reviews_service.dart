import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class ReviewsService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllReviewsStream() {
    return _firestore
        .collection(FOODS_REVIEW)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  static Future<void> updateReviewStatus(String reviewId, String status) async {
    await _firestore.collection(FOODS_REVIEW).doc(reviewId).update({
      'status': status,
      'moderationHistory': FieldValue.arrayUnion([
        {
          'adminId': 'admin',
          'action': 'status_change',
          'reason': status,
          'timestamp': FieldValue.serverTimestamp(),
        }
      ]),
    });
  }

  static Future<void> addReviewReply(
    String reviewId,
    String text, {
    required String adminId,
    required String adminName,
  }) async {
    final reply = {
      'userId': adminId,
      'userType': 'admin',
      'userName': adminName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _firestore.collection(FOODS_REVIEW).doc(reviewId).update({
      'replies': FieldValue.arrayUnion([reply]),
    });
  }

  static Future<void> deleteReview(String reviewId) async {
    await _firestore.collection(FOODS_REVIEW).doc(reviewId).delete();
  }

  static Future<void> dismissReviewFlags(String reviewId) async {
    await _firestore.collection(FOODS_REVIEW).doc(reviewId).update({
      'flaggedBy': [],
      'status': 'approved',
    });
  }

  static Future<List<Map<String, dynamic>>> getVendors() async {
    final snap = await _firestore.collection('vendors').get();
    return snap.docs.map((d) => {'id': d.id, ...?d.data()}).toList();
  }
}
