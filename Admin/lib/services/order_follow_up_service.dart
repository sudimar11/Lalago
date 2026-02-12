import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Sends a follow-up message from Admin to the rider for a specific order.
/// Writes to private chat_admin_driver thread.
class OrderFollowUpService {
  static const _uuid = Uuid();

  /// Sends follow-up message to rider. Returns true on success.
  static Future<bool> sendFollowUpToRider({
    required String orderId,
    required String driverId,
    required String message,
  }) async {
    final firestore = FirebaseFirestore.instance;

    // 0. Fetch rider FCM token for individual push
    final riderSnap = await firestore.collection('users').doc(driverId).get();
    final riderToken = riderSnap.data()?['fcmToken']?.toString() ?? '';
    if (riderToken.trim().isEmpty) {
      // Message can still be stored, but push cannot be sent.
      // Return false so UI can warn; adjust if you prefer "stored but no push".
      return false;
    }

    // 1. Write to chat_admin_driver/{orderId}/thread/{messageId}
    final messageId = _uuid.v4();
    final threadRef = firestore
        .collection('chat_admin_driver')
        .doc(orderId)
        .collection('thread')
        .doc(messageId);

    final chatDoc = {
      'id': messageId,
      'senderId': 'admin',
      'receiverId': driverId,
      'orderId': orderId,
      'message': message,
      'messageType': 'text',
      // Use client timestamp to avoid null-ordering edge cases on orderBy.
      'createdAt': Timestamp.now(),
      'senderType': 'admin',
      'senderRole': 'admin',
      'receiverRole': 'driver',
      'isRead': false,
      'readBy': <String, dynamic>{},
    };

    await threadRef.set(chatDoc);

    // 2. Update metadata doc + increment unread counter for badge
    await firestore.collection('chat_admin_driver').doc(orderId).set(
      {
        'orderId': orderId,
        'driverId': driverId,
        'lastMessage': message,
        'updatedAt': FieldValue.serverTimestamp(),
        'unreadForDriver': FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

    // 3. Send individual FCM via HTTPS function (reliable, single token)
    final projectId = Firebase.app().options.projectId;
    const region = 'us-central1';
    final url = Uri.parse(
      'https://$region-$projectId.cloudfunctions.net/sendIndividualNotification',
    );

    final payload = {
      'title': 'Admin',
      'body': message,
      'token': riderToken.trim(),
      'data': {
        'type': 'admin_driver_chat',
        'orderId': orderId,
        'senderRole': 'admin',
        'messageType': 'chat',
      },
    };

    final resp = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) return false;
    final body = jsonDecode(resp.body) as Map<String, dynamic>?;
    return body?['success'] == true;
  }
}
