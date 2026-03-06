import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:paginate_firestore_plus/paginate_firestore.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/ChatVideoContainer.dart';
import 'package:foodie_customer/model/conversation_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/fullScreenImageViewer/FullScreenImageViewer.dart';
import 'package:foodie_customer/ui/fullScreenVideoViewer/FullScreenVideoViewer.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

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
  final bool isPautos;

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
      this.chatType,
      this.isPautos = false})
      : super(key: key);

  @override
  State<ChatScreens> createState() => _ChatScreensState();
}

class _ChatScreensState extends State<ChatScreens> {
  TextEditingController _messageController = TextEditingController();

  final ScrollController _controller = ScrollController();

  // Track processed message IDs to prevent duplicate handling
  final Set<String> _processedMessageIds = {};

  // Track last log time to prevent excessive logging
  DateTime? _lastLogTime;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _orderSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _driverSubscription;
  String? _orderStatus;
  String? _driverId;
  bool _isDriverOnline = false;
  String? _lastSystemStatusKey;
  Timestamp? _deliveredAt;
  bool _isChatWindowOpen = true;
  DateTime? _lastCustomerMessageAt;
  DateTime? _lastOtherMessageAt;
  bool _shouldShowNoReplyPrompt = false;
  final Duration _chatCloseWindow = const Duration(minutes: 30);
  final Duration _noReplyTimeout = const Duration(minutes: 15);
  Timer? _noReplyTimer;
  Timer? _chatCloseTimer;

