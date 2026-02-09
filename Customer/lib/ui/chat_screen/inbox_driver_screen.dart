import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutterflow_paginate_firestore/paginate_firestore.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/model/inbox_model.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/chat_screen/chat_screen.dart';

class InboxDriverScreen extends StatefulWidget {
  const InboxDriverScreen({Key? key}) : super(key: key);

  @override
  State<InboxDriverScreen> createState() => _InboxDriverScreenState();
}

class _InboxDriverScreenState extends State<InboxDriverScreen> {
  bool _isNavigating = false;

  Future<void> _markOrderAsRead(String orderId) async {
    final userId = MyAppState.currentUser?.userID ?? '';
    if (orderId.isEmpty || userId.isEmpty) {
      return;
    }

    try {
      final unreadMessages = await FirebaseFirestore.instance
          .collection('chat_driver')
          .doc(orderId)
          .collection('thread')
          .where('receiverId', isEqualTo: userId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      final now = Timestamp.now();
      for (final doc in unreadMessages.docs) {
        final data = doc.data();
        final readBy = Map<String, dynamic>.from(data['readBy'] ?? {});
        readBy[userId] = now;
        batch.update(doc.reference, {
          'isRead': true,
          'readBy': readBy,
        });
      }

      if (unreadMessages.docs.isNotEmpty) {
        await batch.commit();
      }

      await FirebaseFirestore.instance
          .collection('chat_driver')
          .doc(orderId)
          .update({'unreadCount': 0});
    } catch (e) {
      await _showErrorDialog('Failed to mark messages as read: $e');
    }
  }

  Future<void> _showDeleteDialog(InboxModel inboxModel) async {
    if (inboxModel.orderId == null || inboxModel.orderId!.isEmpty) {
      return;
    }

    final restaurantName = inboxModel.restaurantName?.toString() ?? 'driver';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete conversation?'),
          content: Text(
            'This will delete your messages with $restaurantName for this '
            'order.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await _deleteConversation(inboxModel.orderId!);
    } catch (e) {
      await _showErrorDialog('Failed to delete conversation: $e');
    }
  }

  Future<void> _deleteConversation(String orderId) async {
    final threadQuery = await FirebaseFirestore.instance
        .collection('chat_driver')
        .doc(orderId)
        .collection('thread')
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in threadQuery.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(
      FirebaseFirestore.instance.collection('chat_driver').doc(orderId),
    );

    await batch.commit();
  }

  Future<void> _showErrorDialog(String message) async {
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
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_COLOR) : Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Color(COLOR_PRIMARY),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Driver Messages',
          style: TextStyle(
            fontFamily: "Poppinsm",
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: PaginateFirestore(
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, documentSnapshots, index) {
          final data = documentSnapshots[index].data() as Map<String, dynamic>?;
          InboxModel inboxModel = InboxModel.fromJson(data!);
          return _buildMessageCard(inboxModel);
        },
        shrinkWrap: true,
        onEmpty: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 80,
                color: Colors.grey.withOpacity(0.3),
              ),
              SizedBox(height: 16),
              Text(
                "No conversations found",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontFamily: "Poppinsm",
                ),
              ),
            ],
          ),
        ),
        query: FirebaseFirestore.instance
            .collection('chat_driver')
            .where("customerId", isEqualTo: MyAppState.currentUser!.userID)
            .orderBy('createdAt', descending: true),
        itemBuilderType: PaginateBuilderType.listView,
        initialLoader: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(COLOR_PRIMARY)),
        ),
        isLive: true,
      ),
    );
  }

  Widget _buildMessageCard(InboxModel inboxModel) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode(context)
              ? Colors.grey.withOpacity(0.2)
              : Colors.grey.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDarkMode(context)
                ? Colors.black.withOpacity(0.3)
                : Colors.grey.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (_isNavigating) {
              return;
            }
            _isNavigating = true;
            final orderId = inboxModel.orderId ?? '';
            if (orderId.isNotEmpty) {
              await _markOrderAsRead(orderId);
            }
            User? customer = await FireStoreUtils.getCurrentUser(
                inboxModel.customerId.toString());
            User? restaurantUser = await FireStoreUtils.getCurrentUser(
                inboxModel.restaurantId.toString());
            hideProgress();
            try {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatScreens(
                    customerName:
                        '${customer!.firstName + " " + customer.lastName}',
                    restaurantName:
                        '${restaurantUser!.firstName + " " + restaurantUser.lastName}',
                    orderId: inboxModel.orderId,
                    restaurantId: restaurantUser.userID,
                    customerId: customer.userID,
                    customerProfileImage: customer.profilePictureURL,
                    restaurantProfileImage: restaurantUser.profilePictureURL,
                    token: restaurantUser.fcmToken,
                    chatType: inboxModel.chatType,
                  ),
                ),
              );
            } finally {
              if (mounted) {
                _isNavigating = false;
              }
            }
          },
          onLongPress: () => _showDeleteDialog(inboxModel),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Color(COLOR_PRIMARY).withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      width: 60,
                      height: 60,
                      imageUrl: inboxModel.restaurantProfileImage.toString(),
                      imageBuilder: (context, imageProvider) => Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: imageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      placeholder: (context, url) => Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey.shade200,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(COLOR_PRIMARY)),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.network(
                          AppGlobal.placeHolderImage!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              inboxModel.restaurantName.toString(),
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode(context)
                                    ? Colors.white
                                    : Colors.black,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if ((inboxModel.unreadCount ?? 0) > 0)
                            Container(
                              margin: EdgeInsets.only(left: 8),
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                (inboxModel.unreadCount ?? 0) > 99
                                    ? '99+'
                                    : '${inboxModel.unreadCount}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Color(COLOR_PRIMARY).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "Order #${inboxModel.orderId}",
                              style: TextStyle(
                                fontFamily: "Poppinsm",
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(COLOR_PRIMARY),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d, yyyy').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                  inboxModel.createdAt!.millisecondsSinceEpoch),
                            ),
                            style: TextStyle(
                              fontFamily: "Poppinsm",
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if ((inboxModel.unreadCount ?? 0) > 0)
                  Container(
                    margin: EdgeInsets.only(right: 8),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
