import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/GroupChatMessage.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:uuid/uuid.dart';

class GroupChatService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static const _uuid = Uuid();

  // Typing indicator management
  Timer? _typingTimer;
  static const _typingTimeout = Duration(seconds: 3);

  // Send text message
  static Future<void> sendMessage(String message, {File? image}) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final user = MyAppState.currentUser;
      if (user == null) {
        throw Exception('User data not available');
      }

      final messageId = _uuid.v4();
      final timestamp = Timestamp.now();
      String? imageUrl;

      // Upload image if provided
      if (image != null) {
        imageUrl = await uploadImage(image, messageId, timestamp);
      }

      // Create message document
      final messageData = GroupChatMessage(
        messageId: messageId,
        senderId: currentUser.uid,
        senderName: user.fullName(),
        message: message,
        imageUrl: imageUrl,
        timestamp: timestamp,
        role: user.role,
        deliveryStatus: 'sent',
      );

      // Add to Firestore
      await _firestore.collection(GROUP_CHAT).doc(messageId).set(messageData.toJson());

      // Send push notifications to other drivers (handled by Cloud Functions or client-side)
      _sendNotificationsToOtherDrivers(messageData, currentUser.uid);
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }

  // Send image message
  static Future<void> sendImageMessage(File image) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final user = MyAppState.currentUser;
      if (user == null) {
        throw Exception('User data not available');
      }

      final messageId = _uuid.v4();
      final timestamp = Timestamp.now();

      // Upload image
      final imageUrl = await uploadImage(image, messageId, timestamp);

      // Create message document with image URL
      final messageData = GroupChatMessage(
        messageId: messageId,
        senderId: currentUser.uid,
        senderName: user.fullName(),
        message: '',
        imageUrl: imageUrl,
        timestamp: timestamp,
        role: user.role,
        deliveryStatus: 'sent',
      );

      await _firestore.collection(GROUP_CHAT).doc(messageId).set(messageData.toJson());
      _sendNotificationsToOtherDrivers(messageData, currentUser.uid);
    } catch (e) {
      debugPrint('Error sending image message: $e');
      rethrow;
    }
  }

  // Get real-time messages stream
  static Stream<List<GroupChatMessage>> getMessagesStream({int limit = 20}) {
    return _firestore
        .collection(GROUP_CHAT)
        .where('deleted', isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return GroupChatMessage.fromJson(data);
      }).toList();
    });
  }

  // Load older messages for pagination
  static Future<List<GroupChatMessage>> loadOlderMessages(
    Timestamp lastTimestamp,
    int limit,
  ) async {
    try {
      final snapshot = await _firestore
          .collection(GROUP_CHAT)
          .where('deleted', isEqualTo: false)
          .where('timestamp', isLessThan: lastTimestamp)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return GroupChatMessage.fromJson(data);
      }).toList();
    } catch (e) {
      debugPrint('Error loading older messages: $e');
      return [];
    }
  }

  // Upload image to Firebase Storage
  static Future<String> uploadImage(File image, String messageId, Timestamp timestamp) async {
    try {
      // Compress image
      final compressedImage = await _compressImage(image);

      // Create storage reference
      final fileName = '${timestamp.seconds}_${timestamp.nanoseconds}.jpg';
      final storageRef = _storage.ref().child('group_chat_images/$messageId/$fileName');

      // Upload file
      final uploadTask = storageRef.putFile(compressedImage);

      // Wait for upload to complete
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl.toString();
    } catch (e) {
      debugPrint('Error uploading image: $e');
      rethrow;
    }
  }

  // Compress image
  static Future<File> _compressImage(File file) async {
    try {
      final targetPath = '${file.path}_compressed.jpg';
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 800,
        minHeight: 600,
        quality: 70,
      );
      if (result != null) {
        final targetFile = File(targetPath);
        await targetFile.writeAsBytes(result);
        return targetFile;
      } else {
        return file;
      }
    } catch (e) {
      debugPrint('Error compressing image: $e');
      return file;
    }
  }

  // Add reaction to message
  static Future<void> addReaction(String messageId, String emoji) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final messageRef = _firestore.collection(GROUP_CHAT).doc(messageId);
      final messageDoc = await messageRef.get();

      if (!messageDoc.exists) return;

      final data = messageDoc.data()!;
      final reactions = Map<String, List<String>>.from(data['reactions'] ?? {});

      // Initialize emoji list if it doesn't exist
      if (!reactions.containsKey(emoji)) {
        reactions[emoji] = [];
      }

      // Add user ID if not already present
      if (!reactions[emoji]!.contains(currentUser.uid)) {
        reactions[emoji]!.add(currentUser.uid);
      }

      await messageRef.update({'reactions': reactions});
    } catch (e) {
      debugPrint('Error adding reaction: $e');
    }
  }

  // Remove reaction from message
  static Future<void> removeReaction(String messageId, String emoji) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final messageRef = _firestore.collection(GROUP_CHAT).doc(messageId);
      final messageDoc = await messageRef.get();

      if (!messageDoc.exists) return;

      final data = messageDoc.data()!;
      final reactions = Map<String, List<String>>.from(data['reactions'] ?? {});

      // Remove user ID from emoji list
      if (reactions.containsKey(emoji)) {
        reactions[emoji]!.remove(currentUser.uid);

        // Remove emoji entry if list is empty
        if (reactions[emoji]!.isEmpty) {
          reactions.remove(emoji);
        }
      }

      await messageRef.update({'reactions': reactions});
    } catch (e) {
      debugPrint('Error removing reaction: $e');
    }
  }

  // Mark message as read
  static Future<void> markAsRead(String messageId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final messageRef = _firestore.collection(GROUP_CHAT).doc(messageId);
      final messageDoc = await messageRef.get();

      if (!messageDoc.exists) return;

      final data = messageDoc.data()!;
      final readBy = Map<String, Timestamp>.from(data['readBy'] ?? {});

      // Add current user to readBy
      readBy[currentUser.uid] = Timestamp.now();

      await messageRef.update({'readBy': readBy});
    } catch (e) {
      debugPrint('Error marking message as read: $e');
    }
  }

  // Batch update read receipts for visible messages
  static Future<void> updateReadReceipts(List<String> messageIds) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final batch = _firestore.batch();
      final timestamp = Timestamp.now();

      for (final messageId in messageIds) {
        final messageRef = _firestore.collection(GROUP_CHAT).doc(messageId);
        final messageDoc = await messageRef.get();

        if (!messageDoc.exists) continue;

        final data = messageDoc.data()!;
        final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});

        // Add current user to readBy
        readBy[currentUser.uid] = timestamp;

        batch.update(messageRef, {'readBy': readBy});
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error updating read receipts: $e');
    }
  }

  // Delete message (soft delete)
  static Future<void> deleteMessage(String messageId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final messageRef = _firestore.collection(GROUP_CHAT).doc(messageId);
      final messageDoc = await messageRef.get();

      if (!messageDoc.exists) return;

      final data = messageDoc.data()!;

      // Only allow users to delete their own messages
      if (data['senderId'] != currentUser.uid) {
        throw Exception('Cannot delete other user\'s messages');
      }

      await messageRef.update({
        'deleted': true,
        'deletedAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('Error deleting message: $e');
      rethrow;
    }
  }

  // Edit message
  static Future<void> editMessage(String messageId, String newMessage) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final messageRef = _firestore.collection(GROUP_CHAT).doc(messageId);
      final messageDoc = await messageRef.get();

      if (!messageDoc.exists) return;

      final data = messageDoc.data()!;

      // Only allow users to edit their own messages
      if (data['senderId'] != currentUser.uid) {
        throw Exception('Cannot edit other user\'s messages');
      }

      // Check if message can still be edited (15 minutes)
      final timestamp = data['timestamp'] as Timestamp;
      final now = Timestamp.now();
      final diff = now.seconds - timestamp.seconds;

      if (diff > 900) {
        // 15 minutes = 900 seconds
        throw Exception('Message can only be edited within 15 minutes');
      }

      await messageRef.update({
        'message': newMessage,
        'editedAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('Error editing message: $e');
      rethrow;
    }
  }

  // Get unread count stream
  static Stream<int> getUnreadCountStream() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value(0);
    }

    return _firestore
        .collection(GROUP_CHAT)
        .where('deleted', isEqualTo: false)
        .orderBy('timestamp', descending: true)
        .limit(100) // Check last 100 messages for performance
        .snapshots()
        .map((snapshot) {
      int unreadCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});
        final senderId = data['senderId'] as String?;

        // Don't count own messages
        if (senderId == currentUser.uid) continue;

        // Check if message is read by current user
        if (!readBy.containsKey(currentUser.uid)) {
          unreadCount++;
        }
      }

      return unreadCount;
    });
  }

  // Start typing indicator
  Future<void> startTyping() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // Cancel existing timer
      _typingTimer?.cancel();

      // Set typing status
      await _firestore.collection(GROUP_CHAT_TYPING).doc(currentUser.uid).set({
        'userId': currentUser.uid,
        'timestamp': Timestamp.now(),
      });

      // Set timer to automatically stop typing after timeout
      _typingTimer = Timer(_typingTimeout, () {
        stopTyping();
      });
    } catch (e) {
      debugPrint('Error starting typing: $e');
    }
  }

  // Stop typing indicator
  Future<void> stopTyping() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      _typingTimer?.cancel();
      await _firestore.collection(GROUP_CHAT_TYPING).doc(currentUser.uid).delete();
    } catch (e) {
      debugPrint('Error stopping typing: $e');
    }
  }

  // Get typing users stream
  static Stream<List<String>> getTypingUsersStream() {
    return _firestore
        .collection(GROUP_CHAT_TYPING)
        .snapshots()
        .map((snapshot) {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return <String>[];

      final typingUsers = <String>[];
      final now = Timestamp.now();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final userId = data['userId'] as String?;
        final timestamp = data['timestamp'] as Timestamp?;

        // Skip current user
        if (userId == currentUser.uid) continue;

        // Check if typing status is recent (within 5 seconds)
        if (timestamp != null) {
          final diff = now.seconds - timestamp.seconds;
          if (diff < 5 && userId != null) {
            typingUsers.add(userId);
          }
        }
      }

      return typingUsers;
    });
  }

  // Send notifications to other drivers
  static Future<void> _sendNotificationsToOtherDrivers(
    GroupChatMessage message,
    String senderId,
  ) async {
    try {
      // Get all drivers except sender
      final driversSnapshot = await _firestore
          .collection(USERS)
          .where('role', isEqualTo: USER_ROLE_DRIVER)
          .get();

      for (final driverDoc in driversSnapshot.docs) {
        final driverData = driverDoc.data();
        final driverId = driverData['id'] ?? driverDoc.id;

        // Skip sender
        if (driverId == senderId) continue;

        final fcmToken = driverData['fcmToken'] as String?;
        if (fcmToken == null || fcmToken.isEmpty) continue;

        // Send FCM notification
        await FireStoreUtils.sendFcmMessage(
          title: '${message.senderName}: Group Chat',
          body: message.imageUrl != null ? '📷 Image' : message.message,
          fcmToken: fcmToken,
        );
      }
    } catch (e) {
      debugPrint('Error sending notifications: $e');
    }
  }

  // Dispose resources
  void dispose() {
    _typingTimer?.cancel();
    stopTyping();
  }
}

