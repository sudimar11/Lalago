import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/ui/chat_screen/admin_driver_chat_screen.dart';
import 'package:intl/intl.dart';

class AdminDriverInboxScreen extends StatelessWidget {
  const AdminDriverInboxScreen({super.key});

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return DateFormat('MMM dd, HH:mm').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final driverId = MyAppState.currentUser?.userID ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Messages'),
      ),
      body: driverId.isEmpty
          ? const Center(child: Text('Driver not signed in.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chat_admin_driver')
                  .where('driverId', isEqualTo: driverId)
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('No admin messages yet.'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final orderId = doc.id;
                    final lastMessage =
                        data['lastMessage']?.toString() ?? '';
                    final updatedAt = data['updatedAt'] as Timestamp?;
                    final unread = data['unreadForDriver'];
                    final unreadCount = unread is num
                        ? unread.toInt()
                        : int.tryParse(unread?.toString() ?? '') ?? 0;

                    return ListTile(
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.blueGrey,
                            child: Icon(Icons.support_agent, color: Colors.white),
                          ),
                          if (unreadCount > 0)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
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
                      title: Text(
                        'Order: $orderId',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        lastMessage.isEmpty ? '—' : lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        _formatTime(updatedAt),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
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
            ),
    );
  }
}

