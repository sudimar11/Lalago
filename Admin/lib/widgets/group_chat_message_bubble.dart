import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:brgy/main.dart';
import 'package:brgy/model/GroupChatMessage.dart';
import 'package:intl/intl.dart';

class GroupChatMessageBubble extends StatefulWidget {
  final GroupChatMessage message;
  final Function(String, String)? onEditMessage;
  final Function(String)? onDeleteMessage;
  final Function(String, String)? onReactionTap;

  const GroupChatMessageBubble({
    Key? key,
    required this.message,
    this.onEditMessage,
    this.onDeleteMessage,
    this.onReactionTap,
  }) : super(key: key);

  @override
  State<GroupChatMessageBubble> createState() => _GroupChatMessageBubbleState();
}

class _GroupChatMessageBubbleState extends State<GroupChatMessageBubble> {
  bool _showReactions = false;
  final List<String> _emojiList = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  bool get _isMyMessage {
    final currentUser = MyAppState.currentUser;
    return currentUser != null && widget.message.senderId == currentUser.userID;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.deleted) {
      return _buildDeletedMessage();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: _isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Sender name (only for others' messages)
          if (!_isMyMessage) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                widget.message.senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ],
          // Message bubble
          Row(
            mainAxisAlignment: _isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!_isMyMessage) ...[
                // Avatar
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.orange,
                  child: Text(
                    widget.message.senderName.isNotEmpty
                        ? widget.message.senderName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Message content
              Flexible(
                child: GestureDetector(
                  onLongPress: _isMyMessage ? _showMessageOptions : _showReactionPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isMyMessage ? Colors.orange : Colors.grey[200],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(_isMyMessage ? 16 : 4),
                        bottomRight: Radius.circular(_isMyMessage ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image or text
                        if (widget.message.imageUrl != null)
                          _buildImageMessage()
                        else if (widget.message.message.isNotEmpty)
                          _buildTextMessage(),
                        // Timestamp and read receipt
                        const SizedBox(height: 4),
                        _buildTimestampAndReceipt(),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isMyMessage) ...[
                const SizedBox(width: 8),
                const SizedBox(width: 32), // Placeholder for alignment
              ],
            ],
          ),
          // Reactions
          if (widget.message.reactions.isNotEmpty || _showReactions) ...[
            const SizedBox(height: 4),
            _buildReactions(),
          ],
        ],
      ),
    );
  }

  Widget _buildDeletedMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: _isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'This message was deleted',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextMessage() {
    return Text(
      widget.message.message,
      style: TextStyle(
        color: _isMyMessage ? Colors.white : Colors.black87,
        fontSize: 15,
      ),
    );
  }

  Widget _buildImageMessage() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => _FullScreenImageViewer(
              imageUrl: widget.message.imageUrl!,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: widget.message.imageUrl!,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 200,
            height: 200,
            color: Colors.grey[300],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            width: 200,
            height: 200,
            color: Colors.grey[300],
            child: const Icon(Icons.error),
          ),
        ),
      ),
    );
  }

  Widget _buildTimestampAndReceipt() {
    final timeFormat = DateFormat('h:mm a');
    final timestamp = widget.message.timestamp.toDate();
    final timeString = timeFormat.format(timestamp);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Edited indicator
        if (widget.message.isEdited()) ...[
          Text(
            'edited',
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: _isMyMessage ? Colors.white70 : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 4),
        ],
        // Timestamp
        Text(
          timeString,
          style: TextStyle(
            fontSize: 10,
            color: _isMyMessage ? Colors.white70 : Colors.grey[600],
          ),
        ),
        // Read receipt (only for my messages)
        if (_isMyMessage) ...[
          const SizedBox(width: 4),
          _buildReadReceipt(),
        ],
      ],
    );
  }

  Widget _buildReadReceipt() {
    final currentUser = MyAppState.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final isRead = widget.message.isReadBy(currentUser.userID);

    return Icon(
      isRead ? Icons.done_all : Icons.done,
      size: 14,
      color: isRead ? Colors.blue[300] : Colors.white70,
    );
  }

  Widget _buildReactions() {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          // Existing reactions
          ...widget.message.reactions.entries.map((entry) {
            final emoji = entry.key;
            final userIds = entry.value;
            final currentUser = MyAppState.currentUser;
            final isMyReaction = currentUser != null && userIds.contains(currentUser.userID);

            return GestureDetector(
              onTap: () {
                if (widget.onReactionTap != null) {
                  widget.onReactionTap!(widget.message.messageId, emoji);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isMyReaction
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: isMyReaction
                      ? Border.all(color: Colors.orange, width: 1)
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 4),
                    Text(
                      '${userIds.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // Reaction picker button
          if (_showReactions)
            ..._emojiList.map((emoji) {
              final hasReaction = widget.message.hasUserReacted(
                MyAppState.currentUser?.userID ?? '',
                emoji,
              );

              if (hasReaction) return const SizedBox.shrink();

              return GestureDetector(
                onTap: () {
                  if (widget.onReactionTap != null) {
                    widget.onReactionTap!(widget.message.messageId, emoji);
                  }
                  setState(() {
                    _showReactions = false;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showMessageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.message.canBeEdited())
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _editMessage();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteMessage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.emoji_emotions),
              title: const Text('Add Reaction'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _showReactions = true;
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker() {
    setState(() {
      _showReactions = true;
    });
  }

  void _editMessage() {
    final controller = TextEditingController(text: widget.message.message);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(
            hintText: 'Enter message',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty && widget.onEditMessage != null) {
                widget.onEditMessage!(widget.message.messageId, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteMessage() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (widget.onDeleteMessage != null) {
                widget.onDeleteMessage!(widget.message.messageId);
              }
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// Simple full screen image viewer
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.contain,
          placeholder: (context, url) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (context, url, error) => const Center(
            child: Icon(Icons.error, color: Colors.white, size: 48),
          ),
        ),
      ),
    );
  }
}

