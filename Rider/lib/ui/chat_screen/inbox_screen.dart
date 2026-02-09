import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutterflow_paginate_firestore/paginate_firestore.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/model/inbox_model.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/chat_read_service.dart';
import 'package:foodie_driver/ui/chat_screen/chat_screen.dart';
import 'package:intl/intl.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({Key? key}) : super(key: key);

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  // Cache streams per orderId to avoid recreating on rebuild
  final Map<String, Stream<int>> _unreadCountStreams = {};

  @override
  void dispose() {
    // Clear cache on dispose
    _unreadCountStreams.clear();
    super.dispose();
  }

  /// Get or create cached unread count stream for an order
  Stream<int> _getUnreadCountStream(String orderId, String userId) {
    final cacheKey = '$orderId-$userId';
    if (!_unreadCountStreams.containsKey(cacheKey)) {
      _unreadCountStreams[cacheKey] = ChatReadService.getUnreadCountStream(
        orderId: orderId,
        userId: userId,
      );
    }
    return _unreadCountStreams[cacheKey]!;
  }

  /// Format timestamp for display
  String _formatMessageTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PaginateFirestore(
        //item builder type is compulsory.
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, documentSnapshots, index) {
          final data = documentSnapshots[index].data() as Map<String, dynamic>?;
          InboxModel inboxModel = InboxModel.fromJson(data!);
          return InkWell(
            onTap: () async {
              await showProgress(context, "Please wait", false);

              User? customer = await FireStoreUtils.getCurrentUser(inboxModel.customerId.toString());
              User? driver = await FireStoreUtils.getCurrentUser(inboxModel.restaurantId.toString());
              hideProgress();
              push(
                  context,
                  ChatScreens(
                    customerName: '${customer!.firstName + " " + customer.lastName}',
                    restaurantName: '${driver!.firstName + " " + driver.lastName}',
                    orderId: inboxModel.orderId,
                    restaurantId: driver.userID,
                    customerId: customer.userID,
                    customerProfileImage: customer.profilePictureURL,
                    restaurantProfileImage: driver.profilePictureURL,
                    token: customer.fcmToken,
                    chatType: inboxModel.chatType,
                  ));
            },
            child: StreamBuilder<int>(
              stream: inboxModel.orderId != null && MyAppState.currentUser?.userID != null
                  ? _getUnreadCountStream(
                      inboxModel.orderId!,
                      MyAppState.currentUser!.userID,
                    )
                  : Stream.value(0),
              builder: (context, unreadSnapshot) {
                final unreadCount = unreadSnapshot.data ?? 0;
                final hasUnread = unreadCount > 0;
                
                // Use createdAt from InboxModel instead of querying thread collection
                // createdAt is updated to Timestamp.now() when inbox is updated with new message
                final lastMessageTime = _formatMessageTime(inboxModel.createdAt);

                return Container(
                      color: hasUnread
                          ? (isDarkMode(context)
                              ? Colors.blue.shade900.withValues(alpha: 0.1)
                              : Colors.blue.shade50)
                          : null,
                      child: ListTile(
                        leading: Stack(
                          children: [
                            ClipOval(
                              child: CachedNetworkImage(
                                  width: 50,
                                  height: 50,
                                  imageUrl: inboxModel.customerProfileImage.toString(),
                                  imageBuilder: (context, imageProvider) => Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                            image: DecorationImage(
                                          image: imageProvider,
                                          fit: BoxFit.cover,
                                        )),
                                      ),
                                  errorWidget: (context, url, error) => ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.network(
                                        placeholderImage,
                                        fit: BoxFit.cover,
                                      ))),
                            ),
                            if (hasUnread)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                inboxModel.customerName.toString(),
                                style: TextStyle(
                                  fontWeight: hasUnread
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (lastMessageTime.isNotEmpty)
                              Text(
                                lastMessageTime,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontWeight: hasUnread
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Expanded(
                              child: Text(
                                "Order Id : #${inboxModel.orderId.toString()}",
                                style: TextStyle(
                                  fontWeight: hasUnread
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
              },
            ),
          );
        },
        shrinkWrap: true,
        onEmpty: Center(child: Text("No Conversion found")),
        // orderBy is compulsory to enable pagination
        query: FirebaseFirestore.instance.collection('chat_driver').where("restaurantId", isEqualTo: MyAppState.currentUser!.userID).orderBy('createdAt', descending: true),
        //Change types customerId
        itemBuilderType: PaginateBuilderType.listView,
        initialLoader: CircularProgressIndicator(),
        // to fetch real-time data
        isLive: true,
      ),
    );
  }
}
