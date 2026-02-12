import 'dart:async';

import 'dart:convert';

import 'dart:developer';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:foodie_customer/AppGlobal.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/TaxModel.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/model/VendorModel.dart';
import 'package:foodie_customer/model/variant_info.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/ui/chat_screen/chat_screen.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/ordertracknew.dart';
import 'package:foodie_customer/ui/ordersScreen/OrdersScreen.dart';
import 'package:foodie_customer/ui/reviewScreen.dart/reviewScreen.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
// Removed Google Maps/Directions client usage from this screen
import 'package:lottie/lottie.dart' as lottie;
import 'package:provider/provider.dart';
// import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/localDatabase.dart';

class OrderDetailsScreen extends StatefulWidget {
  final OrderModel orderModel;

  OrderDetailsScreen({Key? key, required this.orderModel}) : super(key: key);

  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late CartDatabase cartDatabase;

  bool isAnimation = false; // Add this li

  int remainingSeconds = 300; // Default countdown time in seconds

  // Total timer duration in seconds

  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Add StreamSubscription variables to track and cancel streams
  StreamSubscription<User>? _driverStreamSubscription;
  StreamSubscription<OrderModel?>? _ordersStreamSubscription;

  @override
  void didChangeDependencies() {
    cartDatabase = Provider.of<CartDatabase>(context, listen: false);

    super.didChangeDependencies();
  }

  FireStoreUtils fireStoreUtils = FireStoreUtils();

  late String orderStatus;

  bool isTakeAway = false;

  late String storeName;

  late String phoneNumberStore;

  String currentEvent = '';

  double total = 0.0;

  var discount;

  var tipAmount = "0.0";

  @override
  void initState() {
    getCurrentOrder();

    orderStatus = widget.orderModel.status;

    isTakeAway = false; // Default to delivery since takeAway field was removed

    widget.orderModel.products.forEach((element) {
      if (element.extras_price != null &&
          element.extras_price!.isNotEmpty &&
          double.parse(element.extras_price!) != 0.0) {
        total += element.quantity * double.parse(element.extras_price!);
      }

      total += element.quantity * double.parse(element.price);

      discount = widget.orderModel.discount;
    });

    super.initState();

    DateTime orderCreationTime = widget.orderModel.createdAt.toDate();

    if (orderCreationTime
        .isAfter(DateTime.now().subtract(Duration(seconds: 30)))) {
      isAnimation = true;

      // Stop animation after 9 seconds

      Future.delayed(const Duration(seconds: 9), () {
        setState(() {
          isAnimation = false;
        });
      });
    }

    // Initialize notifications and background service

    initializeNotifications();

    // Only start the timer if the order is not already rejected
  }

  @override
  void dispose() {
    // Cancel stream subscriptions to prevent memory leaks and black screen issues
    _driverStreamSubscription?.cancel();
    _ordersStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> showStatusNotification(String status) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'order_status_channel', // Channel ID

      'Order Status Update', // Channel name

      channelDescription: 'Shows updates for the current order status',

      importance: Importance.max,

      priority: Priority.high,

      ongoing: false, // Notification is not persistent
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    try {
      if (Platform.isAndroid) {
        final permission = await Permission.notification.status;
        if (!permission.isGranted) return;
      }
      await flutterLocalNotificationsPlugin.show(
        1, // Notification ID
        'Order Status Updated', // Notification title
        'Current Status: $status', // Notification body
        platformChannelSpecifics,
      );
    } catch (e) {
      debugPrint('showStatusNotification failed: $e');
    }
  }

  void initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('app_icon'); // Your app icon

    final InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final String? payload = response.payload;

