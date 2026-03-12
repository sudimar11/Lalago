import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:foodie_restaurant/constants.dart';
import 'package:foodie_restaurant/main.dart';
import 'package:foodie_restaurant/model/OrderModel.dart';
import 'package:foodie_restaurant/model/User.dart';
import 'package:foodie_restaurant/services/FirebaseHelper.dart';
import 'package:foodie_restaurant/services/acceptance_metrics_service.dart';
import 'package:foodie_restaurant/services/eta_service.dart';
import 'package:foodie_restaurant/services/helper.dart';
import 'package:foodie_restaurant/ui/ordersScreen/OrderDetailsScreen.dart';
import 'package:foodie_restaurant/utils/order_ready_time_helper.dart';

Future<Map<String, String?>> fetchDriverDetails(String driverID) async {
  try {
    final driverDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(driverID)
        .get();
    if (driverDoc.exists) {
      final d = driverDoc.data();
      return {
        "driverName":
            "${d?['firstName'] ?? 'Unknown'} ${d?['lastName'] ?? ''}",
        "driverPhone": d?['phoneNumber'] ?? 'No phone number',
        "driverPhoto": d?['profilePictureURL'] ?? '',
      };
    }
    return {"driverName": "Driver not found", "driverPhone": null, "driverPhoto": null};
  } catch (e) {
    return {"driverName": "Error", "driverPhone": null, "driverPhoto": null};
  }
}

Future<Map<String, String?>> assignOrderToDriver(
    BuildContext context, OrderModel orderModel) async {
  try {
    await FirebaseFirestore.instance
        .collection("restaurant_orders")
        .doc(orderModel.id)
        .update({
      "status": "Order Accepted",
      "dispatch.lock": false,
      "dispatch.lastRetriggerAt": FieldValue.serverTimestamp(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order queued for automatic rider dispatch.'),
          backgroundColor: Colors.green,
        ),
      );
    }
    return {};
  } catch (e, st) {
    print("Error in assignOrderToDriver: $e\n$st");
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to assign order to driver: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return {};
  }
}

Future<double> calculateTotalAndDeductCommission(OrderModel orderModel) async {
  double total = 0.0;
  try {
    for (final e in orderModel.products) {
      if (e.extrasPrice != null &&
          e.extrasPrice!.isNotEmpty &&
          double.tryParse(e.extrasPrice!) != null) {
        total += e.quantity * double.parse(e.extrasPrice!);
      }
      total += e.quantity * double.parse(e.price);
    }
  } catch (_) {}
  final discount = double.tryParse(orderModel.discount?.toString() ?? '0') ?? 0;
  final specialDisc = double.tryParse(
          orderModel.specialDiscount?['special_discount']?.toString() ?? '0') ??
      0;
  final totalAfterDiscount = total - discount - specialDisc;
  final totalQty =
      orderModel.products.fold<int>(0, (sum, item) => sum + item.quantity);
  double adminComm = 0.0;
  try {
    final ct = orderModel.adminCommissionType;
    final cv = orderModel.adminCommission;
    if (ct != null && cv != null) {
      if (ct == 'Percent') {
        adminComm = (totalAfterDiscount * double.parse(cv)) / 100;
      } else {
        adminComm = double.parse(cv) * totalQty;
      }
    }
  } catch (_) {}
  return totalAfterDiscount - adminComm;
}

