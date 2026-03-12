import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

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

  // Temporary transition helper: dual-read canonical + legacy messages.
  // TODO(phase2-cutover): remove legacy order_messages merge after full migration.
  static Stream<List<Map<String, dynamic>>> watchMergedMessages(
    String orderId,
  ) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    List<Map<String, dynamic>> canonicalMessages = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> legacyMessages = <Map<String, dynamic>>[];
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? canonicalSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? legacySub;

    void emitMerged() {
      final byKey = <String, Map<String, dynamic>>{};
      for (final item in [...legacyMessages, ...canonicalMessages]) {
        final key = _dedupeKey(item);
        final existing = byKey[key];
        if (existing == null) {
          byKey[key] = item;
          continue;
        }
        final existingSource = (existing['_source'] ?? '').toString();
        final newSource = (item['_source'] ?? '').toString();
        if (existingSource == 'legacy' && newSource == 'canonical') {
          byKey[key] = item;
        }
      }
      final merged = byKey.values.toList();
      merged.sort((a, b) {
        final aDt = _asDateTime(a['createdAt']);
        final bDt = _asDateTime(b['createdAt']);
        return aDt.compareTo(bDt);
      });
      controller.add(merged);
    }

    canonicalSub = _commDoc(orderId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snapshot) {
      canonicalMessages = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        data['_source'] = 'canonical';
        return data;
      }).toList();
      emitMerged();
    }, onError: controller.addError);

    legacySub = _firestore
        .collection('order_messages')
        .doc(orderId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((snapshot) {
      legacyMessages = snapshot.docs.map((doc) {
        final raw = doc.data();
        return {
          'id': doc.id,
          '_source': 'legacy',
          'type': raw['messageType'] == 'issue' ? 'issue' : 'quick_action',
          'messageKey': raw['messageKey'] ?? '',
          'text': raw['messageText'] ?? raw['text'] ?? '',
          'senderId': raw['senderId'] ?? '',
          'senderRole':
              (raw['senderType'] ?? '').toString() == 'restaurant'
                  ? 'restaurant'
                  : 'rider',
          'status': raw['isRead'] == true ? 'read' : 'sent',
          'isRead': raw['isRead'] == true,
          'createdAt': raw['createdAt'],
          'updatedAt': raw['updatedAt'] ?? raw['createdAt'],
        };
      }).toList();
      emitMerged();
    }, onError: controller.addError);

    controller.onCancel = () async {
      await canonicalSub?.cancel();
      await legacySub?.cancel();
    };
    return controller.stream;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchEvents(
    String orderId,
  ) {
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

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchTyping(String orderId) {
    return _commDoc(orderId).collection('typing').snapshots();
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

    final legacySnapshot = await _firestore
        .collection('order_messages')
        .doc(orderId)
        .collection('messages')
        .where('senderType', isEqualTo: 'restaurant')
        .where('isRead', isEqualTo: false)
        .get();
    final legacyBatch = _firestore.batch();
    for (final doc in legacySnapshot.docs) {
      legacyBatch.update(doc.reference, {
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
    await legacyBatch.commit();
  }

  static String _dedupeKey(Map<String, dynamic> message) {
    final senderRole = (message['senderRole'] ?? '').toString();
    final text = (message['text'] ?? '').toString().trim();
    final messageKey = (message['messageKey'] ?? '').toString();
    final createdAt = _asDateTime(message['createdAt']);
    final minuteBucket = createdAt.millisecondsSinceEpoch ~/ 60000;
    return '$senderRole|$text|$messageKey|$minuteBucket';
  }

  static DateTime _asDateTime(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is Map && ts['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        (ts['_seconds'] as int) * 1000,
      );
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

