import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/GroupChatMessage.dart';
import 'package:foodie_driver/services/group_chat_service.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/widgets/group_chat_message_bubble.dart';
import 'package:foodie_driver/widgets/typing_indicator.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({Key? key}) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GroupChatService _chatService = GroupChatService();
  final ImagePicker _imagePicker = ImagePicker();

  List<GroupChatMessage> _messages = [];
  bool _isLoadingMore = false;
  bool _hasMoreMessages = true;
  Timestamp? _oldestMessageTimestamp;
  List<String> _typingUsers = [];
  Timer? _typingDebounceTimer;

  @override
  void initState() {
    super.initState();
    _setupScrollListener();
    _markVisibleMessagesAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingDebounceTimer?.cancel();
    _chatService.dispose();
    super.dispose();
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      // Check if scrolled to top for pagination
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoadingMore && _hasMoreMessages) {
          _loadOlderMessages();
        }
      }

      // Scroll position tracking if needed
    });
  }

  void _markVisibleMessagesAsRead() {
    // Mark all visible messages as read when screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messages.isNotEmpty) {
        final messageIds = _messages.map((m) => m.messageId).toList();
        GroupChatService.updateReadReceipts(messageIds);
      }
    });
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoadingMore || !_hasMoreMessages || _oldestMessageTimestamp == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final olderMessages = await GroupChatService.loadOlderMessages(
        _oldestMessageTimestamp!,
        20,
      );

      if (olderMessages.isEmpty) {
        setState(() {
          _hasMoreMessages = false;
        });
      } else {
        setState(() {
          _messages.addAll(olderMessages);
          _oldestMessageTimestamp = olderMessages.last.timestamp;
        });
      }
    } catch (e) {
      debugPrint('Error loading older messages: $e');
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _onSendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    try {
      _messageController.clear();
      await _chatService.stopTyping();

      await GroupChatService.sendMessage(message);
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  void _onImagePick() {
    final action = CupertinoActionSheet(
      message: const Text(
        'Send Image',
        style: TextStyle(fontSize: 15.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: const Text('Choose from gallery'),
          onPressed: () async {
            Navigator.pop(context);
            final XFile? image = await _imagePicker.pickImage(
              source: ImageSource.gallery,
            );
            if (image != null) {
              _sendImageMessage(File(image.path));
            }
          },
        ),
        CupertinoActionSheetAction(
          child: const Text('Take a picture'),
          onPressed: () async {
            Navigator.pop(context);
            final XFile? image = await _imagePicker.pickImage(
              source: ImageSource.camera,
            );
            if (image != null) {
              _sendImageMessage(File(image.path));
            }
          },
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        child: const Text('Cancel'),
        onPressed: () => Navigator.pop(context),
      ),
    );
    showCupertinoModalPopup(context: context, builder: (context) => action);
  }

  Future<void> _sendImageMessage(File image) async {
    try {
      showProgress(context, 'Uploading image...', false);
      await GroupChatService.sendImageMessage(image);
      hideProgress();
      _scrollToBottom();
    } catch (e) {
      hideProgress();
      debugPrint('Error sending image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send image: $e')),
        );
      }
    }
  }

  void _onMessageEdit(String messageId, String newMessage) async {
    try {
      await GroupChatService.editMessage(messageId, newMessage);
    } catch (e) {
      debugPrint('Error editing message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to edit message: $e')),
        );
      }
    }
  }

  void _onMessageDelete(String messageId) async {
    try {
      await GroupChatService.deleteMessage(messageId);
    } catch (e) {
      debugPrint('Error deleting message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $e')),
        );
      }
    }
  }

  void _onReactionTap(String messageId, String emoji) async {
    try {
      final message = _messages.firstWhere((m) => m.messageId == messageId);
      final hasReaction = message.hasUserReacted(
        MyAppState.currentUser?.userID ?? '',
        emoji,
      );

      if (hasReaction) {
        await GroupChatService.removeReaction(messageId, emoji);
      } else {
        await GroupChatService.addReaction(messageId, emoji);
      }
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
    }
  }

  void _onTextChanged(String text) {
    // Start typing indicator
    _chatService.startTyping();

    // Reset debounce timer
    _typingDebounceTimer?.cancel();
    _typingDebounceTimer = Timer(const Duration(seconds: 2), () {
      _chatService.stopTyping();
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Chat'),
        backgroundColor:
            isDarkMode(context) ? Colors.black : Colors.blueGrey.shade900,
      ),
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.grey.shade50,
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: StreamBuilder<List<GroupChatMessage>>(
              stream: GroupChatService.getMessagesStream(limit: 50),
              builder: (context, snapshot) {
                // Update messages list when stream data changes
                if (snapshot.hasData && snapshot.data != null && mounted) {
                  final newMessages = snapshot.data!;
                  
                  // Check if we need to update
                  bool needsUpdate = false;
                  
                  if (_messages.length != newMessages.length) {
                    // Length changed - new message or deleted message
                    needsUpdate = true;
                  } else {
                    // Check for content changes (reactions, read receipts, edits)
                    for (int i = 0; i < _messages.length; i++) {
                      if (i >= newMessages.length) {
                        needsUpdate = true;
                        break;
                      }
                      
                      final oldMsg = _messages[i];
                      final newMsg = newMessages[i];
                      
                      if (oldMsg.messageId != newMsg.messageId) {
                        needsUpdate = true;
                        break;
                      }
                      
                      // Check for changes in mutable fields
                      if (oldMsg.message != newMsg.message ||
                          oldMsg.reactions.toString() != newMsg.reactions.toString() ||
                          oldMsg.readBy.toString() != newMsg.readBy.toString() ||
                          oldMsg.editedAt != newMsg.editedAt ||
                          oldMsg.deleted != newMsg.deleted ||
                          oldMsg.imageUrl != newMsg.imageUrl) {
                        needsUpdate = true;
                        break;
                      }
                    }
                  }
                  
                  if (needsUpdate) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      
                      final wasAtBottom = _scrollController.hasClients &&
                          _scrollController.position.pixels <= 100;
                      
                      setState(() {
                        _messages = newMessages;
                        if (_messages.isNotEmpty) {
                          _oldestMessageTimestamp = _messages.last.timestamp;
                        }
                      });
                      
                      // Only scroll to bottom if we were already at bottom (new message)
                      if (wasAtBottom) {
                        _scrollToBottom();
                      }
                      
                      // Mark as read (debounced)
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) {
                          final messageIds = _messages.map((m) => m.messageId).toList();
                          GroupChatService.updateReadReceipts(messageIds);
                        }
                      });
                    });
                  }
                }

              if (snapshot.connectionState == ConnectionState.waiting && _messages.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}'),
                );
              }

              if (_messages.isEmpty) {
                return const Center(
                  child: Text('No messages yet. Start the conversation!'),
                );
              }

              // Typing indicator stream
              return StreamBuilder<List<String>>(
                stream: GroupChatService.getTypingUsersStream(),
                builder: (context, typingSnapshot) {
                  if (typingSnapshot.hasData) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _typingUsers = typingSnapshot.data!;
                        });
                      }
                    });
                  }

                  return Column(
                    children: [
                      // Loading indicator for older messages
                      if (_isLoadingMore)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ),
                      // Messages list
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            // Refresh messages
                            setState(() {
                              _messages = [];
                              _oldestMessageTimestamp = null;
                              _hasMoreMessages = true;
                            });
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.all(8),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              return GroupChatMessageBubble(
                                key: ValueKey(message.messageId),
                                message: message,
                                onEditMessage: _onMessageEdit,
                                onDeleteMessage: _onMessageDelete,
                                onReactionTap: _onReactionTap,
                              );
                            },
                          ),
                        ),
                      ),
                      // Typing indicator
                      TypingIndicator(typingUserIds: _typingUsers),
                    ],
                  );
                },
              );
            },
            ),
          ),
          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode(context)
            ? Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Image picker button
            IconButton(
              icon: const Icon(Icons.image),
              onPressed: _onImagePick,
              color: Color(COLOR_PRIMARY),
            ),
            // Text input
            Expanded(
              child: TextField(
                controller: _messageController,
                onChanged: _onTextChanged,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDarkMode(context)
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _onSendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            CircleAvatar(
              backgroundColor: Color(COLOR_PRIMARY),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _onSendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