class OrderUtils {
  static Widget buildOrderItem(
    BuildContext context,
    OrderModel orderModel,
    int index,
    OrderModel? prevModel, {
    bool showActions = false,
    AudioPlayer? audioPlayer,
    VoidCallback? onStopSound,
    VoidCallback? onStartSound,
    String? selectedTime,
    ValueChanged<String?>? onSelectedTimeChanged,
    void Function(User)? onCustomerTap,
  }) {
    final date = DateFormat('MMM d yyyy').format(
        DateTime.fromMillisecondsSinceEpoch(
            orderModel.createdAt.millisecondsSinceEpoch));
    final date2 = prevModel != null
        ? DateFormat('MMM d yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(
                prevModel.createdAt.millisecondsSinceEpoch))
        : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (index == 0 || (prevModel != null && date != date2))
          Container(
            height: 40,
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: isDarkMode(context)
                  ? Color(DARK_CARD_BG_COLOR)
                  : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              date,
              style: TextStyle(
                fontSize: 16,
                fontFamily: 'Poppinsm',
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
          ),
        InkWell(
          onTap: () async {
            await audioPlayer?.stop();
            push(context, OrderDetailsScreen(orderModel: orderModel));
          },
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 3,
            color:
                isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: _buildOrderContent(
              context,
              orderModel,
              showActions: showActions,
              audioPlayer: audioPlayer,
              onStopSound: onStopSound ?? () {},
              onStartSound: onStartSound ?? () {},
              selectedTime: selectedTime,
              onSelectedTimeChanged: onSelectedTimeChanged ?? (_) {},
              onCustomerTap: onCustomerTap,
            ),
          ),
        ),
      ],
    );
  }

  static Widget _buildOrderContent(
    BuildContext context,
    OrderModel orderModel, {
    required bool showActions,
    AudioPlayer? audioPlayer,
    required VoidCallback onStopSound,
    required VoidCallback onStartSound,
    String? selectedTime,
    required ValueChanged<String?> onSelectedTimeChanged,
    void Function(User)? onCustomerTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showActions) _buildArrivalIndicator(context, orderModel),
          Row(
            children: [
              if (orderModel.products.isNotEmpty)
                Container(
                  width: 60,
                  height: 60,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(orderModel.products.first.photo),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: onCustomerTap != null
                                ? () => onCustomerTap!(orderModel.author)
                                : null,
                            child: Text(
                              '${orderModel.author.firstName} ${orderModel.author.lastName}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode(context)
                                    ? Colors.white
                                    : Colors.black,
                                decoration: onCustomerTap != null
                                    ? TextDecoration.underline
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        if (orderModel.notes != null &&
                            orderModel.notes!.isNotEmpty)
                          Tooltip(
                            message: orderModel.notes!.length > 50
                                ? '${orderModel.notes!.substring(0, 50)}...'
                                : orderModel.notes!,
                            child: Icon(
                              Icons.note,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orderModel.takeAway == true
                          ? 'Takeaway'
                          : 'Deliver to: ${orderModel.address.getFullAddress()}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          FutureBuilder<double>(
            future: calculateTotalAndDeductCommission(orderModel),
            builder: (ctx, snap) {
              if (!snap.hasData) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Order Total', style: TextStyle(color: Colors.grey)),
                  trailing: snap.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : Text('Error', style: TextStyle(color: Colors.red)),
                );
              }
              final net = snap.data ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Order Total', style: TextStyle(color: Colors.grey)),
                trailing: Text(
                  '\₱${net.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Color(COLOR_PRIMARY),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 24),
          _buildRiderSection(context, orderModel, showActions),
          if (showActions &&
              orderModel.driverID != null &&
              (orderModel.status == ORDER_STATUS_DRIVER_ACCEPTED ||
                  orderModel.status == ORDER_STATUS_SHIPPED)) ...[
            _buildRiderEtaCard(context, orderModel),
            const Divider(height: 24),
          ],
          if (orderModel.notes != null && orderModel.notes!.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Remarks', style: TextStyle(color: Colors.grey)),
              subtitle: Text(
                orderModel.notes!,
                style: TextStyle(
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
            ),
          if (showActions) ...[
            const SizedBox(height: 8),
            _buildOrderActions(
              context,
              orderModel,
              onStopSound: onStopSound,
              onStartSound: onStartSound,
              selectedTime: selectedTime,
              onSelectedTimeChanged: onSelectedTimeChanged,
            ),
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Status', style: TextStyle(color: Colors.grey)),
              subtitle: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(orderModel.status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getStatusText(orderModel.status),
                  style: TextStyle(
                    color: _getStatusTextColor(orderModel.status),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _buildArrivalIndicator(BuildContext context, OrderModel o) {
    if (o.driverID == null ||
        (o.status != ORDER_STATUS_DRIVER_ACCEPTED &&
            o.status != ORDER_STATUS_SHIPPED)) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<int>(
      stream: EtaService.watchEtaMinutes(
        riderId: o.driverID!,
        restaurantLat: o.vendor.latitude,
        restaurantLng: o.vendor.longitude,
      ),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data! > 5 || snap.data! >= 999) {
          return const SizedBox.shrink();
        }
        final eta = snap.data!;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: eta <= 2 ? Colors.red : Colors.orange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            eta <= 2 ? 'Rider arriving NOW' : 'Rider arriving in $eta min',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  static Widget _buildRiderSection(
      BuildContext context, OrderModel orderModel, bool showActions) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection("restaurant_orders")
          .doc(orderModel.id)
          .get(),
      builder: (ctx, snap) {
        if (!snap.hasData || !(snap.data?.exists ?? false)) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Driver Selected', style: TextStyle(color: Colors.grey)),
            subtitle: Text(
              'No driver assigned',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
          );
        }
        final driverID =
            (snap.data?.data() as Map<String, dynamic>?)?['driverID'] as String?;
        if (driverID == null) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Driver Selected', style: TextStyle(color: Colors.grey)),
            subtitle: Text(
              'No driver assigned',
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode(context) ? Colors.white : Colors.black,
              ),
            ),
          );
        }
        return FutureBuilder<Map<String, String?>>(
          future: fetchDriverDetails(driverID),
          builder: (ctx2, driverSnap) {
            final d = driverSnap.data;
            final name = d?["driverName"] ?? "Unknown";
            final phone = d?["driverPhone"] ?? "No phone number";
            final photo = d?["driverPhoto"];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Driver Selected', style: TextStyle(color: Colors.grey)),
              subtitle: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 16,
                          color:
                              isDarkMode(context) ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(phone, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                  if (showActions)
                    IconButton(
                      icon: const Icon(Icons.call, color: Colors.green),
                      onPressed: () async {
                        if (phone.isEmpty || phone == "No phone number") return;
                        final uri = Uri(scheme: 'tel', path: phone.trim());
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                ],
              ),
              trailing: CircleAvatar(
                backgroundImage:
                    photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                radius: 30,
                child: photo == null || photo.isEmpty
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildRiderEtaCard(BuildContext context, OrderModel o) {
    return StreamBuilder<int>(
      stream: EtaService.watchEtaMinutes(
        riderId: o.driverID!,
        restaurantLat: o.vendor.latitude,
        restaurantLng: o.vendor.longitude,
      ),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data! >= 999) return const SizedBox.shrink();
        final eta = snap.data!;
        final baseTime =
            o.acceptedAt?.toDate() ?? o.createdAt.toDate();
        final prepMin =
            OrderReadyTimeHelper.parsePreparationMinutes(o.estimatedTimeToPrepare);
        final readyAt = OrderReadyTimeHelper.getReadyAt(baseTime, prepMin);
        final remainingPrep = readyAt.difference(DateTime.now()).inMinutes;
        final showWarn = remainingPrep > 0 && remainingPrep > eta;
        return Card(
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
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                if (showWarn)
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

  static Widget _buildOrderActions(
    BuildContext context,
    OrderModel o, {
    required VoidCallback onStopSound,
    required VoidCallback onStartSound,
    String? selectedTime,
    required ValueChanged<String?> onSelectedTimeChanged,
  }) {
    if (o.status == "Order Rejected") {
      return const Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text("Order Rejected",
                style: TextStyle(
                    fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }
    if (o.status == "Driver Rejected") {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order has been rejected by driver',
              style: TextStyle(
                  fontSize: 14, color: Colors.red, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => assignOrderToDriver(context, o),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Find Another Driver', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }
    if (o.status == "Order Placed") {
      onStartSound();
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => _acceptOrder(context, o, onSelectedTimeChanged),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Accept', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _rejectOrder(context, o),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Reject', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      );
    }
    if (o.status == "Order Accepted") {
      onStopSound();
      return _loadingChip('Waiting for driver assignment...');
    }
    if (o.status == "Driver Assigned") {
      onStopSound();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Driver Assigned - Waiting for Acceptance',
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.green,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _loadingChip('Waiting for driver to accept...'),
        ],
      );
    }
    if (o.status == "Driver Accepted") {
      onStopSound();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Driver Accepted - Preparation in Progress',
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.green,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _PreparationTimerWidget(
            orderId: o.id,
            orderModel: o,
            onShipOrder: () => _shipOrder(context, o),
            acceptedAt: o.acceptedAt?.toDate(),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  static Widget _loadingChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        ],
      ),
    );
  }

  static Color _getStatusColor(String s) {
    switch (s) {
      case "In Transit":
        return Colors.blue.shade100;
      case ORDER_STATUS_COMPLETED:
        return Colors.green.shade100;
      case "Order Shipped":
        return Colors.orange.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  static String _getStatusText(String s) {
    switch (s) {
      case "In Transit":
        return "In Transit";
      case ORDER_STATUS_COMPLETED:
        return "Completed";
      case "Order Shipped":
        return "Shipped";
      default:
        return s;
    }
  }

  static Color _getStatusTextColor(String s) {
    switch (s) {
      case "In Transit":
        return Colors.blue.shade800;
      case ORDER_STATUS_COMPLETED:
        return Colors.green.shade800;
      case "Order Shipped":
        return Colors.orange.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  static Future<void> _acceptOrder(
    BuildContext context,
    OrderModel o,
    ValueChanged<String?> onSelectedTimeChanged,
  ) async {
    String? sel;
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setState) {
            return AlertDialog(
              title: const Text('Select Preparation Time'),
              content: DropdownButton<String>(
                value: sel,
                hint: const Text('Choose time'),
                items: ["0:5", "0:10", "0:20", "0:30", "0:40", "0:50", "1:00", "1:30", "2:00"]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => sel = v),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (sel != null) Navigator.pop(ctx, sel);
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
    if (t == null || t.isEmpty) return;
    final prepMin = OrderReadyTimeHelper.parsePreparationMinutes(t);
    final now = DateTime.now();
    final readyAt = now.add(Duration(minutes: prepMin));
    await FirebaseFirestore.instance.collection("restaurant_orders").doc(o.id).update({
      "status": "Order Accepted",
      "estimatedTimeToPrepare": t,
      "acceptedAt": FieldValue.serverTimestamp(),
      "readyAt": Timestamp.fromDate(readyAt),
      "prepMinutes": prepMin,
    });
    final vid = MyAppState.currentUser?.vendorID;
    if (vid != null) {
      AcceptanceMetricsService.resetConsecutiveMisses(vid);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order accepted! Tap "Find Nearest Driver" next.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  static const _rejectionOptions = [
    {'label': 'Out of stock', 'value': 'out_of_stock'},
    {'label': 'Item not available', 'value': 'item_not_available'},
    {'label': 'Restaurant closed', 'value': 'restaurant_closed'},
    {'label': 'Too busy', 'value': 'too_busy'},
    {'label': 'Distance too far', 'value': 'distance_too_far'},
    {'label': 'Technical issues', 'value': 'technical_issues'},
    {'label': 'Other', 'value': 'other'},
  ];

  static Future<void> _rejectOrder(BuildContext context, OrderModel o) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Order'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _rejectionOptions
                .map((opt) => ListTile(
                      title: Text(opt['label']!),
                      onTap: () => Navigator.pop(ctx, opt['value']),
                    ))
                .toList(),
          ),
        ),
      ),
    );
    if (reason == null) return;
    String selectedReason = reason;
    if (reason == 'other') {
      final ctrl = TextEditingController();
      final custom = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Other Reason'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'Enter reason',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final t = ctrl.text.trim();
                Navigator.pop(ctx, t.isNotEmpty ? t : 'other');
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      );
      if (custom == null) return;
      selectedReason = custom;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Order'),
        content: const Text('Are you sure you want to reject this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('REJECT'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await FirebaseFirestore.instance.collection("restaurant_orders").doc(o.id).update({
      'status': ORDER_STATUS_REJECTED,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectionReason': selectedReason,
    });
    final vid = MyAppState.currentUser?.vendorID;
    if (vid != null) AcceptanceMetricsService.incrementConsecutiveMisses(vid);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order rejected'), backgroundColor: Colors.red),
      );
    }
  }

  static Future<void> _shipOrder(BuildContext context, OrderModel o) async {
    try {
      await FirebaseFirestore.instance.collection('restaurant_orders').doc(o.id).update({
        'status': 'Order Shipped',
        'shippedAt': FieldValue.serverTimestamp(),
      });
      await FireStoreUtils.addDriverChatSystemMessage(
        orderId: o.id,
        status: 'Order Shipped',
        customerId: o.author.userID,
        customerFcmToken: o.author.fcmToken,
        restaurantId: o.vendorID,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order marked as ready for pickup'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update order status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _PreparationTimerWidget extends StatefulWidget {
  final String orderId;
  final OrderModel orderModel;
  final VoidCallback onShipOrder;
  final DateTime? acceptedAt;

  const _PreparationTimerWidget({
    required this.orderId,
    required this.orderModel,
    required this.onShipOrder,
    this.acceptedAt,
  });

  @override
  State<_PreparationTimerWidget> createState() => _PreparationTimerWidgetState();
}

class _PreparationTimerWidgetState extends State<_PreparationTimerWidget> {
  Timer? _timer;
  DateTime? _acceptedTime;
  bool _hasAlarmed = false;
  bool _hasExceededAlarm = false;
  AudioPlayer? _exceededAlarmPlayer;

  @override
  void initState() {
    super.initState();
    _acceptedTime = widget.acceptedAt ??
        widget.orderModel.acceptedAt?.toDate() ??
        widget.orderModel.createdAt.toDate();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _checkAlarm();
        _checkExceeded();
      }
    });
  }

  void _checkAlarm() {
    if (_hasAlarmed) return;
    final rem = _getRemainingMinutes();
    if (rem <= 3 && rem > 0) {
      _hasAlarmed = true;
      _triggerAlarm();
    }
  }

  void _checkExceeded() {
    if (_getRemainingMinutes() <= 0 && !_hasExceededAlarm) {
      _hasExceededAlarm = true;
      _triggerExceededAlarm();
    }
  }

  Future<void> _triggerAlarm() async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order will be ready in ~3 minutes. Mark as ready now!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      final bytes = await rootBundle.load(
          'assets/audio/mixkit-happy-bells-notification-937.mp3');
      final ap = AudioPlayer(playerId: "alarm_${widget.orderId}");
      await ap.play(BytesSource(bytes.buffer.asUint8List()));
      Timer(const Duration(seconds: 10), () {
        ap.stop();
        ap.dispose();
      });
    } catch (_) {}
  }

  Future<void> _triggerExceededAlarm() async {
    try {
      _exceededAlarmPlayer =
          AudioPlayer(playerId: "exceeded_${widget.orderId}");
      final bytes = await rootBundle.load(
          'assets/audio/mixkit-happy-bells-notification-937.mp3');
      final data = bytes.buffer.asUint8List();
      await _exceededAlarmPlayer!.play(BytesSource(data));
      _exceededAlarmPlayer!.onPlayerComplete.listen((_) {
        if (_hasExceededAlarm && mounted) {
          _exceededAlarmPlayer!.play(BytesSource(data));
        }
      });
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showExceededDialog();
      });
    } catch (_) {}
  }

  void _showExceededDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Order Ready?'),
        content: const Text(
          'The preparation time has passed. Is the order ready for pickup?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopExceeded();
            },
            child: const Text('NOT YET'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _stopExceeded();
              widget.onShipOrder();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('YES, MARK READY'),
          ),
        ],
      ),
    );
  }

  void _stopExceeded() {
    _exceededAlarmPlayer?.stop();
    _exceededAlarmPlayer?.dispose();
    _exceededAlarmPlayer = null;
    _hasExceededAlarm = false;
  }

  int _getRemainingMinutes() {
    if (_acceptedTime == null) return 0;
    final total = OrderReadyTimeHelper.parsePreparationMinutes(
        widget.orderModel.estimatedTimeToPrepare);
    final elapsed =
        DateTime.now().difference(_acceptedTime!).inMinutes;
    final rem = total - elapsed;
    return rem > 0 ? rem : 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopExceeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rem = _getRemainingMinutes();
    final elapsed = _acceptedTime != null
        ? '${DateTime.now().difference(_acceptedTime!).inMinutes.toString().padLeft(2, '0')}:${(DateTime.now().difference(_acceptedTime!).inSeconds % 60).toString().padLeft(2, '0')}'
        : '00:00';
    final isWarn = rem <= 3 && rem > 0;
    final isExceeded = rem <= 0;
    final color = isExceeded ? Colors.red : (isWarn ? Colors.orange : Colors.green);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isExceeded ? Icons.error : (isWarn ? Icons.warning : Icons.timer),
                color: isExceeded ? Colors.red : (isWarn ? Colors.red : Colors.blue.shade700),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                elapsed,
                style: TextStyle(
                  color: isExceeded ? Colors.red : (isWarn ? Colors.red : Colors.blue.shade700),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Elapsed Time', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            isExceeded ? 'Time exceeded' : '${rem}min remaining',
            style: TextStyle(
              color: isExceeded ? Colors.red : (isWarn ? Colors.red : Colors.orange.shade700),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              _stopExceeded();
              widget.onShipOrder();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text('Mark as Ready', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
