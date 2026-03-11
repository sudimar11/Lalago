import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/model/OrderModel.dart';
import 'package:foodie_driver/model/OrderProductModel.dart';
import 'package:foodie_driver/constants/quick_messages.dart';
import 'package:foodie_driver/services/eta_service.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/services/order_communication_service.dart';
import 'package:foodie_driver/services/order_location_service.dart';
import 'package:foodie_driver/ui/communication/order_communication_screen.dart';
import 'package:foodie_driver/utils/order_ready_time_helper.dart';
import 'package:image_picker/image_picker.dart';

class PickOrder extends StatefulWidget {
  final OrderModel? currentOrder;

  PickOrder({
    Key? key,
    required this.currentOrder,
  }) : super(key: key);

  @override
  _PickOrderState createState() => _PickOrderState();
}

class _PickOrderState extends State<PickOrder> {
  bool _value = false;
  int val = -1;
  bool _isNearRestaurant = false;
  StreamSubscription<bool>? _proximitySubscription;
  StreamSubscription<DocumentSnapshot>? _orderStatusSubscription;
  StreamSubscription<QuerySnapshot>? _issueStateSubscription;
  Timer? _countdownTimer;
  OrderModel? _orderModel;
  final Map<String, Map<String, dynamic>> _availabilityByProductId = {};
  bool _isAvailabilityLoading = false;
  final Map<String, Map<String, dynamic>> _replacementsByProductId = {};
  final ImagePicker _picker = ImagePicker();
  bool _feedbackPromptShown = false;

  OrderModel get _order => _orderModel ?? widget.currentOrder!;

  bool _isFoodReady() {
    if (_order.status == ORDER_STATUS_SHIPPED) return true;
    final baseTime =
        _order.acceptedAt?.toDate() ?? _order.createdAt.toDate();
    final prepMinutes = OrderReadyTimeHelper.parsePreparationMinutes(
      _order.estimatedTimeToPrepare,
    );
    final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
    return DateTime.now().isAfter(readyAt) ||
        DateTime.now().isAtSameMomentAs(readyAt);
  }

