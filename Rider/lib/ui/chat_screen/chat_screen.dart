import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/conversation_model.dart';
import 'package:foodie_driver/model/inbox_model.dart';
import 'package:foodie_driver/model/optimistic_message.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/chat_read_service.dart';
import 'package:foodie_driver/services/order_service.dart';
import 'package:foodie_driver/ui/fullScreenImageViewer/FullScreenImageViewer.dart';
import 'package:foodie_driver/ui/fullScreenVideoViewer/FullScreenVideoViewer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class ChatScreens extends StatefulWidget {
  final String? orderId;
  final String? customerId;
  final String? customerName;
  final String? customerProfileImage;
  final String? restaurantId;
  final String? restaurantName;
  final String? restaurantProfileImage;
  final String? token;
  final String? chatType;

  ChatScreens(
      {Key? key,
      this.orderId,
      this.customerId,
      this.customerName,
      this.restaurantName,
      this.restaurantId,
      this.customerProfileImage,
      this.restaurantProfileImage,
      this.token,
      this.chatType})
      : super(key: key);

  @override
  State<ChatScreens> createState() => _ChatScreensState();
}

class _ChatScreensState extends State<ChatScreens> {
  TextEditingController _messageController = TextEditingController();

  final ScrollController _controller = ScrollController();

  // Optimistic message state
  List<OptimisticMessage> _optimisticMessages = [];
  Map<String, StreamSubscription> _uploadSubscriptions = {};

  // Order status
  String? _orderStatus;
  StreamSubscription? _orderStatusSubscription;

  // Pagination state - limit messages to keep memory bounded
  static const int _messageLimit = 100;

  @override
  void initState() {
    super.initState();
    _loadOrderStatus();
    _markMessagesAsRead();
    if (_controller.hasClients) {
      Timer(const Duration(milliseconds: 500),
          () => _controller.jumpTo(_controller.position.maxScrollExtent));
    }
  }

