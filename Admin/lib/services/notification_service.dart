import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'notifications';

  /// Create a new notification
  static Future<void> createNotification({
    required String title,
    required String message,
    String type = 'info',
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection(_collection).add({
        'title': title,
        'message': message,
        'type': type,
        'isRead': false,
        'createdAt': Timestamp.now(),
        'data': data ?? {},
      });
    } catch (e) {
      throw Exception('Failed to create notification: $e');
    }
  }

  /// Mark a notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection(_collection).doc(notificationId).update({
        'isRead': true,
        'readAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to mark notification as read: $e');
    }
  }

  /// Mark all notifications as read
  static Future<void> markAllAsRead() async {
    try {
      final batch = _firestore.batch();
      final notifications = await _firestore
          .collection(_collection)
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in notifications.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': Timestamp.now(),
        });
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to mark all notifications as read: $e');
    }
  }

  /// Get unread notification count
  static Stream<int> getUnreadCount() {
    return _firestore
        .collection(_collection)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Get all notifications stream
  static Stream<QuerySnapshot> getNotificationsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Delete a notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore.collection(_collection).doc(notificationId).delete();
    } catch (e) {
      throw Exception('Failed to delete notification: $e');
    }
  }

  /// Delete all read notifications
  static Future<void> deleteAllRead() async {
    try {
      final batch = _firestore.batch();
      final readNotifications = await _firestore
          .collection(_collection)
          .where('isRead', isEqualTo: true)
          .get();

      for (var doc in readNotifications.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete read notifications: $e');
    }
  }

  /// Create notification for new order
  static Future<void> createOrderNotification({
    required String orderId,
    required String customerName,
    required String restaurantName,
  }) async {
    await createNotification(
      title: 'New Order Received',
      message: 'Order #$orderId from $customerName at $restaurantName',
      type: 'order',
      data: {
        'orderId': orderId,
        'customerName': customerName,
        'restaurantName': restaurantName,
      },
    );
  }

  /// Create notification for driver assignment
  static Future<void> createDriverAssignmentNotification({
    required String orderId,
    required String driverName,
  }) async {
    await createNotification(
      title: 'Driver Assigned',
      message: 'Order #$orderId has been assigned to $driverName',
      type: 'driver',
      data: {
        'orderId': orderId,
        'driverName': driverName,
      },
    );
  }

  /// Create notification for order status update
  static Future<void> createOrderStatusNotification({
    required String orderId,
    required String status,
    String? driverName,
  }) async {
    String message = 'Order #$orderId status updated to $status';
    if (driverName != null) {
      message += ' by $driverName';
    }

    await createNotification(
      title: 'Order Status Update',
      message: message,
      type: status == 'delivered' ? 'success' : 'info',
      data: {
        'orderId': orderId,
        'status': status,
        'driverName': driverName,
      },
    );
  }

  /// Create notification for payment received
  static Future<void> createPaymentNotification({
    required String orderId,
    required double amount,
    required String paymentMethod,
  }) async {
    await createNotification(
      title: 'Payment Received',
      message:
          'Payment of ₱${amount.toStringAsFixed(2)} received for Order #$orderId via $paymentMethod',
      type: 'payment',
      data: {
        'orderId': orderId,
        'amount': amount,
        'paymentMethod': paymentMethod,
      },
    );
  }

  /// Create system notification
  static Future<void> createSystemNotification({
    required String title,
    required String message,
    String type = 'info',
  }) async {
    await createNotification(
      title: title,
      message: message,
      type: type,
    );
  }

  /// Create demand alert notification (in-app).
  static Future<void> createDemandAlertNotification({
    required String alertId,
    required String type,
    required String severity,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    await createNotification(
      title: 'Demand Alert: ${severity.toUpperCase()}',
      message: message,
      type: 'demand_alert',
      data: {
        'alertId': alertId,
        'type': type,
        'severity': severity,
        ...?data,
      },
    );
  }

  /// Create a note/reminder notification
  static Future<void> createNote({
    required String title,
    required String content,
    String priority = 'normal',
  }) async {
    await createNotification(
      title: title,
      message: content,
      type: 'note',
      data: {
        'priority': priority,
        'isNote': true,
      },
    );
  }

  /// Create a note in daily_summaries/{date}/notes subcollection
  static Future<void> createDailyNote({
    required String title,
    required String message,
    String? date,
  }) async {
    try {
      final String targetDate =
          date ?? DateTime.now().toIso8601String().split('T')[0];

      await _firestore
          .collection('daily_summaries')
          .doc(targetDate)
          .collection('notes')
          .add({
        'title': title,
        'message': message,
        'created_at': Timestamp.now(),
        'is_read': false,
      });
    } catch (e) {
      throw Exception('Failed to create daily note: $e');
    }
  }

  /// Get notes for a specific date
  static Stream<QuerySnapshot> getDailyNotesStream(String? date) {
    final String targetDate =
        date ?? DateTime.now().toIso8601String().split('T')[0];

    return _firestore
        .collection('daily_summaries')
        .doc(targetDate)
        .collection('notes')
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  /// Get unread notes count for a specific date
  static Stream<int> getUnreadNotesCount(String? date) {
    final String targetDate =
        date ?? DateTime.now().toIso8601String().split('T')[0];

    return _firestore
        .collection('daily_summaries')
        .doc(targetDate)
        .collection('notes')
        .where('is_read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Mark a daily note as read
  static Future<void> markDailyNoteAsRead(String date, String noteId) async {
    try {
      await _firestore
          .collection('daily_summaries')
          .doc(date)
          .collection('notes')
          .doc(noteId)
          .update({
        'is_read': true,
        'read_at': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to mark daily note as read: $e');
    }
  }

  /// Mark all daily notes as read for a specific date
  static Future<void> markAllDailyNotesAsRead(String? date) async {
    try {
      final String targetDate =
          date ?? DateTime.now().toIso8601String().split('T')[0];

      final batch = _firestore.batch();
      final notes = await _firestore
          .collection('daily_summaries')
          .doc(targetDate)
          .collection('notes')
          .where('is_read', isEqualTo: false)
          .get();

      for (var doc in notes.docs) {
        batch.update(doc.reference, {
          'is_read': true,
          'read_at': Timestamp.now(),
        });
      }

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to mark all daily notes as read: $e');
    }
  }

  /// Delete a daily note
  static Future<void> deleteDailyNote(String date, String noteId) async {
    try {
      await _firestore
          .collection('daily_summaries')
          .doc(date)
          .collection('notes')
          .doc(noteId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete daily note: $e');
    }
  }

  /// Add a reaction to a daily note
  static Future<void> addReactionToNote({
    required String date,
    required String noteId,
    required String reaction,
    required String userId,
    required String userName,
  }) async {
    try {
      // Use Firebase Auth UID as the document ID for reactions
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) {
        throw Exception('User not authenticated');
      }

      final reactionRef = _firestore
          .collection('daily_summaries')
          .doc(date)
          .collection('notes')
          .doc(noteId)
          .collection('reactions')
          .doc(authUid);

      await reactionRef.set({
        'reaction': reaction,
        'user_id': userId,
        'user_name': userName,
        'created_at': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Failed to add reaction: $e');
    }
  }

  /// Remove a reaction from a daily note
  static Future<void> removeReactionFromNote({
    required String date,
    required String noteId,
    required String userId,
  }) async {
    try {
      // Use Firebase Auth UID as the document ID for reactions
      final authUid = FirebaseAuth.instance.currentUser?.uid;
      if (authUid == null) {
        throw Exception('User not authenticated');
      }

      await _firestore
          .collection('daily_summaries')
          .doc(date)
          .collection('notes')
          .doc(noteId)
          .collection('reactions')
          .doc(authUid)
          .delete();
    } catch (e) {
      throw Exception('Failed to remove reaction: $e');
    }
  }

  /// Get reactions for a specific note
  static Stream<QuerySnapshot> getNoteReactionsStream({
    required String date,
    required String noteId,
  }) {
    return _firestore
        .collection('daily_summaries')
        .doc(date)
        .collection('notes')
        .doc(noteId)
        .collection('reactions')
        .orderBy('created_at', descending: false)
        .snapshots();
  }

  /// Get reaction counts for a specific note
  static Future<Map<String, int>> getReactionCounts({
    required String date,
    required String noteId,
  }) async {
    try {
      final reactions = await _firestore
          .collection('daily_summaries')
          .doc(date)
          .collection('notes')
          .doc(noteId)
          .collection('reactions')
          .get();

      final Map<String, int> counts = {};
      for (var doc in reactions.docs) {
        final data = doc.data();
        final reaction = data['reaction'] as String?;
        if (reaction != null) {
          counts[reaction] = (counts[reaction] ?? 0) + 1;
        }
      }
      return counts;
    } catch (e) {
      throw Exception('Failed to get reaction counts: $e');
    }
  }
}
