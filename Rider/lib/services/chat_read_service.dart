import 'package:cloud_firestore/cloud_firestore.dart';

class ChatReadService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Mark all messages in an order chat as read for current user
  static Future<void> markMessagesAsRead({
    required String orderId,
    required String userId,
  }) async {
    try {
      final messagesSnapshot = await _firestore
          .collection('chat_driver')
          .doc(orderId)
          .collection('thread')
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      final now = Timestamp.now();

      for (var doc in messagesSnapshot.docs) {
        final data = doc.data();
        final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});
        readBy[userId] = now;

        batch.update(doc.reference, {
          'isRead': true,
          'readBy': readBy,
        });
      }

      await batch.commit();
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  /// Mark a specific message as read
  static Future<void> markMessageAsRead({
    required String orderId,
    required String messageId,
    required String userId,
  }) async {
    try {
      final messageRef = _firestore
          .collection('chat_driver')
          .doc(orderId)
          .collection('thread')
          .doc(messageId);

      final messageDoc = await messageRef.get();
      if (!messageDoc.exists) return;

      final data = messageDoc.data() ?? {};
      final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});
      readBy[userId] = Timestamp.now();

      await messageRef.update({
        'isRead': true,
        'readBy': readBy,
      });
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  /// Get unread message count for an order
  static Future<int> getUnreadCount({
    required String orderId,
    required String userId,
  }) async {
    try {
      final messagesSnapshot = await _firestore
          .collection('chat_driver')
          .doc(orderId)
          .collection('thread')
          .where('receiverId', isEqualTo: userId)
          .get();

      int unreadCount = 0;
      for (var doc in messagesSnapshot.docs) {
        final data = doc.data();
        final isRead = data['isRead'] ?? false;
        final readBy = data['readBy'] as Map<String, dynamic>? ?? {};

        // Message is unread if isRead is false OR user hasn't read it
        if (!isRead || !readBy.containsKey(userId)) {
          unreadCount++;
        }
      }

      return unreadCount;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  /// Get unread message count stream for real-time updates
  static Stream<int> getUnreadCountStream({
    required String orderId,
    required String userId,
  }) {
    return _firestore
        .collection('chat_driver')
        .doc(orderId)
        .collection('thread')
        .where('receiverId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      int unreadCount = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final isRead = data['isRead'] ?? false;
        final readBy = data['readBy'] as Map<String, dynamic>? ?? {};

        if (!isRead || !readBy.containsKey(userId)) {
          unreadCount++;
        }
      }
      return unreadCount;
    });
  }

  /// Get total unread count across all orders for a user
  static Future<int> getTotalUnreadCount(String userId) async {
    try {
      final inboxSnapshot = await _firestore
          .collection('chat_driver')
          .where('customerId', isEqualTo: userId)
          .get();

      int totalUnread = 0;
      for (var inboxDoc in inboxSnapshot.docs) {
        final orderId = inboxDoc.id;
        final count = await getUnreadCount(orderId: orderId, userId: userId);
        totalUnread += count;
      }

      return totalUnread;
    } catch (e) {
      print('Error getting total unread count: $e');
      return 0;
    }
  }

  /// Get unread count stream for all orders
  static Stream<int> getTotalUnreadCountStream(String userId) {
    return _firestore
        .collection('chat_driver')
        .where('customerId', isEqualTo: userId)
        .snapshots()
        .asyncMap((snapshot) async {
      int totalUnread = 0;
      for (var doc in snapshot.docs) {
        final orderId = doc.id;
        final count = await getUnreadCount(orderId: orderId, userId: userId);
        totalUnread += count;
      }
      return totalUnread;
    });
  }
}


