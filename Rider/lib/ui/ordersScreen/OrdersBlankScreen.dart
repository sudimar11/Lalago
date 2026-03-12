import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:foodie_driver/constants.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/widgets/refreshable_order_list.dart';
import 'package:foodie_driver/ui/home/orderdetails.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/services/FirebaseHelper.dart';
import 'package:foodie_driver/services/driver_performance_service.dart';
import 'package:foodie_driver/services/performance_tier_helper.dart';
import 'package:foodie_driver/userPrefrence.dart';
import 'package:intl/intl.dart';
import 'package:foodie_driver/ui/wallet/wallet_detail_page.dart';
import 'package:foodie_driver/model/User.dart';
import 'package:foodie_driver/services/remittance_enforcement_service.dart';
import 'package:foodie_driver/services/rider_preset_location_service.dart';
import 'package:foodie_driver/services/food_ready_highlight_service.dart';
import 'package:foodie_driver/services/user_listener_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'package:foodie_driver/services/audio_service.dart';
import 'package:foodie_driver/services/order_service.dart';
import 'package:foodie_driver/services/array_validation_service.dart';
import 'package:foodie_driver/ui/pautos/my_pautos_orders_screen.dart';
import 'package:foodie_driver/ui/profile/zone_browser_screen.dart';

class OrdersBlankScreen extends StatefulWidget {
  const OrdersBlankScreen({Key? key}) : super(key: key);

  @override
  State<OrdersBlankScreen> createState() => _OrdersBlankScreenState();
}

class _OrdersBlankScreenState extends State<OrdersBlankScreen> {
  static const List<String> _activeStatuses = [
    'Driver Assigned',
    'Driver Accepted',
    'Order Accepted',
    'Order Shipped',
    'In Transit',
    'Order Placed',
  ];

  int _refreshNonce = 0;
  bool _hasShownOfflineDialog = false;
  double _sliderPosition = 0.0;
  bool _isSavingGoOnline = false;
  Stream<QuerySnapshot>? _ordersStream;
  String? _ordersStreamUserId;

  // Notification-related variables
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, String> _previousOrderStatuses = <String, String>{};
  StreamSubscription<QuerySnapshot>? _orderStatusSubscription;

  // New order badge: orders we haven't seen before
  final Set<String> _newOrderIds = {};
  final Set<String> _lastSeenOrderIds = {};
  final Map<String, Timer> _newOrderTimers = {};

  @override
  void initState() {
    super.initState();
    _initializeLocalNotifications();
    _listenForOrderStatusChanges();
    _checkOfflineStatus();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      ArrayValidationService.validate(uid);
    }

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
      // Only show offline dialog if user cannot receive orders.
      final canReceiveOrders =
          MyAppState.currentUser!.isOnline == true &&
              (MyAppState.currentUser!.riderAvailability == 'available' ||
                  MyAppState.currentUser!.riderAvailability ==
                      'on_delivery');

