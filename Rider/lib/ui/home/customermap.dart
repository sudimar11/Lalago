import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:foodie_driver/main.dart';
import 'package:foodie_driver/services/helper.dart';
import 'package:foodie_driver/model/conversation_model.dart';
import 'package:foodie_driver/ui/chat_screen/chat_screen.dart';
import 'package:foodie_driver/ui/home/confirm_delivery_summary_page.dart';

class CustomerDriverLocationPage extends StatefulWidget {
  final String orderId;

  const CustomerDriverLocationPage({
    Key? key,
    required this.orderId,
  }) : super(key: key);

  @override
  _CustomerDriverLocationPageState createState() =>
      _CustomerDriverLocationPageState();
}

class _CustomerDriverLocationPageState
    extends State<CustomerDriverLocationPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Completer<GoogleMapController> _controller = Completer();

  Timer? _timer;
  LatLng? _currentPosition;
  LatLng? _customerPosition;

  String _customerName = 'Customer';
  String _customerPhoneNumber = 'No phone number';
  String? _customerPhotoUrl;
  Map<String, dynamic>? _defaultAddress;

  BitmapDescriptor? _driverIcon;
  bool _loading = true;

  int _unreadCount = 0;
  int _previousUnreadCount = -1;
  List<StreamSubscription> _subscriptions = [];
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  String? _customerId;
  String? _customerFcmToken;

  @override
  void initState() {
    super.initState();
    _loadDriverIcon();
    _initializeNotifications();
    _fetchCustomerData().whenComplete(() {
      _startPeriodicDriverUpdates();
      if (_customerId != null) {
        _setupUnreadCountListener();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    
    // Properly dispose map controller
    _controller.future.then((controller) {
      controller.dispose();
    }).catchError((_) => Future<void>.value());
    
    super.dispose();
  }

  Future<void> _loadDriverIcon() async {
    try {
      _driverIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/drivericon.png',
      );
    } catch (e) {
      log('Error loading driver icon: $e');
    }
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(initSettings);

    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'chat_messages',
        'Chat Messages',
        description: 'Notifications for new chat messages',
        importance: Importance.high,
      );
      final androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.createNotificationChannel(channel);
    } catch (e) {
      // Channel creation failed, but notifications may still work
    }
  }

  void _setupUnreadCountListener() {
    final currentDriverId = MyAppState.currentUser?.userID;
    if (currentDriverId == null || widget.orderId.isEmpty) return;

    final lastMessageStream = _firestore
        .collection('chat_driver')
        .doc(widget.orderId)
        .collection('thread')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots();

    _subscriptions.add(lastMessageStream.listen((lastMessageSnapshot) {
      bool isUnread = false;
      if (lastMessageSnapshot.docs.isNotEmpty) {
        try {
          final lastMessageData = lastMessageSnapshot.docs.first.data();
          final lastMessage = ConversationModel.fromJson(lastMessageData);
          isUnread = lastMessage.senderId != currentDriverId;
        } catch (e) {
          log('Error parsing message: $e');
        }
      }

      final previousCount = _unreadCount;
      final newCount = isUnread ? 1 : 0;

      if (mounted) {
        setState(() {
          _unreadCount = newCount;
        });

        if (newCount > previousCount && _previousUnreadCount >= 0) {
          _showUnreadMessageNotification();
        }
        _previousUnreadCount = previousCount;
      }
    }));
  }

  Future<void> _showUnreadMessageNotification() async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'chat_messages',
        'Chat Messages',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        'New Message',
        '$_customerName sent you a message',
        notificationDetails,
      );
    } catch (e) {
      // Handle error silently
    }
  }

  void _openChat() {
    try {
      final currentDriverId = MyAppState.currentUser?.userID ??
          auth.FirebaseAuth.instance.currentUser?.uid;
      if (currentDriverId == null) return;

      if (_customerId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer information not available'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final driverName =
          '${MyAppState.currentUser?.firstName ?? ''} ${MyAppState.currentUser?.lastName ?? ''}';
      final driverProfileImage =
          MyAppState.currentUser?.profilePictureURL ?? '';

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreens(
            orderId: widget.orderId,
            customerId: _customerId!,
            customerName: _customerName,
            customerProfileImage: _customerPhotoUrl ?? '',
            restaurantId: currentDriverId,
            restaurantName: driverName,
            restaurantProfileImage: driverProfileImage,
            token: _customerFcmToken ?? '',
            chatType: 'Driver',
          ),
        ),
      );
    } catch (e) {
      log('Error opening chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open chat'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fetchCustomerData() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    
    try {
      final doc = await _firestore
          .collection('restaurant_orders')
          .doc(widget.orderId)
          .get();

      if (!doc.exists) return;
      final data = doc.data()!;
      final author = data['author'] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          _customerName =
              '${author?['firstName'] ?? ''} ${author?['lastName'] ?? ''}';
          _customerPhoneNumber = author?['phoneNumber'] ?? 'No phone number';
          _customerPhotoUrl = author?['profilePictureURL'];
          _customerId = author?['id'];
          _customerFcmToken = author?['fcmToken'];

          final addresses = author?['shippingAddress'] as List<dynamic>?;
          _defaultAddress = addresses
              ?.cast<Map<String, dynamic>>()
              .firstWhere((a) => a['isDefault'] == true, orElse: () => {});
          if (_defaultAddress != null) {
            _customerPosition = LatLng(
              _defaultAddress!['location']['latitude'],
              _defaultAddress!['location']['longitude'],
            );
          }
        });
      }
    } catch (e) {
      log('Error fetching customer data: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startPeriodicDriverUpdates() {
    // immediately fetch once, then every 5 minutes
    _updateDriverLocation();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      _updateDriverLocation();
    });
  }

  Future<void> _updateDriverLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);
      final newLoc = LatLng(pos.latitude, pos.longitude);

      if (mounted) {
        setState(() {
          _currentPosition = newLoc;
        });
      }

      // Optionally update in Firestore under the driver's user doc
      // await _firestore.collection('users').doc(driverId).update({
      //   'currentLocation': {
      //     'latitude': newLoc.latitude,
      //     'longitude': newLoc.longitude,
      //   }
      // });
    } catch (e) {
      log('Error getting driver position: $e');
    }
  }

  Widget _buildCustomerInfoCard() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: _customerPhotoUrl != null
                      ? NetworkImage(_customerPhotoUrl!)
                      : null,
                  child: _customerPhotoUrl == null
                      ? const Icon(Icons.person, size: 30, color: Colors.grey)
                      : null,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _makePhoneCall,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.phone,
                      color: Colors.green,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _openChat,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline,
                          color: Colors.blue,
                          size: 30,
                        ),
                      ),
                      if (_unreadCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
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
                              _unreadCount > 99
                                  ? '99+'
                                  : _unreadCount.toString(),
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
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _customerName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Address: ${_defaultAddress?['address'] ?? 'N/A'}',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makePhoneCall() async {
    final phone = _customerPhoneNumber;
    if (phone.isEmpty || phone == 'No phone number') return;

    final status = await Permission.phone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Phone permission denied'),
            backgroundColor: Colors.red),
      );
      return;
    }

    await launchPhoneCall(context, phone);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _customerPosition == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Customer & Driver')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _customerPosition!,
              zoom: 14,
            ),
            onMapCreated: (ctrl) async {
              if (!mounted) return;
              _controller.complete(ctrl);
              
              // Add delay to ensure map is ready
              await Future.delayed(const Duration(milliseconds: 300));
            },
            markers: {
              Marker(
                markerId: const MarkerId('customer'),
                position: _customerPosition!,
                infoWindow: InfoWindow(title: _customerName),
              ),
              if (_currentPosition != null)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: _currentPosition!,
                  icon: _driverIcon ?? BitmapDescriptor.defaultMarker,
                  infoWindow: const InfoWindow(title: 'Driver'),
                ),
            },
          ),
          Positioned(
            top: 20,
            left: 16,
            right: 16,
            child: _buildCustomerInfoCard(),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.75,
            left: 16,
            right: 16,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ConfirmDeliverySummaryPage(
                      orderId: widget.orderId,
                    ),
                  ),
                );
              },
              icon: const Icon(
                Icons.check_circle,
                color: Colors.white,
              ),
              label: const Text(
                'Confirm Delivery',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