  @override
  void initState() {
    super.initState();
    if (widget.isPautos) {
      _ensurePautosInboxExists();
    }
    _resetUnreadCount();
    _subscribeToOrderStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _markAllMessagesAsRead();
    });
    if (_controller.hasClients) {
      Timer(const Duration(milliseconds: 500),
          () => _controller.jumpTo(_controller.position.maxScrollExtent));
    }
  }

  Future<void> _ensurePautosInboxExists() async {
    try {
      if (widget.orderId == null || widget.orderId!.isEmpty) return;
      if (widget.customerId == null || widget.restaurantId == null) return;

      final inboxRef = FirebaseFirestore.instance
          .collection('chat_driver')
          .doc(widget.orderId);

      final snapshot = await inboxRef.get();
      if (!snapshot.exists) {
        await inboxRef.set({
          'customerId': widget.customerId,
          'restaurantId': widget.restaurantId,
          'orderId': widget.orderId,
          'chatType': 'Driver',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Error ensuring PAUTOS inbox: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _controller.dispose();
    _processedMessageIds.clear();
    _orderSubscription?.cancel();
    _driverSubscription?.cancel();
    _noReplyTimer?.cancel();
    _chatCloseTimer?.cancel();
    super.dispose();
  }

  Future<void> _resetUnreadCount() async {
    try {
      if (widget.orderId == null || widget.orderId!.isEmpty) return;

      final String collectionName =
          widget.chatType == "Driver" ? 'chat_driver' : 'chat_restaurant';

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(widget.orderId)
          .update({'unreadCount': 0});
    } catch (e) {
      debugPrint('Error resetting unread count: $e');
    }
  }

  /// Handle incoming message - detect if it's from rider and log appropriately
  void _handleIncomingMessage(ConversationModel message) {
    // Validate current user exists
    if (MyAppState.currentUser == null) {
      return;
    }

    // Validate message belongs to current customer
    if (message.receiverId != MyAppState.currentUser!.userID) {
      return;
    }

    // Validate order ID matches
    if (message.orderId != widget.orderId) {
      return;
    }

    // Check if message is from rider (not current customer)
    final bool isFromRider = _isRiderMessage(message);

    if (isFromRider) {
      // Log rider message receipt (safe logging - metadata only)
      _logIncomingRiderMessage(message);
    }

    if (message.receiverId == MyAppState.currentUser!.userID) {
      _markMessageAsDelivered(message);
    }
  }

  /// Check if message is from a rider
  bool _isRiderMessage(ConversationModel message) {
    // Message is from rider when:
    // 1. Chat type is "Driver" (indicating driver/rider chat)
    // 2. Sender is not the current customer
    // 3. Receiver is the current customer
    return widget.chatType == "Driver" &&
        message.senderId != MyAppState.currentUser!.userID &&
        message.receiverId == MyAppState.currentUser!.userID;
  }

  /// Safe logging for incoming rider messages (metadata only, no sensitive content)
  void _logIncomingRiderMessage(ConversationModel message) {
    try {
      // Debounce logging - prevent excessive logs (max once per second)
      final now = DateTime.now();
      if (_lastLogTime != null && now.difference(_lastLogTime!).inSeconds < 1) {
        return;
      }
      _lastLogTime = now;

      // Log metadata only (no message content)
      log('📨 Rider message received - Order: ${message.orderId}, '
          'MessageId: ${message.id}, '
          'SenderId: ${message.senderId}, '
          'Time: ${message.createdAt}');
    } catch (e) {
      debugPrint('Error logging rider message: $e');
    }
  }

  /// Mark all messages in current chat as read
  Future<void> _markAllMessagesAsRead() async {
    try {
      if (widget.orderId == null || widget.orderId!.isEmpty) return;

      final String collectionName =
          widget.chatType == "Driver" ? 'chat_driver' : 'chat_restaurant';

      // Get all unread messages in this chat
      final unreadMessages = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(widget.orderId)
          .collection('thread')
          .where('isRead', isEqualTo: false)
          .where('receiverId', isEqualTo: MyAppState.currentUser!.userID)
          .get();

      // Batch update all unread messages to read
      final userId = MyAppState.currentUser?.userID ?? '';
      if (userId.isEmpty) {
        return;
      }
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in unreadMessages.docs) {
        final data = doc.data();
        final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});
        final readAt = Map<String, dynamic>.from(data['readAt'] ?? {});
        readBy[userId] = now;
        readAt[userId] = now;
        batch.update(doc.reference, {
          'isRead': true,
          'readBy': readBy,
          'readAt': readAt,
        });
      }

      if (unreadMessages.docs.isNotEmpty) {
        await batch.commit();
      }

      if (widget.chatType == "Driver") {
        await FirebaseFirestore.instance
            .collection('chat_driver')
            .doc(widget.orderId)
            .update({'unreadCount': 0});
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  /// Mark a specific message as read
  // ignore: unused_element
  Future<void> _markMessageAsRead(String messageId) async {
    try {
      if (widget.orderId == null || widget.orderId!.isEmpty) return;
      if (messageId.isEmpty) return;

      final String collectionName =
          widget.chatType == "Driver" ? 'chat_driver' : 'chat_restaurant';

      final userId = MyAppState.currentUser?.userID ?? '';
      if (userId.isEmpty) {
        return;
      }
      final messageRef = FirebaseFirestore.instance
          .collection(collectionName)
          .doc(widget.orderId)
          .collection('thread')
          .doc(messageId);
      final messageDoc = await messageRef.get();
      if (!messageDoc.exists) {
        return;
      }
      final data = messageDoc.data() ?? {};
      final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});
      final readAt = Map<String, dynamic>.from(data['readAt'] ?? {});
      readBy[userId] = Timestamp.now();
      readAt[userId] = Timestamp.now();
      await messageRef.update({
        'isRead': true,
        'readBy': readBy,
        'readAt': readAt,
      });
    } catch (e) {
      debugPrint('Error marking message as read: $e');
    }
  }

  Future<void> _markMessageAsDelivered(ConversationModel message) async {
    try {
      if (widget.orderId == null || widget.orderId!.isEmpty) return;
      final messageId = message.id ?? '';
      if (messageId.isEmpty) return;

      final userId = MyAppState.currentUser?.userID ?? '';
      if (userId.isEmpty) return;

      final deliveredBy = Map<String, dynamic>.from(message.deliveredBy ?? {});
      if (deliveredBy.containsKey(userId)) {
        return;
      }

      final now = Timestamp.now();
      final deliveredAt = Map<String, dynamic>.from(message.deliveredAt ?? {});
      deliveredBy[userId] = now;
      deliveredAt[userId] = now;

      final String collectionName =
          widget.chatType == "Driver" ? 'chat_driver' : 'chat_restaurant';
      final messageRef = FirebaseFirestore.instance
          .collection(collectionName)
          .doc(widget.orderId)
          .collection('thread')
          .doc(messageId);
      await messageRef.update({
        'deliveredBy': deliveredBy,
        'deliveredAt': deliveredAt,
      });
    } catch (e) {
      debugPrint('Error marking message as delivered: $e');
    }
  }

  void _subscribeToOrderStatus() {
    if (widget.orderId == null || widget.orderId!.isEmpty) {
      return;
    }
    if (_orderSubscription != null) {
      return;
    }
    final collection = widget.isPautos ? PAUTOS_ORDERS : ORDERS;
    _orderSubscription = FirebaseFirestore.instance
        .collection(collection)
        .doc(widget.orderId)
        .snapshots()
        .listen((orderDoc) async {
      if (!mounted) return;
      final data = orderDoc.data();
      if (data == null) return;

      final status = data['status']?.toString();
      if (status != null && status.isNotEmpty) {
        _orderStatus = status;
        await _maybeCreateSystemMessage(status);
      }
      if (data['deliveredAt'] is Timestamp) {
        _deliveredAt = data['deliveredAt'] as Timestamp;
      }
      _updateChatWindowState();

      final String? driverIdUpdate = (data['driverID'] ??
              data['driverId'] ??
              (data['driver'] is Map<String, dynamic>
                  ? data['driver']['id']
                  : null))
          ?.toString();
      if (driverIdUpdate != null &&
          driverIdUpdate.isNotEmpty &&
          driverIdUpdate != _driverId) {
        _driverId = driverIdUpdate;
        _subscribeToDriver(driverIdUpdate);
      }

      setState(() {});
    });
  }

  void _subscribeToDriver(String driverId) {
    _driverSubscription?.cancel();
    _driverSubscription = FirebaseFirestore.instance
        .collection(USERS)
        .doc(driverId)
        .snapshots()
        .listen((driverDoc) {
      if (!mounted) return;
      final data = driverDoc.data();
      if (data == null) return;

      final active = data['active'] is bool ? data['active'] as bool : false;
      final lastOnline = data['lastOnlineTimestamp'];
      bool isOnline = active;
      if (lastOnline is Timestamp) {
        final lastSeen = lastOnline.toDate();
        if (DateTime.now().difference(lastSeen).inMinutes <= 5) {
          isOnline = true;
        }
      }

      if (_isDriverOnline != isOnline) {
        setState(() {
          _isDriverOnline = isOnline;
        });
      }
    });
  }

  String? _buildRiderStatusText() {
    if (widget.isPautos) {
      if (_orderStatus == 'Shopping') return 'Shopping in progress';
      if (_orderStatus == 'Delivering') return 'On the way';
      if (_orderStatus == 'Delivered') return 'Delivered';
      if (_driverId != null && _isDriverOnline) return 'Rider online';
      return null;
    }
    if (_orderStatus == ORDER_STATUS_IN_TRANSIT ||
        _orderStatus == ORDER_STATUS_SHIPPED) {
      return 'On the way';
    }
    if (_orderStatus == ORDER_STATUS_COMPLETED) {
      return 'Arrived nearby';
    }
    if (_driverId != null && _isDriverOnline) {
      return 'Rider online';
    }
    return null;
  }

  Map<String, String>? _systemMessageInfo(String? status) {
    if (status == null || status.isEmpty) return null;
    if (widget.isPautos) {
      if (status == 'Driver Accepted') {
        return {'key': 'accepted', 'text': 'Driver accepted. Shopping soon.'};
      }
      if (status == 'Shopping') {
        return {'key': 'shopping', 'text': 'Rider is shopping.'};
      }
      if (status == 'Delivering') {
        return {'key': 'on_the_way', 'text': 'Rider is on the way.'};
      }
      if (status == 'Delivered') {
        return {'key': 'delivered', 'text': 'Order delivered.'};
      }
      return null;
    }
    if (status == ORDER_STATUS_ACCEPTED) {
      return {'key': 'accepted', 'text': 'Order is being prepared.'};
    }
    if (status == ORDER_STATUS_IN_TRANSIT || status == ORDER_STATUS_SHIPPED) {
      return {'key': 'on_the_way', 'text': 'Rider is on the way.'};
    }
    if (status == ORDER_STATUS_COMPLETED) {
      return {'key': 'delivered', 'text': 'Order delivered.'};
    }
    return null;
  }

  Future<void> _maybeCreateSystemMessage(String? status) async {
    final info = _systemMessageInfo(status);
    if (info == null) return;

    final statusKey = info['key'] ?? '';
    if (statusKey.isEmpty || _lastSystemStatusKey == statusKey) {
      return;
    }
    _lastSystemStatusKey = statusKey;

    final orderId = widget.orderId ?? '';
    if (orderId.isEmpty) return;

    final String collectionName =
        widget.chatType == "Driver" ? 'chat_driver' : 'chat_restaurant';
    final messageId = 'system_$statusKey';
    final messageRef = FirebaseFirestore.instance
        .collection(collectionName)
        .doc(orderId)
        .collection('thread')
        .doc(messageId);

    final existing = await messageRef.get();
    if (existing.exists) return;

    final userId = MyAppState.currentUser?.userID ?? '';
    final now = Timestamp.now();
    final messageData = ConversationModel(
      id: messageId,
      senderId: 'system',
      receiverId: userId,
      orderId: orderId,
      message: info['text'] ?? '',
      messageType: 'system',
      createdAt: now,
      isRead: true,
      deliveredBy: userId.isNotEmpty ? {userId: now} : {},
      deliveredAt: userId.isNotEmpty ? {userId: now} : {},
      readBy: userId.isNotEmpty ? {userId: now} : {},
      readAt: userId.isNotEmpty ? {userId: now} : {},
    ).toJson();

    await messageRef.set(messageData);
  }

  void _updateChatWindowState() {
    final now = DateTime.now();
    bool nextOpen = true;
    if (_deliveredAt != null) {
      final closeAt = _deliveredAt!.toDate().add(_chatCloseWindow);
      nextOpen = now.isBefore(closeAt);
      _chatCloseTimer?.cancel();
      if (nextOpen) {
        final remaining = closeAt.difference(now);
        _chatCloseTimer = Timer(remaining, () {
          if (!mounted) return;
          _updateChatWindowState();
          setState(() {});
        });
      }
    }
    if (_isChatWindowOpen != nextOpen) {
      _isChatWindowOpen = nextOpen;
    }
  }

  void _trackSupportActivity(ConversationModel message) {
    final createdAt = message.createdAt;
    if (createdAt == null) return;
    final messageTime = createdAt.toDate();
    final currentUserId = MyAppState.currentUser?.userID ?? '';
    if (currentUserId.isEmpty) return;

    if (message.senderId == currentUserId) {
      if (_lastCustomerMessageAt == null ||
          messageTime.isAfter(_lastCustomerMessageAt!)) {
        _lastCustomerMessageAt = messageTime;
      }
    } else {
      if (_lastOtherMessageAt == null ||
          messageTime.isAfter(_lastOtherMessageAt!)) {
        _lastOtherMessageAt = messageTime;
      }
    }
    _updateNoReplyPrompt();
  }

  void _updateNoReplyPrompt() {
    void scheduleRefreshIfNeeded(bool nextValue) {
      if (_shouldShowNoReplyPrompt == nextValue) {
        return;
      }
      _shouldShowNoReplyPrompt = nextValue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }

    if (widget.chatType != "Driver") {
      _noReplyTimer?.cancel();
      scheduleRefreshIfNeeded(false);
      return;
    }
    if (_lastCustomerMessageAt == null) {
      _noReplyTimer?.cancel();
      scheduleRefreshIfNeeded(false);
      return;
    }
    if (_lastOtherMessageAt != null &&
        !_lastCustomerMessageAt!.isAfter(_lastOtherMessageAt!)) {
      _noReplyTimer?.cancel();
      scheduleRefreshIfNeeded(false);
      return;
    }
    final now = DateTime.now();
    final elapsed = now.difference(_lastCustomerMessageAt!);
    final isTimedOut = elapsed >= _noReplyTimeout;
    if (isTimedOut) {
      _noReplyTimer?.cancel();
      scheduleRefreshIfNeeded(true);
      return;
    }

    scheduleRefreshIfNeeded(false);
    _noReplyTimer?.cancel();
    final remaining = _noReplyTimeout - elapsed;
    _noReplyTimer = Timer(remaining, () {
      if (!mounted) return;
      _updateNoReplyPrompt();
      setState(() {});
    });
  }

  Future<void> _showIssuePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _issueTile('missing_item', 'Missing item'),
              _issueTile('wrong_item', 'Wrong item'),
              _issueTile('rider_not_responding', 'Rider not responding'),
              _issueTile('other', 'Other'),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    await _createSupportReport(selected);
  }

  Widget _issueTile(String value, String label) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
  }

  Future<void> _createSupportReport(String issueType) async {
    try {
      final orderId = widget.orderId ?? '';
      if (orderId.isEmpty) {
        await _showSupportError('Order is missing. Please try again.');
        return;
      }
      final userId = MyAppState.currentUser?.userID ?? '';
      final String collectionName =
          widget.chatType == "Driver" ? 'chat_driver' : 'chat_restaurant';
      final chatThreadRef = '$collectionName/$orderId/thread';

      await FirebaseFirestore.instance.collection(REPORTS).add({
        'orderId': orderId,
        'driverId': _driverId ?? '',
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'chat_support',
        'issueType': issueType,
        'chatThreadRef': chatThreadRef,
      });
    } catch (e) {
      await _showSupportError('Failed to submit report. Please try again.');
    }
  }

  Future<void> _showSupportError(String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: SelectableText.rich(
            TextSpan(
              text: message,
              style: const TextStyle(color: Colors.red),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final riderStatusText = _buildRiderStatusText();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        actionsIconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        iconTheme: IconThemeData(
            color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white),
        backgroundColor: Color(COLOR_PRIMARY),
        title: Text(
          widget.restaurantName.toString(),
          style: TextStyle(
              color: isDarkMode(context) ? Colors.grey.shade200 : Colors.white,
              fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(left: 8.0, right: 8, bottom: 8),
        child: Column(
          children: <Widget>[
            if (riderStatusText != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.directions_bike,
                      size: 16,
                      color: Color(COLOR_PRIMARY),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      riderStatusText,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    // currentRecordingState = RecordingState.HIDDEN;
                  });
                },
                child: PaginateFirestore(
                  scrollController: _controller,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, documentSnapshots, index) {
                    ConversationModel inboxModel = ConversationModel.fromJson(
                        documentSnapshots[index].data()
                            as Map<String, dynamic>);

                    // Handle incoming message detection
                    if (inboxModel.id != null &&
                        !_processedMessageIds.contains(inboxModel.id)) {
                      _processedMessageIds.add(inboxModel.id!);
                      _handleIncomingMessage(inboxModel);
                      _trackSupportActivity(inboxModel);
                    }

                    return chatItemView(
                        inboxModel.senderId == MyAppState.currentUser!.userID,
                        inboxModel);
                  },
                  onEmpty: Center(child: Text("No Conversion found")),
                  // orderBy is compulsory to enable pagination
                  query: FirebaseFirestore.instance
                      .collection(widget.chatType == "Driver"
                          ? 'chat_driver'
                          : 'chat_restaurant')
                      .doc(widget.orderId)
                      .collection("thread")
                      .orderBy('createdAt', descending: false),
                  //Change types customerId
                  itemBuilderType: PaginateBuilderType.listView,
                  // to fetch real-time data
                  isLive: true,
                ),
              ),
            ),
            if (_shouldShowNoReplyPrompt)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.report_problem, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Rider not responding?',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: _showIssuePicker,
                      child: const Text('Report'),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _showIssuePicker,
                child: const Text('Report a problem'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  height: 50,
                  child: _isChatWindowOpen
                      ? Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.05),
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
                                  fillColor: Colors.black.withOpacity(0.05),
                                  contentPadding:
                                      const EdgeInsets.only(top: 3, left: 10),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Colors.black.withOpacity(0.05),
                                        width: 0.0),
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(30)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Colors.black.withOpacity(0.05),
                                        width: 0.0),
                                    borderRadius: const BorderRadius.all(
                                        Radius.circular(30)),
                                  ),
                                  hintText: 'Start typing ...',
                                ),
                                onSubmitted: (value) async {
                                  if (_messageController.text.isNotEmpty) {
                                    _sendMessage(_messageController.text, null,
                                        '', 'text');
                                    Timer(
                                        const Duration(milliseconds: 500),
                                        () => _controller.jumpTo(_controller
                                            .position.maxScrollExtent));
                                    _messageController.clear();
                                    setState(() {});
                                  }
                                },
                              ),
                            )),
                            Container(
                              margin: const EdgeInsets.only(left: 10),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: IconButton(
                                onPressed: () async {
                                  if (_messageController.text.isNotEmpty) {
                                    _sendMessage(_messageController.text, null,
                                        '', 'text');
                                    _messageController.clear();
                                    setState(() {});
                                  }
                                },
                                icon: const Icon(Icons.send_rounded),
                                color: Color(COLOR_PRIMARY),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Chat is closed. Please contact support.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget chatItemView(bool isMe, ConversationModel data) {
    // Handle system messages separately - display centered with special styling
    if (data.messageType == "system" || data.senderId == "system") {
      return Container(
        padding:
            const EdgeInsets.only(left: 10, right: 10, top: 10, bottom: 10),
        child: Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              data.message.toString(),
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, top: 10, bottom: 10),
      child: isMe
          ? Align(
              alignment: Alignment.topRight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                          child: Text(
                            data.message.toString(),
                            style: TextStyle(
                                color: data.senderId ==
                                        MyAppState.currentUser!.userID
                                    ? Colors.white
                                    : Colors.black),
                          ),
                        )
                      : data.messageType == "image"
                          ? ConstrainedBox(
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
                                                heroTag: 'chat_image_${data.id}',
                                              ));
                                        },
                                        child: Hero(
                                          tag: 'chat_image_${data.id}',
                                          child: CachedNetworkImage(
                                            imageUrl: data.url!.url,
                                            placeholder: (context, url) => Center(
                                                child:
                                                    CircularProgressIndicator()),
                                            errorWidget:
                                                (context, url, error) =>
                                                    const Icon(Icons.error),
                                          ),
                                        ),
                                      ),
                                    ]),
                              ))
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
                  SizedBox(height: 5),
                  _buildMessageMeta(data),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            child: Text(
                              data.message.toString(),
                              style: TextStyle(
                                  color: data.senderId ==
                                          MyAppState.currentUser!.userID
                                      ? Colors.white
                                      : Colors.black),
                            ),
                          )
                        : data.messageType == "image"
                            ? ConstrainedBox(
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
                                                  heroTag: 'chat_image_${data.id}',
                                                ));
                                          },
                                          child: Hero(
                                            tag: 'chat_image_${data.id}',
                                            child: CachedNetworkImage(
                                              imageUrl: data.url!.url,
                                              placeholder: (context, url) => Center(
                                                  child:
                                                      CircularProgressIndicator()),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const Icon(Icons.error),
                                            ),
                                          ),
                                        ),
                                      ]),
                                ))
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
                SizedBox(height: 5),
                Text(
                    DateFormat('MMM d, yyyy hh:mm aa').format(
                        DateTime.fromMillisecondsSinceEpoch(
                            data.createdAt!.millisecondsSinceEpoch)),
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
    );
  }

  Widget _buildMessageMeta(ConversationModel data) {
    final timeText = DateFormat('MMM d, yyyy hh:mm aa').format(
        DateTime.fromMillisecondsSinceEpoch(
            data.createdAt!.millisecondsSinceEpoch));
    final statusText = _messageStatusText(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          timeText,
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          statusText,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        ),
      ],
    );
  }

  String _messageStatusText(ConversationModel data) {
    final receiverId = data.receiverId ?? '';
    if (receiverId.isEmpty) {
      return 'Sent';
    }
    final readBy = data.readBy ?? {};
    if (readBy.containsKey(receiverId)) {
      return 'Read';
    }
    final deliveredBy = data.deliveredBy ?? {};
    if (deliveredBy.containsKey(receiverId)) {
      return 'Delivered';
    }
    return 'Sent';
  }

  _sendMessage(String message, Url? url, String videoThumbnail,
      String messageType) async {
    print("📌 Sending Message:");
    print("🔹 Given Order ID: ${widget.orderId}");
    print("🔹 Given Restaurant ID: ${widget.restaurantId}");

    String correctOrderId =
        widget.orderId ?? ""; // Make sure orderId is not null

    if (correctOrderId.isEmpty) {
      print("❌ ERROR: Order ID is EMPTY! Cannot send message.");
      return;
    }

    ConversationModel conversationModel = ConversationModel(
      senderId: widget.customerId,
      receiverId: widget.restaurantId,
      orderId: correctOrderId, // ✅ Use the correct orderId
      message: message,
      messageType: messageType,
      videoThumbnail: videoThumbnail,
      createdAt: Timestamp.now(),
      isRead: false,
      deliveredBy: {},
      deliveredAt: {},
      readBy: {},
      readAt: {},
      url: url,
    );

    // ✅ Store message under the correct orderId and correct chat collection
    final String collectionName =
        widget.chatType == "Driver" ? 'chat_driver' : 'chat_restaurant';
    DocumentReference newMessageRef = FirebaseFirestore.instance
        .collection(collectionName)
        .doc(correctOrderId)
        .collection("thread")
        .doc();

    conversationModel.id = newMessageRef.id; // Assign Firestore-generated ID
    await newMessageRef.set(conversationModel.toJson());

    print("✅ Message stored under Order ID: $correctOrderId");

    // Notify rider when customer sends a Driver chat message
    if (widget.chatType == 'Driver' &&
        widget.token != null &&
        widget.token!.isNotEmpty) {
      debugPrint(
          '[CustomerChat] Sending FCM to rider: token length=${widget.token!.length} '
          'orderId=$correctOrderId');
      final title = widget.customerName ?? 'Customer';
      final bodyText = messageType == 'text'
          ? message
          : (messageType == 'image'
              ? 'Sent an image'
              : messageType == 'video'
                  ? 'Sent a video'
                  : 'Sent a message');
      unawaited(
        FireStoreUtils.sendChatFcmMessage(
          title,
          bodyText,
          widget.token!,
          orderId: correctOrderId,
          senderRole: 'customer',
          messageType: 'chat',
          customerId: widget.customerId,
        ),
      );
    } else if (widget.chatType == 'Driver') {
      debugPrint(
          '[CustomerChat] Skipping FCM: rider token empty or null '
          '(orderId=$correctOrderId)');
    }
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future<File?> _compressImage(File original) async {
    try {
      final directory = await getTemporaryDirectory();
      final targetPath =
          '${directory.path}/chat_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        original.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1280,
        minHeight: 1280,
      );
      return result != null ? File(result.path) : original;
    } catch (e) {
      log('Image compression failed: $e');
      return original;
    }
  }

  _onCameraClick() {
    if (!mounted) return;
    final isTablet =
        MediaQuery.of(context).size.shortestSide >= 600;
    final isRecordVideoAvailable = !isTablet;

    final List<Widget> actions = <Widget>[
      CupertinoActionSheetAction(
        child: Text("Choose image from gallery"),
        isDefaultAction: false,
        onPressed: () async {
          Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          try {
            XFile? image =
                await _imagePicker.pickImage(source: ImageSource.gallery);
            if (!mounted) return;
            if (image != null) {
              final compressed =
                  await _compressImage(File(image.path));
              Url url = await FireStoreUtils()
                  .uploadChatImageToFireStorage(
                      compressed ?? File(image.path), context);
              _sendMessage('', url, '', 'image');
            }
          } catch (e, s) {
            log('ChatScreen gallery image picker: $e $s');
          }
        },
      ),
      CupertinoActionSheetAction(
        child: Text("Choose video from gallery"),
        isDefaultAction: false,
        onPressed: () async {
          Navigator.pop(context);
          await Future.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          try {
            XFile? galleryVideo =
                await _imagePicker.pickVideo(source: ImageSource.gallery);
            if (!mounted) return;
            if (galleryVideo != null) {
              ChatVideoContainer videoContainer = await FireStoreUtils()
                  .uploadChatVideoToFireStorage(
                      File(galleryVideo.path), context);
              _sendMessage('', videoContainer.videoUrl,
                  videoContainer.thumbnailUrl, 'video');
            }
          } catch (e, s) {
            log('ChatScreen gallery video picker: $e $s');
          }
        },
      ),
      if (isRecordVideoAvailable)
        CupertinoActionSheetAction(
          child: Text("Record video"),
          isDestructiveAction: false,
          onPressed: () async {
            Navigator.pop(context);
            await Future.delayed(const Duration(milliseconds: 300));
            if (!mounted) return;
            var status = await Permission.camera.status;
            if (!status.isGranted) {
              status = await Permission.camera.request();
            }
            if (!status.isGranted) return;
            if (!mounted) return;
            try {
              XFile? recordedVideo =
                  await _imagePicker.pickVideo(source: ImageSource.camera);
              if (!mounted) return;
              if (recordedVideo != null) {
                ChatVideoContainer videoContainer = await FireStoreUtils()
                    .uploadChatVideoToFireStorage(
                        File(recordedVideo.path), context);
                _sendMessage('', videoContainer.videoUrl,
                    videoContainer.thumbnailUrl, 'video');
              }
            } catch (e, s) {
              log('ChatScreen record video picker: $e $s');
            }
          },
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Text(
            'Video recording is not available on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.0,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ),
    ];

    final action = CupertinoActionSheet(
      message: Text(
        'sendMedia',
        style: TextStyle(fontSize: 15.0),
      ),
      actions: actions,
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
