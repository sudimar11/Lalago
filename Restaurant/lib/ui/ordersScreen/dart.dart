import 'dart:async';

import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:foodie_restaurant/constants.dart';

import 'package:foodie_restaurant/main.dart';

import 'package:foodie_restaurant/model/CurrencyModel.dart';

import 'package:foodie_restaurant/model/OrderModel.dart';

import 'package:foodie_restaurant/model/OrderProductModel.dart';

import 'package:foodie_restaurant/model/User.dart';

import 'package:foodie_restaurant/model/VendorModel.dart';

import 'package:foodie_restaurant/model/variant_info.dart';

import 'package:foodie_restaurant/services/FirebaseHelper.dart';

import 'package:foodie_restaurant/services/helper.dart';

import 'package:foodie_restaurant/services/pushnotification.dart';

import 'package:foodie_restaurant/ui/chat_screen/chat_screen.dart';

import 'package:foodie_restaurant/ui/ordersScreen/OrderDetailsScreen.dart';

import 'package:foodie_restaurant/ui/reviewScreen.dart';

class OrdersScreen extends StatefulWidget {
  @override
  _OrdersScreenState createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  FireStoreUtils _fireStoreUtils = FireStoreUtils();

  late Stream<List<OrderModel>> ordersStream;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final audioPlayer = AudioPlayer(playerId: "playerId");

  bool isPlaying = false;

  bool isLoading = true;

  String? selectedTime;

  Map<String, Map<String, String?>> driverDetailsCache = {};

  Map<String, String?> driverDetails = {}; // Add this state variable

  @override
  void initState() {
    super.initState();

    initializeData();
  }

