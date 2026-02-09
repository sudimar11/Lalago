import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/widgets/refreshable_order_list.dart';
import 'package:foodie_driver/ui/home/orderdetails.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/ui/profile/ProfileScreen.dart';
import 'package:foodie_driver/ui/group_chat/GroupChatScreen.dart';
import 'package:foodie_driver/ui/wallet/wallet_detail_page.dart';
import 'package:foodie_driver/services/group_chat_service.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class OrdersBlankScreen extends StatefulWidget {
  const OrdersBlankScreen({Key? key}) : super(key: key);

  @override
  State<OrdersBlankScreen> createState() => _OrdersBlankScreenState();
}

class _OrdersBlankScreenState extends State<OrdersBlankScreen> {
  static const List<String> _activeStatuses = [
    'Driver Pending',
    'Driver Accepted',
    'Order Accepted',
    'Order Shipped',
    'In Transit',
    'Order Placed',
    'Driver Assigned',
  ];

  int _refreshNonce = 0;
  bool _hasShownOfflineDialog = false;
  bool _showSlowLoadRetry = false;
  Timer? _loadingTimeoutTimer;
  Stream<QuerySnapshot>? _ordersStream;
  String? _ordersStreamUserId;

  // Notification-related variables
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, String> _previousOrderStatuses = <String, String>{};
  StreamSubscription<QuerySnapshot>? _orderStatusSubscription;

  @override
  void initState() {
    super.initState();
    // #region agent log
    final user = MyAppState.currentUser;
    final userMap = user != null
        ? {
            'isOnline': user.isOnline,
            'suspended': user.suspended,
            'checkedInToday': (user as dynamic).checkedInToday,
            'userId': user.userID
          }
        : null;
    debugPrint('[DEBUG LOG] initState - screen initialized: $userMap');
    http
        .post(
            Uri.parse(
                'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'location': 'OrdersBlankScreen.dart:36',
              'message': 'initState - screen initialized',
              'data': {'user': userMap},
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'sessionId': 'debug-session',
              'runId': 'run1',
              'hypothesisId': 'C,E'
            }))
        .catchError((e) => http.Response('', 500));
    // #endregion
    _initializeLocalNotifications();
    _listenForOrderStatusChanges();
    _checkOfflineStatus();

