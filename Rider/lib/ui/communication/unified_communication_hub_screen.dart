import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/model/inbox_model.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/chat_read_service.dart';
import 'package:foodie_driver/services/group_chat_service.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/unified_inbox_service.dart';
import 'package:foodie_driver/ui/chat_screen/admin_driver_chat_screen.dart';
import 'package:foodie_driver/ui/chat_screen/chat_screen.dart';
import 'package:foodie_driver/ui/communication/order_communication_screen.dart';
import 'package:foodie_driver/ui/group_chat/GroupChatScreen.dart';
import 'package:intl/intl.dart';

enum UnifiedCommunicationTab {
  customers,
  restaurants,
  support,
  community,
}

class UnifiedCommunicationHubScreen extends StatefulWidget {
  const UnifiedCommunicationHubScreen({
    super.key,
    this.initialTab = UnifiedCommunicationTab.customers,
    this.initialOrderId,
    this.autoOpenConversation = false,
  });

  final UnifiedCommunicationTab initialTab;
  final String? initialOrderId;
  final bool autoOpenConversation;

  @override
  State<UnifiedCommunicationHubScreen> createState() =>
      _UnifiedCommunicationHubScreenState();
}

class _UnifiedCommunicationHubScreenState
    extends State<UnifiedCommunicationHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _openedInitialConversation = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: UnifiedCommunicationTab.values.length,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoOpenConversation();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _maybeAutoOpenConversation() async {
    if (!widget.autoOpenConversation || _openedInitialConversation) return;
    final orderId = (widget.initialOrderId ?? '').trim();
    if (orderId.isEmpty || !mounted) return;
    _openedInitialConversation = true;

    switch (widget.initialTab) {
      case UnifiedCommunicationTab.customers:
        await _openCustomerChatByOrder(orderId);
        break;
      case UnifiedCommunicationTab.restaurants:
        await _openRestaurantChatByOrder(orderId);
        break;
      case UnifiedCommunicationTab.support:
        _openSupportChat(orderId);
        break;
      case UnifiedCommunicationTab.community:
        _openCommunityChat();
        break;
    }
  }

  Future<void> _openCustomerChatByOrder(String orderId) async {
    final snap = await FirebaseFirestore.instance
        .collection('chat_driver')
        .doc(orderId)
        .get();
    if (!mounted || !snap.exists) return;
    final data = snap.data() ?? {};
    final inbox = InboxModel.fromJson(data);
    final customerId = (inbox.customerId ?? '').trim();
    final riderId = MyAppState.currentUser?.userID ?? '';
    if (customerId.isEmpty || riderId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreens(
          orderId: orderId,
          customerId: customerId,
          customerName: inbox.customerName ?? 'Customer',
          customerProfileImage: inbox.customerProfileImage ?? '',
          restaurantId: riderId,
          restaurantName: MyAppState.currentUser?.fullName() ?? 'Rider',
          restaurantProfileImage:
              MyAppState.currentUser?.profilePictureURL ?? '',
          chatType: 'Driver',
        ),
      ),
    );
  }

  Future<void> _openRestaurantChatByOrder(String orderId) async {
    final snap = await FirebaseFirestore.instance
        .collection('restaurant_orders')
        .doc(orderId)
        .get();
    if (!mounted || !snap.exists) return;
    final data = snap.data() ?? {};
    final riderId =
        (data['driverID'] ?? data['driverId'] ?? '').toString().trim();
    final vendorId = (data['vendorID'] ?? '').toString().trim();
    final customerId =
        (data['authorID'] ?? data['authorId'] ?? '').toString().trim();
    if (riderId.isEmpty || vendorId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderCommunicationScreen(
          orderId: orderId,
          riderId: riderId,
          vendorId: vendorId,
          customerId: customerId,
        ),
      ),
    );
  }

  void _openSupportChat(String orderId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDriverChatScreen(orderId: orderId),
      ),
    );
  }

  void _openCommunityChat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GroupChatScreen(),
      ),
    );
  }

  String _formatTs(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final dt = ts.toDate();
    if (now.difference(dt).inDays == 0) {
      return DateFormat('HH:mm').format(dt);
    }
    return DateFormat('MMM dd, HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final rider = MyAppState.currentUser;
    final riderId = rider?.userID ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor:
            isDarkMode(context) ? Colors.black : Colors.blueGrey.shade900,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Customers'),
            Tab(text: 'Restaurants'),
            Tab(text: 'Support'),
            Tab(text: 'Community'),
          ],
        ),
      ),
      body: riderId.isEmpty
          ? const Center(child: Text('Driver not signed in.'))
          : TabBarView(
              controller: _tabController,
              children: [
                _CustomersTab(
                  riderId: riderId,
                  formatTs: _formatTs,
                ),
                _RestaurantsTab(
                  riderId: riderId,
                  formatTs: _formatTs,
                ),
                _SupportTab(
                  riderId: riderId,
                  formatTs: _formatTs,
                ),
                const _CommunityTab(),
              ],
            ),
    );
  }
}

