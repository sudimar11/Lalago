import 'package:cloud_firestore/cloud_firestore.dart';

class OrderCommunicationService {
  OrderCommunicationService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _commDoc(String orderId) {
    return _firestore.collection('order_communications').doc(orderId);
  }

  static Future<void> ensureCommunicationDoc({
    required String orderId,
    required String riderId,
    required String vendorId,
    required String customerId,
  }) async {
    await _commDoc(orderId).set({
      'orderId': orderId,
      'participants': {
        'riderId': riderId,
        'vendorId': vendorId,
        'customerId': customerId,
      },
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastEventAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchMessages(
    String orderId,
  ) {
    return _commDoc(orderId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEvents(String orderId) {
    return _commDoc(orderId)
        .collection('events')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  static Future<void> sendTextMessage({
    required String orderId,
    required String senderId,
    required String receiverId,
    required String senderRole,
    required String receiverRole,
    required String text,
  }) async {
    await _commDoc(orderId).collection('messages').add({
      'type': 'text',
      'senderId': senderId,
      'receiverId': receiverId,
      'senderRole': senderRole,
      'receiverRole': receiverRole,
      'text': text.trim(),
      'status': 'sent',
      'isRead': false,
      'attachments': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _commDoc(orderId).set({
      'lastMessageAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> sendQuickAction({
    required String orderId,
    required String senderId,
    required String receiverId,
    required String senderRole,
    required String receiverRole,
    required String actionKey,
    required String actionText,
    String? eventType,
    Map<String, dynamic>? eventPayload,
    String? legacyMessageId,
  }) async {
    await _commDoc(orderId).collection('messages').add({
      'type': 'quick_action',
      'messageKey': actionKey,
      'text': actionText,
      'senderId': senderId,
      'receiverId': receiverId,
      'senderRole': senderRole,
      'receiverRole': receiverRole,
      'status': 'sent',
      'isRead': false,
      'attachments': <Map<String, dynamic>>[],
      'legacyMessageId': legacyMessageId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (eventType != null && eventType.isNotEmpty) {
      await _commDoc(orderId).collection('events').add({
        'eventType': eventType,
        'actorRole': senderRole,
        'actorId': senderId,
        'payload': eventPayload ?? <String, dynamic>{},
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await _commDoc(orderId).set({
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastEventAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchTyping(String orderId) {
    return _commDoc(orderId).collection('typing').snapshots();
  }

  static Future<void> setTyping({
    required String orderId,
    required String userId,
    required bool isTyping,
    required String role,
  }) async {
    await _commDoc(orderId).collection('typing').doc(userId).set({
      'isTyping': isTyping,
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> markVisibleMessagesRead({
    required String orderId,
    required String currentUserId,
  }) async {
    final snapshot = await _commDoc(orderId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUserId)
        .where('isRead', isEqualTo: false)
        .get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      final readBy =
          Map<String, dynamic>.from(doc.data()['readBy'] as Map? ?? {});
      readBy[currentUserId] = Timestamp.now();
      batch.update(doc.reference, {
        'isRead': true,
        'status': 'read',
        'readBy': readBy,
        'readAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

