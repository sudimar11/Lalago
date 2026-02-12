import 'package:cloud_firestore/cloud_firestore.dart';

class ChatReadService {
  static final FirebaseFirestore firestore = FirebaseFirestore.instance;
  static void _badgeLog(String message) => print('[BADGE] $message');

  /// Returns a stream of total unread message count for the given user
  /// from all driver chat threads across all orders
  static Stream<int> getTotalUnreadCountStream(String userId) {
    if (userId.isEmpty) {
      _badgeLog(
          'ChatReadService: ERROR - userId is empty! Returning empty stream.');
      return Stream.value(0);
    }
    _badgeLog('ChatReadService: Starting stream for user $userId');
    return firestore
        .collection('chat_driver')
        .where('customerId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      int totalUnread = 0;

      for (final inboxDoc in snapshot.docs) {
        final orderId = inboxDoc.id;

        final messagesSnapshot = await firestore
            .collection('chat_driver')
            .doc(orderId)
            .collection('thread')
            .where('receiverId', isEqualTo: userId)
            .get();

        for (final msgDoc in messagesSnapshot.docs) {
          final data = msgDoc.data();
          final isRead = data['isRead'] as bool? ?? false;
          final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});

          if (!isRead || !readBy.containsKey(userId)) {
            totalUnread++;
          }
        }
      }

      _badgeLog(
          'ChatReadService: Total unread driver messages: $totalUnread for user $userId');
      return totalUnread;
    }).handleError((error, stackTrace) {
      _badgeLog('Error in ChatReadService.getTotalUnreadCountStream: $error');
      _badgeLog('Stack trace: $stackTrace');
      return 0;
    });
  }
}
