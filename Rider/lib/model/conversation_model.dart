import 'package:cloud_firestore/cloud_firestore.dart';

class ConversationModel {
  String? id;
  String? senderId;
  String? receiverId;
  String? orderId;
  String? message;
  String? messageType;
  String? videoThumbnail;
  Url? url;
  Timestamp createdAt;
  String? senderType; // 'system' | 'driver' | 'customer'
  bool isRead;
  Map<String, Timestamp> readBy; // userId -> read timestamp
  String? orderStatus; // Order status when system message was sent

  ConversationModel({
    this.id,
    this.senderId,
    this.receiverId,
    this.orderId,
    this.message,
    this.messageType,
    this.videoThumbnail,
    this.url,
    required this.createdAt,
    this.senderType,
    this.isRead = false,
    Map<String, Timestamp>? readBy,
    this.orderStatus,
  }) : readBy = readBy ?? {};

  factory ConversationModel.fromJson(Map<String, dynamic> parsedJson) {
    // Parse readBy map
    Map<String, Timestamp> readByMap = {};
    if (parsedJson['readBy'] != null) {
      final readByData = parsedJson['readBy'] as Map<String, dynamic>;
      readByData.forEach((userId, timestamp) {
        if (timestamp is Timestamp) {
          readByMap[userId] = timestamp;
        } else if (timestamp is Map) {
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

    return ConversationModel(
      id: parsedJson['id'] ?? '',
      senderId: parsedJson['senderId'] ?? '',
      receiverId: parsedJson['receiverId'] ?? '',
      orderId: parsedJson['orderId'] ?? '',
      message: parsedJson['message'] ?? '',
      messageType: parsedJson['messageType'] ?? '',
      videoThumbnail: parsedJson['videoThumbnail'] ?? '',
      url: parsedJson.containsKey('url')
          ? parsedJson['url'] != null
              ? Url.fromJson(parsedJson['url'])
              : null
          : Url(),
      createdAt: parsedJson['createdAt'] ?? Timestamp.now(),
      senderType: parsedJson['senderType'] ?? 'driver',
      isRead: parsedJson['isRead'] ?? false,
      readBy: readByMap,
      orderStatus: parsedJson['orderStatus'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': this.id,
      'senderId': this.senderId,
      'receiverId': this.receiverId,
      'orderId': this.orderId,
      'message': this.message,
      'messageType': this.messageType,
      'videoThumbnail': this.videoThumbnail,
      'url': url == null ? null : this.url!.toJson(),
      'createdAt': this.createdAt,
      'senderType': this.senderType ?? 'driver',
      'isRead': this.isRead,
      'readBy': this.readBy.map((key, value) => MapEntry(key, value)),
      'orderStatus': this.orderStatus,
    };
  }
}

class Url {
  String mime;

  String url;

  String? videoThumbnail;

  Url({this.mime = '', this.url = '', this.videoThumbnail});

  factory Url.fromJson(Map<dynamic, dynamic> parsedJson) {
    return Url(mime: parsedJson['mime'] ?? '', url: parsedJson['url'] ?? '', videoThumbnail: parsedJson['videoThumbnail'] ?? '');
  }

  Map<String, dynamic> toJson() {
    return {'mime': this.mime, 'url': this.url, 'videoThumbnail': videoThumbnail};
  }
}
