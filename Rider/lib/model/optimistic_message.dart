import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:foodie_driver/model/conversation_model.dart';

enum UploadState {
  pending,
  uploading,
  completed,
  failed,
}

class OptimisticMessage {
  final String id;
  final String localFilePath;
  final String messageType;
  UploadState uploadState;
  double progress;
  String? error;
  Url? finalUrl;
  String? finalVideoThumbnail;
  final Timestamp createdAt;
  final String senderId;
  final String receiverId;
  final String orderId;

  OptimisticMessage({
    required this.id,
    required this.localFilePath,
    required this.messageType,
    this.uploadState = UploadState.pending,
    this.progress = 0.0,
    this.error,
    this.finalUrl,
    this.finalVideoThumbnail,
    required this.createdAt,
    required this.senderId,
    required this.receiverId,
    required this.orderId,
  });

  ConversationModel toConversationModel() {
    return ConversationModel(
      id: id,
      message: messageType == 'image'
          ? 'sent a message'
          : messageType == 'video'
              ? 'Sent a video'
              : '',
      senderId: senderId,
      receiverId: receiverId,
      orderId: orderId,
      createdAt: createdAt,
      url: finalUrl,
      messageType: messageType,
      videoThumbnail: finalVideoThumbnail,
      isRead: false,
      readBy: {},
    );
  }

  File get localFile => File(localFilePath);
}