class _CustomersTab extends StatelessWidget {
  const _CustomersTab({
    required this.riderId,
    required this.formatTs,
  });

  final String riderId;
  final String Function(Timestamp?) formatTs;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chat_driver')
          .where('restaurantId', isEqualTo: riderId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No customer conversations yet.'),
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final inbox = InboxModel.fromJson(data);
            final orderId =
                (inbox.orderId ?? docs[index].id).toString();
            final customerId = (inbox.customerId ?? '').trim();
            return StreamBuilder<int>(
              stream: ChatReadService.getUnreadCountStream(
                orderId: orderId,
                userId: riderId,
              ),
              builder: (context, unreadSnap) {
                final unread = unreadSnap.data ?? 0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade700,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(inbox.customerName ?? 'Customer'),
                  subtitle: Text(
                    inbox.lastMessage?.isNotEmpty == true
                        ? inbox.lastMessage!
                        : 'Open conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatTs(inbox.createdAt),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    if (customerId.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreens(
                          orderId: orderId,
                          customerId: customerId,
                          customerName: inbox.customerName ?? 'Customer',
                          customerProfileImage:
                              inbox.customerProfileImage ?? '',
                          restaurantId: riderId,
                          restaurantName:
                              MyAppState.currentUser?.fullName() ?? 'Rider',
                          restaurantProfileImage:
                              MyAppState.currentUser?.profilePictureURL ?? '',
                          chatType: 'Driver',
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RestaurantsTab extends StatelessWidget {
  const _RestaurantsTab({
    required this.riderId,
    required this.formatTs,
  });

  final String riderId;
  final String Function(Timestamp?) formatTs;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('order_communications')
          .where('participants.riderId', isEqualTo: riderId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = [...(snapshot.data?.docs ?? [])];
        docs.sort((a, b) {
          final aTs = (a.data()['lastMessageAt'] ??
                  a.data()['updatedAt']) as Timestamp?;
          final bTs = (b.data()['lastMessageAt'] ??
                  b.data()['updatedAt']) as Timestamp?;
          final aMillis = aTs?.millisecondsSinceEpoch ?? 0;
          final bMillis = bTs?.millisecondsSinceEpoch ?? 0;
          return bMillis.compareTo(aMillis);
        });
        if (docs.isEmpty) {
          return const Center(
            child: Text('No restaurant conversations yet.'),
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final orderId = docs[index].id;
            final participants =
                Map<String, dynamic>.from(data['participants'] ?? {});
            final vendorId = (participants['vendorId'] ?? '').toString();
            final customerId =
                (participants['customerId'] ?? '').toString();
            final updatedAt = (data['lastMessageAt'] ??
                data['updatedAt']) as Timestamp?;
            return StreamBuilder<int>(
              stream: UnifiedInboxService.watchRestaurantUnreadForOrder(
                orderId,
                riderId,
              ),
              builder: (context, unreadSnap) {
                final unread = unreadSnap.data ?? 0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(COLOR_PRIMARY),
                    child: const Icon(Icons.store, color: Colors.white),
                  ),
                  title: Text('Order #${orderId.substring(0, 6)}'),
                  subtitle: const Text(
                    'Restaurant communication',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatTs(updatedAt),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    if (vendorId.isEmpty) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderCommunicationScreen(
                          orderId: orderId,
                          riderId: riderId,
                          vendorId: vendorId,
                          customerId: customerId,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SupportTab extends StatelessWidget {
  const _SupportTab({
    required this.riderId,
    required this.formatTs,
  });

  final String riderId;
  final String Function(Timestamp?) formatTs;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chat_admin_driver')
          .where('driverId', isEqualTo: riderId)
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No support conversations yet.'),
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final orderId = docs[index].id;
            final raw = data['unreadForDriver'];
            final unread = raw is num
                ? raw.toInt()
                : int.tryParse(raw?.toString() ?? '') ?? 0;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blueGrey.shade700,
                child: const Icon(Icons.support_agent, color: Colors.white),
              ),
              title: Text('Order: $orderId'),
              subtitle: Text(
                (data['lastMessage'] ?? 'Open support thread').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatTs(data['updatedAt'] as Timestamp?),
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (unread > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminDriverChatScreen(orderId: orderId),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CommunityTab extends StatelessWidget {
  const _CommunityTab();

  String _formatTs(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return DateFormat('MMM dd, HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const GroupChatScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.group),
              label: const Text('Open Rider Community Chat'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection(GROUP_CHAT)
                .where('deleted', isEqualTo: false)
                .orderBy('timestamp', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No community messages yet.'),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final sender = (data['senderName'] ?? 'Rider').toString();
                  final text = (data['message'] ?? '').toString();
                  final hasImage =
                      (data['imageUrl'] ?? '').toString().isNotEmpty;
                  final preview = hasImage
                      ? '[Image]'
                      : (text.isNotEmpty ? text : 'Open community thread');
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.people),
                    ),
                    title: Text(sender),
                    subtitle: Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _formatTs(data['timestamp'] as Timestamp?),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const GroupChatScreen(),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