  void _loadOrderStatus() {
    if (widget.orderId == null) return;
    _orderStatusSubscription = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .doc(widget.orderId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        final status = data?['status'] as String? ?? '';
        setState(() {
          _orderStatus = status;
        });
      }
    });
  }

  void _markMessagesAsRead() {
    if (widget.orderId != null && MyAppState.currentUser != null) {
      ChatReadService.markMessagesAsRead(
        orderId: widget.orderId!,
        userId: MyAppState.currentUser!.userID,
      );
    }
  }

  @override
  void dispose() {
    // Cancel all upload subscriptions
    for (var subscription in _uploadSubscriptions.values) {
      subscription.cancel();
    }
    _uploadSubscriptions.clear();
    _orderStatusSubscription?.cancel();
    _messageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildOrderProgressIndicator() {
    final status = _orderStatus ?? '';
    final steps = [
      'Order Placed',
      'Driver Assigned',
      'Driver Pending',
      'Order Shipped',
      'In Transit',
      'Delivered',
    ];

    int currentStep = 0;
    if (status == 'Driver Assigned')
      currentStep = 1;
    else if (status == 'Driver Pending')
      currentStep = 2;
    else if (status == 'Order Shipped')
      currentStep = 3;
    else if (status == 'In Transit')
      currentStep = 4;
    else if (status == 'Order Completed') currentStep = 5;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color:
            isDarkMode(context) ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Progress',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDarkMode(context) ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(steps.length, (index) {
              final isActive = index <= currentStep;
              final isLast = index == steps.length - 1;
              return Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? Color(COLOR_PRIMARY)
                            : Colors.grey.shade400,
                      ),
                      child: isActive
                          ? const Icon(Icons.check,
                              size: 16, color: Colors.white)
                          : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: isActive
                              ? Color(COLOR_PRIMARY)
                              : Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              steps[currentStep],
              style: TextStyle(
                fontSize: 12,
                color: Color(COLOR_PRIMARY),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReplyButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _QuickReplyButton(
            label: 'On my way',
            onTap: () => _handleQuickReply('On my way', 'In Transit'),
          ),
          _QuickReplyButton(
            label: 'Arrived',
            onTap: () => _handleQuickReply('I have arrived at your location'),
          ),
          _QuickReplyButton(
            label: 'Running late',
            onTap: () => _handleQuickReply(
                'I apologize, but I am running a bit late. I will be there soon.'),
          ),
          _QuickReplyButton(
            label: 'Order ready',
            onTap: () => _handleQuickReply('Order ready', 'Order Shipped'),
          ),
        ],
      ),
    );
  }

  void _handleQuickReply(String message, [String? status]) async {
    if (widget.orderId == null) return;

    // Send message
    _sendMessage(message, null, '', 'text');
    _messageController.clear();

    // Update status if provided
    if (status != null && widget.orderId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('restaurant_orders')
            .doc(widget.orderId)
            .update({'status': status});

        // Send FCM notification to customer after successful status update
        try {
          await OrderService.sendStatusUpdateNotification(
            widget.orderId!,
            status,
            customerFcmToken: widget.token,
          );
        } catch (e) {
          // Log but don't block UI - FCM errors are non-critical
          debugPrint('Error sending FCM notification: $e');
        }
      } catch (e) {
        print('Error updating status: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        actionsIconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        backgroundColor: Color(COLOR_PRIMARY),
        title: Text(
          widget.customerName.toString(),
          style: TextStyle(
              color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 8.0, right: 8, bottom: 8),
        child: Column(
          children: <Widget>[
            if (widget.orderId != null) _buildOrderProgressIndicator(),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    // currentRecordingState = RecordingState.HIDDEN;
                  });
                },
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chat_driver')
                      .doc(widget.orderId)
                      .collection("thread")
                      .orderBy('createdAt', descending: false)
                      .limit(_messageLimit)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Convert Firestore documents to ConversationModel
                    final firestoreMessages = snapshot.data!.docs
                        .map((doc) => ConversationModel.fromJson(
                            doc.data() as Map<String, dynamic>))
                        .toList();

                    // Convert optimistic messages to ConversationModel
                    final optimisticConversations = _optimisticMessages
                        .map((opt) => opt.toConversationModel())
                        .toList();

                    // Merge two sorted lists using O(n) linear merge
                    // Firestore messages are already sorted by createdAt (orderBy)
                    // Optimistic messages are added in chronological order
                    final allMessages = _mergeSortedLists(
                      firestoreMessages,
                      optimisticConversations,
                    );

                    if (allMessages.isEmpty) {
                      return const Center(child: Text("No Conversion found"));
                    }

                    return ListView.builder(
                      controller: _controller,
                      physics: const BouncingScrollPhysics(),
                      itemCount: allMessages.length,
                      itemBuilder: (context, index) {
                        final message = allMessages[index];
                        final isMe =
                            message.senderId == MyAppState.currentUser!.userID;

                        // Check if this is an optimistic message
                        final optimisticIndex = _optimisticMessages
                            .indexWhere((opt) => opt.id == message.id);
                        final isOptimistic = optimisticIndex != -1;
                        final optimisticMsg = isOptimistic
                            ? _optimisticMessages[optimisticIndex]
                            : null;

                        // If optimistic and not completed, show optimistic bubble
                        if (isOptimistic &&
                            optimisticMsg != null &&
                            optimisticMsg.uploadState !=
                                UploadState.completed) {
                          if (optimisticMsg.messageType == 'image') {
                            return Container(
                              padding: const EdgeInsets.only(
                                  left: 14, right: 14, top: 10, bottom: 10),
                              child: Align(
                                alignment: Alignment.topRight,
                                child:
                                    _OptimisticImageBubble(optimisticMsg, isMe),
                              ),
                            );
                          } else if (optimisticMsg.messageType == 'video') {
                            return Container(
                              padding: const EdgeInsets.only(
                                  left: 14, right: 14, top: 10, bottom: 10),
                              child: Align(
                                alignment: Alignment.topRight,
                                child:
                                    _OptimisticVideoBubble(optimisticMsg, isMe),
                              ),
                            );
                          }
                        }

                        // Otherwise show normal message
                        return chatItemView(isMe, message);
                      },
                    );
                  },
                ),
              ),
            ),
            _buildQuickReplyButtons(),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      Flexible(
                          child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: TextField(
                          textInputAction: TextInputAction.send,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.sentences,
                          controller: _messageController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.05),
                            contentPadding:
                                const EdgeInsets.only(top: 3, left: 10),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  width: 0.0),
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(30)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  width: 0.0),
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(30)),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Colors.grey.withValues(alpha: 0.3),
                                  width: 0.0),
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(30)),
                            ),
                            hintText: 'Start typing ...',
                          ),
                          onSubmitted: (value) async {
                            if (_messageController.text.isNotEmpty) {
                              _sendMessage(
                                  _messageController.text, null, '', 'text');
                              Timer(
                                  const Duration(milliseconds: 500),
                                  () => _controller.jumpTo(
                                      _controller.position.maxScrollExtent));
                              _messageController.clear();
                              setState(() {});
                            }
                          },
                        ),
                      )),
                      Container(
                        margin: const EdgeInsets.only(left: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: IconButton(
                          onPressed: () async {
                            if (_messageController.text.isNotEmpty) {
                              _sendMessage(
                                  _messageController.text, null, '', 'text');
                              _messageController.clear();
                              setState(() {});
                            }
                          },
                          icon: const Icon(Icons.send_rounded),
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: IconButton(
                          onPressed: () async {
                            _onCameraClick();
                          },
                          icon: const Icon(Icons.camera_alt),
                          color: Color(COLOR_PRIMARY),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Optimistic image bubble widget
  Widget _OptimisticImageBubble(OptimisticMessage optimisticMsg, bool isMe) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 50,
        maxWidth: 200,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(10),
          topRight: const Radius.circular(10),
          bottomLeft: isMe ? const Radius.circular(10) : Radius.zero,
          bottomRight: isMe ? Radius.zero : const Radius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.file(
              optimisticMsg.localFile,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.error),
            ),
            // Progress indicator overlay - only show when uploading and not completed
            if (optimisticMsg.uploadState == UploadState.uploading &&
                optimisticMsg.progress < 1.0)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: optimisticMsg.progress,
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            // Retry button overlay
            if (optimisticMsg.uploadState == UploadState.failed)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.white, size: 32),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _retryUpload(optimisticMsg),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(COLOR_PRIMARY),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Optimistic video bubble widget
  Widget _OptimisticVideoBubble(OptimisticMessage optimisticMsg, bool isMe) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 50,
        maxWidth: 200,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(10),
          topRight: const Radius.circular(10),
          bottomLeft: isMe ? const Radius.circular(10) : Radius.zero,
          bottomRight: isMe ? Radius.zero : const Radius.circular(10),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              color: Colors.black,
              child: const Center(
                child: Icon(Icons.play_circle_outline,
                    color: Colors.white, size: 48),
              ),
            ),
            // Progress indicator overlay - only show when uploading and not completed
            if (optimisticMsg.uploadState == UploadState.uploading &&
                optimisticMsg.progress < 1.0)
              Container(
                color: Colors.black.withValues(alpha: 0.3),
                child: Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: optimisticMsg.progress,
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            // Retry button overlay
            if (optimisticMsg.uploadState == UploadState.failed)
              Container(
                color: Colors.black.withValues(alpha: 0.5),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.white, size: 32),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _retryUpload(optimisticMsg),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(COLOR_PRIMARY),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Merge two sorted lists of ConversationModel by createdAt in O(n) time
  /// Both lists are assumed to be sorted by createdAt in ascending order
  List<ConversationModel> _mergeSortedLists(
    List<ConversationModel> list1,
    List<ConversationModel> list2,
  ) {
    final result = <ConversationModel>[];
    int i = 0, j = 0;

    // Merge using two pointers
    while (i < list1.length && j < list2.length) {
      if (list1[i].createdAt.compareTo(list2[j].createdAt) <= 0) {
        result.add(list1[i]);
        i++;
      } else {
        result.add(list2[j]);
        j++;
      }
    }

    // Add remaining elements from list1
    while (i < list1.length) {
      result.add(list1[i]);
      i++;
    }

    // Add remaining elements from list2
    while (j < list2.length) {
      result.add(list2[j]);
      j++;
    }

    return result;
  }

  String _formatTimestamp(Timestamp timestamp) {
    final now = DateTime.now();
    final messageTime = timestamp.toDate();
    final difference = now.difference(messageTime);

    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(messageTime);
    } else if (difference.inDays < 7) {
      return DateFormat('EEE, HH:mm').format(messageTime);
    } else {
      return DateFormat('MMM dd, HH:mm').format(messageTime);
    }
  }

  String _getSenderLabel(ConversationModel message) {
    if (message.senderType == 'system') {
      return 'System';
    }
    if (message.senderType == 'admin') {
      return 'Admin';
    }
    if (message.senderId == MyAppState.currentUser?.userID) {
      return 'You';
    }
    return widget.customerName ?? 'Customer';
  }

  Widget chatItemView(bool isMe, ConversationModel data) {
    final isSystemMessage = data.senderType == 'system';
    final timestamp = data.createdAt;
    final senderLabel = _getSenderLabel(data);

    // System message styling
    if (isSystemMessage) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 4),
                Text(
                  senderLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Text(
                    data.message ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 10),
      child: isMe
          ? Align(
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (senderLabel != 'You')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, right: 8),
                      child: Text(
                        senderLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  data.messageType == "text"
                      ? Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                                bottomLeft: Radius.circular(10)),
                            color: Color(COLOR_PRIMARY),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                data.message.toString(),
                                style: const TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTimestamp(timestamp),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : data.messageType == "image"
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 50,
                                    maxWidth: 200,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(10),
                                        topRight: Radius.circular(10),
                                        bottomLeft: Radius.circular(10)),
                                    child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          GestureDetector(
                                            onTap: () {
                                              push(
                                                  context,
                                                  FullScreenImageViewer(
                                                    imageUrl: data.url!.url,
                                                  ));
                                            },
                                            child: Hero(
                                              tag: data.url!.url,
                                              child: CachedNetworkImage(
                                                imageUrl: data.url!.url,
                                                placeholder: (context, url) =>
                                                    Center(
                                                        child:
                                                            CircularProgressIndicator()),
                                                errorWidget:
                                                    (context, url, error) =>
                                                        const Icon(Icons.error),
                                              ),
                                            ),
                                          ),
                                        ]),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    _formatTimestamp(timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : FloatingActionButton(
                              mini: true,
                              heroTag: data.id,
                              backgroundColor: Color(COLOR_PRIMARY),
                              onPressed: () {
                                push(
                                    context,
                                    FullScreenVideoViewer(
                                      heroTag: data.id.toString(),
                                      videoUrl: data.url!.url,
                                    ));
                              },
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                              ),
                            ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 8),
                  child: Text(
                    senderLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    data.messageType == "text"
                        ? Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  topRight: Radius.circular(10),
                                  bottomRight: Radius.circular(10)),
                              color: Colors.grey.shade300,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.message.toString(),
                                  style: const TextStyle(color: Colors.black),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatTimestamp(timestamp),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : data.messageType == "image"
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 50,
                                      maxWidth: 200,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(10),
                                          topRight: Radius.circular(10),
                                          bottomRight: Radius.circular(10)),
                                      child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                push(
                                                    context,
                                                    FullScreenImageViewer(
                                                      imageUrl: data.url!.url,
                                                    ));
                                              },
                                              child: Hero(
                                                tag: data.url!.url,
                                                child: CachedNetworkImage(
                                                  imageUrl: data.url!.url,
                                                  placeholder: (context, url) =>
                                                      Center(
                                                          child:
                                                              CircularProgressIndicator()),
                                                  errorWidget: (context, url,
                                                          error) =>
                                                      const Icon(Icons.error),
                                                ),
                                              ),
                                            ),
                                          ]),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      _formatTimestamp(timestamp),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : FloatingActionButton(
                                mini: true,
                                heroTag: data.id,
                                backgroundColor: Color(COLOR_PRIMARY),
                                onPressed: () {
                                  push(
                                      context,
                                      FullScreenVideoViewer(
                                        heroTag: data.id.toString(),
                                        videoUrl: data.url!.url,
                                      ));
                                },
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                ),
                              ),
                  ],
                ),
              ],
            ),
    );
  }

  // Start image upload with progress tracking
  void _startImageUpload(OptimisticMessage optimisticMsg, File file) {
    // Set upload state to uploading immediately
    setState(() {
      final index =
          _optimisticMessages.indexWhere((msg) => msg.id == optimisticMsg.id);
      if (index != -1) {
        _optimisticMessages[index].uploadState = UploadState.uploading;
        _optimisticMessages[index].progress = 0.0;
      }
    });

    final subscription =
        FireStoreUtils().uploadChatImageWithProgress(file).listen(
      (progress) {
        if (mounted) {
          setState(() {
            final index = _optimisticMessages
                .indexWhere((msg) => msg.id == optimisticMsg.id);
            if (index != -1) {
              _optimisticMessages[index].progress = progress.progress;
              if (progress.error != null) {
                _optimisticMessages[index].uploadState = UploadState.failed;
                _optimisticMessages[index].error = progress.error;
              } else if (progress.progress >= 1.0 && progress.result != null) {
                // Upload completed - remove immediately and send to Firestore
                _optimisticMessages[index].uploadState = UploadState.completed;
                _optimisticMessages[index].finalUrl = progress.result;

                // Send message to Firestore
                _sendMessage('', progress.result, '', 'image');

                // Remove from optimistic list immediately (no delay)
                _optimisticMessages.removeAt(index);
                _uploadSubscriptions.remove(optimisticMsg.id);
              } else {
                // Update progress during upload
                _optimisticMessages[index].uploadState = UploadState.uploading;
              }
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            final index = _optimisticMessages
                .indexWhere((msg) => msg.id == optimisticMsg.id);
            if (index != -1) {
              _optimisticMessages[index].uploadState = UploadState.failed;
              _optimisticMessages[index].error = error.toString();
            }
          });
        }
      },
    );

    _uploadSubscriptions[optimisticMsg.id] = subscription;
  }

  // Start video upload with progress tracking
  void _startVideoUpload(OptimisticMessage optimisticMsg, File file) {
    // Set upload state to uploading immediately
    setState(() {
      final index =
          _optimisticMessages.indexWhere((msg) => msg.id == optimisticMsg.id);
      if (index != -1) {
        _optimisticMessages[index].uploadState = UploadState.uploading;
        _optimisticMessages[index].progress = 0.0;
      }
    });

    final subscription =
        FireStoreUtils().uploadChatVideoWithProgress(file).listen(
      (progress) {
        if (mounted) {
          setState(() {
            final index = _optimisticMessages
                .indexWhere((msg) => msg.id == optimisticMsg.id);
            if (index != -1) {
              _optimisticMessages[index].progress = progress.progress;
              if (progress.error != null) {
                _optimisticMessages[index].uploadState = UploadState.failed;
                _optimisticMessages[index].error = progress.error;
              } else if (progress.progress >= 1.0 &&
                  progress.videoResult != null) {
                // Upload completed - remove immediately and send to Firestore
                _optimisticMessages[index].uploadState = UploadState.completed;
                _optimisticMessages[index].finalUrl =
                    progress.videoResult!.videoUrl;
                _optimisticMessages[index].finalVideoThumbnail =
                    progress.videoResult!.thumbnailUrl;

                // Send message to Firestore
                _sendMessage('', progress.videoResult!.videoUrl,
                    progress.videoResult!.thumbnailUrl, 'video');

                // Remove from optimistic list immediately (no delay)
                _optimisticMessages.removeAt(index);
                _uploadSubscriptions.remove(optimisticMsg.id);
              } else {
                // Update progress during upload
                _optimisticMessages[index].uploadState = UploadState.uploading;
              }
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            final index = _optimisticMessages
                .indexWhere((msg) => msg.id == optimisticMsg.id);
            if (index != -1) {
              _optimisticMessages[index].uploadState = UploadState.failed;
              _optimisticMessages[index].error = error.toString();
            }
          });
        }
      },
    );

    _uploadSubscriptions[optimisticMsg.id] = subscription;
  }

  // Retry failed upload
  void _retryUpload(OptimisticMessage optimisticMsg) {
    // Cancel existing subscription if any
    _uploadSubscriptions[optimisticMsg.id]?.cancel();

    // Reset state
    setState(() {
      final index =
          _optimisticMessages.indexWhere((msg) => msg.id == optimisticMsg.id);
      if (index != -1) {
        _optimisticMessages[index].uploadState = UploadState.uploading;
        _optimisticMessages[index].progress = 0.0;
        _optimisticMessages[index].error = null;
      }
    });

    // Restart upload
    if (optimisticMsg.messageType == 'image') {
      _startImageUpload(optimisticMsg, optimisticMsg.localFile);
    } else if (optimisticMsg.messageType == 'video') {
      _startVideoUpload(optimisticMsg, optimisticMsg.localFile);
    }
  }

  _sendMessage(String message, Url? url, String videoThumbnail,
      String messageType) async {
    // Resolve customerId from order document to ensure correct receiverId
    String? resolvedCustomerId = widget.customerId;
    if (widget.chatType == "Driver" && widget.orderId != null) {
      try {
        final orderDoc = await FirebaseFirestore.instance
            .collection('restaurant_orders')
            .doc(widget.orderId)
            .get();

        if (orderDoc.exists) {
          final orderData = orderDoc.data();
          final author = orderData?['author'] as Map<String, dynamic>? ?? {};
          resolvedCustomerId = author['id'] as String? ??
              author['customerID'] as String? ??
              widget.customerId;
        }
      } catch (e) {
        debugPrint(
            '[DriverChat] Order ${widget.orderId}: Error resolving customerId: $e');
        // Fallback to widget.customerId if resolution fails
      }
    }

    InboxModel inboxModel = InboxModel(
        lastSenderId: resolvedCustomerId,
        customerId: resolvedCustomerId,
        customerName: widget.customerName,
        restaurantId: widget.restaurantId,
        restaurantName: widget.restaurantName,
        createdAt: Timestamp.now(),
        orderId: widget.orderId,
        customerProfileImage: widget.customerProfileImage,
        restaurantProfileImage: widget.restaurantProfileImage,
        lastMessage: _messageController.text,
        chatType: widget.chatType);

    if (widget.chatType == "Driver") {
      await FireStoreUtils.addDriverInbox(inboxModel);
    }

    ConversationModel conversationModel = ConversationModel(
        id: Uuid().v4(),
        message: message,
        senderId: widget.restaurantId,
        receiverId: resolvedCustomerId,
        createdAt: Timestamp.now(),
        url: url,
        orderId: widget.orderId,
        messageType: messageType,
        videoThumbnail: videoThumbnail,
        senderType: 'driver',
        isRead: false,
        readBy: {});

    if (url != null) {
      if (url.mime.contains('image')) {
        conversationModel.message = "sent a message";
      } else if (url.mime.contains('video')) {
        conversationModel.message = "Sent a video";
      } else if (url.mime.contains('audio')) {
        conversationModel.message = "Sent a audio";
      }
    }

    if (widget.chatType == "Driver") {
      // Debug log to verify message fields before writing
      debugPrint(
          '[DriverChat] Writing message - orderId: ${conversationModel.orderId}, receiverId: ${conversationModel.receiverId}, isRead: ${conversationModel.isRead}, readBy: ${conversationModel.readBy}');
      await FireStoreUtils.addDriverChat(conversationModel);
    }

    // Send FCM notification to customer after successful message save
    if (widget.chatType == "Driver" && widget.orderId != null) {
      try {
        // Resolve FCM token with fallback: order.author -> users/{customerId}
        // Use already-resolved customerId from message creation
        String? fcmToken;
        String? fallbackToken;
        String? fcmResolvedCustomerId = resolvedCustomerId;
        String tokenSource = 'unknown';

        try {
          final orderDoc = await FirebaseFirestore.instance
              .collection('restaurant_orders')
              .doc(widget.orderId)
              .get();

          if (orderDoc.exists) {
            final orderData = orderDoc.data();
            final author = orderData?['author'] as Map<String, dynamic>? ?? {};
            fcmToken = author['fcmToken'] as String?;
            // Use order document customerId if available, otherwise use already-resolved value
            fcmResolvedCustomerId = author['id'] as String? ??
                author['customerID'] as String? ??
                resolvedCustomerId;
            tokenSource = 'order.author';

            // Always fetch fallback token from users collection in case order.author token is invalid
            if (fcmResolvedCustomerId != null) {
              try {
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(fcmResolvedCustomerId)
                    .get();
                if (userDoc.exists) {
                  final userData = userDoc.data();
                  fallbackToken = userData?['fcmToken'] as String?;
                  if (fallbackToken != null &&
                      fallbackToken.isNotEmpty &&
                      fallbackToken != fcmToken) {
                    debugPrint(
                        '[DriverChat] Order ${widget.orderId}: Retrieved fallback FCM token from users collection for customer $fcmResolvedCustomerId');
                  }
                }
              } catch (userError) {
                debugPrint(
                    '[DriverChat] Order ${widget.orderId}: Error reading user doc: $userError');
              }
            }

            // If order.author token is missing, use fallback token
            if ((fcmToken == null || fcmToken.isEmpty) &&
                fallbackToken != null) {
              fcmToken = fallbackToken;
              tokenSource = 'users.collection';
              fallbackToken = null; // Clear fallback since we're using it
            }
            String _tokPrev(String? t) =>
                t != null && t.length > 20
                    ? '${t.substring(0, 12)}...${t.substring(t.length - 4)}'
                    : t != null && t.isNotEmpty
                        ? '***'
                        : 'null';
            final orderAuthorToken = author['fcmToken'] as String?;
            debugPrint(
                '[TOKEN_DEBUG] Rider: tokenSource=$tokenSource customerId=$fcmResolvedCustomerId tokenPreview=${_tokPrev(fcmToken)} orderAuthorEmpty=${orderAuthorToken == null || orderAuthorToken.isEmpty}');
          } else {
            debugPrint(
                '[DriverChat] Order ${widget.orderId}: Order document not found');
          }
        } catch (orderError) {
          debugPrint(
              '[DriverChat] Order ${widget.orderId}: Error reading order doc: $orderError');
        }

        // Only send notification if token is available
        if (fcmToken != null && fcmToken.isNotEmpty) {
          // Truncate message preview safely (max 100 characters)
          final messagePreview = conversationModel.message.toString();
          final truncatedMessage = messagePreview.length > 100
              ? '${messagePreview.substring(0, 100)}...'
              : messagePreview;

          // Build payload keys for debug logging
          final payloadKeys = <String>[
            'type',
            'orderId',
            'senderRole',
            'messageType'
          ];

          // Log resolved customer ID, token source, and payload keys
          debugPrint(
              '[DriverChat] Order ${widget.orderId}: Resolved customerId=${fcmResolvedCustomerId ?? "null"}, tokenSource=$tokenSource, payloadKeys=[${payloadKeys.join(", ")}]');

          // Send notification with proper payload (await to ensure completion)
          bool sendSuccess = await FireStoreUtils.sendChatFcmMessage(
            'New message from ${widget.restaurantName ?? "rider"}',
            truncatedMessage,
            fcmToken,
            orderId: widget.orderId,
            senderRole: 'rider',
            messageType: 'chat',
            customerId: fcmResolvedCustomerId,
            restaurantId: widget.restaurantId,
            tokenSource: tokenSource,
          );

          // If first attempt failed and we have a fallback token, try again with fallback
          if (!sendSuccess &&
              fallbackToken != null &&
              fallbackToken.isNotEmpty &&
              fcmToken != fallbackToken) {
            debugPrint(
                '[TOKEN_DEBUG] Rider: First send failed, retrying with fallback users.fcmToken orderId=${widget.orderId}');
            debugPrint(
                '[DriverChat] Order ${widget.orderId}: First token failed, retrying with fallback token from users collection');
            sendSuccess = await FireStoreUtils.sendChatFcmMessage(
              'New message from ${widget.restaurantName ?? "rider"}',
              truncatedMessage,
              fallbackToken,
              orderId: widget.orderId,
              senderRole: 'rider',
              messageType: 'chat',
              customerId: fcmResolvedCustomerId,
              restaurantId: widget.restaurantId,
              tokenSource: 'users.collection',
            );
            if (sendSuccess) {
              debugPrint(
                  '[DriverChat] Order ${widget.orderId}: FCM notification sent successfully using fallback token');
            }
          }

          if (sendSuccess) {
            debugPrint(
                '[TOKEN_DEBUG] Rider: sendChatFcmMessage SUCCESS orderId=${widget.orderId}');
            debugPrint(
                '[DriverChat] Order ${widget.orderId}: FCM notification sent successfully');
          } else {
            debugPrint(
                '[TOKEN_DEBUG] Rider: sendChatFcmMessage FAILED orderId=${widget.orderId} tokenSource=$tokenSource customerId=${fcmResolvedCustomerId ?? "unknown"}');
            debugPrint(
                '[DriverChat] Order ${widget.orderId}: FCM notification failed to send - token may be invalid. Customer ID: ${fcmResolvedCustomerId ?? "unknown"}');
          }
        } else {
          debugPrint(
              '[TOKEN_DEBUG] Rider: No FCM token available customerId=${fcmResolvedCustomerId ?? "unknown"}');
          debugPrint(
              '[DriverChat] Order ${widget.orderId}: No FCM token available for customer ${fcmResolvedCustomerId ?? "unknown"}');
        }
      } catch (e) {
        // Silently handle FCM errors - don't block chat sending
        debugPrint('[DriverChat] Error sending FCM notification: $e');
      }
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  // Handle image selection with optimistic updates
  Future<void> _handleImageSelection(File imageFile) async {
    try {
      // Compress image first
      final compressedImage = await FireStoreUtils.compressImage(imageFile);

      // Create optimistic message
      final optimisticMsg = OptimisticMessage(
        id: Uuid().v4(),
        localFilePath: compressedImage.path,
        messageType: 'image',
        uploadState: UploadState.pending,
        createdAt: Timestamp.now(),
        senderId: widget.restaurantId ?? '',
        receiverId: widget.customerId ?? '',
        orderId: widget.orderId ?? '',
      );

      // Add to optimistic messages list
      setState(() {
        _optimisticMessages.add(optimisticMsg);
      });

      // Start background upload
      _startImageUpload(optimisticMsg, compressedImage);

      // Scroll to bottom to show new message
      Timer(const Duration(milliseconds: 300), () {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to process image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Handle video selection with optimistic updates
  Future<void> _handleVideoSelection(File videoFile) async {
    try {
      // For now, use video file directly (compression happens during upload)
      // The upload method will handle compression
      final compressedVideo = videoFile;

      // Create optimistic message
      final optimisticMsg = OptimisticMessage(
        id: Uuid().v4(),
        localFilePath: compressedVideo.path,
        messageType: 'video',
        uploadState: UploadState.pending,
        createdAt: Timestamp.now(),
        senderId: widget.restaurantId ?? '',
        receiverId: widget.customerId ?? '',
        orderId: widget.orderId ?? '',
      );

      // Add to optimistic messages list
      setState(() {
        _optimisticMessages.add(optimisticMsg);
      });

      // Start background upload
      _startVideoUpload(optimisticMsg, compressedVideo);

      // Scroll to bottom to show new message
      Timer(const Duration(milliseconds: 300), () {
        if (_controller.hasClients) {
          _controller.jumpTo(_controller.position.maxScrollExtent);
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to process video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  _onCameraClick() {
    final action = CupertinoActionSheet(
      message: Text(
        'sendMedia',
        style: TextStyle(fontSize: 15.0),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          child: Text("chooseImageFromGallery"),
          isDefaultAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? image =
                await _imagePicker.pickImage(source: ImageSource.gallery);
            if (image != null) {
              await _handleImageSelection(File(image.path));
            }
          },
        ),
        CupertinoActionSheetAction(
          child: Text("chooseVideoFromGallery"),
          isDefaultAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? galleryVideo =
                await _imagePicker.pickVideo(source: ImageSource.gallery);
            if (galleryVideo != null) {
              await _handleVideoSelection(File(galleryVideo.path));
            }
          },
        ),
        CupertinoActionSheetAction(
          child: Text("Take a Picture"),
          isDestructiveAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? image =
                await _imagePicker.pickImage(source: ImageSource.camera);
            if (image != null) {
              await _handleImageSelection(File(image.path));
            }
          },
        ),
        CupertinoActionSheetAction(
          child: Text("Record Video"),
          isDestructiveAction: false,
          onPressed: () async {
            Navigator.pop(context);
            XFile? recordedVideo =
                await _imagePicker.pickVideo(source: ImageSource.camera);
            if (recordedVideo != null) {
              await _handleVideoSelection(File(recordedVideo.path));
            }
          },
        )
      ],
      cancelButton: CupertinoActionSheetAction(
        child: Text(
          'Cancel',
        ),
        onPressed: () {
          Navigator.pop(context);
        },
      ),
    );
    showCupertinoModalPopup(context: context, builder: (context) => action);
  }
}

class _QuickReplyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickReplyButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Color(COLOR_PRIMARY).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Color(COLOR_PRIMARY).withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Color(COLOR_PRIMARY),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
