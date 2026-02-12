import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/main.dart';
import 'package:uuid/uuid.dart';

class AdminDriverChatScreen extends StatefulWidget {
  final String orderId;

  const AdminDriverChatScreen({
    super.key,
    required this.orderId,
  });

  @override
  State<AdminDriverChatScreen> createState() => _AdminDriverChatScreenState();
}

class _AdminDriverChatScreenState extends State<AdminDriverChatScreen> {
  static const _uuid = Uuid();

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _markThreadAsRead();
  }

  Future<void> _markThreadAsRead() async {
    final driverId = MyAppState.currentUser?.userID;
    if (driverId == null || driverId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('chat_admin_driver')
          .doc(widget.orderId)
          .set(
        {
          'unreadForDriver': 0,
          'driverId': driverId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final driver = MyAppState.currentUser;
    if (driver == null) return;

    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (_isSending) return;
    setState(() => _isSending = true);

    final messageId = _uuid.v4();
    final now = Timestamp.now();
    final driverId = driver.userID;

    try {
      await FirebaseFirestore.instance
          .collection('chat_admin_driver')
          .doc(widget.orderId)
          .collection('thread')
          .doc(messageId)
          .set({
        'id': messageId,
        'senderId': driverId,
        'receiverId': 'admin',
        'orderId': widget.orderId,
        'message': text,
        'messageType': 'text',
        'createdAt': now,
        'senderType': 'driver',
        'senderRole': 'driver',
        'receiverRole': 'admin',
        'isRead': false,
        'readBy': <String, dynamic>{},
      });

      await FirebaseFirestore.instance
          .collection('chat_admin_driver')
          .doc(widget.orderId)
          .set(
        {
          'orderId': widget.orderId,
          'driverId': driverId,
          'lastMessage': text,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      _messageController.clear();
      setState(() => _isSending = false);

      // Scroll down after send
      if (_scrollController.hasClients) {
        Timer(
          const Duration(milliseconds: 150),
          () => _scrollController.jumpTo(_scrollController.position.maxScrollExtent),
        );
      }
    } catch (e) {
      setState(() => _isSending = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverId = MyAppState.currentUser?.userID ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Messages'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat_admin_driver')
                  .doc(widget.orderId)
                  .collection('thread')
                  .orderBy('createdAt', descending: false)
                  .limit(200)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No messages yet.'));
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: docs.length,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final senderId = data['senderId']?.toString() ?? '';
                    final message = data['message']?.toString() ?? '';
                    final senderType = data['senderType']?.toString() ?? '';
                    final isMe = senderId.isNotEmpty && senderId == driverId;

                    final label = senderType == 'admin'
                        ? 'Admin'
                        : (isMe ? 'You' : 'Rider');

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        constraints: const BoxConstraints(maxWidth: 320),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue.shade600 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMe ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              message,
                              style: TextStyle(
                                fontSize: 14,
                                color: isMe ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isSending,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: Icon(_isSending ? Icons.hourglass_top : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

