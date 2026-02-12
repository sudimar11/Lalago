import 'dart:async';

import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:easy_localization/easy_localization.dart';

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

  Stream<List<OrderModel>> ordersStream = Stream.empty();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  final audioPlayer = AudioPlayer(playerId: "playerId");

  bool isPlaying = false;

  bool isLoading = true;

  Set<String> _previousOrderIds = {};

  String? selectedTime;
  Timer? _soundLoopTimer;
  bool isSoundLooping = false;

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
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      return;
    }

    ordersStream =
        _fireStoreUtils.watchOrdersPlaced(vendorID).asBroadcastStream();

    ordersStream.listen((orders) {
      final currentIds = orders.map((o) => o.id).toSet();
      final newIds = currentIds.difference(_previousOrderIds);

      if (newIds.isNotEmpty) {
        _startSoundLoop(); // 🔊 Play sound for new orders
      }

      // Timer management is now handled by individual _PreparationTimerWidget instances
      // No need to manage timers here anymore

      _previousOrderIds = currentIds;
    }, onError: (error) {
      print('Error listening to orders stream: $error');
    });

    final pushNotificationService = PushNotificationService(_firebaseMessaging);

    pushNotificationService.initialise();

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _stopSoundLoop() {
    _soundLoopTimer?.cancel();
    isSoundLooping = false;
  }

  void _startSoundLoop() {
    if (isSoundLooping) return;

    isSoundLooping = true;
    _soundLoopTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      playSound();
    });
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

                return Column(
                  children: [
                    // Average Preparation Time Card
                    Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDarkMode(context)
                            ? Color(DARK_CARD_BG_COLOR)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: _calculateAveragePreparationTime(),
                        builder: (context, avgSnapshot) {
                          if (avgSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Row(
                              children: [
                                CircularProgressIndicator(),
                                const SizedBox(width: 16),
                                Text(
                                  'Calculating average preparation time...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode(context)
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ],
                            );
                          }

                          if (avgSnapshot.hasError || !avgSnapshot.hasData) {
                            return Text(
                              'Unable to calculate average preparation time',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            );
                          }

                          final data = avgSnapshot.data!;
                          final avgMinutes = data['avgMinutes'] as double;
                          final totalOrders = data['totalOrders'] as int;
                          final rating = data['rating'] as String;
                          final stars = data['stars'] as int;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Today\'s Performance',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode(context)
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  Icon(
                                    Icons.analytics,
                                    color: Color(COLOR_PRIMARY),
                                    size: 24,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Average Preparation Time',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${avgMinutes.toStringAsFixed(1)} minutes',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Color(COLOR_PRIMARY),
                                          ),
                                        ),
                                        Text(
                                          'Based on $totalOrders orders today',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Rating',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: List.generate(5, (index) {
                                          return Icon(
                                            index < stars
                                                ? Icons.star
                                                : Icons.star_border,
                                            color: index < stars
                                                ? Colors.amber
                                                : Colors.grey,
                                            size: 20,
                                          );
                                        }),
                                      ),
                                      Text(
                                        rating,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: _getRatingColor(rating),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    // Orders List
                    if (!snapshot.hasData || snapshot.data!.isEmpty)
                      Expanded(
                        child: Center(
                          child: showEmptyState('No Orders'.tr(),
                              'New order requests will show up here'.tr()),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: ClampingScrollPhysics(),
                          itemCount: snapshot.data!.length,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                        ),
                      ),
                  ],
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
                          ? 'Takeaway'.tr()
                          : 'Deliver to: ${orderModel.address.getFullAddress()}'
                              .tr(),
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
              title: Text('Remarks'.tr(), style: TextStyle(color: Colors.grey)),
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
            'Order has been rejected by driver'.tr(),
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
                    'Find Another Driver'.tr(),
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
      _startSoundLoop();
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
                'Accept'.tr(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    // Accepted → show loading indicator when no driver assigned
    else if (orderModel.status == "Order Accepted") {
      _stopSoundLoop();
      return Row(
        children: [
          Expanded(
            child: Container(
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
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Waiting for driver assignment...'.tr(),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Driver Assigned → show waiting status
    else if (orderModel.status == "Driver Assigned") {
      _stopSoundLoop();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Driver Assigned - Waiting for Acceptance'.tr(),
            style: TextStyle(
              fontSize: 16,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.grey.shade600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Waiting for driver to accept...'.tr(),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    // Driver Accepted or Driver Pending → show preparation timer
    else if (orderModel.status == "Driver Accepted" ||
        orderModel.status == "Driver Pending") {
      print(
          '🕒 DEBUG: Building UI for ${orderModel.status} order: ${orderModel.id}');
      _stopSoundLoop();

      // Timer is now handled by the separate _PreparationTimerWidget
      // No need to manage timers here anymore

      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            orderModel.status == "Driver Accepted"
                ? 'Driver Accepted - Preparation in Progress'.tr()
                : 'Driver Pending - Preparation in Progress'.tr(),
            style: TextStyle(
              fontSize: 16,
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Timer display above the button
          _PreparationTimerWidget(
            orderId: orderModel.id,
            orderModel: orderModel,
            onShipOrder: () => shipOrder(orderModel),
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
    try {
      final bytes = await rootBundle
          .load('assets/audio/mixkit-happy-bells-notification-937.mp3');
      final audioData = bytes.buffer.asUint8List();

      await audioPlayer.play(BytesSource(audioData));
    } catch (e) {
      print('🔊 Error playing sound: $e');
    }
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

  Future<Map<String, dynamic>> _calculateAveragePreparationTime() async {
    try {
      final vendorID = MyAppState.currentUser?.vendorID;
      if (vendorID == null) {
        return {
          'avgMinutes': 0.0,
          'totalOrders': 0,
          'rating': 'No Data',
          'stars': 0,
        };
      }

      // Get today's start and end
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(Duration(days: 1));

      // Fetch completed orders for today
      final querySnapshot = await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .where('vendorID', isEqualTo: vendorID)
          .where('status',
              whereIn: ['Order Shipped', 'Order Completed', 'Order Delivered'])
          .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
          .where('createdAt', isLessThan: endOfDay)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return {
          'avgMinutes': 0.0,
          'totalOrders': 0,
          'rating': 'No Data',
          'stars': 0,
        };
      }

      double totalPreparationTime = 0.0;
      int validOrders = 0;

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        final shippedAt = data['shippedAt'] as Timestamp?;
        final deliveredAt = data['deliveredAt'] as Timestamp?;

        if (createdAt != null) {
          DateTime? endTime;

          // Use deliveredAt if available, otherwise shippedAt
          if (deliveredAt != null) {
            endTime = deliveredAt.toDate();
          } else if (shippedAt != null) {
            endTime = shippedAt.toDate();
          }

          if (endTime != null) {
            final duration = endTime.difference(createdAt.toDate());
            final minutes = duration.inMinutes;

            // Only count reasonable preparation times (between 1 minute and 2 hours)
            if (minutes >= 1 && minutes <= 120) {
              totalPreparationTime += minutes;
              validOrders++;
            }
          }
        }
      }

      if (validOrders == 0) {
        return {
          'avgMinutes': 0.0,
          'totalOrders': 0,
          'rating': 'No Data',
          'stars': 0,
        };
      }

      final avgMinutes = totalPreparationTime / validOrders;
      final ratingData = _calculateRating(avgMinutes);

      return {
        'avgMinutes': avgMinutes,
        'totalOrders': validOrders,
        'rating': ratingData['rating'],
        'stars': ratingData['stars'],
      };
    } catch (e) {
      print('Error calculating average preparation time: $e');
      return {
        'avgMinutes': 0.0,
        'totalOrders': 0,
        'rating': 'Error',
        'stars': 0,
      };
    }
  }

  Map<String, dynamic> _calculateRating(double avgMinutes) {
    // Target time T = 20 minutes (standard preparation time)
    const double T = 20.0;

    if (avgMinutes <= 0.8 * T) {
      // ≤ 16 minutes
      return {'rating': 'Excellent', 'stars': 5};
    } else if (avgMinutes <= T) {
      // 16-20 minutes
      return {'rating': 'Good', 'stars': 4};
    } else if (avgMinutes <= 1.2 * T) {
      // 20-24 minutes
      return {'rating': 'Average', 'stars': 3};
    } else if (avgMinutes <= 1.5 * T) {
      // 24-30 minutes
      return {'rating': 'Below Avg', 'stars': 2};
    } else {
      // > 30 minutes
      return {'rating': 'Poor', 'stars': 1};
    }
  }

  Color _getRatingColor(String rating) {
    switch (rating) {
      case 'Excellent':
        return Colors.green;
      case 'Good':
        return Colors.lightGreen;
      case 'Average':
        return Colors.orange;
      case 'Below Avg':
        return Colors.deepOrange;
      case 'Poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

Future<Map<String, String?>> assignOrderToDriver(
    BuildContext context, OrderModel orderModel) async {
  try {
    List<Map<String, dynamic>> drivers = [];
    String? nearestDriverId;
    double? nearestDistance;
    String? driverName;
    String? driverPhoto;

    // Haversine formula
    double calculateDistance(
        double lat1, double lon1, double lat2, double lon2) {
      const R = 6371;
      final dLat = (lat2 - lat1) * (pi / 180);
      final dLon = (lon2 - lon1) * (pi / 180);
      final a = sin(dLat / 2) * sin(dLat / 2) +
          cos(lat1 * (pi / 180)) *
              cos(lat2 * (pi / 180)) *
              sin(dLon / 2) *
              sin(dLon / 2);
      final c = 2 * atan2(sqrt(a), sqrt(1 - a));
      return R * c;
    }

    // Fetch only active drivers
    Future<void> fetchDrivers() async {
      final querySnapshot = await FirebaseFirestore.instance
          .collection("users")
          .where("role", isEqualTo: "driver")
          .where("isActive", isEqualTo: true)
          .get();

      drivers = querySnapshot.docs.map((doc) {
        final data = doc.data();
        final dist = calculateDistance(
          orderModel.vendor.latitude,
          orderModel.vendor.longitude,
          data['location']['latitude'] ?? 0.0,
          data['location']['longitude'] ?? 0.0,
        );
        return {
          "id": doc.id,
          "data": data,
          "distance": dist,
        };
      }).toList();

      drivers.sort((a, b) =>
          (a["distance"] as double).compareTo(b["distance"] as double));

      if (drivers.isNotEmpty) {
        final nearest = drivers.first;
        nearestDriverId = nearest["id"] as String;
        nearestDistance = nearest["distance"] as double;
        driverName =
            "${nearest["data"]['firstName']} ${nearest["data"]['lastName']}";
        driverPhoto = nearest["data"]['profilePictureURL'] as String?;
      }
    }

    // Recursive assignment
    Future<void> assignDriver() async {
      await fetchDrivers();

      if (nearestDriverId == null) {
        // no active drivers found; wait and retry
        await Future.delayed(const Duration(seconds: 10));
        return assignDriver();
      }

      // double-check that this driver is still active
      final userSnap = await FirebaseFirestore.instance
          .collection("users")
          .doc(nearestDriverId)
          .get();
      final stillActive = (userSnap.data()?['isActive'] ?? false) as bool;
      if (!stillActive) {
        // remove and retry with next driver
        drivers.removeWhere((d) => d["id"] == nearestDriverId);
        nearestDriverId = null;
        return assignDriver();
      }

      // perform the assignment
      await FirebaseFirestore.instance
          .collection("restaurant_orders")
          .doc(orderModel.id)
          .update({
        "status": "Driver Assigned",
        "driverID": nearestDriverId,
        "driverDistance": nearestDistance,
      });

      await FirebaseFirestore.instance
          .collection("users")
          .doc(nearestDriverId)
          .update({
        "isActive": false,
        "inProgressOrderID": FieldValue.arrayUnion([orderModel.id]),
      });
    }

    // kick off
    await assignDriver();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order successfully assigned to the nearest driver!'),
        backgroundColor: Colors.green,
      ),
    );

    return {
      "driverName": driverName,
      "driverPhoto": driverPhoto,
    };
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
          title: Text('Driver Selected'.tr(),
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
          title: Text('Driver Selected'.tr(),
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
          title: Text('Driver Selected'.tr(),
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
              title: Text('Driver Selected'.tr(),
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
              title: Text('Driver Selected'.tr(),
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
              'Driver Selected'.tr(),
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

// Separate widget for timer display to avoid rebuilding entire order card
class _PreparationTimerWidget extends StatefulWidget {
  final String orderId;
  final OrderModel orderModel;
  final VoidCallback onShipOrder;

  const _PreparationTimerWidget({
    required this.orderId,
    required this.orderModel,
    required this.onShipOrder,
  });

  @override
  _PreparationTimerWidgetState createState() => _PreparationTimerWidgetState();
}

class _PreparationTimerWidgetState extends State<_PreparationTimerWidget> {
  Timer? _timer;
  DateTime? _acceptedTime;
  bool _hasAlarmed = false; // Track if alarm has already been triggered
  bool _hasExceededAlarm = false; // Track if exceeded alarm has been triggered
  AudioPlayer? _exceededAlarmPlayer; // For continuous alarm when time exceeds

  @override
  void initState() {
    super.initState();
    _acceptedTime = DateTime.now();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // This will only rebuild this widget, not the entire order card
        });

        // Check if we need to trigger alarms
        _checkAndTriggerAlarm();
        _checkAndTriggerExceededAlarm();
      }
    });
  }

  void _checkAndTriggerAlarm() {
    if (_hasAlarmed) return; // Don't alarm multiple times

    final remainingMinutes = _getRemainingMinutes();
    if (remainingMinutes <= 3 && remainingMinutes > 0) {
      _hasAlarmed = true;
      _triggerAlarm();
    }
  }

  void _checkAndTriggerExceededAlarm() {
    final remainingMinutes = _getRemainingMinutes();
    if (remainingMinutes <= 0 && !_hasExceededAlarm) {
      _hasExceededAlarm = true;
      _triggerExceededAlarm();
    }
  }

  void _triggerAlarm() async {
    try {
      // Use the device's default alarm sound
      final bytes = await rootBundle
          .load('assets/audio/mixkit-happy-bells-notification-937.mp3');
      final audioData = bytes.buffer.asUint8List();

      final audioPlayer = AudioPlayer(playerId: "alarm_${widget.orderId}");
      await audioPlayer.play(BytesSource(audioData));

      // Stop alarm after 10 seconds
      Timer(Duration(seconds: 10), () {
        audioPlayer.stop();
        audioPlayer.dispose();
      });

      print('🚨 ALARM: 3 minutes remaining for order ${widget.orderId}');
    } catch (e) {
      print('🚨 Error triggering alarm: $e');
    }
  }

  void _triggerExceededAlarm() async {
    try {
      print('🚨 EXCEEDED ALARM: Time exceeded for order ${widget.orderId}');

      // Create a new audio player for the exceeded alarm
      _exceededAlarmPlayer =
          AudioPlayer(playerId: "exceeded_alarm_${widget.orderId}");

      // Load and play the alarm sound
      final bytes = await rootBundle
          .load('assets/audio/mixkit-happy-bells-notification-937.mp3');
      final audioData = bytes.buffer.asUint8List();

      // Play the alarm continuously
      await _exceededAlarmPlayer!.play(BytesSource(audioData));

      // Set up looping for continuous alarm
      _exceededAlarmPlayer!.onPlayerComplete.listen((event) {
        if (_hasExceededAlarm && mounted) {
          // Replay the alarm if time is still exceeded
          _exceededAlarmPlayer!.play(BytesSource(audioData));
        }
      });
    } catch (e) {
      print('🚨 Error triggering exceeded alarm: $e');
    }
  }

  void _stopExceededAlarm() {
    if (_exceededAlarmPlayer != null) {
      _exceededAlarmPlayer!.stop();
      _exceededAlarmPlayer!.dispose();
      _exceededAlarmPlayer = null;
      _hasExceededAlarm = false;
      print('🔇 Stopped exceeded alarm for order ${widget.orderId}');
    }
  }

  int _getRemainingMinutes() {
    if (widget.orderModel.estimatedTimeToPrepare == null ||
        widget.orderModel.estimatedTimeToPrepare!.isEmpty) {
      return 0;
    }

    final timeParts = widget.orderModel.estimatedTimeToPrepare!.split(':');
    if (timeParts.length != 2) {
      return 0;
    }

    int estimatedMinutes;
    if (timeParts[0].contains('.')) {
      estimatedMinutes = (double.parse(timeParts[0]) * 60).round();
    } else {
      estimatedMinutes = int.parse(timeParts[0]) * 60 + int.parse(timeParts[1]);
    }

    if (_acceptedTime == null) {
      return estimatedMinutes;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_acceptedTime!).inMinutes;
    final remaining = estimatedMinutes - elapsed;

    return remaining > 0 ? remaining : 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopExceededAlarm();
    super.dispose();
  }

  String _getElapsedTime() {
    if (_acceptedTime == null) return '00:00';

    final now = DateTime.now();
    final difference = now.difference(_acceptedTime!);
    final minutes = difference.inMinutes;
    final seconds = difference.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getEstimatedTimeRemaining() {
    if (widget.orderModel.estimatedTimeToPrepare == null ||
        widget.orderModel.estimatedTimeToPrepare!.isEmpty) {
      return 'No time set';
    }

    final timeParts = widget.orderModel.estimatedTimeToPrepare!.split(':');
    if (timeParts.length != 2) {
      return 'Invalid time format';
    }

    int estimatedMinutes;
    if (timeParts[0].contains('.')) {
      estimatedMinutes = (double.parse(timeParts[0]) * 60).round();
    } else {
      estimatedMinutes = int.parse(timeParts[0]) * 60 + int.parse(timeParts[1]);
    }

    if (_acceptedTime == null) {
      return '${estimatedMinutes}min';
    }

    final now = DateTime.now();
    final elapsed = now.difference(_acceptedTime!).inMinutes;
    final remaining = estimatedMinutes - elapsed;

    if (remaining <= 0) {
      return 'Time exceeded';
    }

    return '${remaining}min remaining';
  }

  @override
  Widget build(BuildContext context) {
    final elapsedTime = _getElapsedTime();
    final estimatedTime = _getEstimatedTimeRemaining();
    final remainingMinutes = _getRemainingMinutes();
    final isWarning = remainingMinutes <= 3 && remainingMinutes > 0;
    final isExceeded = remainingMinutes <= 0;

    return Column(
      children: [
        // Timer display
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                isExceeded
                    ? Icons.error
                    : (isWarning ? Icons.warning : Icons.timer),
                color: isExceeded
                    ? Colors.red
                    : (isWarning ? Colors.red : Colors.blue.shade700),
                size: 20),
            const SizedBox(width: 8),
            Text(
              elapsedTime,
              style: TextStyle(
                color: isExceeded
                    ? Colors.red
                    : (isWarning ? Colors.red : Colors.blue.shade700),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Elapsed Time',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          estimatedTime,
          style: TextStyle(
            color: isExceeded
                ? Colors.red
                : (isWarning ? Colors.red : Colors.orange.shade700),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        // Show warning message when 3 minutes or less remain
        if (isWarning) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Time is running out!',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        // Show exceeded message when time has exceeded
        if (isExceeded) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text(
                  'TIME EXCEEDED! Click "Mark as Ready" to stop alarm',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  // Stop the exceeded alarm before shipping the order
                  _stopExceededAlarm();
                  widget.onShipOrder();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Mark as Ready'.tr(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