    // Request permissions after UI is built to avoid blocking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission();
      _requestLocationPermission();
    });
  }

  void _requestNotificationPermission() async {
    // Request notification permission for Android 13+
    // Non-blocking - runs after UI loads
    if (mounted) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> _requestLocationPermission() async {
    // Request location permission for driver to receive orders
    // Non-blocking - runs after UI loads
    if (!mounted) return;

    try {
      var locationStatus = await Permission.location.request();
      if (locationStatus.isGranted) {
        var backgroundStatus = await Permission.locationAlways.request();
        if (backgroundStatus.isGranted) {
          debugPrint("✅ Background location granted");

          // Only enable background mode after confirmed permission
          Location location = Location();
          await location.enableBackgroundMode(enable: true);
        } else {
          debugPrint("❌ Background location denied.");
        }
      } else {
        debugPrint("❌ Location permission denied.");
      }
    } catch (e) {
      debugPrint("Error requesting location permission: $e");
    }
  }

  void _checkOfflineStatus() {
    // Use postFrameCallback to show dialog after build completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // #region agent log
      final user = MyAppState.currentUser;
      final userMap = user != null
          ? {
              'isOnline': user.isOnline,
              'suspended': user.suspended,
              'checkedInToday': (user as dynamic).checkedInToday,
              'userId': user.userID
            }
          : null;
      debugPrint(
          '[DEBUG LOG] _checkOfflineStatus called: $userMap, mounted=$mounted, hasShownDialog=$_hasShownOfflineDialog');
      http
          .post(
              Uri.parse(
                  'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'location': 'OrdersBlankScreen.dart:88',
                'message': '_checkOfflineStatus called',
                'data': {
                  'user': userMap,
                  'mounted': mounted,
                  'hasShownDialog': _hasShownOfflineDialog
                },
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'sessionId': 'debug-session',
                'runId': 'run1',
                'hypothesisId': 'A,C,D'
              }))
          .catchError((e) => http.Response('', 500));
      // #endregion
      // Only show offline dialog if user cannot receive orders
      // User can receive orders only if: checked in today AND not checked out AND online
      final isCheckedInToday =
          (MyAppState.currentUser! as dynamic).checkedInToday == true;
      final isCheckedOutToday =
          (MyAppState.currentUser! as dynamic).checkedOutToday == true;
      final canReceiveOrders =
          (isCheckedInToday && !isCheckedOutToday) &&
              (MyAppState.currentUser!.isOnline == true);

      if (mounted &&
          MyAppState.currentUser != null &&
          MyAppState.currentUser!.suspended != true &&
          !canReceiveOrders &&
          !_hasShownOfflineDialog) {
        // #region agent log
        debugPrint(
            '[DEBUG LOG] Showing offline dialog - condition met: isOnline=${MyAppState.currentUser!.isOnline}, checkedInToday=${(MyAppState.currentUser! as dynamic).checkedInToday}, checkedOutToday=${(MyAppState.currentUser! as dynamic).checkedOutToday}');
        http
            .post(
                Uri.parse(
                    'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'location': 'OrdersBlankScreen.dart:96',
                  'message': 'Showing offline dialog - condition met',
                  'data': {
                    'isOnline': MyAppState.currentUser!.isOnline,
                    'checkedInToday':
                        (MyAppState.currentUser! as dynamic).checkedInToday,
                    'checkedOutToday':
                        (MyAppState.currentUser! as dynamic).checkedOutToday,
                    'canReceiveOrders': canReceiveOrders
                  },
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'sessionId': 'debug-session',
                  'runId': 'run1',
                  'hypothesisId': 'B,D'
                }))
            .catchError((e) => http.Response('', 500));
        // #endregion
        _hasShownOfflineDialog = true;
        _showOfflineDialog();
      }
    });
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('You are Offline'),
          content: const Text(
            'You cannot receive orders unless you are checked in and online. Please check in to start receiving orders.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to Profile screen with navigation bar
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(
                      user: MyAppState.currentUser!,
                      showNavigationBar: true,
                    ),
                  ),
                );
              },
              child: const Text('Check In'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _loadingTimeoutTimer?.cancel();
    _orderStatusSubscription?.cancel();
    super.dispose();
  }

  void _recreateOrdersStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _ordersStream = _createOrdersStream(uid);
      _ordersStreamUserId = uid;
      _showSlowLoadRetry = false;
      _loadingTimeoutTimer?.cancel();
    }
  }

  void _initializeLocalNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings();
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: iosInitializationSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('Notification clicked: ${response.payload}');
        if (response.payload != null && response.payload!.isNotEmpty) {
          _handleNotificationTap(response.payload!);
        }
      },
    );
  }

  void _listenForOrderStatusChanges() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    // Listen to ALL orders assigned to this driver (no status filter)
    _orderStatusSubscription = firestore
        .collection('restaurant_orders')
        .where('driverID', isEqualTo: currentUserId)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;

        final orderId = change.doc.id;
        final currentStatus = (data['status'] ?? 'Unknown') as String;
        final previousStatus = _previousOrderStatuses[orderId];

        // Only notify if status actually changed (not on initial load)
        if (previousStatus != null && previousStatus != currentStatus) {
          _showOrderStatusChangeNotification(
            change.doc,
            previousStatus,
            currentStatus,
          );
        }

        // Update the tracked status
        _previousOrderStatuses[orderId] = currentStatus;
      }
    });
  }

  Future<void> _showOrderStatusChangeNotification(
    DocumentSnapshot doc,
    String previousStatus,
    String newStatus,
  ) async {
    final orderData = doc.data() as Map<String, dynamic>?;
    if (orderData == null) return;

    final orderId = doc.id;
    final author = (orderData['author'] ?? {}) as Map<String, dynamic>;
    final vendor = (orderData['vendor'] ?? {}) as Map<String, dynamic>;
    final customerName =
        '${author['firstName'] ?? 'Customer'} ${author['lastName'] ?? ''}'
            .trim();
    final restaurantName = (vendor['title'] ?? 'Restaurant').toString();
    final totalAmount = (orderData['totalAmount'] ??
            orderData['grand_total'] ??
            orderData['total'] ??
            '0')
        .toString();

    // Create a user-friendly status message
    String statusMessage = _getStatusChangeMessage(newStatus);

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'order_status_channel',
      'Order Status Updates',
      channelDescription: 'Shows notifications when order status changes.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final String bodyLines = [
      'Order #${orderId.substring(0, orderId.length > 8 ? 8 : orderId.length)}',
      'Status: $previousStatus → $newStatus',
      if (restaurantName.isNotEmpty) 'Restaurant: $restaurantName',
      if (customerName.trim().isNotEmpty) 'Customer: $customerName',
      'Amount: ₱$totalAmount',
    ].join('\n');

    // Use a unique notification ID based on order ID and timestamp
    final notificationId =
        orderId.hashCode + DateTime.now().millisecondsSinceEpoch % 10000;

    await flutterLocalNotificationsPlugin.show(
      notificationId,
      statusMessage,
      bodyLines,
      details,
      payload: orderId,
    );
  }

  // Helper method to create user-friendly status messages
  String _getStatusChangeMessage(String status) {
    switch (status) {
      case 'Order Placed':
        return '📦 New Order Placed';
      case 'Order Accepted':
        return '✅ Order Accepted by Restaurant';
      case 'Driver Assigned':
        return '🚗 Order Assigned to You';
      case 'Driver Pending':
        return '⏳ Waiting for Your Response';
      case 'Driver Accepted':
        return '✅ Order Accepted';
      case 'Driver Rejected':
        return '❌ Order Rejected';
      case 'Order Shipped':
        return '📤 Order Ready for Pickup';
      case 'In Transit':
        return '🚚 Order In Transit';
      case 'Order Completed':
        return '🎉 Order Completed';
      case 'Order Rejected':
        return '❌ Order Rejected by Restaurant';
      default:
        return '📋 Order Status Updated';
    }
  }

  // Build suspension warning card (full screen version)
  Widget _buildSuspensionWarningCard() {
    final user = MyAppState.currentUser;
    if (user == null || user.suspended != true) {
      return const SizedBox.shrink();
    }

    String suspensionMessage = 'Your account has been temporarily suspended.';
    if (user.suspensionDate != null && user.suspensionDate! > 0) {
      suspensionMessage +=
          ' Suspension period: ${user.suspensionDate} day${user.suspensionDate! > 1 ? 's' : ''}.';
    }

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.orange.shade300,
                width: 2,
              ),
            ),
            color: isDarkMode(context)
                ? Color(DARK_CARD_BG_COLOR)
                : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Account Suspended',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context)
                          ? Colors.orange.shade300
                          : Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    suspensionMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDarkMode(context)
                          ? Colors.grey.shade300
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Build offline warning card
  Widget _buildOfflineWarningCard() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.red.shade300,
                width: 2,
              ),
            ),
            color: isDarkMode(context)
                ? Color(DARK_CARD_BG_COLOR)
                : Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.offline_bolt,
                    size: 64,
                    color: Colors.red.shade700,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You are Offline',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context)
                          ? Colors.red.shade300
                          : Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You cannot receive orders unless you are checked in and online. Please check in to start receiving orders.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDarkMode(context)
                          ? Colors.grey.shade300
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Navigate to Profile screen with navigation bar
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfileScreen(
                            user: MyAppState.currentUser!,
                            showNavigationBar: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Check In Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRemittanceRequiredCard() {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.orange.shade300,
                width: 2,
              ),
            ),
            color: isDarkMode(context)
                ? Color(DARK_CARD_BG_COLOR)
                : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 64,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Daily Remittance Required',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode(context)
                          ? Colors.orange.shade300
                          : Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Please remit your credit wallet to continue receiving '
                    'orders.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDarkMode(context)
                          ? Colors.grey.shade300
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Scaffold(
                            appBar: AppBar(
                              title: const Text('Credit Wallet'),
                              backgroundColor: Color(COLOR_PRIMARY),
                              foregroundColor: Colors.white,
                            ),
                            body: const WalletDetailPage(
                              walletType: 'credit',
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('Go to Wallet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(COLOR_PRIMARY),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Handle notification tap - navigate to order details
  Future<void> _handleNotificationTap(String orderId) async {
    try {
      // Fetch the order from Firestore
      final orderDoc = await FirebaseFirestore.instance
          .collection('restaurant_orders')
          .doc(orderId)
          .get();

      if (!orderDoc.exists) {
        debugPrint('Order not found: $orderId');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Order not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final orderData = orderDoc.data();
      if (orderData == null) {
        debugPrint('Order data is null: $orderId');
        return;
      }

      // Add the order ID to the data map
      final orderMap = Map<String, dynamic>.from(orderData);
      orderMap['id'] = orderId;
      orderMap['orderId'] = orderId;

      // Navigate to order details page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OrderDetailsPage(order: orderMap),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error navigating to order details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Stream<QuerySnapshot> _createOrdersStream(String currentUserId) {
    return FirebaseFirestore.instance
        .collection('restaurant_orders')
        .where('status', whereIn: _activeStatuses)
        .where('driverID', isEqualTo: currentUserId)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final remittanceService =
        context.watch<RemittanceEnforcementService>();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null || currentUserId.isEmpty) {
      return Scaffold(
        backgroundColor:
            isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
        body: Center(
          child: Text(
            'No current order',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    // #region agent log
    if (_ordersStream == null || _ordersStreamUserId != currentUserId) {
      _ordersStream = _createOrdersStream(currentUserId);
      _ordersStreamUserId = currentUserId;
      try {
        final f = File(
            '/Users/sudimard/Downloads/Lalago/.cursor/debug.log');
        f.writeAsStringSync(
            '${jsonEncode(<String, dynamic>{"location": "OrdersBlankScreen.dart:build", "message": "orders stream created", "data": {"userId": currentUserId, "streamWasNull": _ordersStream == null}, "timestamp": DateTime.now().millisecondsSinceEpoch, "sessionId": "debug-session", "hypothesisId": "H1"})}\n',
            mode: FileMode.append);
      } catch (_) {}
    }
    // #endregion

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            isDarkMode(context) ? Colors.black : Colors.blueGrey.shade900,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<DocumentSnapshot>(
                stream: firestore
                    .collection('users')
                    .doc(currentUserId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Performance: --',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const Text(
                      'Performance: N/A',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  final data =
                      snapshot.data!.data() as Map<String, dynamic>? ?? {};
                  final performance = data['driver_performance'];

                  double? perfValue;
                  if (performance is num) {
                    perfValue = performance.toDouble();
                  }

                  final perfText = perfValue != null
                      ? '${perfValue.toStringAsFixed(0)}%'
                      : 'N/A';

                  // Map performance to tier label:
                  // < 75  -> Silver
                  // < 85  -> Platinum
                  // >= 85 -> Gold
                  String tierLabel = '';
                  if (perfValue != null) {
                    if (perfValue < 75) {
                      tierLabel = 'Silver';
                    } else if (perfValue < 85) {
                      tierLabel = 'Platinum';
                    } else {
                      tierLabel = 'Gold';
                    }
                  }

                  final tierSuffix =
                      tierLabel.isNotEmpty ? ' ($tierLabel)' : '';

                  return Text(
                    'Performance: $perfText$tierSuffix',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              StreamBuilder<QuerySnapshot>(
                stream: firestore
                    .collection('restaurant_orders')
                    .where('status', whereIn: _activeStatuses)
                    .where('driverID', isEqualTo: currentUserId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Orders: --',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Text(
                      'Orders: --',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  final orderCount = snapshot.data?.docs.length ?? 0;
                  return Text(
                    'Orders: $orderCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              StreamBuilder<QuerySnapshot>(
                stream: () {
                  final now = DateTime.now();
                  final startOfDay = DateTime(now.year, now.month, now.day);
                  final startOfTomorrow =
                      startOfDay.add(const Duration(days: 1));

                  return firestore
                      .collection('restaurant_orders')
                      .where('status', isEqualTo: 'Order Completed')
                      .where('driverID', isEqualTo: currentUserId)
                      .where('deliveredAt',
                          isGreaterThanOrEqualTo:
                              Timestamp.fromDate(startOfDay))
                      .where('deliveredAt',
                          isLessThan: Timestamp.fromDate(startOfTomorrow))
                      .snapshots();
                }(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Completed: --',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Text(
                      'Completed: --',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  final completedCount = snapshot.data?.docs.length ?? 0;
                  return Text(
                    'Completed: $completedCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              StreamBuilder<QuerySnapshot>(
                stream: firestore
                    .collection('restaurant_orders')
                    .where('status', isEqualTo: 'Driver Rejected')
                    .where('driverID', isEqualTo: currentUserId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Rejected: --',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Text(
                      'Rejected: --',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }

                  final rejectedCount = snapshot.data?.docs.length ?? 0;
                  return Text(
                    'Rejected: $rejectedCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        centerTitle: true,
      ),
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Orders list
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _ordersStream!,
                    builder: (context, snapshot) {
                      // #region agent log
                      final rawCheckedIn =
                          (MyAppState.currentUser as dynamic)?.checkedInToday;
                      final rawCheckedOut =
                          (MyAppState.currentUser as dynamic)?.checkedOutToday;
                      final rawOnline = MyAppState.currentUser?.isOnline;
                      // Only show offline card when we have explicit evidence
                      // user cannot receive; null (unloaded) = show list/loading
                      final cannotReceiveOrders =
                          (rawCheckedIn == false) ||
                              (rawCheckedOut == true) ||
                              (rawOnline == false);
                      final canReceiveOrders = !cannotReceiveOrders;
                      final isCheckedInToday = rawCheckedIn == true;
                      final isCheckedOutToday = rawCheckedOut == true;
                      final branch = remittanceService.isBlockedByRemittance
                          ? 'remittance'
                          : (MyAppState.currentUser?.suspended == true)
                              ? 'suspended'
                              : (!canReceiveOrders)
                                  ? 'offline'
                                  : (snapshot.connectionState ==
                                          ConnectionState.waiting)
                                      ? 'waiting'
                                      : (snapshot.hasError)
                                          ? 'error'
                                          : ((snapshot.data?.docs ?? []).isEmpty)
                                              ? 'empty'
                                              : 'list';
                      // Log so we see in release logcat why order screen shows loading/list/error.
                      print(
                          '📋 Orders screen: branch=$branch '
                          'conn=${snapshot.connectionState} '
                          'hasData=${snapshot.hasData} hasError=${snapshot.hasError} '
                          'docs=${snapshot.data?.docs.length ?? 0}');
                      // #region agent log
                      try {
                        final f = File(
                            '/Users/sudimard/Downloads/Lalago/.cursor/debug.log');
                        f.writeAsStringSync(
                            '${jsonEncode(<String, dynamic>{"location": "OrdersBlankScreen.dart:StreamBuilder", "message": "branch", "data": {"connectionState": snapshot.connectionState.toString(), "hasData": snapshot.hasData, "hasError": snapshot.hasError, "branch": branch, "docsLength": snapshot.data?.docs.length ?? 0}, "timestamp": DateTime.now().millisecondsSinceEpoch, "sessionId": "debug-session", "hypothesisId": "H2,H3,H4"})}\n',
                            mode: FileMode.append);
                      } catch (_) {}
                      // #endregion
                      http
                          .post(
                            Uri.parse(
                                'http://127.0.0.1:7244/ingest/c9ab929b-94d3-40bd-8785-7deb40c047f7'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({
                              'location': 'OrdersBlankScreen.dart:builder',
                              'message': 'StreamBuilder branch',
                              'data': {
                                'connectionState':
                                    snapshot.connectionState.toString(),
                                'hasData': snapshot.hasData,
                                'hasError': snapshot.hasError,
                                'remittanceBlocked':
                                    remittanceService.isBlockedByRemittance,
                                'suspended':
                                    MyAppState.currentUser?.suspended,
                                'canReceiveOrders': canReceiveOrders,
                                'isCheckedInToday': isCheckedInToday,
                                'isCheckedOutToday': isCheckedOutToday,
                                'isOnline': MyAppState.currentUser?.isOnline,
                                'branch': branch,
                                'docsLength':
                                    snapshot.data?.docs.length ?? 0,
                              },
                              'timestamp':
                                  DateTime.now().millisecondsSinceEpoch,
                                'sessionId': 'debug-session',
                              'runId': 'run1',
                              'hypothesisId': 'A,B,C,D,E',
                            }),
                          )
                          .catchError((_) => http.Response('', 500));
                      // #endregion
                      if (remittanceService.isBlockedByRemittance) {
                        return _buildRemittanceRequiredCard();
                      }
                      if (MyAppState.currentUser?.suspended == true) {
                        return _buildSuspensionWarningCard();
                      }

                      // Check if user is offline
                      // #region agent log
                      final user = MyAppState.currentUser;
                      if (user != null) {
                        debugPrint(
                            '[DEBUG LOG] Build - checking offline status: isOnline=${user.isOnline}, checkedInToday=${(user as dynamic).checkedInToday}, suspended=${user.suspended}');
                        http
                            .post(
                                Uri.parse(
                                    'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'location': 'OrdersBlankScreen.dart:767',
                                  'message': 'Build - checking offline status',
                                  'data': {
                                    'isOnline': user.isOnline,
                                    'checkedInToday':
                                        (user as dynamic).checkedInToday,
                                    'suspended': user.suspended
                                  },
                                  'timestamp':
                                      DateTime.now().millisecondsSinceEpoch,
                                  'sessionId': 'debug-session',
                                  'runId': 'run1',
                                  'hypothesisId': 'A,B,C'
                                }))
                            .catchError((e) => http.Response('', 500));
                      }
                      // #endregion
                      // Only show offline card if user cannot receive orders
                      // (isCheckedInToday, isCheckedOutToday, canReceiveOrders already computed above for logging)

                      if (!canReceiveOrders) {
                        // #region agent log
                        debugPrint(
                            '[DEBUG LOG] Build - displaying offline card: isOnline=${MyAppState.currentUser!.isOnline}, checkedInToday=$isCheckedInToday, checkedOutToday=$isCheckedOutToday');
                        http
                            .post(
                                Uri.parse(
                                    'http://127.0.0.1:7242/ingest/65d50706-9e3e-423b-80b8-1c248fbe9093'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'location': 'OrdersBlankScreen.dart:773',
                                  'message': 'Build - displaying offline card',
                                  'data': {
                                    'isOnline':
                                        MyAppState.currentUser!.isOnline,
                                    'checkedInToday': isCheckedInToday,
                                    'checkedOutToday': isCheckedOutToday,
                                    'canReceiveOrders': canReceiveOrders
                                  },
                                  'timestamp':
                                      DateTime.now().millisecondsSinceEpoch,
                                  'sessionId': 'debug-session',
                                  'runId': 'run1',
                                  'hypothesisId': 'B,D'
                                }))
                            .catchError((e) => http.Response('', 500));
                        // #endregion
                        return _buildOfflineWarningCard();
                      }

                      if (snapshot.connectionState != ConnectionState.waiting) {
                        _loadingTimeoutTimer?.cancel();
                        _loadingTimeoutTimer = null;
                        _showSlowLoadRetry = false;
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        if (!_showSlowLoadRetry) {
                          _loadingTimeoutTimer ??= Timer(
                            const Duration(seconds: 15),
                            () {
                              if (mounted) {
                                setState(() {
                                  _showSlowLoadRetry = true;
                                  _loadingTimeoutTimer = null;
                                });
                              }
                            },
                          );
                          return const Center(
                              child: CircularProgressIndicator.adaptive());
                        }
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Taking longer than usual.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() => _recreateOrdersStream());
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Error loading orders.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(height: 12),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() => _recreateOrdersStream());
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? const [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.inbox_outlined,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No orders at the moment',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'New orders will appear here when assigned to you.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return RefreshableOrderList(
                        docs: docs,
                        onRefresh: () {
                          setState(() => _recreateOrdersStream());
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Floating chat button with unread badge
          Positioned(
            bottom: 16,
            right: 16,
            child: StreamBuilder<int>(
              stream: GroupChatService.getUnreadCountStream(),
              builder: (context, snapshot) {
                final unreadCount = snapshot.data ?? 0;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    FloatingActionButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GroupChatScreen(),
                          ),
                        );
                      },
                      backgroundColor: Color(COLOR_PRIMARY),
                      child: const Icon(Icons.chat, color: Colors.white),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