        if (payload != null) {
          OrderModel? order =
              await getOrderById(payload); // Use the standalone function

          if (order != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => OrderDetailsScreen(orderModel: order),
              ),
            );
          }
        }
      },
    );
  }

  void showNotification(int remainingSeconds, String orderId) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'auto_cancel_timer_channel', // Channel ID

      'Waiting for feedback from the restaurant', // Channel name

      channelDescription: 'Displays the countdown timer for auto-cancel',

      importance: Importance.max,

      priority: Priority.high,

      ongoing: true, // Makes the notification persistent
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    try {
      if (Platform.isAndroid) {
        final permission = await Permission.notification.status;
        if (!permission.isGranted) return;
      }
      await flutterLocalNotificationsPlugin.show(
        0, // Notification ID (replace or update this notification)
        'Auto Cancel', // Notification title including order ID
        'Waiting for feedback from restaurant: ${formatTime(remainingSeconds)}', // Notification body
        platformChannelSpecifics,
      );
    } catch (e) {
      debugPrint('showNotification failed: $e');
    }
  }

  Future<OrderModel?> getOrderById(String orderId) async {
    try {
      DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
          .instance
          .collection(
              'restaurant_orders') // Replace with your actual collection name

          .doc(orderId)
          .get();

      if (doc.exists) {
        return OrderModel.fromJson(doc.data()!);
      } else {
        return null; // Order not found
      }
    } catch (e) {
      debugPrint('Error fetching order by ID: $e');

      return null;
    }
  }

  // Removed unused _onTimerEnd (auto-reject handled elsewhere)

  void _showOrderRejectedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Order Unsuccessful'),
          content: const Text(
            "We regret to inform you that this order could not be completed as the restaurant is currently unavailable. We kindly recommend exploring other restaurant options. Thank you for your patience and understanding.",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showNotification() async {
    // Android: disable flutter_local_notifications to avoid
    // "Too many inflation attempts" SIGABRT crashes. Rely on system FCM UI.
    if (Platform.isAndroid) return;
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'order_rejected_channel',
      'Order Rejected Notifications',
      channelDescription: 'Notifications for rejected orders',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    try {
      await flutterLocalNotificationsPlugin.show(
        0,
        'Order Rejected',
        'Your order has been rejected due to unavailability.',
        notificationDetails,
      );
    } catch (e) {
      debugPrint('_showNotification failed: $e');
    }
  }

  String formatTime(int seconds) {
    final minutes = seconds ~/ 60;

    final remainingSeconds = seconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          isDarkMode(context) ? const Color(DARK_BG_COLOR) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Your Order',
          style: TextStyle(color: Color(COLOR_PRIMARY)),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Color(COLOR_PRIMARY)),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: isAnimation
          ? Center(
              child: Image.asset(
                'assets/order_place_gif.gif', // Replace with your .gif path

                fit: BoxFit.cover,

                height: 400,

                width: 400,
              ),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: fireStoreUtils.watchOrderStatus(widget.orderModel.id),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  OrderModel orderModel =
                      OrderModel.fromJson(snapshot.data!.data()!);

                  orderStatus = orderModel.status;

                  storeName = orderModel.vendor.title;

                  phoneNumberStore = orderModel.vendor.phonenumber;

                  debugPrint('_PlaceOrderScreenState.initState $orderStatus');

                  switch (orderStatus) {
                    case ORDER_STATUS_PLACED:
                      currentEvent = 'We sent your order to' +
                          " (${orderModel.vendor.title})";

                      break;

                    case ORDER_STATUS_ACCEPTED:
                      currentEvent = 'Preparing your order...';

                      break;

                    case ORDER_STATUS_REJECTED:
                      currentEvent = 'Your order is not successfull';

                      break;

                    case ORDER_STATUS_CANCELLED:
                      currentEvent = 'Your order is not successfull';

                      break;

                    case ORDER_STATUS_DRIVER_PENDING:
                      currentEvent = 'Driver picking up your order...';

                      break;

                    case ORDER_STATUS_DRIVER_REJECTED:
                      currentEvent = 'Looking for a driver...';

                      break;

                    case ORDER_STATUS_SHIPPED:
                      currentEvent =
                          '${orderModel.driver?.firstName ?? 'Our Driver'} has picked up your order.';

                      break;

                    case ORDER_STATUS_IN_TRANSIT:
                      currentEvent = 'Your order is on the way';

                      break;

                    case ORDER_STATUS_COMPLETED:
                      currentEvent = 'Your order is Deliver.';

                      break;
                  }

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 12),
                          child: Card(
                            color: isDarkMode(context)
                                ? const Color(DARK_BG_COLOR)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 16, right: 16, top: 16),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'ORDER ID',
                                        style: TextStyle(
                                          fontFamily: 'Poppinsm',
                                          fontSize: 14,
                                          letterSpacing: 0.5,
                                          color: isDarkMode(context)
                                              ? Colors.grey.shade300
                                              : const Color(0xff9091A4),
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          widget.orderModel.id,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'Poppinsm',
                                            letterSpacing: 0.5,
                                            fontSize: 14,
                                            color: isDarkMode(context)
                                                ? Colors.grey.shade300
                                                : const Color(0xff333333),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      right: 10, left: 10, bottom: 12),
                                  child: RichText(
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(children: [
                                      TextSpan(
                                        text: currentEvent,
                                        style: TextStyle(
                                          letterSpacing: 0.5,

                                          color: isDarkMode(context)
                                              ? Colors.grey.shade200
                                              : const Color(0XFF2A2A2A),

                                          fontFamily: "Poppinsm",

                                          // fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        orderModel.status == ORDER_STATUS_ACCEPTED ||
                                orderModel.status ==
                                    ORDER_STATUS_DRIVER_PENDING ||
                                orderModel.status ==
                                    ORDER_STATUS_DRIVER_REJECTED
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 5),
                                child: Card(
                                  color: isDarkMode(context)
                                      ? const Color(DARK_BG_COLOR)
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: ListTile(
                                      title: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Estimated time to Prepare from your order time',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'Poppinsm',
                                              fontSize: 16,
                                              letterSpacing: 0.5,
                                              color: isDarkMode(context)
                                                  ? Colors.grey.shade300
                                                  : const Color(0xff9091A4),
                                            ),
                                          ),
                                          SizedBox(
                                            height: 10,
                                          ),
                                          Text(
                                            orderModel.estimatedTimeToPrepare
                                                    .toString() +
                                                "${_getTimeUnit(orderModel.estimatedTimeToPrepare)}",
                                            style: TextStyle(
                                              fontFamily: 'Poppinsm',
                                              letterSpacing: 0.5,
                                              fontSize: 16,
                                              color: isDarkMode(context)
                                                  ? Colors.grey.shade300
                                                  : const Color(0xff333333),
                                            ),
                                          )
                                        ],
                                      ),
                                      trailing: Flexible(
                                        child: Container(
                                            height: 60,
                                            width: 60,
                                            child: lottie.Lottie.asset(
                                              isDarkMode(context)
                                                  ? 'assets/images/chef_dark_bg.json'
                                                  : 'assets/images/chef_light_bg.json',
                                            )),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Container(),
                        orderModel.status == ORDER_STATUS_SHIPPED ||
                                orderModel.status == ORDER_STATUS_IN_TRANSIT
                            ? Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 12),
                                child: Card(
                                  color: isDarkMode(context)
                                      ? const Color(DARK_BG_COLOR)
                                      : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                  child: ListTile(
                                    title: Text(
                                      'Track Order',
                                      style: TextStyle(
                                        fontFamily: 'Poppinsm',
                                        fontSize: 16,
                                        letterSpacing: 0.5,
                                        color: isDarkMode(context)
                                            ? Colors.grey.shade300
                                            : const Color(0xff9091A4),
                                      ),
                                    ),
                                    trailing: TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: Color(COLOR_PRIMARY),
                                        padding: EdgeInsets.only(
                                            top: 12, bottom: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8.0),
                                            side: BorderSide(
                                                color: isDarkMode(context)
                                                    ? Colors.grey.shade700
                                                    : Colors.grey.shade200)),
                                      ),
                                      child: Text(
                                        'Go',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isDarkMode(context)
                                                ? Colors.white
                                                : Colors.white),
                                      ),
                                      onPressed: () async {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                OrderTrackingPage(
                                                    orderId:
                                                        widget.orderModel.id),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              )
                            : Container(),
                        Visibility(
                            visible: (orderStatus == ORDER_STATUS_SHIPPED ||
                                orderStatus == ORDER_STATUS_IN_TRANSIT),
                            child: buildDriverCard(orderModel)),
                        const SizedBox(height: 16),
                        buildDeliveryDetailsCard(),
                        const SizedBox(height: 16),
                        buildOrderSummaryCard(orderModel),
                      ],
                    ),
                  );
                } else if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator.adaptive(
                      valueColor: AlwaysStoppedAnimation(Color(COLOR_PRIMARY)),
                    ),
                  );
                } else {
                  return Center(
                    child: showEmptyState('Order Not Found', context),
                  );
                }
              }),
    );
  }

  Widget buildDeliveryDetailsCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        color: isDarkMode(context) ? const Color(DARK_BG_COLOR) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              !isTakeAway
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivery Details',
                          style: TextStyle(
                              fontSize: 20,
                              letterSpacing: 0.5,
                              color: isDarkMode(context)
                                  ? Colors.grey.shade200
                                  : const Color(0XFF000000),
                              fontFamily: "Poppinsb"),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Address',
                          style: TextStyle(
                              fontSize: 16,
                              letterSpacing: 0.5,
                              color: isDarkMode(context)
                                  ? Colors.grey.shade200
                                  : Color(COLOR_PRIMARY),
                              fontFamily: "Poppinsm"),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${widget.orderModel.address!.getFullAddress()}',
                          style: TextStyle(
                              fontFamily: "Poppinss",
                              fontSize: 18,
                              letterSpacing: 0.5,
                              color: isDarkMode(context)
                                  ? Colors.grey.shade200
                                  : Colors.grey.shade700),
                        ),
                        const Divider(height: 40),
                      ],
                    )
                  : Container(),
              Text(
                'Type',
                style: TextStyle(
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: isDarkMode(context)
                        ? Colors.grey.shade200
                        : Color(COLOR_PRIMARY),
                    fontFamily: "Poppinsm"),
              ),
              const SizedBox(height: 8),
              !isTakeAway
                  ? Text(
                      'Deliver to door',
                      style: TextStyle(
                          fontFamily: "Poppinss",
                          fontSize: 18,
                          letterSpacing: 0.5,
                          color: isDarkMode(context)
                              ? Colors.grey.shade200
                              : Colors.grey.shade700),
                    )
                  : Text(
                      'Takeaway',
                      style: TextStyle(
                          fontFamily: "Poppinss",
                          fontSize: 18,
                          letterSpacing: 0.5,
                          color: isDarkMode(context)
                              ? Colors.grey.shade200
                              : Colors.grey.shade700),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildOrderSummaryCard(OrderModel orderModel) {
    debugPrint("order status ${widget.orderModel.id}");

    double tipValue = (widget.orderModel.tipValue != null &&
            widget.orderModel.tipValue!.isNotEmpty)
        ? double.parse(widget.orderModel.tipValue!)
        : 0.0;

    double specialDiscountAmount = 0.0;

    String taxAmount = "0.0";

    if (widget.orderModel.specialDiscount != null &&
        widget.orderModel.specialDiscount!.isNotEmpty) {
      specialDiscountAmount = double.parse(
          widget.orderModel.specialDiscount!['special_discount'].toString());
    }

    if (taxList != null) {
      for (var element in taxList!) {
        taxAmount = (double.parse(taxAmount) +
                calculateTax(
                    amount:
                        (total - discount - specialDiscountAmount).toString(),
                    taxModel: element))
            .toString();
      }
    }

    var totalamount = widget.orderModel.deliveryCharge == null ||
            widget.orderModel.deliveryCharge!.isEmpty
        ? total + double.parse(taxAmount) - discount - specialDiscountAmount
        : total +
            double.parse(taxAmount) +
            double.parse(widget.orderModel.deliveryCharge!) +
            tipValue -
            discount -
            specialDiscountAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        color: isDarkMode(context) ? const Color(DARK_BG_COLOR) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 14, top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '`Order Summary`',
                style: TextStyle(
                  fontFamily: 'Poppinsm',
                  fontSize: 18,
                  letterSpacing: 0.5,
                  color: isDarkMode(context)
                      ? Colors.white
                      : const Color(0XFF000000),
                ),
              ),
              const SizedBox(
                height: 15,
              ),
              ListView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: widget.orderModel.products.length,
                  itemBuilder: (context, index) {
                    VariantInfo? variantIno =
                        widget.orderModel.products[index].variant_info;

                    List<dynamic>? addon =
                        widget.orderModel.products[index].extras;

                    String extrasDisVal = '';

                    if (addon != null) {
                      for (int i = 0; i < addon.length; i++) {
                        extrasDisVal +=
                            '${addon[i].toString().replaceAll("\"", "")} ${(i == addon.length - 1) ? "" : ","}';
                      }
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

                                imageUrl: getImageVAlidUrl(
                                    widget.orderModel.products[index].photo),
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
                                      AppGlobal.placeHolderImage!,
                                      fit: BoxFit.cover,
                                      width: MediaQuery.of(context).size.width,
                                      height:
                                          MediaQuery.of(context).size.height,
                                    ))),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            widget.orderModel.products[index]
                                                .name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontFamily: 'Poppinsr',
                                                fontSize: 15,
                                                letterSpacing: 0.5,
                                                fontWeight: FontWeight.bold,
                                                color: isDarkMode(context)
                                                    ? Colors.grey.shade200
                                                    : const Color(0xff333333)),
                                          ),
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
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                        fontFamily: 'Poppinsr'),
                                  ),
                                ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                  child: Container(
                                      width: MediaQuery.of(context).size.width,
                                      padding: const EdgeInsets.only(
                                          top: 8, bottom: 8),
                                      decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          border: Border.all(
                                              width: 0.8,
                                              color: const Color(0XFF82807F))),
                                      child: Center(
                                        child: Text(
                                          'REORDER',
                                          style: TextStyle(
                                              color: isDarkMode(context)
                                                  ? const Color(0xffFFFFFF)
                                                  : const Color(DARK_COLOR),
                                              fontFamily: "Poppinsm",
                                              fontSize: 15),
                                        ),
                                      )),
                                  onTap: () async {
                                    try {
                                      showProgress(
                                          context, "Please wait", false);

                                      // Validate order has products
                                      if (widget.orderModel.products.isEmpty) {
                                        hideProgress();
                                        showAlertDialog(
                                          context,
                                          "Reorder Failed",
                                          "This order has no products to reorder.",
                                          true,
                                        );
                                        return;
                                      }

                                      // Clear current cart with timeout
                                      try {
                                        await Provider.of<CartDatabase>(context,
                                                listen: false)
                                            .deleteAllProducts()
                                            .timeout(Duration(seconds: 10));
                                      } catch (e) {
                                        debugPrint("Error clearing cart: $e");
                                        // Continue anyway - cart might already be empty
                                      }

                                      final cartDatabase =
                                          Provider.of<CartDatabase>(context,
                                              listen: false);
                                      int successCount = 0;
                                      int failCount = 0;
                                      List<String> failedProducts = [];

                                      // Re-add each ordered product into cart with validation
                                      for (final CartProduct p
                                          in widget.orderModel.products) {
                                        try {
                                          debugPrint(
                                              "Processing product: ${p.name}, id: ${p.id}");
                                          // Validate and transform CartProduct
                                          final validatedProduct =
                                              _validateAndTransformCartProduct(
                                                  p);

                                          if (validatedProduct != null) {
                                            debugPrint(
                                                "Product validated, adding to cart: ${p.name}");
                                            // Add timeout to prevent hanging
                                            await cartDatabase
                                                .reAddProduct(validatedProduct)
                                                .timeout(Duration(seconds: 5),
                                                    onTimeout: () {
                                              throw TimeoutException(
                                                  'Product add operation timed out');
                                            });
                                            successCount++;
                                            debugPrint(
                                                "Product added successfully: ${p.name}, successCount: $successCount");
                                          } else {
                                            failCount++;
                                            failedProducts.add(p.name);
                                            debugPrint(
                                                "Failed to validate product: ${p.name}");
                                          }
                                        } catch (e) {
                                          failCount++;
                                          failedProducts.add(p.name);
                                          debugPrint(
                                              "Error adding product ${p.name}: $e");
                                        }
                                      }

                                      hideProgress();

                                      // Debug logging
                                      debugPrint(
                                          "Reorder completed - successCount: $successCount, failCount: $failCount");
                                      debugPrint(
                                          "Failed products: ${failedProducts.join(', ')}");

                                      // Show appropriate feedback
                                      if (successCount > 0 && failCount == 0) {
                                        // All products added successfully
                                        debugPrint(
                                            "Navigating to CartScreen - all products added");
                                        // Open Cart screen so user can review and checkout
                                        if (mounted) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => CartScreen(
                                                  fromContainer: false),
                                            ),
                                          );
                                        }
                                      } else if (successCount > 0 &&
                                          failCount > 0) {
                                        // Partial success
                                        debugPrint(
                                            "Navigating to CartScreen - partial success");
                                        showAlertDialog(
                                          context,
                                          "Partial Reorder",
                                          "$successCount product(s) added to cart. $failCount product(s) could not be added: ${failedProducts.join(', ')}",
                                          true,
                                        );
                                        // Still navigate to cart to show what was added
                                        if (mounted) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => CartScreen(
                                                  fromContainer: false),
                                            ),
                                          );
                                        }
                                      } else {
                                        // Complete failure
                                        debugPrint(
                                            "Reorder failed - no products added");
                                        showAlertDialog(
                                          context,
                                          "Reorder Failed",
                                          "Unable to add products to cart. Please try again or contact support.",
                                          true,
                                        );
                                      }
                                    } catch (e, stackTrace) {
                                      hideProgress();
                                      debugPrint("Error during reorder: $e");
                                      debugPrint("StackTrace: $stackTrace");
                                      showAlertDialog(
                                        context,
                                        "Reorder Failed",
                                        "An error occurred while reordering. Please try again.",
                                        true,
                                      );
                                    }
                                  }),
                            ),
                            const SizedBox(
                              width: 10,
                            ),
                            Expanded(
                              child: InkWell(
                                child: Container(
                                    width: MediaQuery.of(context).size.width,
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 8),
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                            width: 0.8,
                                            color: const Color(0XFF82807F))),
                                    child: Center(
                                      child: Text(
                                        'RATE Product',
                                        style: TextStyle(
                                            color: isDarkMode(context)
                                                ? const Color(0xffFFFFFF)
                                                : const Color(DARK_COLOR),
                                            fontFamily: "Poppinsm",
                                            fontSize: 15),
                                      ),
                                    )),
                                onTap: () {
                                  push(
                                      context,
                                      ReviewScreen(
                                        product:
                                            widget.orderModel.products[index],
                                        orderId: widget.orderModel.id,
                                      ));
                                },
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Divider(
                            thickness: 1.5,
                            color: isDarkMode(context)
                                ? const Color(0Xff35363A)
                                : null,
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
                    fontSize: 16,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff333333),
                  ),
                ),
              ),
              Visibility(
                visible: orderModel.vendor.specialDiscountEnable &&
                    widget.orderModel.specialDiscount != null,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                  title: Text(
                    'Special Discount' +
                        (widget.orderModel.specialDiscount != null
                            ? "(${widget.orderModel.specialDiscount!['special_discount_label']}${widget.orderModel.specialDiscount!['specialType'] == "amount" ? currencyModel!.symbol : "%"})"
                            : ""),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                      fontSize: 16,
                      color: Colors.red,
                    ),
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
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ),
              !isTakeAway
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 0),
                      title: Text(
                        'Delivery Charges',
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
                        widget.orderModel.deliveryCharge == null
                            ? amountShow(amount: "0")
                            : amountShow(
                                amount: widget.orderModel.deliveryCharge!),
                        style: TextStyle(
                          fontSize: 16,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff333333),
                        ),
                      ),
                    )
                  : Container(),
              !isTakeAway
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 0),
                      title: Text(
                        'Sadaqa Amount',
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
                        (widget.orderModel.tipValue == null ||
                                widget.orderModel.tipValue!.isEmpty)
                            ? amountShow(amount: "0.0")
                            : amountShow(amount: widget.orderModel.tipValue!),
                        style: TextStyle(
                          fontSize: 16,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff333333),
                        ),
                      ),
                    )
                  : Container(),
              (orderModel.taxModel != null && orderModel.taxModel!.isNotEmpty)
                  ? ListView.builder(
                      itemCount: orderModel.taxModel!.length,
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      physics: NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        TaxModel taxModel = orderModel.taxModel![index];

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0, vertical: 0),
                          title: Text(
                            '${taxModel.title.toString()} (${taxModel.type == "fix" ? amountShow(amount: taxModel.tax) : "${taxModel.tax}%"})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                                        amount:
                                            (double.parse(total.toString()) -
                                                    discount -
                                                    specialDiscountAmount)
                                                .toString(),
                                        taxModel: taxModel)
                                    .toString()),
                            style: TextStyle(
                              fontSize: 16,
                              color: isDarkMode(context)
                                  ? Colors.grey.shade300
                                  : const Color(0xff333333),
                            ),
                          ),
                        );
                      },
                    )
                  : Container(),
              (widget.orderModel.notes != null &&
                      widget.orderModel.notes!.isNotEmpty)
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 0),
                      title: Text(
                        "Remarks",
                        style: TextStyle(
                          fontFamily: 'Poppinsm',
                          fontSize: 17,
                          letterSpacing: 0.5,
                          color: isDarkMode(context)
                              ? Colors.grey.shade300
                              : const Color(0xff9091A4),
                        ),
                      ),
                      trailing: InkWell(
                        onTap: () {
                          showModalBottomSheet(
                              isScrollControlled: true,
                              isDismissible: true,
                              context: context,
                              backgroundColor: Colors.transparent,
                              enableDrag: true,
                              builder: (BuildContext context) =>
                                  viewNotesheet(widget.orderModel.notes!));
                        },
                        child: Text(
                          "View",
                          style: TextStyle(
                              fontSize: 18,
                              color: Color(COLOR_PRIMARY),
                              letterSpacing: 0.5,
                              fontFamily: 'Poppinsm'),
                        ),
                      ),
                    )
                  : Container(),
              (widget.orderModel.couponCode != null &&
                      widget.orderModel.couponCode!.trim().isNotEmpty)
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
                        widget.orderModel.couponCode ?? '',
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
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: isDarkMode(context)
                        ? Colors.grey.shade300
                        : const Color(0xff333333),
                  ),
                ),
                trailing: Text(
                  amountShow(amount: totalamount.toString()),
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
                          child: Row(
                            mainAxisSize: MainAxisSize
                                .min, // Ensures the row takes up minimal space

                            children: [
                              Icon(
                                Icons.arrow_back, // Back arrow icon

                                color: isDarkMode(context)
                                    ? const Color(0xffFFFFFF)
                                    : Colors.white,

                                size: 20, // Icon size
                              ),

                              const SizedBox(
                                  width:
                                      8), // Spacing between the icon and text

                              Text(
                                'Back',
                                style: TextStyle(
                                  color: isDarkMode(context)
                                      ? const Color(0xffFFFFFF)
                                      : Colors.white,
                                  fontFamily: "Poppinsm",
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )),
                    onTap: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => ContainerScreen(
                            user: MyAppState.currentUser!,
                            currentWidget: OrdersScreen(isAnimation: true),
                            appBarTitle: 'Orders',
                          ),
                        ),

                        (route) => false, // Clear all previous routes
                      );
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
    showAlertDialog(context, "Printing Unavailable",
        "Printing temporarily unavailable", true);
  }

  String taxAmount = "0.0";

  Future<List<int>> getTicket() async {
    List<int> bytes = [];

    CapabilityProfile profile = await CapabilityProfile.load();

    final generator = Generator(PaperSize.mm80, profile);

    bytes += generator.text("Invoice",
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
        linesAfter: 1);

    bytes += generator.text(storeName,
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.text('Tel: $phoneNumberStore',
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(
          text: 'Address',
          width: 12,
          styles: const PosStyles(
              align: PosAlign.left,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
              bold: true)),
    ]);

    bytes += generator.row([
      PosColumn(
          text: '${widget.orderModel.address!.getFullAddress()}',
          width: 12,
          styles: const PosStyles(
              align: PosAlign.right,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
              bold: true)),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Type',
          width: 12,
          styles: const PosStyles(
              align: PosAlign.left,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
              bold: true)),
    ]);

    bytes += generator.row([
      PosColumn(
          text: !isTakeAway ? 'Deliver to door' : 'Takeaway',
          width: 12,
          styles: const PosStyles(
              align: PosAlign.right,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
              bold: true)),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Date',
          width: 12,
          styles: const PosStyles(
              align: PosAlign.left,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
              bold: true)),
    ]);

    bytes += generator.row([
      PosColumn(
          text: DateFormat('dd-MM-yyyy, HH:mm')
              .format(DateTime.fromMicrosecondsSinceEpoch(
                  widget.orderModel.createdAt.microsecondsSinceEpoch))
              .toString(),
          width: 12,
          styles: const PosStyles(
              align: PosAlign.right,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
              bold: true)),
    ]);

    bytes += generator.hr();

    List<CartProduct> products = widget.orderModel.products;

    for (int i = 0; i < products.length; i++) {
//  bytes += generator.row([

//    PosColumn(

//           text: 'No',

//           width: 12,

//           styles: PosStyles(align: PosAlign.left, bold: true)),

//   ]);

//  bytes += generator.row([

//     PosColumn(

//           text: (i + 1).toString(),

//           width: 12,

//           styles: PosStyles(

//             align: PosAlign.left,

//           )),

//   ]);

      bytes += generator.row([
        PosColumn(
            text: 'Item:',
            width: 12,
            styles: const PosStyles(align: PosAlign.left, bold: true)),
      ]);

      bytes += generator.row([
        PosColumn(
            text: products[i].name,
            width: 12,
            styles: const PosStyles(
              align: PosAlign.left,
            )),
      ]);

      bytes += generator.row([
        PosColumn(
            text: 'Qty:',
            width: 12,
            styles: const PosStyles(align: PosAlign.left, bold: true)),
      ]);

      bytes += generator.row([
        PosColumn(
            text: products[i].quantity.toString(),
            width: 12,
            styles: const PosStyles(
              align: PosAlign.left,
            )),
      ]);

      bytes += generator.row([
        PosColumn(
            text: 'Price:',
            width: 12,
            styles: const PosStyles(align: PosAlign.left, bold: true)),
      ]);

      bytes += generator.row([
        PosColumn(
            text: products[i].price.toString(),
            width: 12,
            styles: const PosStyles(align: PosAlign.left)),
      ]);

      bytes += generator.hr();

      //   bytes += generator.row([

      //   PosColumn(

      //       text: ' ',

      //       width: 1,

      //       styles: PosStyles(align: PosAlign.center, bold: true)),

      // ]);

      // bytes += generator.row([

      //   // PosColumn(text: (i + 1).toString(), width: 1),

      // PosColumn(

      //     text: '',

      //     width: 1,

      //     styles: PosStyles(

      //       align: PosAlign.center,

      //     )),

      // ]);
    }

    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(
          text: 'Subtotal',
          width: 5,
          styles: const PosStyles(
            align: PosAlign.left,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: '',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: total.toDouble().toStringAsFixed(currencyModel!.decimal),
          width: 3,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Discount',
          width: 5,
          styles: const PosStyles(
            align: PosAlign.left,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: '',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: discount.toDouble().toStringAsFixed(currencyModel!.decimal),
          width: 3,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Special Discount',
          width: 5,
          styles: const PosStyles(
            align: PosAlign.left,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: '',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: widget.orderModel.specialDiscount != null
              ? widget.orderModel.specialDiscount!['special_discount']
                  .toDouble()
                  .toStringAsFixed(currencyModel!.decimal)
              : '0',
          width: 3,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Delivery charges',
          width: 5,
          styles: const PosStyles(
            align: PosAlign.left,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: '',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: widget.orderModel.deliveryCharge == null
              ? "0.0"
              : double.parse(widget.orderModel.deliveryCharge
                      .toString()
                      .replaceAll(',', '')
                      .replaceAll('\€', ''))
                  .toString(),

          // widget.orderModel.deliveryCharge!,

          width: 3,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Tip Amount',
          width: 5,
          styles: const PosStyles(
            align: PosAlign.left,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: '',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: (widget.orderModel.tipValue == null ||
                  widget.orderModel.tipValue!.isEmpty)
              ? "0.0"
              : widget.orderModel.tipValue!,
          width: 3,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
    ]);

    bytes += generator.row([
      PosColumn(
          text: 'Tax',
          width: 5,
          styles: const PosStyles(
            align: PosAlign.left,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: '',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: taxAmount.toString(),
          width: 3,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
    ]);

    if (widget.orderModel.notes != null &&
        widget.orderModel.notes!.isNotEmpty) {
      bytes += generator.row([
        PosColumn(
            text: "Remark",
            width: 5,
            styles: const PosStyles(
              align: PosAlign.left,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
            )),
        PosColumn(
            text: '',
            width: 4,
            styles: const PosStyles(
              align: PosAlign.center,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
            )),
        PosColumn(
            text: widget.orderModel.notes!.toString(),
            width: 3,
            styles: const PosStyles(
              align: PosAlign.right,
              height: PosTextSize.size1,
              width: PosTextSize.size1,
            )),
      ]);
    }

    double tipValue = (widget.orderModel.tipValue != null &&
            widget.orderModel.tipValue!.isNotEmpty)
        ? double.parse(widget.orderModel.tipValue!)
        : 0.0;

    if (taxList != null) {
      for (var element in taxList!) {
        taxAmount = (double.parse(taxAmount) +
                calculateTax(
                    amount: (total - discount).toString(), taxModel: element))
            .toString();
      }
    }

    var totalamount = widget.orderModel.deliveryCharge == null ||
            widget.orderModel.deliveryCharge!.isEmpty
        ? total + double.parse(taxAmount) - discount
        : total +
            double.parse(taxAmount) +
            double.parse(widget.orderModel.deliveryCharge!) +
            tipValue -
            discount;

    bytes += generator.row([
      PosColumn(
          text: 'Order Total',
          width: 5,
          styles: const PosStyles(
            align: PosAlign.left,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: '',
          width: 4,
          styles: const PosStyles(
            align: PosAlign.center,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
      PosColumn(
          text: totalamount.toDouble().toStringAsFixed(currencyModel!.decimal),
          width: 3,
          styles: const PosStyles(
            align: PosAlign.right,
            height: PosTextSize.size1,
            width: PosTextSize.size1,
          )),
    ]);

    bytes += generator.hr(ch: '=', linesAfter: 1);

    // ticket.feed(2);

    bytes += generator.text('Thank you!',
        styles: const PosStyles(align: PosAlign.center, bold: true));

    bytes += generator.cut();

    return bytes;
  }

  // Widget buildOrderSummaryCard() {

  //   return Padding(

  //     padding: const EdgeInsets.symmetric(horizontal: 8.0),

  //     child: Card(

  //       color: isDarkMode(context) ? Colors.grey.shade900 : Colors.white,

  //       child: Padding(

  //         padding: const EdgeInsets.all(16.0),

  //         child: Column(

  //           crossAxisAlignment: CrossAxisAlignment.start,

  //           children: [

  //             Text(

  //               'Order Summary',

  //               style: TextStyle(

  //                   fontWeight: FontWeight.w700,

  //                   fontSize: 20,

  //                   color: isDarkMode(context)

  //                       ? Colors.grey.shade200

  //                       : Colors.grey.shade700),

  //             ),

  //             SizedBox(height: 16),

  //             Text(

  //               '${widget.orderModel.vendor.title}',

  //               style: TextStyle(

  //                   fontWeight: FontWeight.w400,

  //                    fontSize: 16,

  //                   color: isDarkMode(context)

  //                       ? Colors.grey.shade200

  //                       : Colors.grey.shade700),

  //             ),

  //             SizedBox(height: 16),

  //             ListView.builder(

  //               physics: NeverScrollableScrollPhysics(),

  //               shrinkWrap: true,

  //               itemCount: widget.orderModel.products.length,

  //               itemBuilder: (context, index) => Padding(

  //                 padding: EdgeInsets.symmetric(vertical: 12),

  //                 child: Row(

  //                   children: [

  //                     Container(

  //                       color: isDarkMode(context)

  //                           ? Colors.grey.shade700

  //                           : Colors.grey.shade200,

  //                       padding: EdgeInsets.all(6),

  //                       child: Text(

  //                         '${widget.orderModel.products[index].quantity}',

  //                         style: TextStyle(

  //                             fontSize: 18, fontWeight: FontWeight.bold),

  //                       ),

  //                     ),

  //                     SizedBox(width: 16),

  //                     Text(

  //                       '${widget.orderModel.products[index].name}',

  //                       style: TextStyle(

  //                           color: isDarkMode(context)

  //                               ? Colors.grey.shade300

  //                               : Colors.grey.shade800,

  //                           fontWeight: FontWeight.w500,

  //                           fontSize: 18),

  //                     )

  //                   ],

  //                 ),

  //               ),

  //             ),

  //             SizedBox(height: 16),

  //             ListTile(

  //               title: Text(

  //                 'Total',

  //                 style: TextStyle(

  //                   fontSize: 25,

  //                   fontWeight: FontWeight.w700,

  //                   color: isDarkMode(context)

  //                       ? Colors.grey.shade300

  //                       : Colors.grey.shade700,

  //                 ),

  //               ),

  //               trailing: Text(

  //                 '\$${total.toStringAsFixed(decimal)}',

  //                 style: TextStyle(

  //                   fontSize: 25,

  //                   fontWeight: FontWeight.w400,

  //                   color: isDarkMode(context)

  //                       ? Colors.grey.shade300

  //                       : Colors.grey.shade700,

  //                 ),

  //               ),

  //             ),

  //           ],

  //         ),

  //       ),

  //     ),

  //   );

  // }

  // Map/Directions removed from this screen. Tracking happens in OrderTrackingPage.

  late Stream<User> driverStream;

  User? _driverModel = User();

  getDriver() async {
    driverStream =
        FireStoreUtils().getDriver(currentOrder!.driverID.toString());

    // Store the subscription and cancel previous one if exists
    _driverStreamSubscription?.cancel();
    _driverStreamSubscription = driverStream.listen((event) {
      debugPrint("--->${event.location.latitude} ${event.location.longitude}");

      _driverModel = event;

      // Client-side Directions disabled; tracking handled in OrderTrackingPage
      // getDirections();

      if (mounted) {
        setState(() {});
      }
    });
  }

  late Stream<OrderModel?> ordersFuture;

  OrderModel? currentOrder;

  getCurrentOrder() async {
    try {
      debugPrint("Fetching current order with ID: ${widget.orderModel.id}...");
      ordersFuture = FireStoreUtils().getOrderByID(widget.orderModel.id);

      // Store the subscription and cancel previous one if exists
      _ordersStreamSubscription?.cancel();
      _ordersStreamSubscription = ordersFuture.listen((event) {
        if (event == null) {
          debugPrint("Order not found for ID: ${widget.orderModel.id}");
          return;
        }

        debugPrint("Order fetched successfully: ${event.toJson()}");
        debugPrint("Driver ID in order: ${event.driverID}");

        if (mounted) {
          setState(() {
            currentOrder = event;

            if (event.driverID != null) {
              debugPrint("Driver ID is not null. Fetching driver details...");
              getDriver();
            } else {
              debugPrint(
                  "Driver ID is null. No driver assigned to this order.");
            }
          });
        }
      });
    } catch (e) {
      debugPrint("Error in getCurrentOrder: $e");
    }
  }

  getDirections() async {
    // No-op: directions were removed from this screen.
  }

  Widget buildDriverCard(OrderModel order) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        color: isDarkMode(context) ? const Color(DARK_BG_COLOR) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(children: [
                      TextSpan(
                          text:
                              '${order.driver?.firstName ?? 'Our driver'} is in ${order.driver?.carName ?? 'his car'}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isDarkMode(context)
                                  ? Colors.grey.shade200
                                  : Colors.grey.shade600,
                              fontSize: 17)),
                      TextSpan(
                        text:
                            '\nPlate No. ${_driverModel?.carNumber ?? 'No car number provided'}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: isDarkMode(context)
                              ? Colors.grey.shade200
                              : Colors.grey.shade800,
                        ),
                      ),
                    ]),
                  ),
                ),
                SizedBox(width: 8),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    displayCircleImage(
                        order.driver?.carPictureURL ?? '', 80, true),
                    Positioned.directional(
                        textDirection: Directionality.of(context),
                        start: -65,
                        child: displayCircleImage(
                            order.author.profilePictureURL, 80, true))
                  ],
                ),
              ]),
              const SizedBox(height: 16),
              ListTile(
                leading: FloatingActionButton(
                  onPressed: () async {
                    try {
                      if (widget.orderModel.driverID != null) {
                        // Fetch driver details
                        DocumentSnapshot<
                            Map<String,
                                dynamic>> driverDoc = await FirebaseFirestore
                            .instance
                            .collection(
                                'users') // Replace with your drivers collection
                            .doc(widget.orderModel.driverID)
                            .get();

                        if (driverDoc.exists) {
                          String? phoneNumber =
                              driverDoc.data()?['phoneNumber'];
                          if (phoneNumber != null && phoneNumber.isNotEmpty) {
                            String url = 'tel:$phoneNumber';
                            await launch(url);
                          } else {
                            debugPrint(
                                "Driver's phone number is not available.");
                          }
                        } else {
                          debugPrint(
                              "Driver information is not found in the database.");
                        }
                      } else {
                        debugPrint("Driver ID is null in the order model.");
                      }
                    } catch (e) {
                      debugPrint("Error fetching driver details: $e");
                    }
                  },
                  mini: true,
                  tooltip: widget.orderModel.driverID != null
                      ? 'Call Driver'
                      : 'Driver not assigned',
                  backgroundColor: widget.orderModel.driverID != null
                      ? Colors.green
                      : Colors.grey,
                  elevation: 0,
                  child: const Icon(Icons.phone, color: Color(0xFFFFFFFF)),
                ),
                title: GestureDetector(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDarkMode(context)
                          ? Colors.grey.shade700
                          : Colors.grey.shade300,
                      borderRadius:
                          const BorderRadius.all(Radius.circular(360)),
                    ),
                    child: Text(
                      'Send a message',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  onTap: () async {
                    try {
                      debugPrint("Fetching information for messaging...");
                      getFirebaseInformation((result) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ChatScreens(
                              customerName: result['customerName'],
                              restaurantName: result['restaurantName'],
                              orderId: result['orderId'],
                              restaurantId: result['restaurantId'],
                              customerId: result['customerId'],
                              customerProfileImage:
                                  result['customerProfileImage'],
                              restaurantProfileImage:
                                  result['restaurantProfileImage'],
                              token: result['token'],
                              chatType: result['chatType'],
                            ),
                          ),
                        );
                      });
                    } catch (e) {
                      debugPrint("Error in messaging functionality: $e");
                    }
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void getFirebaseInformation(Function(Map<String, dynamic>) callback) async {
    try {
      // Fetch the Order ID from the widget
      String orderId = widget.orderModel.id;
      debugPrint("Fetching details for Order ID: $orderId");

      // Fetch Order Details
      DocumentSnapshot<Map<String, dynamic>> orderDoc = await FirebaseFirestore
          .instance
          .collection('restaurant_orders') // Replace with your order collection
          .doc(orderId) // Use widget.orderModel.id dynamically
          .get();

      if (!orderDoc.exists) {
        debugPrint('Order not found for ID: $orderId');
        return;
      }

      Map<String, dynamic> orderData = orderDoc.data()!;
      String customerId = orderData['authorID']; // Adjust key if different
      String driverId = orderData['driverID'];

      debugPrint("Customer ID: $customerId, Driver ID: $driverId");

      // Fetch Customer Details
      DocumentSnapshot<Map<String, dynamic>> customerDoc =
          await FirebaseFirestore.instance
              .collection('users') // Replace with your users collection
              .doc(customerId)
              .get();

      if (!customerDoc.exists) {
        debugPrint('Customer not found for ID: $customerId');
        return;
      }

      Map<String, dynamic> customerData = customerDoc.data()!;
      String customerName =
          '${customerData['firstName']} ${customerData['lastName']}';
      String customerProfileImage = customerData['profilePictureURL'];

      // Fetch Driver Details
      DocumentSnapshot<Map<String, dynamic>> driverDoc = await FirebaseFirestore
          .instance
          .collection(
              'users') // Replace with your drivers collection if different
          .doc(driverId)
          .get();

      if (!driverDoc.exists) {
        debugPrint('Driver not found for ID: $driverId');
        return;
      }

      Map<String, dynamic> driverData = driverDoc.data()!;
      String driverName =
          '${driverData['firstName']} ${driverData['lastName']}';
      String driverProfileImage = driverData['profilePictureURL'];
      String driverToken = driverData['fcmToken'];

      debugPrint(
          "Customer Name: $customerName, Driver Name: $driverName, Order ID: $orderId");

      // Create a Map to pass the required data
      Map<String, dynamic> result = {
        'customerName': customerName,
        'restaurantName': driverName,
        'orderId': orderId,
        'restaurantId': driverId,
        'customerId': customerId,
        'customerProfileImage': customerProfileImage,
        'restaurantProfileImage': driverProfileImage,
        'token': driverToken,
        'chatType': 'Driver',
      };

      // Pass the result to the callback
      callback(result);
    } catch (e) {
      debugPrint('Error fetching information: $e');
    }
  }

  getPriceTotalText(CartProduct s) {
    double total = 0.0;

    if (s.extras_price != null &&
        s.extras_price!.isNotEmpty &&
        double.parse(s.extras_price!) != 0.0) {
      total += s.quantity * double.parse(s.extras_price!);
    }

    total += s.quantity * double.parse(s.price);

    return Text(
      amountShow(amount: total.toString()),
      style: TextStyle(fontSize: 20, color: Color(COLOR_PRIMARY)),
    );
  }

  /// Validates and transforms a CartProduct to ensure all required fields are present
  /// and properly formatted for database insertion
  CartProduct? _validateAndTransformCartProduct(CartProduct product) {
    try {
      // Validate required fields
      if (product.id.isEmpty ||
          product.name.isEmpty ||
          product.vendorID.isEmpty ||
          product.price.isEmpty) {
        debugPrint(
            "CartProduct missing required fields: id=${product.id}, name=${product.name}, vendorID=${product.vendorID}, price=${product.price}");
        return null;
      }

      // Ensure category_id is set (use product ID as fallback if missing)
      String categoryId = product.category_id ?? product.id.split('~').first;
      if (categoryId.isEmpty) {
        categoryId = product.id;
      }

      // Convert extras from List to String if needed
      String? extrasString;
      if (product.extras != null) {
        if (product.extras is List) {
          // Convert List to comma-separated string
          final extrasList =
              (product.extras as List).map((e) => e.toString()).toList();
          extrasString = extrasList.join(',');
        } else if (product.extras is String) {
          extrasString = product.extras as String;
        } else {
          extrasString = product.extras.toString();
        }
      }

      // Ensure variant_info is properly handled (can be VariantInfo object or null)
      dynamic variantInfo = product.variant_info;
      // If variant_info is a Map, it might need conversion, but CartProduct should handle it
      // The database will serialize it appropriately

      // Create validated and transformed CartProduct
      return CartProduct(
        id: product.id,
        category_id: categoryId,
        name: product.name,
        photo: product.photo.isNotEmpty
            ? product.photo
            : AppGlobal.placeHolderImage ?? '',
        price: product.price,
        discountPrice: product.discountPrice ?? "",
        vendorID: product.vendorID,
        quantity: product.quantity > 0
            ? product.quantity
            : 1, // Ensure quantity is at least 1
        extras_price: product.extras_price ?? "0.0",
        extras: extrasString,
        variant_info: variantInfo,
      );
    } catch (e) {
      debugPrint("Error validating CartProduct: $e");
      return null;
    }
  }

  String _getTimeUnit(String? estimatedTime) {
    if (estimatedTime == null || estimatedTime.isEmpty) {
      return " mins.";
    }

    try {
      List<String> timeParts = estimatedTime.split(":");
      if (timeParts.isEmpty) {
        return " mins.";
      }

      String hourPart = timeParts.first.trim();
      if (hourPart.isEmpty) {
        return " mins.";
      }

      int hours = int.parse(hourPart);
      return hours == 0 ? " mins." : " hr.";
    } catch (e) {
      debugPrint("Error parsing estimated time: $e");
      return " mins.";
    }
  }

  // Removed unused _getDriverRotation

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
                            ? const Color(DARK_BG_COLOR)
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