  void _startOrderStatusListener() {
    if (widget.currentOrder == null) return;
    final orderId = widget.currentOrder!.id;
    _orderStatusSubscription = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .doc(orderId)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      try {
        final data = snap.data()!;
        data['id'] = orderId;
        final updated = OrderModel.fromJson(data);
        if (mounted) {
          setState(() => _orderModel = updated);
        }
      } catch (_) {}
    });
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() {});
      if (_isFoodReady()) {
        _countdownTimer?.cancel();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _orderModel = widget.currentOrder;
    _checkProximity();
    _loadAvailability();
    _startOrderStatusListener();
    _bootstrapCommunication();
    _listenForIssueResolutionFeedback();
    if (!_isFoodReady()) {
      _startCountdownTimer();
    }
    _proximitySubscription = OrderLocationService.proximityStream.listen(
      (isNear) {
        if (mounted) {
          setState(() {
            _isNearRestaurant = isNear;
          });
        }
      },
    );
  }

  Future<void> _bootstrapCommunication() async {
    final riderId = MyAppState.currentUser?.userID ?? '';
    if (riderId.isEmpty) return;
    await OrderCommunicationService.ensureCommunicationDoc(
      orderId: _order.id,
      riderId: riderId,
      vendorId: _order.vendorID,
      customerId: _order.authorID,
    );
  }

  @override
  void dispose() {
    _proximitySubscription?.cancel();
    _orderStatusSubscription?.cancel();
    _issueStateSubscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _listenForIssueResolutionFeedback() {
    _issueStateSubscription = FirebaseFirestore.instance
        .collection('order_communications')
        .doc(_order.id)
        .collection('issues')
        .where('state', isEqualTo: 'closed')
        .snapshots()
        .listen((snapshot) async {
      if (!mounted || _feedbackPromptShown || snapshot.docs.isEmpty) return;
      final issueDoc = snapshot.docs.first;
      final data = issueDoc.data();
      final riderFeedback =
          Map<String, dynamic>.from(data['riderFeedback'] ?? {});
      if (riderFeedback.isNotEmpty) return;
      _feedbackPromptShown = true;
      await _showIssueSatisfactionPrompt(issueDoc.id);
    });
  }

  Future<void> _showIssueSatisfactionPrompt(String issueId) async {
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
        .doc(_order.id)
        .collection('issues')
        .doc(issueId)
        .set({
      'riderFeedback': {
        'rating': rating,
        'comment': commentController.text.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _checkProximity() async {
    final driverLocation = MyAppState.currentUser?.location;
    if (driverLocation != null && widget.currentOrder != null) {
      _isNearRestaurant = OrderLocationService.isNearRestaurant(
          _order, driverLocation);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadAvailability() async {
    if (widget.currentOrder == null) return;
    final ids = _order.products
        .map((product) => product.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;

    setState(() {
      _isAvailabilityLoading = true;
    });

    final Map<String, Map<String, dynamic>> next = {};
    for (final id in ids) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('vendor_products')
            .doc(id)
            .get();
        if (doc.exists) {
          final data = doc.data();
          next[id] = {
            'availabilityStatus': data?['availabilityStatus'],
            'unavailableReason': data?['unavailableReason'],
          };
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _availabilityByProductId
        ..clear()
        ..addAll(next);
      _isAvailabilityLoading = false;
    });
  }

  String _readOrderVendorId() {
    if (widget.currentOrder == null) return '';
    final order = _order;
    if (order.vendorID.isNotEmpty) return order.vendorID;
    final vendorId = order.vendor.id;
    return vendorId;
  }

  String _readFoodName(Map<String, dynamic> data) {
    final value = (data['name'] ??
            data['title'] ??
            data['product_name'] ??
            data['productName'] ??
            'Food')
        .toString();
    return value.isEmpty ? 'Food' : value;
  }

  String _readFoodCategoryId(Map<String, dynamic> data) {
    final value = (data['categoryId'] ?? data['category_id'] ?? '').toString();
    return value;
  }

  String _readFoodPhoto(Map<String, dynamic> data) {
    final value = (data['photo'] ??
            data['image'] ??
            data['imageUrl'] ??
            data['thumbnail'] ??
            data['picture'] ??
            '')
        .toString();
    return value;
  }

  Future<List<Map<String, dynamic>>> _loadVendorAvailableFoods(
    String vendorId,
  ) async {
    if (vendorId.isEmpty) return [];
    final collection =
        FirebaseFirestore.instance.collection('vendor_products');

    final queries = [
      collection
          .where('publish', isEqualTo: true)
          .where('vendorId', isEqualTo: vendorId)
          .get(),
      collection
          .where('publish', isEqualTo: true)
          .where('vendorID', isEqualTo: vendorId)
          .get(),
      collection
          .where('publish', isEqualTo: true)
          .where('vendor_id', isEqualTo: vendorId)
          .get(),
    ];

    final results = await Future.wait(queries);
    final Map<String, Map<String, dynamic>> foodsById = {};

    for (final snapshot in results) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        foodsById[doc.id] = {
          'id': doc.id,
          'name': _readFoodName(data),
          'categoryId': _readFoodCategoryId(data),
          'photo': _readFoodPhoto(data),
        };
      }
    }

    return foodsById.values.toList();
  }

  List<Map<String, dynamic>> _buildReplacementCandidates(
    OrderProductModel product,
    List<Map<String, dynamic>> foods,
  ) {
    final categoryId = product.categoryId;
    if (categoryId.isEmpty) {
      return foods;
    }

    final sameCategory = foods
        .where((food) => food['categoryId']?.toString() == categoryId)
        .toList();
    final sameCategoryIds = sameCategory
        .map((food) => food['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final otherFoods = foods
        .where((food) => !sameCategoryIds.contains(food['id']?.toString()))
        .toList();

    return [...sameCategory, ...otherFoods];
  }

  Future<Map<String, dynamic>?> _showReplacementPicker({
    required String title,
    required List<Map<String, dynamic>> candidates,
  }) async {
    if (candidates.isEmpty) return null;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final food = candidates[index];
              return ListTile(
                title: Text(food['name']?.toString() ?? 'Food'),
                onTap: () => Navigator.of(context).pop(food),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _handleReplace(
    OrderProductModel product,
  ) async {
    final vendorId = _readOrderVendorId();
    final foods = await _loadVendorAvailableFoods(vendorId);
    final candidates = _buildReplacementCandidates(product, foods);
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No replacement available')),
      );
      return;
    }

    final selection = await _showReplacementPicker(
      title: product.name,
      candidates: candidates,
    );
    if (selection == null) return;

    final originalId = product.id;
    setState(() {
      product.id = selection['id']?.toString() ?? product.id;
      product.name = selection['name']?.toString() ?? product.name;
      final newCategoryId =
          selection['categoryId']?.toString() ?? product.categoryId;
      product.categoryId = newCategoryId;
      final newPhoto = selection['photo']?.toString() ?? '';
      if (newPhoto.isNotEmpty) {
        product.photo = newPhoto;
      }
      _replacementsByProductId[originalId] = {
        'replacementId': selection['id'],
        'replacementName': selection['name'],
        'vendorId': vendorId,
        'replacedAt': DateTime.now().toIso8601String(),
      };
    });

    await _loadAvailability();
  }

  Widget _buildPreparingView() {
    final baseTime =
        _order.acceptedAt?.toDate() ?? _order.createdAt.toDate();
    final prepMinutes = OrderReadyTimeHelper.parsePreparationMinutes(
      _order.estimatedTimeToPrepare,
    );
    final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
    final now = DateTime.now();
    final remaining = readyAt.difference(now);
    final remainingMinutes = remaining.inMinutes.clamp(0, 999);
    final isReadyNow = remainingMinutes <= 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.grey.shade100, width: 0.1),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 2.0,
                  spreadRadius: 0.4,
                  offset: Offset(0.2, 0.2),
                ),
              ],
              color: isDarkMode(context)
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(
                  Icons.schedule,
                  size: 32,
                  color: Colors.orange.shade700,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Food is being prepared",
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontFamily: "Poppinsm",
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isReadyNow
                          ? "Ready now"
                          : "Ready in ~$remainingMinutes min",
                      style: TextStyle(
                        color: Colors.orange.shade600,
                        fontFamily: "Poppinsr",
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_order.driverID != null &&
              (_order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
                  _order.status == ORDER_STATUS_SHIPPED))
            _buildEtaBanner(),
          if (_order.driverID != null &&
              (_order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
                  _order.status == ORDER_STATUS_SHIPPED))
            const SizedBox(height: 12),
          _buildContactRestaurantPanel(),
          const SizedBox(height: 28),
          Text(
            "${_order.vendor.title}",
            style: TextStyle(
              color: isDarkMode(context) ? Colors.white : Color(0xff333333),
              fontFamily: "Poppinsm",
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Waiting for restaurant to finish preparing your order.",
            style: TextStyle(
              color: isDarkMode(context)
                  ? Colors.grey.shade400
                  : Color(0xff9091A4),
              fontFamily: "Poppinsr",
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMessageButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.message),
      onSelected: (key) => _sendQuickMessage(key),
      itemBuilder: (context) =>
          QuickMessages.getKeys('rider').map((key) {
            final label = QuickMessages.getMessage(key, 'rider');
            return PopupMenuItem<String>(
              value: key,
              child: Text(label),
            );
          }).toList(),
    );
  }

  Future<void> _sendPanelAction({
    required String key,
    required String text,
    required String eventType,
    bool updateArrival = false,
    bool markPickedUp = false,
  }) async {
    final riderId = MyAppState.currentUser?.userID ?? '';
    if (riderId.isEmpty) return;

    if (updateArrival) {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(_order.id)
          .update({
        'restaurantArrivalConfirmed': true,
        'arrivalNotifiedAt': FieldValue.serverTimestamp(),
      });
    }
    if (markPickedUp) {
      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(_order.id)
          .update({
        'status': ORDER_STATUS_IN_TRANSIT,
        'pickedUpAt': FieldValue.serverTimestamp(),
        'restaurantArrivalConfirmed': true,
      });
    }

    await OrderCommunicationService.sendQuickAction(
      orderId: _order.id,
      senderId: riderId,
      receiverId: _order.vendorID,
      senderRole: 'rider',
      receiverRole: 'restaurant',
      actionKey: key,
      actionText: text,
      eventType: eventType,
      eventPayload: {
        'orderId': _order.id,
        'status': markPickedUp ? ORDER_STATUS_IN_TRANSIT : _order.status,
      },
    );

    await FirebaseFirestore.instance
        .collection('order_messages')
        .doc(_order.id)
        .collection('messages')
        .add({
      'senderId': riderId,
      'senderType': 'rider',
      'messageType': 'quick',
      'messageKey': key,
      'messageText': text,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent: $text')),
      );
    }
  }

  Future<void> _openStructuredIssueFlow() async {
    final options = <Map<String, String>>[
      {'key': 'missing_items', 'label': 'Missing Items'},
      {'key': 'restaurant_closed', 'label': 'Restaurant Closed'},
      {'key': 'excessive_wait_time', 'label': 'Excessive Wait Time'},
      {'key': 'order_incorrect', 'label': 'Order Incorrect'},
      {
        'key': 'restaurant_requested_cancellation',
        'label': 'Restaurant Requested Cancellation',
      },
      {'key': 'other', 'label': 'Other'},
    ];
    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: options
              .map(
                (o) => ListTile(
                  leading: const Icon(Icons.report_problem),
                  title: Text(o['label']!),
                  onTap: () => Navigator.pop(context, o),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (selected == null) return;

    final noteController = TextEditingController();
    final waitRanges = ['0-5 min', '5-10 min', '10-20 min', '20+ min'];
    String selectedWait = waitRanges.first;
    XFile? attachment;

    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) {
          return AlertDialog(
            title: Text(selected['label']!),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected['key'] == 'excessive_wait_time')
                  DropdownButtonFormField<String>(
                    value: selectedWait,
                    decoration: const InputDecoration(
                      labelText: 'How long have you been waiting?',
                    ),
                    items: waitRanges
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(v),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setLocalState(() => selectedWait = v);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Add details',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final file = await _picker.pickImage(
                          source: ImageSource.camera,
                        );
                        if (file != null) {
                          setLocalState(() => attachment = file);
                        }
                      },
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('Take Photo'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final file = await _picker.pickImage(
                          source: ImageSource.gallery,
                        );
                        if (file != null) {
                          setLocalState(() => attachment = file);
                        }
                      },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
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

    String? imageUrl;
    if (attachment != null) {
      imageUrl = await FireStoreUtils.uploadPautosReceipt(
        File(attachment!.path),
        _order.id,
      );
    }

    final issueRef = FirebaseFirestore.instance
        .collection('order_communications')
        .doc(_order.id)
        .collection('issues')
        .doc();

    await issueRef.set({
      'issueId': issueRef.id,
      'orderId': _order.id,
      'riderId': MyAppState.currentUser?.userID ?? '',
      'restaurantId': _order.vendorID,
      'issueType': selected['key'],
      'issueLabel': selected['label'],
      'details': noteController.text.trim(),
      'waitTimeRange':
          selected['key'] == 'excessive_wait_time' ? selectedWait : null,
      'attachments': imageUrl == null
          ? <Map<String, dynamic>>[]
          : [
              {'type': 'photo', 'url': imageUrl},
            ],
      'state': 'opened',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await issueRef.collection('transitions').add({
      'from': null,
      'to': 'opened',
      'actorRole': 'rider',
      'actorId': MyAppState.currentUser?.userID ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('pickup_issues').add({
      'orderId': _order.id,
      'riderId': MyAppState.currentUser?.userID ?? '',
      'restaurantId': _order.vendorID,
      'issueType': selected['key'],
      'issueLabel': selected['label'],
      'details': noteController.text.trim(),
      'photoUrl': imageUrl,
      'status': 'opened',
      'reportedAt': FieldValue.serverTimestamp(),
    });

    await _sendPanelAction(
      key: 'issue_reported',
      text: 'Issue reported: ${selected['label']}',
      eventType: 'issue_opened',
    );
  }

  Widget _buildContactRestaurantPanel() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contact Restaurant',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionChip(
                  icon: Icons.storefront,
                  label: 'Arrived',
                  onTap: () => _sendPanelAction(
                    key: 'arrived_at_restaurant',
                    text: 'Driver arrived at restaurant',
                    eventType: 'arrived',
                    updateArrival: true,
                  ),
                ),
                _ActionChip(
                  icon: Icons.hourglass_bottom,
                  label: 'Waiting',
                  onTap: () => _sendPanelAction(
                    key: 'waiting_for_order',
                    text: 'Driver is waiting for order',
                    eventType: 'waiting',
                  ),
                ),
                _ActionChip(
                  icon: Icons.check_circle,
                  label: 'Order Ready?',
                  onTap: () => _sendPanelAction(
                    key: 'is_order_ready',
                    text: 'Is the order ready for pickup?',
                    eventType: 'ready_check',
                  ),
                ),
                _ActionChip(
                  icon: Icons.local_shipping,
                  label: 'Picked Up',
                  onTap: () => _sendPanelAction(
                    key: 'order_picked_up',
                    text: 'Driver picked up the order',
                    eventType: 'picked_up',
                    markPickedUp: true,
                  ),
                ),
                _ActionChip(
                  icon: Icons.report_problem,
                  label: 'Report Issue',
                  onTap: _openStructuredIssueFlow,
                ),
                _ActionChip(
                  icon: Icons.chat_bubble_outline,
                  label: 'Open Chat',
                  onTap: () {
                    push(
                      context,
                      OrderCommunicationScreen(
                        orderId: _order.id,
                        riderId: MyAppState.currentUser?.userID ?? '',
                        vendorId: _order.vendorID,
                        customerId: _order.authorID,
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

  Future<void> _sendQuickMessage(String key) async {
    final message = QuickMessages.getMessage(key, 'rider');
    await FirebaseFirestore.instance
        .collection('order_messages')
        .doc(_order.id)
        .collection('messages')
        .add({
      'senderId': MyAppState.currentUser?.userID ?? '',
      'senderType': 'rider',
      'messageType': 'quick',
      'messageKey': key,
      'messageText': message,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent: $message')),
      );
    }
  }

  Widget _buildReportIssueButton() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.report_problem),
      onSelected: (key) => _reportIssue(key),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'long_wait', child: Text('Long wait')),
        const PopupMenuItem(
          value: 'restaurant_closed',
          child: Text('Restaurant closed'),
        ),
        const PopupMenuItem(value: 'wrong_order', child: Text('Wrong order')),
        const PopupMenuItem(value: 'missing_items', child: Text('Missing items')),
        const PopupMenuItem(value: 'rude_staff', child: Text('Rude staff')),
        const PopupMenuItem(value: 'other', child: Text('Other')),
      ],
    );
  }

  Future<void> _reportIssue(String issueType) async {
    await _openStructuredIssueFlow();
  }

  int? _getRemainingPrepMinutes() {
    final baseTime =
        _order.acceptedAt?.toDate() ?? _order.createdAt.toDate();
    final prepMinutes = OrderReadyTimeHelper.parsePreparationMinutes(
      _order.estimatedTimeToPrepare,
    );
    final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMinutes);
    final remaining = readyAt.difference(DateTime.now()).inMinutes;
    return remaining > 0 ? remaining : null;
  }

  Widget _buildEtaBanner() {
    final riderId = _order.driverID;
    if (riderId == null || riderId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: EtaService.watchEtaMinutes(
        riderId: riderId,
        restaurantLat: _order.vendor.latitude,
        restaurantLng: _order.vendor.longitude,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data! >= 999) {
          return const SizedBox.shrink();
        }
        final eta = snapshot.data!;
        final remainingPrep = _getRemainingPrepMinutes();
        final showWarning = remainingPrep != null && remainingPrep > eta;
        Color bgColor = Colors.green.shade700;
        if (showWarning) bgColor = Colors.orange.shade700;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.timer, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arriving in ~$eta min',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (showWarning)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Food may not be ready when you arrive',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.95),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasUnavailableItems = _order.products.any((product) {
      final status =
          _availabilityByProductId[product.id]?['availabilityStatus']?.toString();
      return status == 'unavailable';
    });
    final canConfirmItems = !hasUnavailableItems;
    final isFoodReady = _isFoodReady();

    if (!isFoodReady) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.chevron_left),
            onPressed: () => Navigator.pop(context),
          ),
          titleSpacing: -8,
          title: Text(
            "Pick: ${_order.id}",
            style: TextStyle(
              color: isDarkMode(context)
                  ? Color(0xffFFFFFF)
                  : Color(0xff000000),
              fontFamily: "Poppinsr",
            ),
          ),
          centerTitle: false,
          actions: [
            _buildQuickMessageButton(),
            _buildReportIssueButton(),
          ],
        ),
        body: _buildPreparingView(),
      );
    }

    return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.chevron_left),
            onPressed: () => Navigator.pop(context),
          ),
          titleSpacing: -8,
          title: Text(
            "Pick: ${_order.id}",
            style: TextStyle(
              color: isDarkMode(context) ? Color(0xffFFFFFF) : Color(0xff000000),
              fontFamily: "Poppinsr",
            ),
          ),
          centerTitle: false,
          actions: [
            _buildQuickMessageButton(),
            _buildReportIssueButton(),
          ],
        ),
        body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.grey.shade100, width: 0.1),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.shade200, blurRadius: 2.0, spreadRadius: 0.4, offset: Offset(0.2, 0.2)),
                  ],
                  color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Image.asset(
                    'assets/images/order3x.png',
                    height: 25,
                    width: 25,
                    color: Color(COLOR_PRIMARY),
                  ),
                  Text(
                    "Order ready, Pick now !",
                    style: TextStyle(
                      color: Color(COLOR_PRIMARY),
                      fontFamily: "Poppinsm",
                    ),
                  )
                ],
              ),
            ),
            if (_order.driverID != null &&
                (_order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
                    _order.status == ORDER_STATUS_SHIPPED))
              _buildEtaBanner(),
            if (_order.driverID != null &&
                (_order.status == ORDER_STATUS_DRIVER_ACCEPTED ||
                    _order.status == ORDER_STATUS_SHIPPED))
              const SizedBox(height: 12),
            _buildContactRestaurantPanel(),
            SizedBox(height: 28),
            Text(
              "ITEMS",
              style: TextStyle(
                color: Color(0xff9091A4),
                fontFamily: "Poppinsm",
              ),
            ),
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isAvailabilityLoading ? null : _loadAvailability,
                icon: _isAvailabilityLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Refresh Menu'),
              ),
            ),
            SizedBox(height: 24),
            ListView.builder(
                shrinkWrap: true,
                itemCount: _order.products.length,
                itemBuilder: (context, index) {
                  final product = widget.currentOrder!.products[index];
                  final availability = _availabilityByProductId[product.id];
                  final status =
                      availability?['availabilityStatus']?.toString() ?? '';
                  final reason =
                      availability?['unavailableReason']?.toString() ?? '';
                  final isUnavailable = status == 'unavailable';
                  return Container(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CachedNetworkImage(
                                height: 55,
                                // width: 50,
                                imageUrl: '${_order.products[index].photo}',
                                imageBuilder: (context, imageProvider) => Container(
                                      decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: imageProvider,
                                            fit: BoxFit.cover,
                                          )),
                                    )),
                          ),
                          Expanded(
                            flex: 10,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${product.name}',
                                    style: TextStyle(
                                        fontFamily: 'Poppinsr',
                                        letterSpacing: 0.5,
                                        color: isDarkMode(context) ? Color(0xffFFFFFF) : Color(0xff333333)),
                                  ),
                                  if (isUnavailable)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            reason.isNotEmpty
                                                ? 'Unavailable - $reason'
                                                : 'Unavailable',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red.shade600,
                                              fontFamily: 'Poppinsr',
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          TextButton(
                                            onPressed: () =>
                                                _handleReplace(product),
                                            child: const Text('Quick Replace'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  SizedBox(height: 5),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.close,
                                        size: 15,
                                        color: Color(COLOR_PRIMARY),
                                      ),
                                      Text('${product.quantity}',
                                          style: TextStyle(
                                            fontFamily: 'Poppinsm',
                                            fontSize: 17,
                                            color: Color(COLOR_PRIMARY),
                                          )),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          )
                        ],
                      ));
                  // Card(
                  //   child: Text(widget.currentOrder!.products[index].name),
                  // );
                }),
            SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey, width: 0.1),
                  // boxShadow: [
                  //   BoxShadow(
                  //       color: Colors.grey.shade200,
                  //       blurRadius: 8.0,
                  //       spreadRadius: 1.2,
                  //       offset: Offset(0.2, 0.2)),
                  // ],
                  color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white),
              child: ListTile(
                onTap: canConfirmItems
                    ? () {
                  setState(() {
                    _value = !_value;
                  });
                  }
                    : null,
                selected: _value,
                leading: _value
                    ? Image.asset(
                        'assets/images/mark_selected3x.png',
                        height: 21,
                        width: 21,
                      )
                    : Image.asset(
                        'assets/images/mark_unselected3x.png',
                        height: 21,
                        width: 21,
                      ),
                title: Text(
                  "Confirm Items",
                  style: TextStyle(
                    color: !canConfirmItems
                        ? Colors.grey
                        : _value
                            ? Color(0xff3DAE7D)
                            : Colors.black,
                    fontFamily: 'Poppinsm',
                  ),
                ),
              ),
            ),
            SizedBox(height: 26),
            Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey, width: 0.1),
                  boxShadow: [
                    BoxShadow(color: Colors.grey.shade200, blurRadius: 2.0, spreadRadius: 0.4, offset: Offset(0.2, 0.2)),
                  ],
                  color: isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, top: 12),
                    child: Text(
                      "DELIVER",
                      style: TextStyle(
                        color: isDarkMode(context) ? Colors.white : Color(0xff9091A4),
                        fontFamily: "Poppinsr",
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text(
                      '${_order.author.fullName()}',
                      style: TextStyle(
                        color: isDarkMode(context) ? Colors.white : Color(0xff333333),
                        fontFamily: "Poppinsm",
                      ),
                    ),
                    subtitle: Text(
                      "${_order.address.getFullAddress()}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDarkMode(context) ? Colors.white : Color(0xff9091A4),
                        fontFamily: "Poppinsr",
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 26),
        child: SizedBox(
          height: 45,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(8),
                ),
              ),
              backgroundColor: (_value == true &&
                      _isNearRestaurant &&
                      canConfirmItems)
                  ? Color(COLOR_PRIMARY)
                  : Color(COLOR_PRIMARY).withOpacity(0.5),
            ),
            child: Text(
              _isNearRestaurant
                  ? "PICKED ORDER"
                  : "Move closer to restaurant (within 50m)",
              style: TextStyle(letterSpacing: 0.5),
            ),
            onPressed: (_value == true && _isNearRestaurant && canConfirmItems)
                ? () async {
                    showProgress(context, 'Updating order...', false);
                    _order.status = ORDER_STATUS_IN_TRANSIT;
                    await FireStoreUtils.updateOrder(_order);
                    hideProgress();
                    setState(() {});
                    Navigator.pop(context);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
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
          borderRadius: BorderRadius.circular(20),
          color: Color(COLOR_PRIMARY).withOpacity(0.1),
          border: Border.all(
            color: Color(COLOR_PRIMARY).withOpacity(0.3),
          ),
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
