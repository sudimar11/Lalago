import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/services/order_communication_service.dart';

class OrderCommunicationScreen extends StatefulWidget {
  const OrderCommunicationScreen({
    super.key,
    required this.orderId,
    required this.riderId,
    required this.vendorId,
    required this.customerId,
  });

  final String orderId;
  final String riderId;
  final String vendorId;
  final String customerId;

  @override
  State<OrderCommunicationScreen> createState() =>
      _OrderCommunicationScreenState();
}

class _OrderCommunicationScreenState extends State<OrderCommunicationScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    OrderCommunicationService.ensureCommunicationDoc(
      orderId: widget.orderId,
      riderId: widget.riderId,
      vendorId: widget.vendorId,
      customerId: widget.customerId,
    );
    OrderCommunicationService.markVisibleMessagesRead(
      orderId: widget.orderId,
      currentUserId: widget.vendorId,
    );
  }

  @override
  void dispose() {
    OrderCommunicationService.setTyping(
      orderId: widget.orderId,
      userId: widget.vendorId,
      isTyping: false,
      role: 'restaurant',
    );
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_controller.text.trim().isEmpty) return;
    await OrderCommunicationService.sendTextMessage(
      orderId: widget.orderId,
      senderId: widget.vendorId,
      receiverId: widget.riderId,
      senderRole: 'restaurant',
      receiverRole: 'rider',
      text: _controller.text.trim(),
    );
    _controller.clear();
  }

  IconData _statusIcon(String? status) {
    if (status == 'read') return Icons.done_all;
    if (status == 'delivered') return Icons.done_all;
    return Icons.check;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order Chat #${widget.orderId}')),
      body: Column(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: OrderCommunicationService.watchTyping(widget.orderId),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final otherTyping = docs.any((doc) {
                final data = doc.data();
                return doc.id != widget.vendorId &&
                    data['isTyping'] == true &&
                    data['role'] == 'rider';
              });
              if (!otherTyping) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Rider is typing...',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              );
            },
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await OrderCommunicationService.markVisibleMessagesRead(
                  orderId: widget.orderId,
                  currentUserId: widget.vendorId,
                );
              },
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: OrderCommunicationService.watchMessages(widget.orderId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const ListView(
                      children: [
                        SizedBox(height: 120),
                        Center(child: Text('No messages yet')),
                      ],
                    );
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final msg = docs[index].data();
                      final mine = msg['senderId'] == widget.vendorId;
                      final createdAt = msg['createdAt'] as Timestamp?;
                      final text = (msg['text'] ?? '').toString();
                      final status = (msg['status'] ?? 'sent').toString();
                      final role = (msg['senderRole'] ?? '').toString();
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: mine
                                ? Color(COLOR_PRIMARY)
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!mine)
                                Text(
                                  role == 'rider' ? 'Rider' : 'System',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              Text(
                                text,
                                style: TextStyle(
                                  color: mine ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    createdAt == null
                                        ? ''
                                        : _hm(createdAt.toDate()),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mine
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      _statusIcon(status),
                                      size: 12,
                                      color: status == 'read'
                                          ? Colors.lightBlueAccent
                                          : Colors.white70,
                                    ),
                                  ],
                                ],
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
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: _controller,
                      onChanged: (value) {
                        OrderCommunicationService.setTyping(
                          orderId: widget.orderId,
                          userId: widget.vendorId,
                          isTyping: value.trim().isNotEmpty,
                          role: 'restaurant',
                        );
                      },
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _hm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

