import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:brgy/constants.dart';
import 'package:brgy/model/User.dart';

class FireStoreUtils {
  static FirebaseFirestore firestore = FirebaseFirestore.instance;

  static Future<User?> getCurrentUser(String uid) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> userDocument =
          await firestore.collection(USERS).doc(uid).get();
      if (userDocument.data() != null && userDocument.exists) {
        return User.fromJson(userDocument.data()!);
      } else {
        return null;
      }
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }

  static Future<User?> updateCurrentUser(User user) async {
    try {
      await firestore.collection(USERS).doc(user.userID).set(user.toJson());
      return user;
    } catch (e) {
      print('Error updating current user: $e');
      return null;
    }
  }

  /// Popular searches aggregated by keyword (from search_analytics).
  static Future<List<Map<String, dynamic>>> getPopularSearches({
    int limit = 50,
    String? searchType,
    int daysBack = 30,
  }) async {
    try {
      final startTime = Timestamp.fromDate(
        DateTime.now().subtract(Duration(days: daysBack)),
      );

      Query<Map<String, dynamic>> query = firestore
          .collection(SEARCH_ANALYTICS)
          .where('timestamp', isGreaterThanOrEqualTo: startTime);

      if (searchType != null) {
        query = query.where('searchType', isEqualTo: searchType);
      }

      final snapshot = await query
          .orderBy('timestamp', descending: true)
          .limit(limit * 10)
          .get();

      final Map<String, int> searchCounts = {};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final q = data['searchQuery'] as String? ?? '';
        if (q.isNotEmpty) {
          searchCounts[q] = (searchCounts[q] ?? 0) + 1;
        }
      }

      final List<Map<String, dynamic>> popularSearches = searchCounts.entries
          .map((e) => {'query': e.key, 'count': e.value})
          .toList();
      popularSearches.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

      return popularSearches.take(limit).toList();
    } catch (e) {
      print('Error getting popular searches: $e');
      return [];
    }
  }

  /// Recent search events from all users (keyword, timestamp, userId).
  static Future<List<Map<String, dynamic>>> getRecentSearches({
    int limit = 100,
  }) async {
    try {
      final snapshot = await firestore
          .collection(SEARCH_ANALYTICS)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final d = doc.data();
        final ts = d['timestamp'];
        return {
          'query': d['searchQuery'] as String? ?? '',
          'timestamp': ts is Timestamp ? ts : Timestamp.now(),
          'userId': d['userId'] as String? ?? '',
          'searchType': d['searchType'] as String? ?? '',
        };
      }).toList();
    } catch (e) {
      print('Error getting recent searches: $e');
      return [];
    }
  }
}