  Future<void> initializeData() async {
    await setCurrency();

    final vendorID = MyAppState.currentUser?.vendorID;
    if (vendorID == null) {
      // Handle null vendorID appropriately
      return;
    }
    ordersStream = _fireStoreUtils.watchOrdersPlaced(vendorID);

    final pushNotificationService = PushNotificationService(_firebaseMessaging);

    pushNotificationService.initialise();

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> setCurrency() async {
    currencyModel = await FireStoreUtils().getCurrency() ??
        CurrencyModel(
          id: "",
          code: "USD",
          decimal: 2,
          isactive: true,
          name: "US Dollar",
          symbol: "\$",
          symbolatright: false,
        );
  }

  @override
  void dispose() {
    _fireStoreUtils.closeOrdersStream();

    audioPlayer.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Color(0XFFFFFFFF),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : StreamBuilder<List<OrderModel>>(
              stream: ordersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                      child: Text('Error loading orders. Please try again.'));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: showEmptyState('No Orders',
                        'New order requests will show up here'),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: ClampingScrollPhysics(),
                  itemCount: snapshot.data!.length,
                  padding: const EdgeInsets.all(20),
                  itemBuilder: (context, index) {
                    final orderModel = snapshot.data![index];

                    return InkWell(
                      onTap: () async {
                        await audioPlayer.stop();

                        push(
                          context,
                          OrderDetailsScreen(orderModel: orderModel),
                        );
                      },
                      child: buildOrderItem(
                        orderModel,
                        index,
                        index != 0 ? snapshot.data![index - 1] : null,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> fetchAndCacheDriverDetails(String driverID) async {
    if (!driverDetailsCache.containsKey(driverID)) {
      driverDetailsCache[driverID] = await fetchDriverDetails(driverID);
    }
  }

  Widget buildOrderItem(
    OrderModel orderModel,
    int index,
    OrderModel? prevModel,
  ) {
    // Format the date for the current and previous order
    String date = DateFormat('MMM d yyyy').format(
      DateTime.fromMillisecondsSinceEpoch(
        orderModel.createdAt.millisecondsSinceEpoch,
      ),
    );

    String date2 = prevModel != null
        ? DateFormat('MMM d yyyy').format(
            DateTime.fromMillisecondsSinceEpoch(
              prevModel.createdAt.millisecondsSinceEpoch,
            ),
          )
        : "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show date header if it's the first item or a different date than the previous
        if (index == 0 || (index != 0 && prevModel != null && date != date2))
          Container(
            height: 40.0,
            margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
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

        // The actual order card
        InkWell(
          onTap: () async {
            // Stop any playing audio
            await audioPlayer.stop();
            // Navigate to OrderDetails
            push(context, OrderDetailsScreen(orderModel: orderModel));
          },
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            elevation: 3,
            color:
                isDarkMode(context) ? Color(DARK_CARD_BG_COLOR) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: buildOrderContent(orderModel),
          ),
        ),
      ],
    );
  }

  Widget buildOrderContent(OrderModel orderModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer & Delivery Info
          Row(
            children: [
              // Product image (first product)
              Container(
                width: 60,
                height: 60,
                margin: const EdgeInsets.only(right: 12.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(orderModel.products.first.photo),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              // Customer name & address
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${orderModel.author.firstName} ${orderModel.author.lastName}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orderModel.takeAway == true
                          ? 'Takeaway'
                          : 'Deliver to: ${orderModel.address.getFullAddress()}'
                              ,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 24),

          // Order Total (with commission deduction)
          FutureBuilder<double>(
            future: calculateTotalAndDeductCommission(orderModel),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Order Total',
                    style: TextStyle(color: Colors.grey),
                  ),
                  trailing: CircularProgressIndicator(),
                );
              } else if (snapshot.hasError || !snapshot.hasData) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Order Total',
                    style: TextStyle(color: Colors.grey),
                  ),
                  trailing: Text(
                    'Error',
                    style: TextStyle(color: Colors.red),
                  ),
                );
              } else {
                double netTotal = snapshot.data ?? 0.0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Order Total',
                    style: TextStyle(color: Colors.grey),
                  ),
                  trailing: Text(
                    '\₱${netTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Color(COLOR_PRIMARY),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
            },
          ),

          const Divider(height: 24),

          // Driver Selected
          buildDriverContent(orderModel),

          const Divider(height: 24),

          // Remarks (if any)
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

          // Action Buttons / Status
          const SizedBox(height: 8),
          _buildOrderActions(orderModel),
        ],
      ),
    );
  }

  Widget _buildOrderActions(OrderModel orderModel) {
    // Rejected
    if (orderModel.status == "Order Rejected") {
      return Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.cancel, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text(
              "Order Rejected",
              style: TextStyle(
                fontSize: 16,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (orderModel.status == "Driver Rejected") {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order has been rejected by driver',
            style: TextStyle(
              fontSize: 14,
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => assignOrderToDriver(context, orderModel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Find Another Driver',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Placed (can accept)
    else if (orderModel.status == "Order Placed") {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => acceptOrder(orderModel),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Accept',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    // Accepted → show "Find Nearest Driver" button
    else if (orderModel.status == "Order Accepted") {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => assignOrderToDriver(context, orderModel),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Find Nearest Driver',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    // Driver Accepted => "Order Prepared" button (rider accepted, restaurant preparing)
    else if (orderModel.status == "Driver Accepted") {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => shipOrder(orderModel),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                'Order Prepared',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    // Driver Assigned → show "Driver On The Way"
    else if (orderModel.status == "Driver Assigned") {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Waiting for Driver to Accept',
            style: TextStyle(
              fontSize: 16,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => assignOrderToDriver(context, orderModel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Change Driver',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
    // Default fallback
    return const SizedBox.shrink();
  }

  void shipOrder(OrderModel orderModel) async {
    try {
      // Update the order's status to "Order Shipped" in Firestore

      await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderModel.id)
          .update({'status': 'Order Shipped'});

      // Display a success message

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order status updated to "Order Shipped".'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Display an error message if something goes wrong

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update order status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void acceptOrder(OrderModel orderModel) async {
    try {
      // Show dialog to prompt for preparation time
      final preparationTime = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          final TextEditingController preparationTimeController =
              TextEditingController();

          return AlertDialog(
            title: Text('Select Preparation Time'),
            content: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                List<String> preparationTimes = [
                  "0:5",
                  "0:10",
                  "0:20",
                  "0:30",
                  "0:40",
                  "0:50",
                  "1:00",
                  "1:30",
                  "2:00"
                ];
                return DropdownButton<String>(
                  value: selectedTime,
                  hint: Text('Choose time'),
                  items: preparationTimes.map((String time) {
                    return DropdownMenuItem<String>(
                      value: time,
                      child: Text(time),
                    );
                  }).toList(),
                  onChanged: (String? value) {
                    setState(() {
                      selectedTime = value;
                    });
                  },
                );
              },
            ),
            actions: <Widget>[
              TextButton(
                child: Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: Text('Submit'),
                onPressed: () {
                  if (selectedTime != null) {
                    Navigator.of(context).pop(selectedTime);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Please select a preparation time.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ],
          );
        },
      );

      // If no time selected, bail out
      if (preparationTime == null || preparationTime.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preparation time is required to accept the order!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Update only the status and prep-time
      await FirebaseFirestore.instance
          .collection("restaurant_orders")
          .doc(orderModel.id)
          .update({
        "status": "Order Accepted",
        "estimatedTimeToPrepare": preparationTime,
      });

      // Prompt user to find a driver next
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order accepted! Tap “Find Nearest Driver” next.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("Error in acceptOrder: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept the order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> playSound() async {
    final path = await rootBundle
        .load("assets/audio/mixkit-happy-bells-notification-937.mp3");

    await audioPlayer.setSourceBytes(path.buffer.asUint8List());

    audioPlayer.play(BytesSource(path.buffer.asUint8List()));
  }

  Future<double> calculateTotalAndDeductCommission(
      OrderModel orderModel) async {
    double total = 0.0;

    // Step 1: Calculate total for all products
    try {
      for (final element in orderModel.products) {
        // Add extrasPrice if available
        if (element.extrasPrice != null &&
            element.extrasPrice!.isNotEmpty &&
            double.tryParse(element.extrasPrice!) != null) {
          total += element.quantity * double.parse(element.extrasPrice!);
        }
        // Add base price
        total += element.quantity * double.parse(element.price);
      }
    } catch (e) {
      print('Error calculating product total: $e');
    }

    // Step 2: Apply discounts (if any)
    final discount =
        double.tryParse(orderModel.discount?.toString() ?? '0.0') ?? 0.0;
    final specialDiscount = double.tryParse(
            orderModel.specialDiscount?['special_discount']?.toString() ??
                '0.0') ??
        0.0;

    final totalAfterDiscount = total - discount - specialDiscount;

    // Count total number of items
    final totalQty = orderModel.products.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    // Step 3: Deduct admin commission
    double adminComm = 0.0;
    try {
      final commissionType = orderModel.adminCommissionType;
      final commissionValue = orderModel.adminCommission;

      if (commissionType != null && commissionValue != null) {
        if (commissionType == 'Percent') {
          adminComm =
              (totalAfterDiscount * double.parse(commissionValue)) / 100;
        } else if (commissionType == 'Fixed') {
          // charge fixed fee per item
          adminComm = double.parse(commissionValue) * totalQty;
        }
      }
    } catch (e) {
      print('Error calculating admin commission: $e');
    }

    // Step 4: Calculate the final net total
    final netTotal = totalAfterDiscount - adminComm;

    print('Initial Total: $total');
    print('Discount: $discount');
    print('Special Discount: $specialDiscount');
    print('Total After Discounts: $totalAfterDiscount');
    print('Admin Commission: $adminComm');
    print('Net Total: $netTotal');

    return netTotal;
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order queued for automatic rider dispatch.'),
        backgroundColor: Colors.green,
      ),
    );

    return {};
  } catch (e, stackTrace) {
    print("Error in assignOrderToDriver: $e\n$stackTrace");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to assign order to driver: $e'),
        backgroundColor: Colors.red,
      ),
    );
    return {};
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

Future<Map<String, String?>> fetchDriverDetails(String driverID) async {
  try {
    final driverDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(driverID)
        .get();

    if (driverDoc.exists) {
      final driverData = driverDoc.data();
      final driverName =
          "${driverData?['firstName'] ?? 'Unknown'} ${driverData?['lastName'] ?? ''}";
      final driverPhone = driverData?['phoneNumber'] ?? 'No phone number';
      final driverPhoto = driverData?['profilePictureURL'] ?? '';

      return {
        "driverName": driverName,
        "driverPhone": driverPhone,
        "driverPhoto": driverPhoto,
      };
    } else {
      return {
        "driverName": "Driver not found",
        "driverPhone": null,
        "driverPhoto": null,
      };
    }
  } catch (e) {
    return {"driverName": "Error", "driverPhone": null, "driverPhoto": null};
  }
}

Widget buildDriverContent(OrderModel orderModel) {
  return FutureBuilder<DocumentSnapshot>(
    future: FirebaseFirestore.instance
        .collection("restaurant_orders")
        .doc(orderModel.id)
        .get(),
    builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot> snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }

      if (snapshot.hasError) {
        return ListTile(
          title: Text('Driver Selected',
              style: const TextStyle(color: Colors.grey)),
          subtitle: Text(
            'Error fetching order data',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode(context) ? Colors.white : Colors.black,
            ),
          ),
        );
      }

      if (!snapshot.hasData || !(snapshot.data?.exists ?? false)) {
        return ListTile(
          title: Text('Driver Selected',
              style: const TextStyle(color: Colors.grey)),
          subtitle: Text(
            'No order data found',
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode(context) ? Colors.white : Colors.black,
            ),
          ),
        );
      }

      final orderData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
      final String? driverID = orderData['driverID'] as String?;

      if (driverID == null) {
        return ListTile(
          title: Text('Driver Selected',
              style: const TextStyle(color: Colors.grey)),
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
        builder: (BuildContext context,
            AsyncSnapshot<Map<String, String?>> driverSnapshot) {
          if (driverSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (driverSnapshot.hasError) {
            return ListTile(
              title: Text('Driver Selected',
                  style: const TextStyle(color: Colors.grey)),
              subtitle: Text(
                'Error fetching driver details',
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
            );
          }

          if (!driverSnapshot.hasData || driverSnapshot.data == null) {
            return ListTile(
              title: Text('Driver Selected',
                  style: const TextStyle(color: Colors.grey)),
              subtitle: Text(
                'Driver details not available',
                style: TextStyle(
                  fontSize: 16,
                  color: isDarkMode(context) ? Colors.white : Colors.black,
                ),
              ),
            );
          }

          final driverDetails = driverSnapshot.data!;
          final driverName = driverDetails["driverName"] ?? "Unknown Driver";
          final driverPhone = driverDetails["driverPhone"] ?? "No phone number";
          final driverPhoto = driverDetails["driverPhoto"];

          return ListTile(
            title: Text(
              'Driver Selected',
              style: const TextStyle(color: Colors.grey),
            ),
            subtitle: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            isDarkMode(context) ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      driverPhone,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () async {
                    if (driverPhone.isNotEmpty &&
                        driverPhone != "No phone number") {
                      final Uri phoneUri = Uri(
                        scheme: 'tel',
                        path: driverPhone.trim(),
                      );

                      final bool canCall = await canLaunchUrl(phoneUri);
                      if (!canCall) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Calling is not supported on this device.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      try {
                        await launchUrl(
                          phoneUri,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                'Error occurred while trying to make a call: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Driver phone number is not available.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            trailing: CircleAvatar(
              backgroundImage: driverPhoto != null && driverPhoto.isNotEmpty
                  ? NetworkImage(driverPhoto)
                  : null,
              radius: 30,
              child: driverPhoto == null || driverPhoto.isEmpty
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
          );
        },
      );
    },
  );
}