      // Slider card is shown in body when !canReceiveOrders; no dialog.
      if (mounted &&
          MyAppState.currentUser != null &&
          MyAppState.currentUser!.suspended != true &&
          !canReceiveOrders) {
        _hasShownOfflineDialog = true;
      }
    });
  }

  Future<void> _showLocationPickerThenGoOnline() async {
    if (MyAppState.currentUser == null) return;
    setState(() => _sliderPosition = 0.0);

    try {
      final savedId = MyAppState.currentUser!.selectedPresetLocationId;
      if (savedId != null && savedId.trim().isNotEmpty) {
        final preset =
            await RiderPresetLocationService.getPresetById(savedId);
        if (preset != null && mounted) {
          MyAppState.currentUser!.location = UserLocation(
            latitude: preset.latitude,
            longitude: preset.longitude,
          );
          MyAppState.currentUser!.locationUpdatedAt = Timestamp.now();
          await _slideGoOnline();
          return;
        }
        MyAppState.currentUser!.selectedPresetLocationId = null;
      }

      final presets =
          await RiderPresetLocationService.getPresetLocations();
      if (!mounted) return;
      if (presets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No preset locations. Contact admin.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final selected = await showModalBottomSheet<
          RiderPresetLocationData>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (_, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Saan ka mag-aantay ng order?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: presets.length,
                  itemBuilder: (_, i) {
                    final p = presets[i];
                    return ListTile(
                      leading: const Icon(Icons.place),
                      title: Text(p.name),
                      subtitle: Text(
                        '${p.latitude.toStringAsFixed(5)}, '
                        '${p.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

      if (selected == null || !mounted) return;

      MyAppState.currentUser!.location = UserLocation(
        latitude: selected.latitude,
        longitude: selected.longitude,
      );
      MyAppState.currentUser!.locationUpdatedAt = Timestamp.now();
      MyAppState.currentUser!.selectedPresetLocationId = selected.id;

      await FirebaseFirestore.instance
          .collection('service_areas')
          .doc(selected.id)
          .update({
        'assignedDriverIds': FieldValue.arrayUnion(
          [MyAppState.currentUser!.userID],
        ),
      });

      if (savedId != null &&
          savedId.isNotEmpty &&
          savedId != selected.id) {
        await FirebaseFirestore.instance
            .collection('service_areas')
            .doc(savedId)
            .update({
          'assignedDriverIds': FieldValue.arrayRemove(
            [MyAppState.currentUser!.userID],
          ),
        });
      }

      await _slideGoOnline();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load locations: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _slideGoOnline() async {
    if (MyAppState.currentUser == null) return;
    if (_isSavingGoOnline) return;
    _isSavingGoOnline = true;
    setState(() {});

    try {
      final now = DateTime.now();
      final timeString = DateFormat('h:mm a').format(now);
      final todayString = DateFormat('yyyy-MM-dd').format(now);

      MyAppState.currentUser!.isOnline = true;
      MyAppState.currentUser!.isActive = true;
      MyAppState.currentUser!.active = true;
      UserListenerService.instance.markLocalMutation();

      try {
        final absentDaysMarked =
            await DriverPerformanceService.detectAndMarkMissingAbsences(
                MyAppState.currentUser!.userID);
        if (absentDaysMarked > 0 && mounted) {
          final pointsDeducted =
              absentDaysMarked * DriverPerformanceService.ADJUSTMENT_ABSENT;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$absentDaysMarked absent day(s) detected and marked. '
                'Performance deducted: ${pointsDeducted.toStringAsFixed(1)} points',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        debugPrint(
            'Error detecting missing absences during slide-go-online: $e');
      }

      if (MyAppState.currentUser!.checkInTime != null &&
          MyAppState.currentUser!.checkInTime!.isNotEmpty) {
        final newPerformance =
            await DriverPerformanceService.applyCheckInAdjustment(
                MyAppState.currentUser!.userID,
                MyAppState.currentUser!.checkInTime!,
                timeString);
        MyAppState.currentUser!.driverPerformance = newPerformance;
      }

      await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
      await OrderService.updateRiderStatus();
      await FireStoreUtils.touchLastActivity(MyAppState.currentUser!.userID);
      UserPreference.setLastCheckInDate(date: todayString);

      if (mounted) {
        setState(() {
          _sliderPosition = 0.0;
          _isSavingGoOnline = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Successfully went online!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sliderPosition = 0.0;
          _isSavingGoOnline = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to go online: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _updateNewOrderIds(List<QueryDocumentSnapshot> docs) {
    final currentIds = docs.map((d) => d.id).toSet();
    final newIds = currentIds.difference(_lastSeenOrderIds);
    if (newIds.isNotEmpty && mounted) {
      setState(() {
        for (final id in newIds) {
          _newOrderIds.add(id);
          _newOrderTimers[id]?.cancel();
          _newOrderTimers[id] = Timer(const Duration(seconds: 30), () {
            if (mounted) {
              setState(() {
                _newOrderIds.remove(id);
                _newOrderTimers.remove(id);
              });
            }
          });
        }
        _lastSeenOrderIds.addAll(currentIds);
      });
    } else if (currentIds.isNotEmpty) {
      _lastSeenOrderIds.addAll(currentIds);
    }
  }

  @override
  void dispose() {
    _orderStatusSubscription?.cancel();
    for (final t in _newOrderTimers.values) {
      t.cancel();
    }
    _newOrderTimers.clear();
    super.dispose();
  }

  void _recreateOrdersStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _ordersStream = _createOrdersStream(uid);
      _ordersStreamUserId = uid;
    }
  }

  bool _shouldShowWorkAreaBanner() {
    final user = MyAppState.currentUser;
    if (user == null) return false;
    final canReceive = user.isOnline == true &&
        (user.riderAvailability == 'available' ||
            user.riderAvailability == 'on_delivery');
    return canReceive &&
        !RiderPresetLocationService.hasValidWorkArea(user);
  }

  Widget _buildWorkAreaBanner() {
    final bgColor = isDarkMode(context)
        ? Colors.orange.shade900.withValues(alpha: 0.3)
        : Colors.orange.shade100;
    final fgColor = isDarkMode(context)
        ? Colors.orange.shade200
        : Colors.orange.shade900;
    return Material(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: fgColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "You don't have a work area set. Select one to receive orders.",
                style: TextStyle(fontSize: 14, color: fgColor),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ZoneBrowserScreen(),
                  ),
                );
              },
              child: const Text('Select Work Area'),
            ),
          ],
        ),
      ),
    );
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
    if (newStatus == 'Order Shipped') {
      AudioService.instance.playNewOrderSound(orderId: orderId);
    }
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

  static const double _sliderTrackWidth = 280;
  static const double _sliderTrackHeight = 48;
  static const double _sliderKnobSize = 44;
  static const double _sliderTriggerThreshold = 0.85;

  Widget _buildSlideToGoOnlineCard() {
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
                  const SizedBox(height: 8),
                  Text(
                    'Slide to go online to receive orders.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDarkMode(context)
                          ? Colors.grey.shade300
                          : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onHorizontalDragUpdate: _isSavingGoOnline
                        ? null
                        : (details) {
                            final maxDrag =
                                _sliderTrackWidth - _sliderKnobSize - 4;
                            final delta = details.delta.dx / maxDrag;
                            setState(() {
                              _sliderPosition =
                                  (_sliderPosition + delta).clamp(0.0, 1.0);
                              if (_sliderPosition >= _sliderTriggerThreshold) {
                                _showLocationPickerThenGoOnline();
                              }
                            });
                          },
                    onHorizontalDragEnd: _isSavingGoOnline
                        ? null
                        : (_) {
                            if (_sliderPosition < _sliderTriggerThreshold) {
                              setState(() => _sliderPosition = 0.0);
                            }
                          },
                    child: SizedBox(
                      width: _sliderTrackWidth,
                      height: _sliderTrackHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: _sliderTrackWidth,
                            height: _sliderTrackHeight,
                            decoration: BoxDecoration(
                              color: isDarkMode(context)
                                  ? Colors.grey.shade700
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(
                                  _sliderTrackHeight / 2),
                            ),
                          ),
                          Positioned(
                            left: 2 +
                                (_sliderPosition *
                                    (_sliderTrackWidth -
                                        _sliderKnobSize -
                                        4)),
                            top: (_sliderTrackHeight - _sliderKnobSize) / 2,
                            child: IgnorePointer(
                              ignoring: _isSavingGoOnline,
                              child: Container(
                                width: _sliderKnobSize,
                                height: _sliderKnobSize,
                                decoration: BoxDecoration(
                                  color: _isSavingGoOnline
                                      ? Colors.grey
                                      : Color(COLOR_ACCENT),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: _isSavingGoOnline
                                    ? const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: CircularProgressIndicator
                                            .adaptive(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        Icons.chevron_right,
                                        color: Colors.white,
                                        size: _sliderKnobSize * 0.6,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isSavingGoOnline)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Saving...',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode(context)
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
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
        body: const Center(
          child: CircularProgressIndicator.adaptive(),
        ),
      );
    }

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    if (_ordersStream == null || _ordersStreamUserId != currentUserId) {
      _ordersStream = _createOrdersStream(currentUserId);
      _ordersStreamUserId = currentUserId;
    }

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

                  String tierLabel = '';
                  if (perfValue != null) {
                    tierLabel = PerformanceTierHelper.getTier(
                      perfValue,
                    ).name;
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
              Text(
                MyAppState.currentUser?.riderDisplayStatus ?? '⚪ Offline',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
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
        actions: [
          IconButton(
            tooltip: 'My PAUTOS Orders',
            icon: const Icon(Icons.shopping_bag_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MyPautosOrdersScreen(),
                ),
              );
            },
          ),
        ],
        centerTitle: true,
      ),
      backgroundColor:
          isDarkMode(context) ? Color(DARK_VIEWBG_COLOR) : Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
              children: [
                if (_shouldShowWorkAreaBanner()) _buildWorkAreaBanner(),
                // Orders list
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _ordersStream!,
                    builder: (context, snapshot) {
                      final canReceiveOrders =
                          MyAppState.currentUser?.riderAvailability ==
                              'available' ||
                          MyAppState.currentUser?.riderAvailability ==
                              'on_delivery';
                      if (remittanceService.isBlockedByRemittance) {
                        return _buildRemittanceRequiredCard();
                      }
                      if (MyAppState.currentUser?.suspended == true) {
                        return _buildSuspensionWarningCard();
                      }

                      if (!canReceiveOrders) {
                        return _buildSlideToGoOnlineCard();
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator.adaptive());
                      }

                      if (snapshot.hasError) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text(
                              'Error loading orders.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? const [];
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _updateNewOrderIds(docs);
                      });
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

                      return ValueListenableBuilder<String?>(
                        valueListenable:
                            FoodReadyHighlightService.instance.highlightedOrderId,
                        builder: (context, highlightedId, _) {
                          final highlightedIds = highlightedId != null
                              ? {highlightedId}
                              : <String>{};
                          return RefreshableOrderList(
                            docs: docs,
                            onRefresh: () {
                              final user = MyAppState.currentUser;
                              if (user != null) {
                                FireStoreUtils.touchLastActivity(
                                    user.userID);
                              }
                              if (mounted) {
                                setState(() => _recreateOrdersStream());
                              }
                            },
                            newOrderIds: _newOrderIds,
                            highlightedOrderIds: highlightedIds,
                            onOrderViewed: (orderId) {
                              FoodReadyHighlightService.instance
                                  .clearHighlight(orderId);
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
