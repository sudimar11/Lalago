import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/constants/quick_messages.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/model/OrderProductModel.dart';
import 'package:foodie_restaurant/model/TaxModel.dart';
import 'package:foodie_restaurant/model/variant_info.dart';
import 'package:foodie_restaurant/services/eta_service.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/services/order_communication_service.dart';
import 'package:foodie_restaurant/ui/communication/order_communication_screen.dart';
import 'package:foodie_restaurant/utils/order_ready_time_helper.dart';
import 'package:foodie_restaurant/ui/ordersScreen/print.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class OrderDetailsScreen extends StatefulWidget {
  final OrderModel orderModel;

  const OrderDetailsScreen({Key? key, required this.orderModel})
      : super(key: key);

  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  FireStoreUtils fireStoreUtils = FireStoreUtils();

  double total = 0.0;

  double adminComm = 0.0;

  double specialDiscount = 0.0;

  double discount = 0.0;

  var tipAmount = "0.0";

  List<Map<String, dynamic>> _internalNotes = [];
  bool _feedbackPromptShown = false;

  @override
  void initState() {
    super.initState();

    // 1. Sum up product prices + extras
    total = 0.0;
    for (final element in widget.orderModel.products) {
      if (element.extrasPrice != null &&
          element.extrasPrice!.isNotEmpty &&
          double.tryParse(element.extrasPrice!) != null) {
        total += element.quantity * double.parse(element.extrasPrice!);
      }
      total += element.quantity * double.parse(element.price);
    }

    // 2. Calculate discounts
    discount = double.tryParse(widget.orderModel.discount.toString()) ?? 0.0;
    specialDiscount = 0.0;
    if (widget.orderModel.specialDiscount != null &&
        widget.orderModel.specialDiscount!['special_discount'] != null) {
      specialDiscount = double.tryParse(
        widget.orderModel.specialDiscount!['special_discount'].toString(),
      )!;
    }

    // 3. Total after discounts
    final double totalAmount = total - discount - specialDiscount;

    // 4. Count total items
    final int totalQty = widget.orderModel.products
        .fold<int>(0, (sum, item) => sum + item.quantity);

    // 5. Compute admin commission
    if (widget.orderModel.adminCommissionType == 'Percent') {
      adminComm =
          (totalAmount * double.parse(widget.orderModel.adminCommission!)) /
              100;
    } else {
      // fixed fee per item
      adminComm = double.parse(widget.orderModel.adminCommission!) * totalQty;
    }

    // 6. Deduct commission
    total = totalAmount - adminComm;
    _internalNotes = List<Map<String, dynamic>>.from(
      widget.orderModel.internalNotes ?? [],
    );
    _bootstrapCommunication();
  }

  Future<void> _bootstrapCommunication() async {
    final riderId = widget.orderModel.driverID ?? '';
    if (riderId.isEmpty) return;
    await OrderCommunicationService.ensureCommunicationDoc(
      orderId: widget.orderModel.id,
      riderId: riderId,
      vendorId: widget.orderModel.vendorID,
      customerId: widget.orderModel.authorID,
    );
    _listenForClosedIssueFeedback();
  }

  void _listenForClosedIssueFeedback() {
    FirebaseFirestore.instance
        .collection('order_communications')
        .doc(widget.orderModel.id)
        .collection('issues')
        .where('state', isEqualTo: 'closed')
        .snapshots()
        .listen((snapshot) async {
      if (!mounted || _feedbackPromptShown || snapshot.docs.isEmpty) return;
      final issueDoc = snapshot.docs.first;
      final data = issueDoc.data();
      final feedback =
          Map<String, dynamic>.from(data['restaurantFeedback'] ?? {});
      if (feedback.isNotEmpty) return;
      _feedbackPromptShown = true;
      await _showRestaurantSatisfactionPrompt(issueDoc.id);
    });
  }

  Future<void> _showRestaurantSatisfactionPrompt(String issueId) async {
    int rating = 5;
    final commentController = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          return AlertDialog(
            title: const Text('Issue Resolution Feedback'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('How satisfied were you with this issue handling?'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                    (index) => IconButton(
                      onPressed: () => setLocalState(() => rating = index + 1),
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                ),
                TextField(
                  controller: commentController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Optional comment',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
    if (submit != true) return;
    await FirebaseFirestore.instance
        .collection('order_communications')
        .doc(widget.orderModel.id)
        .collection('issues')
        .doc(issueId)
        .set({
      'restaurantFeedback': {
        'rating': rating,
        'comment': commentController.text.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _addInternalNote() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Internal Note'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter note...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty && mounted) {
      await FireStoreUtils.addOrderNote(widget.orderModel.id, controller.text.trim());
      final updated = await FireStoreUtils.getOrderById(widget.orderModel.id);
      if (mounted && updated != null) {
        setState(() => _internalNotes = List.from(updated.internalNotes ?? []));
      }
    }
  }

  Future<void> _editInternalNote(String noteId, String currentNote) async {
    final controller = TextEditingController(text: currentNote);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Internal Note'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter note...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      await FireStoreUtils.updateOrderInternalNote(
        widget.orderModel.id,
        noteId,
        controller.text.trim(),
      );
      final updated = await FireStoreUtils.getOrderById(widget.orderModel.id);
      if (mounted && updated != null) {
        setState(() => _internalNotes = List.from(updated.internalNotes ?? []));
      }
    }
  }

  Widget _buildInternalNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Internal Notes',
              style: TextStyle(
                fontFamily: 'Poppinsm',
                fontSize: 17,
                letterSpacing: 0.5,
                color: isDarkMode(context)
                    ? Colors.grey.shade300
                    : const Color(0xff9091A4),
              ),
            ),
            TextButton.icon(
              onPressed: _addInternalNote,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Note'),
            ),
          ],
        ),
        if (_internalNotes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No internal notes',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          )
        else
          ..._internalNotes.map((n) {
            final id = n['id'] as String? ?? '';
            final note = n['note'] as String? ?? '';
            final createdAt = n['createdAt'];
            String dateStr = '';
            if (createdAt != null && createdAt is Timestamp) {
              dateStr = '${createdAt.toDate().toIso8601String().substring(0, 16)}';
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ),
                        if (dateStr.isNotEmpty)
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _editInternalNote(id, note),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? const Color(DARK_CARD_BG_COLOR) : Colors.white,
      appBar: AppBar(
          title: Text(
        "Order Summary",
        style: TextStyle(
            fontFamily: 'Poppinsr',
            letterSpacing: 0.5,
            fontWeight: FontWeight.bold,
            color: isDarkMode(context)
                ? Colors.grey.shade200
                : const Color(0xff333333)),
      )),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildOrderSummaryCard(widget.orderModel),
            if (widget.orderModel.driverID != null &&
                (widget.orderModel.status == ORDER_STATUS_DRIVER_ACCEPTED ||
                    widget.orderModel.status == ORDER_STATUS_SHIPPED))
              _buildRiderEtaCard(widget.orderModel),
            if (widget.orderModel.driverID != null &&
                (widget.orderModel.status == ORDER_STATUS_DRIVER_ACCEPTED ||
                    widget.orderModel.status == ORDER_STATUS_SHIPPED))
              _buildOrderMessagesCard(widget.orderModel),
            if (widget.orderModel.driverID != null)
              _buildCommunicationPanel(),
            _buildIssueResolutionPanel(),
            Card(
              color: isDarkMode(context)
                  ? const Color(DARK_CARD_BG_COLOR)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Admin commission",
                          ),
                        ),
                        Text(
                          "(-${amountShow(amount: adminComm.toString())})",
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      "Note: Admin commission is already deducted from your total orders. \nAdmin commission will apply on order Amount minus Discount & Special Discount (if applicable).",
                      style: TextStyle(color: Colors.red),
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiderEtaCard(OrderModel orderModel) {
    final riderId = orderModel.driverID!;
    return StreamBuilder<int>(
      stream: EtaService.watchEtaMinutes(
        riderId: riderId,
        restaurantLat: orderModel.vendor.latitude,
        restaurantLng: orderModel.vendor.longitude,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data! >= 999) {
          return const SizedBox.shrink();
        }
        final eta = snapshot.data!;
        final baseTime =
            orderModel.acceptedAt?.toDate() ?? orderModel.createdAt.toDate();
        final prepMinutes =
            OrderReadyTimeHelper.parsePreparationMinutes(
                orderModel.estimatedTimeToPrepare);
        final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
        final remainingPrep = readyAt.difference(DateTime.now()).inMinutes;
        final showWarning = remainingPrep > 0 && remainingPrep > eta;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.delivery_dining, color: Color(COLOR_PRIMARY)),
                    const SizedBox(width: 8),
                    Text(
                      'Rider ETA: ~$eta min',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDarkMode(context)
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
                if (showWarning)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Food may not be ready when rider arrives',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendRestaurantAction({
    required String actionKey,
    required String actionText,
    required String eventType,
    bool markReady = false,
    bool confirmPickup = false,
  }) async {
    final vendorUserId = MyAppState.currentUser?.userID ?? '';
    final riderId = widget.orderModel.driverID ?? '';
    if (vendorUserId.isEmpty || riderId.isEmpty) return;

    if (markReady) {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(widget.orderModel.id)
          .update({
        'status': ORDER_STATUS_SHIPPED,
        'shippedAt': FieldValue.serverTimestamp(),
      });
    }
    if (confirmPickup) {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(widget.orderModel.id)
          .update({
        'status': ORDER_STATUS_IN_TRANSIT,
        'pickedUpAt': FieldValue.serverTimestamp(),
      });
    }

    final legacyRef = FirebaseFirestore.instance
        .collection('order_messages')
        .doc(widget.orderModel.id)
        .collection('messages')
        .doc();
    await legacyRef.set({
      'senderId': vendorUserId,
      'senderType': 'restaurant',
      'messageType': 'quick',
      'messageKey': actionKey,
      'messageText': actionText,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await OrderCommunicationService.sendQuickAction(
      orderId: widget.orderModel.id,
      senderId: vendorUserId,
      receiverId: riderId,
      senderRole: 'restaurant',
      receiverRole: 'rider',
      actionKey: actionKey,
      actionText: actionText,
      eventType: eventType,
      eventPayload: {
        'orderId': widget.orderModel.id,
        'status': confirmPickup
            ? ORDER_STATUS_IN_TRANSIT
            : (markReady ? ORDER_STATUS_SHIPPED : widget.orderModel.status),
      },
      legacyMessageId: legacyRef.id,
    );
  }

  Widget _buildCommunicationPanel() {
    final riderId = widget.orderModel.driverID ?? '';
    if (riderId.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Driver Communication',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  OrderCommunicationService.watchEvents(widget.orderModel.id),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Text(
                    'No driver actions yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  );
                }
                return Column(
                  children: docs.take(5).map((doc) {
                    final data = doc.data();
                    final eventType =
                        (data['eventType'] ?? 'update').toString();
                    final actorRole =
                        (data['actorRole'] ?? '').toString();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        actorRole == 'rider'
                            ? Icons.local_shipping
                            : Icons.storefront,
                        size: 18,
                      ),
                      title: Text(eventType.replaceAll('_', ' ')),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RestaurantActionChip(
                  icon: Icons.check_circle,
                  label: 'Order Ready',
                  onTap: () => _sendRestaurantAction(
                    actionKey: 'order_ready',
                    actionText: 'Order is ready for pickup',
                    eventType: 'ready',
                    markReady: true,
                  ),
                ),
                _RestaurantActionChip(
                  icon: Icons.inventory_2,
                  label: 'Confirm Pickup',
                  onTap: () => _sendRestaurantAction(
                    actionKey: 'confirm_pickup',
                    actionText: 'Restaurant confirmed pickup',
                    eventType: 'pickup_confirmed',
                    confirmPickup: true,
                  ),
                ),
                _RestaurantActionChip(
                  icon: Icons.chat_bubble_outline,
                  label: 'Open Chat',
                  onTap: () {
                    push(
                      context,
                      OrderCommunicationScreen(
                        orderId: widget.orderModel.id,
                        riderId: riderId,
                        vendorId: widget.orderModel.vendorID,
                        customerId: widget.orderModel.authorID,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _transitionIssueState({
    required String issueId,
    required String currentState,
    required String nextState,
    String? resolutionAction,
  }) async {
    await FirebaseFirestore.instance
        .collection('order_communications')
        .doc(widget.orderModel.id)
        .collection('issues')
        .doc(issueId)
        .set({
      'state': nextState,
      'lastActorRole': 'restaurant',
      'lastActorId': MyAppState.currentUser?.userID ?? '',
      'resolutionAction': resolutionAction,
      'updatedAt': FieldValue.serverTimestamp(),
      if (nextState == 'resolved') 'resolvedAt': FieldValue.serverTimestamp(),
      if (nextState == 'confirmed') 'confirmedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Widget _buildIssueResolutionPanel() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('order_communications')
          .doc(widget.orderModel.id)
          .collection('issues')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.report_problem, color: Colors.orange),
                    SizedBox(width: 6),
                    Text(
                      'Issue Resolution',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...docs.take(3).map((doc) {
                  final d = doc.data();
                  final issueId = doc.id;
                  final state = (d['state'] ?? 'opened').toString();
                  final label =
                      (d['issueLabel'] ?? d['issueType'] ?? 'Issue').toString();
                  final details = (d['details'] ?? '').toString();
                  final attachments =
                      List<Map<String, dynamic>>.from(d['attachments'] ?? []);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$label (${state.toUpperCase()})',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(details),
                        ],
                        if (attachments.isNotEmpty &&
                            (attachments.first['url'] ?? '').toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(
                                attachments.first['url'].toString(),
                                height: 80,
                                width: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (state == 'opened')
                              OutlinedButton(
                                onPressed: () => _transitionIssueState(
                                  issueId: issueId,
                                  currentState: state,
                                  nextState: 'acknowledged',
                                ),
                                child: const Text('Acknowledge'),
                              ),
                            if (state == 'acknowledged' || state == 'opened')
                              ElevatedButton(
                                onPressed: () => _transitionIssueState(
                                  issueId: issueId,
                                  currentState: state,
                                  nextState: 'resolved',
                                  resolutionAction: 'items_added',
                                ),
                                child: const Text('Items Added'),
                              ),
                            if (state == 'acknowledged' || state == 'opened')
                              ElevatedButton(
                                onPressed: () => _transitionIssueState(
                                  issueId: issueId,
                                  currentState: state,
                                  nextState: 'resolved',
                                  resolutionAction: 'order_replaced',
                                ),
                                child: const Text('Order Replaced'),
                              ),
                            if (state == 'acknowledged' || state == 'opened')
                              ElevatedButton(
                                onPressed: () => _transitionIssueState(
                                  issueId: issueId,
                                  currentState: state,
                                  nextState: 'resolved',
                                  resolutionAction: 'refund_issued',
                                ),
                                child: const Text('Refund Issued'),
                              ),
                            if (state != 'closed' && state != 'escalated')
                              OutlinedButton(
                                onPressed: () => _transitionIssueState(
                                  issueId: issueId,
                                  currentState: state,
                                  nextState: 'escalated',
                                ),
                                child: const Text('Escalate'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderMessagesCard(OrderModel orderModel) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Messages',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showQuickReplyDialog(orderModel.id),
                  icon: const Icon(Icons.reply, size: 18),
                  label: const Text('Quick Reply'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('order_messages')
                  .doc(orderModel.id)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Text(
                    'No messages yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  );
                }
                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final isRider = d['senderType'] == 'rider';
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isRider ? Icons.delivery_dining : Icons.restaurant,
                        size: 20,
                      ),
                      title: Text(d['messageText']?.toString() ?? ''),
                      subtitle: d['createdAt'] != null
                          ? Text(
                              _formatTimestamp(d['createdAt']),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            )
                          : null,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is Map && ts['_seconds'] != null) {
      dt = DateTime.fromMillisecondsSinceEpoch(
          (ts['_seconds'] as int) * 1000);
    } else {
      return '';
    }
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showQuickReplyDialog(String orderId) async {
    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: QuickMessages.getKeys('restaurant').map((k) {
            return ListTile(
              title: Text(QuickMessages.getMessage(k, 'restaurant')),
              onTap: () => Navigator.pop(context, k),
            );
          }).toList(),
        ),
      ),
    );
    if (key != null && mounted) {
      final message = QuickMessages.getMessage(key, 'restaurant');
      final uid = MyAppState.currentUser?.userID;
      final riderId = widget.orderModel.driverID ?? '';
      final legacyRef = FirebaseFirestore.instance
          .collection('order_messages')
          .doc(orderId)
          .collection('messages')
          .doc();
      await legacyRef.set({
        'senderId': uid ?? '',
        'senderType': 'restaurant',
        'messageType': 'quick',
        'messageKey': key,
        'messageText': message,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (riderId.isNotEmpty && uid != null && uid.isNotEmpty) {
        await OrderCommunicationService.sendQuickAction(
          orderId: orderId,
          senderId: uid,
          receiverId: riderId,
          senderRole: 'restaurant',
          receiverRole: 'rider',
          actionKey: key,
          actionText: message,
          eventType: 'quick_message',
          eventPayload: {'orderId': orderId, 'messageKey': key},
          legacyMessageId: legacyRef.id,
        );
      }
    }
  }

  Widget buildOrderSummaryCard(OrderModel orderModel) {
    print("order status ${widget.orderModel.id}");

    // Default specialDiscount to empty map when null
    final Map<String, dynamic> specialDiscount =
        widget.orderModel.specialDiscount ?? {};

    // Default taxModel to empty list when null
    final List<TaxModel> taxModel = widget.orderModel.taxModel ?? [];

    double specialDiscountAmount = 0.0;

    String taxAmount = "0.0";

    // Compute specialDiscountAmount only if the map contains a special_discount key
    if (specialDiscount.isNotEmpty &&
        specialDiscount.containsKey('special_discount')) {
      specialDiscountAmount =
          double.tryParse(specialDiscount['special_discount'].toString()) ??
              0.0;
    }

    // Iterate over the safe taxes list instead of force-unwrapping
    for (var element in taxModel) {
      taxAmount = (double.parse(taxAmount) +
              calculateTax(
                  amount: (total - discount - specialDiscountAmount).toString(),
                  taxModel: element))
          .toString();
    }

    var totalamount =
        total + double.parse(taxAmount) - discount - specialDiscountAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        color: isDarkMode(context)
            ? const Color(DARK_CARD_BG_COLOR)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 15,
              ),
              ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: widget.orderModel.products.length,
                  itemBuilder: (context, index) {
                    VariantInfo? variantIno =
                        widget.orderModel.products[index].variantInfo;

                    List<dynamic>? addon =
                        widget.orderModel.products[index].extras;

                    String extrasDisVal = '';

                    for (int i = 0; i < addon!.length; i++) {
                      extrasDisVal +=
                          '${addon[i].toString().replaceAll("\"", "")} ${(i == addon.length - 1) ? "" : ","}';
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CachedNetworkImage(
                                height: 55,
                                width: 55,

                                // width: 50,

                                imageUrl:
                                    widget.orderModel.products[index].photo,
                                imageBuilder: (context, imageProvider) =>
                                    Container(
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: imageProvider,
                                            fit: BoxFit.cover,
                                          )),
                                    ),
                                errorWidget: (context, url, error) => ClipRRect(
                                    borderRadius: BorderRadius.circular(15),
                                    child: Image.network(
                                      placeholderImage,
                                      fit: BoxFit.cover,
                                      width: MediaQuery.of(context).size.width,
                                      height:
                                          MediaQuery.of(context).size.height,
                                    ))),
                            Padding(
                              padding: const EdgeInsets.only(left: 10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        widget.orderModel.products[index].name,
                                        style: TextStyle(
                                            fontFamily: 'Poppinsr',
                                            fontSize: 14,
                                            letterSpacing: 0.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode(context)
                                                ? Colors.grey.shade200
                                                : const Color(0xff333333)),
                                      ),
                                      Text(
                                        ' x ${widget.orderModel.products[index].quantity}',
                                        style: TextStyle(
                                            fontFamily: 'Poppinsr',
                                            letterSpacing: 0.5,
                                            color: isDarkMode(context)
                                                ? Colors.grey.shade200
                                                : Colors.black
                                                    .withValues(alpha: 0.60)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  getPriceTotalText(
                                      widget.orderModel.products[index]),
                                ],
                              ),
                            )
                          ],
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        variantIno == null || variantIno.variantOptions!.isEmpty
                            ? Container()
                            : Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                child: Wrap(
                                  spacing: 6.0,
                                  runSpacing: 6.0,
                                  children: List.generate(
                                    variantIno.variantOptions!.length,
                                    (i) {
                                      return _buildChip(
                                          "${variantIno.variantOptions!.keys.elementAt(i)} : ${variantIno.variantOptions![variantIno.variantOptions!.keys.elementAt(i)]}",
                                          i);
                                    },
                                  ).toList(),
                                ),
                              ),
                        const SizedBox(
                          height: 5,
                        ),
                        Container(
                          margin: const EdgeInsets.only(left: 5, right: 10),
                          child: extrasDisVal.isEmpty
                              ? Container()
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    extrasDisVal,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                        fontFamily: 'Poppinsr'),
                                  ),
                                ),
                        ),
                      ],
                    );
                  }),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                title: Text(
                  'Subtotal',
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff9091A4),
                  ),
                ),
                trailing: Text(
                  amountShow(amount: total.toString()),
                  style: TextStyle(
                    fontFamily: 'Poppinssm',
                    letterSpacing: 0.5,
                    fontSize: 16,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff333333),
                  ),
                ),
              ),
              Visibility(
                visible: orderModel.vendor.specialDiscountEnable &&
                    specialDiscount.isNotEmpty,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                  title: Text(
                    'Special Discount' +
                        "(${specialDiscount['special_discount_label'] ?? ''}${specialDiscount['specialType'] == "amount" ? currencyModel!.symbol : "%"})",
                    style: TextStyle(
                      fontFamily: 'Poppinsm',
                      fontSize: 16,
                      letterSpacing: 0.5,
                      color: isDarkMode(context)
                          ? Colors.grey.shade300
                          : const Color(0xff9091A4),
                    ),
                  ),
                  trailing: Text(
                    "(-${amountShow(amount: specialDiscountAmount.toString())})",
                    style: TextStyle(
                        fontFamily: 'Poppinssm',
                        letterSpacing: 0.5,
                        fontSize: 16,
                        color: Colors.red),
                  ),
                ),
              ),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                title: Text(
                  'Discount',
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff9091A4),
                  ),
                ),
                trailing: Text(
                  "(-${amountShow(amount: discount.toString())})",
                  style: TextStyle(
                      fontFamily: 'Poppinssm',
                      letterSpacing: 0.5,
                      fontSize: 16,
                      color: Colors.red),
                ),
              ),
              ListView.builder(
                itemCount: taxModel.length,
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  TaxModel currentTaxModel = taxModel[index];

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    title: Text(
                      '${currentTaxModel.title.toString()} (${currentTaxModel.type == "fix" ? amountShow(amount: currentTaxModel.tax) : "${currentTaxModel.tax}%"})',
                      style: TextStyle(
                        fontFamily: 'Poppinsm',
                        fontSize: 16,
                        letterSpacing: 0.5,
                        color: isDarkMode(context)
                            ? Colors.grey.shade300
                            : const Color(0xff9091A4),
                      ),
                    ),
                    trailing: Text(
                      amountShow(
                          amount: calculateTax(
                                  amount: (double.parse(total.toString()) -
                                          discount -
                                          specialDiscountAmount)
                                      .toString(),
                                  taxModel: currentTaxModel)
                              .toString()),
                      style: TextStyle(
                        fontFamily: 'Poppinssm',
                        letterSpacing: 0.5,
                        fontSize: 16,
                        color: isDarkMode(context)
                            ? Colors.grey.shade300
                            : const Color(0xff333333),
                      ),
                    ),
                  );
                },
              ),
              (widget.orderModel.notes != null &&
                      widget.orderModel.notes!.isNotEmpty)
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 0),
                      title: Text(
                        "Customer Notes",
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 17,
                          letterSpacing: 0.5,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff9091A4),
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          widget.orderModel.notes!,
                          style: TextStyle(
                            fontFamily: 'Poppinsm',
                            fontSize: 14,
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: widget.orderModel.notes!),
                              );
                            },
                          ),
                          InkWell(
                            onTap: () {
                              showModalBottomSheet(
                                isScrollControlled: true,
                                isDismissible: true,
                                context: context,
                                backgroundColor: Colors.transparent,
                                enableDrag: true,
                                builder: (ctx) =>
                                    viewNotesheet(widget.orderModel.notes!),
                              );
                            },
                            child: Text(
                              "View",
                              style: TextStyle(
                                fontSize: 18,
                                color: Color(COLOR_PRIMARY),
                                letterSpacing: 0.5,
                                fontFamily: 'Poppinsm',
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(),
              _buildInternalNotesSection(),
              widget.orderModel.couponCode!.trim().isNotEmpty
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 0),
                      title: Text(
                        'Coupon Code',
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 16,
                          letterSpacing: 0.5,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff9091A4),
                        ),
                      ),
                      trailing: Text(
                        widget.orderModel.couponCode!,
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          letterSpacing: 0.5,
                          fontSize: 16,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff333333),
                        ),
                      ),
                    )
                  : Container(),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                title: Text(
                  'Order Total',
                  style: TextStyle(
                    fontFamily: 'Poppinsm',
                    letterSpacing: 0.5,
                  ),
                ),
                trailing: Text(
                  amountShow(amount: totalamount.toString()),
                  style: TextStyle(
                    fontFamily: 'Poppinssm',
                    letterSpacing: 0.5,
                    fontSize: 22,
                    color: Color(COLOR_PRIMARY),
                  ),
                ),
              ),
              //ElevatedButton(
              //  onPressed: () {
              //    Navigator.push(
              //      context,
              //      MaterialPageRoute(
              //          builder: (context) => BluetoothPrinterPage()),
              //    );
              //  },
              //  child: const Text("Go to Bluetooth Printer"),
              //),
              Visibility(
                visible: orderModel.status != ORDER_STATUS_DRIVER_REJECTED,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: InkWell(
                    child: Container(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        decoration: BoxDecoration(
                            color: Color(COLOR_PRIMARY),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                                width: 0.8, color: Color(COLOR_PRIMARY))),
                        child: Center(
                          child: Text(
                            'Print Invoice',
                            style: TextStyle(
                                color: isDarkMode(context)
                                    ? const Color(0xffFFFFFF)
                                    : Colors.white,
                                fontFamily: "Poppinsm",
                                fontSize: 15

                                // fontWeight: FontWeight.bold,

                                ),
                          ),
                        )),
                    onTap: () {
                      printTicket();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> printTicket() async {
    String? isConnected =
        await PrintBluetoothThermal.connectionStatus.toString();

    if (isConnected == "true") {
      List<int> bytes = await getTicket();
      final String? result =
          await PrintBluetoothThermal.writeBytes(bytes).toString();

      if (result == "true") {
        showAlertDialog(
            context, "Success", "Invoice printed successfully.", true);
      } else {
        showAlertDialog(
            context, "Error", "Failed to print the invoice.", false);
      }
    } else {
      showAlertDialog(context, "Not Connected",
          "Please connect to a printer first.", false);
      getBluetooth();
    }
  }

  String taxAmount = "0.0";
  Future<List<int>> getTicket() async {
    List<int> bytes = [];
    CapabilityProfile profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);

    bytes += generator.text("Invoice",
        styles: const PosStyles(align: PosAlign.center, bold: true),
        linesAfter: 1);

    bytes += generator.text(widget.orderModel.vendor.title,
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.text('Tel: ${widget.orderModel.vendor.phonenumber}',
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.hr();

    for (var product in widget.orderModel.products) {
      bytes += generator.text(
        "Item: ${product.name} x ${product.quantity}",
        styles: const PosStyles(align: PosAlign.left),
      );
      bytes += generator.text("Price: ${product.price}",
          styles: const PosStyles(align: PosAlign.left));
    }

    bytes += generator.hr();

    bytes += generator.text("Thank you!",
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.cut();

    return bytes;
  }

  List availableBluetoothDevices = [];

  Future<void> getBluetooth() async {
    try {
      final List? bluetooths = await PrintBluetoothThermal.pairedBluetooths;

      if (bluetooths == null || bluetooths.isEmpty) {
        showAlertDialog(
          context,
          "No Devices Found",
          "No paired Bluetooth devices were found. Please pair your printer in the Bluetooth settings.",
          false,
        );
        return;
      }

      print("Paired devices: $bluetooths");

      setState(() {
        availableBluetoothDevices = bluetooths;
      });

      showLoadingAlert();
    } catch (e) {
      print("Error fetching Bluetooth devices: $e");

      showAlertDialog(
        context,
        "Error",
        "Failed to retrieve Bluetooth devices. Please try again.",
        false,
      );
    }
  }

  void showLoadingAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connect Bluetooth Device'),
          content: SizedBox(
            width: double.maxFinite,
            child: availableBluetoothDevices.isEmpty
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text("Searching for devices..."),
                      const SizedBox(height: 8),
                      const Text(
                        "If no devices are found, please pair your printer in Bluetooth settings.",
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : ListView.builder(
                    itemCount: availableBluetoothDevices.length,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      String select = availableBluetoothDevices[index];
                      List<String> deviceInfo = select.split("#");
                      String deviceName = deviceInfo[0];
                      String mac = deviceInfo[1];

                      return ListTile(
                        onTap: () {
                          setConnect(mac);
                          Navigator.pop(context);
                        },
                        title: Text(deviceName.isNotEmpty
                            ? deviceName
                            : "Unknown Device"),
                        subtitle: Text("MAC: $mac"),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  Future<void> setConnect(String mac) async {
    try {
      final bool result =
          await PrintBluetoothThermal.connect(macPrinterAddress: mac);

      if (result == "true") {
        print("Connected to device: $mac");
        showAlertDialog(context, "Success", "Connected to the printer.", true);
      } else {
        showAlertDialog(
            context, "Failed", "Could not connect to the printer.", false);
      }
    } catch (e) {
      print("Error connecting to printer: $e");
      showAlertDialog(
          context, "Error", "An error occurred while connecting.", false);
    }
  }

  getPriceTotalText(OrderProductModel s) {
    double total = 0.0;

    if (s.extrasPrice != null &&
        s.extrasPrice!.isNotEmpty &&
        double.parse(s.extrasPrice!) != 0.0) {
      total += s.quantity * double.parse(s.extrasPrice!);
    }

    total += s.quantity * double.parse(s.price);

    return Text(
      amountShow(amount: total.toString()),
      style: TextStyle(
        fontSize: 15,
      ),
    );
  }

  viewNotesheet(String notes) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height / 4.3,
          left: 25,
          right: 25),
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(style: BorderStyle.none)),
      child: Column(
        children: [
          InkWell(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 45,

                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 0.3),
                    color: Colors.transparent,
                    shape: BoxShape.circle),

                // radius: 20,

                child: const Center(
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              )),
          const SizedBox(
            height: 25,
          ),
          Expanded(
              child: Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDarkMode(context)
                    ? const Color(0XFF2A2A2A)
                    : Colors.white),
            alignment: Alignment.center,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'Remark',
                        style: TextStyle(
                            fontFamily: 'Poppinssb',
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black,
                            fontSize: 16),
                      )),
                  Container(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, top: 20),

                    // height: 120,

                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      child: Container(
                        padding: const EdgeInsets.only(
                            left: 20, right: 20, top: 20, bottom: 20),

                        color: isDarkMode(context)
                            ? const Color(DARK_CARD_BG_COLOR)
                            : const Color(0XFFF1F4F7),

                        // height: 120,

                        alignment: Alignment.center,

                        child: Text(
                          notes,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDarkMode(context)
                                ? Colors.white70
                                : Colors.black,
                            fontFamily: 'Poppinsm',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )),
        ],
      ),
    );
  }
}

Widget _buildChip(String label, int attributesOptionIndex) {
  return Container(
    decoration: BoxDecoration(
        color: const Color(0xffEEEDED), borderRadius: BorderRadius.circular(4)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
        ),
      ),
    ),
  );
}

class _RestaurantActionChip extends StatelessWidget {
  const _RestaurantActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Color(COLOR_PRIMARY).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Color(COLOR_PRIMARY).withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Color(COLOR_PRIMARY)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Color(COLOR_PRIMARY),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
