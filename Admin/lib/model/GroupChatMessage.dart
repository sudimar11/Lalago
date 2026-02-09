import 'package:cloud_firestore/cloud_firestore.dart';

class GroupChatMessage {
  String messageId;
  String senderId;
  String senderName;
  String message;
  String? imageUrl;
  Timestamp timestamp;
  String role;
  Map<String, List<String>> reactions; // Format: {"emoji": ["userId1", "userId2"]}
  Map<String, Timestamp> readBy; // Format: {"userId": Timestamp}
  String deliveryStatus; // "sending" | "sent" | "delivered" | "seen"
  Timestamp? editedAt;
  bool deleted;
  Timestamp? deletedAt;

  GroupChatMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.message,
    this.imageUrl,
    required this.timestamp,
    required this.role,
    this.reactions = const {},
    this.readBy = const {},
    this.deliveryStatus = 'sent',
    this.editedAt,
    this.deleted = false,
    this.deletedAt,
  });

  factory GroupChatMessage.fromJson(Map<String, dynamic> parsedJson) {
    // Handle reactions map
    Map<String, List<String>> reactionsMap = {};
    if (parsedJson['reactions'] != null) {
      final reactionsData = parsedJson['reactions'] as Map<String, dynamic>;
      reactionsData.forEach((emoji, userIds) {
        if (userIds is List) {
          reactionsMap[emoji] = userIds.map((e) => e.toString()).toList();
        }
      });
    }

    // Handle readBy map
    Map<String, Timestamp> readByMap = {};
    if (parsedJson['readBy'] != null) {
      final readByData = parsedJson['readBy'] as Map<String, dynamic>;
      readByData.forEach((userId, timestamp) {
        if (timestamp is Timestamp) {
          readByMap[userId] = timestamp;
        } else if (timestamp is Map) {
          // Handle Firestore timestamp conversion
          try {
            readByMap[userId] = Timestamp(
              timestamp['_seconds'] ?? 0,
              timestamp['_nanoseconds'] ?? 0,
            );
          } catch (e) {
            // Skip invalid timestamps
          }
        }
      });
    }

    return GroupChatMessage(
      messageId: parsedJson['messageId'] ?? '',
      senderId: parsedJson['senderId'] ?? '',
      senderName: parsedJson['senderName'] ?? '',
      message: parsedJson['message'] ?? '',
      imageUrl: parsedJson['imageUrl'],
      timestamp: parsedJson['timestamp'] ?? Timestamp.now(),
      role: parsedJson['role'] ?? 'driver',
      reactions: reactionsMap,
      readBy: readByMap,
      deliveryStatus: parsedJson['deliveryStatus'] ?? 'sent',
      editedAt: parsedJson['editedAt'],
      deleted: parsedJson['deleted'] ?? false,
      deletedAt: parsedJson['deletedAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'imageUrl': imageUrl,
      'timestamp': timestamp,
      'role': role,
      'reactions': reactions,
      'readBy': readBy,
      'deliveryStatus': deliveryStatus,
      'editedAt': editedAt,
      'deleted': deleted,
      'deletedAt': deletedAt,
    };
  }

  // Helper method to check if message is read by a specific user
  bool isReadBy(String userId) {
    return readBy.containsKey(userId);
  }

  // Helper method to get read count
  int getReadCount() {
    return readBy.length;
  }

  // Helper method to check if user has reacted with specific emoji
  bool hasUserReacted(String userId, String emoji) {
    return reactions[emoji]?.contains(userId) ?? false;
  }

  // Helper method to get reaction count for emoji
  int getReactionCount(String emoji) {
    return reactions[emoji]?.length ?? 0;
  }

  // Helper method to check if message can be edited (15 minutes limit)
  bool canBeEdited() {
    if (deleted) return false;
    final now = Timestamp.now();
    final diff = now.seconds - timestamp.seconds;
    return diff <= 900; // 15 minutes = 900 seconds
  }

  // Helper method to check if message is edited
  bool isEdited() {
    return editedAt != null;
  }
}

