import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';

class CustomerFeedbackService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const int defaultPageSize = 50;

  /// Real-time stream of the first [limit] feedback entries, newest first.
  static Stream<QuerySnapshot> getFeedbackStream({int limit = defaultPageSize}) {
    return _firestore
        .collection(CUSTOMER_FEEDBACK)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// One-time fetch of the next page for "Load more". Returns up to [pageSize]
  /// documents after [startAfter]. Pass the last document from the current list.
  static Future<QuerySnapshot> getNextPage(
    int pageSize,
    DocumentSnapshot? startAfter,
  ) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection(CUSTOMER_FEEDBACK)
        .orderBy('created_at', descending: true)
        .limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    return query.get();
  }
}
