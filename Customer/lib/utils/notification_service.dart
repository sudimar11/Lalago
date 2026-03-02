import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:foodie_customer/model/User.dart';
import 'package:foodie_customer/services/FirebaseHelper.dart';
import 'package:foodie_customer/services/helper.dart';
import 'package:foodie_customer/model/OrderModel.dart';
import 'package:foodie_customer/services/ash_notification_history.dart';
import 'package:foodie_customer/services/notification_action_handler.dart';
import 'package:foodie_customer/ui/cartScreen/CartScreen.dart';
import 'package:foodie_customer/ui/vendorProductsScreen/newVendorProductsScreen.dart';
import 'package:foodie_customer/ui/chat_screen/chat_screen.dart';
import 'package:foodie_customer/ui/ordersScreen/OrdersScreen.dart';
import 'package:foodie_customer/firebase_options.dart';
import 'package:foodie_customer/main.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/model/ProductModel.dart';
import 'package:foodie_customer/ui/container/ContainerScreen.dart';
import 'package:foodie_customer/ui/home/HomeScreen.dart';
import 'package:foodie_customer/ui/orderDetailsScreen/OrderDetailsScreen.dart';
import 'package:foodie_customer/ui/order_recovery/order_recovery_screen.dart';
import 'package:foodie_customer/ui/productDetailsScreen/ProductDetailsScreen.dart';
import 'package:permission_handler/permission_handler.dart';

// #region agent log
void _debugLog(String location, String message, Map<String, dynamic> data,
    String hypothesisId) {
  try {
    final payload = <String, dynamic>{
      'location': location,
      'message': message,
      'data': data,
      'hypothesisId': hypothesisId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    File('/Users/sudimard/Downloads/Lalago/.cursor/debug.log').writeAsStringSync(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}
// #endregion

@pragma('vm:entry-point')
Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  // TEMP DIAGNOSTIC: full FCM payload in background handler
  debugPrint(
      '[FCM_TRACE] ========== firebaseMessageBackgroundHandle TRIGGERED ==========');
  debugPrint('[FCM_TRACE] messageId=${message.messageId}');
  debugPrint('[FCM_TRACE] notification=${message.notification != null}');
  if (message.notification != null) {
    debugPrint(
        '[FCM_TRACE] notification.title=${message.notification!.title}');
    debugPrint(
        '[FCM_TRACE] notification.body=${message.notification!.body}');
  }
  debugPrint('[FCM_TRACE] message.data=${message.data}');
  debugPrint('[FCM_TRACE] data keys=${message.data.keys.toList()}');
  debugPrint('[TOKEN_DEBUG] Customer: firebaseMessageBackgroundHandle received messageId=${message.messageId} dataKeys=${message.data.keys.toList()}');
  log("BackGround Message :: ${message.messageId}");

  // Ensure Firebase is available in the background isolate.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // Best-effort; background work should stay minimal.
  }

  // Android: prefer system-handled notifications via FCM `notification` payload.
  // Avoid flutter_local_notifications in background to reduce native crashes.
  if (Platform.isAndroid) return;

  await NotificationService.showBackgroundNotification(message);
}

class NotificationService {
  // Singleton pattern
  static final NotificationService instance = NotificationService._internal();
  factory NotificationService() => instance;
  NotificationService._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialization guards
  bool _isInitialized = false;
  bool _listenersRegistered = false;
  static bool _backgroundHandlerRegistered = false;
  bool _settingsPromptShown = false;

  // Stream subscriptions
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  static const String _chatChannelId = 'chat_messages';
  static const String _chatChannelName = 'Chat Messages';
  static const String _promoChannelId = 'promo_system';
  static const String _promoChannelName = 'Promo & System';
  static const String _orderStatusChannelId = 'order_status';
  static const String _orderStatusChannelName = 'Order Updates';

  static bool _notificationPermissionDialogShown = false;

  /// Returns true if notification permission is granted (enables pop-up display).
  static Future<bool> isNotificationPermissionGranted() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      return status.isGranted;
    }
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Shows a dialog to enable notifications when permission is denied.
  /// Call when the app has context (e.g. from ContainerScreen/HomeScreen).
  static Future<void> showEnableNotificationsDialogIfNeeded(
      BuildContext context) async {
    if (_notificationPermissionDialogShown) return;
    if (!await isNotificationPermissionGranted()) {
      _notificationPermissionDialogShown = true;
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Notifications'),
          content: const Text(
            'To receive pop-up notifications when riders send you chat '
            'messages, please enable notifications for this app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
  }

  initInfo() async {
    // #region agent log
    _debugLog(
      'notification_service.dart:initInfo',
      'initInfo called',
      {'_isInitialized': _isInitialized},
      'A',
    );
    // #endregion
    if (_isInitialized) return;

    // Register background handler exactly once
    if (!_backgroundHandlerRegistered) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessageBackgroundHandle);
      _backgroundHandlerRegistered = true;
    }
    try {
      if (Platform.isAndroid) {
        final status = await Permission.notification.status;
        debugPrint(
            '[FCM_DEBUG] Android POST_NOTIFICATIONS status=$status');
        if (status.isDenied || status.isPermanentlyDenied) {
          debugPrint(
              '[FCM_DEBUG] requesting POST_NOTIFICATIONS permission');
          await Permission.notification.request();
          final after = await Permission.notification.status;
          debugPrint(
              '[FCM_DEBUG] POST_NOTIFICATIONS after request=$after');
        }
      }

      final request = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint(
          '[FCM_DEBUG] iOS permission status: ${request.authorizationStatus}');

      if (Platform.isIOS) {
        String? apnsToken;
        const delays = [0, 2, 5];
        for (var i = 0; i < delays.length; i++) {
          if (i > 0) {
            await Future<void>.delayed(Duration(seconds: delays[i]));
          }
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          debugPrint(
              '[FCM_DEBUG] APNs getAPNSToken attempt ${i + 1}/${delays.length}: '
              '${apnsToken != null && apnsToken.isNotEmpty ? "received" : "null"}');
          if (apnsToken != null && apnsToken.isNotEmpty) break;
        }
        if (apnsToken != null && apnsToken.isNotEmpty) {
          final preview = apnsToken.length > 20
              ? '${apnsToken.substring(0, 12)}...${apnsToken.substring(apnsToken.length - 4)}'
              : '***';
          debugPrint('[FCM_CONFIRM] APNs token received: $preview');
          log('APNs token received (len=${apnsToken.length})');
        } else {
          debugPrint(
              '[FCM_DEBUG] APNs token still unavailable after ${delays.length} attempts. '
              'Ensure app runs on a real device, Push capability and '
              'Background Modes > Remote notifications are enabled.');
          log('APNs token unavailable after retries.');
        }

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          final preview = fcmToken.length > 20
              ? '${fcmToken.substring(0, 12)}...${fcmToken.substring(fcmToken.length - 4)}'
              : '***';
          debugPrint('[FCM_CONFIRM] FCM token generated: $preview');
          log('FCM token generated (len=${fcmToken.length})');
          if (MyAppState.currentUser != null) {
            MyAppState.currentUser!.fcmToken = fcmToken;
            await FireStoreUtils.updateCurrentUser(MyAppState.currentUser!);
            unawaited(FireStoreUtils.updateActiveOrdersFcmTokenForUser(
                MyAppState.currentUser!.userID, fcmToken));
            debugPrint(
                '[FCM_CONFIRM] FCM token saved to Firestore: '
                'users/${MyAppState.currentUser!.userID}');
          }
        } else {
          debugPrint(
              '[FCM_DEBUG] FCM token null/empty (APNs may still be pending)');
        }
      }

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Android: do not use flutter_local_notifications to avoid native
      // "Too many inflation attempts" SIGABRT crashes on some devices.
      // Rely on system-handled FCM notifications + in-app UI instead.
      if (Platform.isAndroid) {
        setupInteractedMessage();
        _isInitialized = true;
        debugPrint(
            '[FCM_DEBUG] Android: skipped flutter_local_notifications init');
        return;
      }

      // iOS (and other platforms): initialize local notifications for pop-ups.
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInitializationSettings = DarwinInitializationSettings();
      final InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: iosInitializationSettings,
      );
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationTap(
            response.payload,
            actionId: response.actionId,
          );
        },
      );
      await _ensureAndroidDefaultChannel();
      await _ensureAndroidChatChannel();
      await _ensureAndroidPromoChannel();
      await _ensureOrderStatusChannel();
      debugPrint(
          '[FCM_DEBUG] flutter_local_notifications initialized once '
          '(channels: high_importance_channel, chat_messages, promo_system, '
          'order_status)');
      setupInteractedMessage();
      _isInitialized = true;
      // #region agent log
      _debugLog(
        'notification_service.dart:initInfo',
        'initInfo completed',
        {'permission': request.authorizationStatus.toString()},
        'A',
      );
      // #endregion
      debugPrint('[TOKEN_DEBUG] Customer: initInfo completed - FCM listeners registered');

      // Only show settings prompt when permission is granted (so user can
      // enable pop-ups in system settings)
      if (request.authorizationStatus == AuthorizationStatus.authorized ||
          request.authorizationStatus == AuthorizationStatus.provisional) {
        _showAndroidChatSettingsPrompt();
      }
    } catch (e) {
      // #region agent log
      _debugLog(
        'notification_service.dart:initInfo',
        'initInfo FAILED',
        {'error': e.toString()},
        'A',
      );
      // #endregion
      debugPrint('[TOKEN_DEBUG] Customer: initInfo FAILED $e');
      log('Notification init failed: $e');
    }
  }

  /// Strict check: used for navigation to chat (tap). Keeps original semantics.
  static bool isRiderChatNotification(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final senderRole = data['senderRole']?.toString();
    final messageType = data['messageType']?.toString();
    if (senderRole != 'rider') {
      return false;
    }
    final isChatType = type == 'chat' || type == 'chat_message';
    if (!isChatType) {
      return false;
    }
    return messageType == null ||
        messageType.isEmpty ||
        messageType == 'chat' ||
        messageType == 'status_update';
  }

  /// Tolerant check: show popup if message has notification or non-empty data.
  /// Ensures any valid FCM from rider (or with title/body) always triggers popup.
  static bool shouldShowPopupForMessage(RemoteMessage message) {
    if (message.notification != null) {
      debugPrint(
          '[FCM_DEBUG] shouldShowPopupForMessage=true (notification present)');
      return true;
    }
    if (message.data.isEmpty) {
      debugPrint('[FCM_DEBUG] shouldShowPopupForMessage=false (empty data)');
      return false;
    }
    debugPrint(
        '[FCM_DEBUG] shouldShowPopupForMessage=true (data keys='
        '${message.data.keys.toList()})');
    return true;
  }

  static bool isHappyHourNotification(Map<String, dynamic> data) {
    return data['type'] == 'happy_hour';
  }

  static bool isOrderUpdateNotification(Map<String, dynamic> data) {
    return data['type'] == 'order_update';
  }

  static Future<void> showBackgroundNotification(
    RemoteMessage message,
  ) async {
    final service = NotificationService.instance;
    // Android: do not use flutter_local_notifications; rely on system FCM UI.
    if (Platform.isAndroid) return;
    debugPrint(
        '[FCM_DEBUG] showBackgroundNotification dataKeys=${message.data.keys.toList()}');
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await service.flutterLocalNotificationsPlugin
        .initialize(initializationSettings);
    await service._ensureAndroidDefaultChannel();
    await service._ensureAndroidChatChannel();
    await service._ensureAndroidPromoChannel();
    await service._ensureOrderStatusChannel();

    if (shouldShowPopupForMessage(message)) {
      log("Rider/displayable notification received in background");
      if (isOrderUpdateNotification(message.data)) {
        await service._showOrderUpdateNotification(message);
      } else {
        await service._showChatNotification(message);
      }
      return;
    }
    if (isHappyHourNotification(message.data) ||
        service._hasDisplayableNotification(message)) {
      await service._showPromoSystemNotification(message);
    }
  }

  void _handleNotificationTap(String? payload, {String? actionId}) {
    if (payload == null || payload.isEmpty) return;

    try {
      final Map<String, dynamic> data = jsonDecode(payload);
      if (actionId != null && actionId.isNotEmpty) {
        NotificationActionHandler.handleAction(null, actionId, data);
        return;
      }
      if (isRiderChatNotification(data)) {
        _navigateToChat(data);
      } else if (isOrderUpdateNotification(data)) {
        _navigateToOrderDetails(data);
      } else if (data['type'] == 'happy_hour') {
        _navigateToHome();
      }
    } catch (e) {
      log('Error handling notification tap: $e');
    }
  }

  /// Public method for NotificationActionHandler to navigate to chat.
  void navigateToChat(Map<String, dynamic> data) => _navigateToChat(data);

  Future<void> _navigateToOrderDetails(Map<String, dynamic> data) async {
    try {
      BuildContext? context = navigatorKey.currentContext;
      if (context == null) {
        await Future.delayed(const Duration(seconds: 1));
        context = navigatorKey.currentContext;
      }
      if (context == null) {
        log('No context for order details navigation');
        return;
      }

      final orderId = data['orderId']?.toString();
      final customerId = data['customerId']?.toString();
      if (orderId == null || orderId.isEmpty) {
        log('Missing orderId for order_update notification');
        return;
      }

      if (MyAppState.currentUser != null &&
          customerId != null &&
          customerId != MyAppState.currentUser!.userID) {
        log('Customer ID mismatch, ignoring order_update');
        return;
      }

      final OrderModel? order =
          await FireStoreUtils.getOrderByIdOnce(orderId);
      if (order == null) {
        log('Order not found: $orderId');
        return;
      }

      push(
        context,
        OrderDetailsScreen(
          orderModel: order,
          fromNotification: true,
        ),
      );
    } catch (e) {
      log('Error navigating to order details: $e');
    }
  }

  Future<void> _navigateToHome({String? highlightMealPeriod}) async {
    try {
      BuildContext? context = navigatorKey.currentContext;

      if (context == null) {
        await Future.delayed(const Duration(seconds: 1));
        context = navigatorKey.currentContext;
        if (context == null) {
          log('No context available for navigation to home');
          return;
        }
      }

      pushAndRemoveUntil(
        context,
        ContainerScreen(
          user: MyAppState.currentUser,
          currentWidget: HomeScreen(
            user: MyAppState.currentUser,
            highlightMealPeriod: highlightMealPeriod,
            filterByMeal: highlightMealPeriod != null,
          ),
        ),
        false,
      );
    } catch (e) {
      log('Error navigating to home: $e');
    }
  }

  Future<void> _navigateToChat(Map<String, dynamic> data) async {
    try {
      final BuildContext? context = navigatorKey.currentContext;
      if (context == null) {
        log('No context available for navigation');
        return;
      }

      final String? orderId = data['orderId']?.toString();
      final String? customerId = data['customerId']?.toString();
      String? restaurantId = data['restaurantId']?.toString();
      final String? chatType = data['chatType']?.toString() ?? 'Driver';

      // Fallback: fetch driver ID from order when restaurantId is missing
      if ((restaurantId == null || restaurantId.isEmpty) &&
          orderId != null &&
          orderId.isNotEmpty) {
        try {
          final orderDoc = await FirebaseFirestore.instance
              .collection('restaurant_orders')
              .doc(orderId)
              .get();
          if (orderDoc.exists) {
            final orderData = orderDoc.data();
            restaurantId = orderData?['driverID'] as String? ??
                orderData?['driverId'] as String?;
          }
        } catch (e) {
          log('Error fetching order for restaurantId fallback: $e');
        }
      }

      if (orderId == null ||
          orderId.isEmpty ||
          customerId == null ||
          restaurantId == null ||
          restaurantId.isEmpty) {
        log('Missing required chat data');
        return;
      }

      // Validate customer ID matches current user
      if (MyAppState.currentUser == null) {
        log('⚠️ Current user not available, ignoring push notification');
        return;
      }

      final currentId = MyAppState.currentUser!.userID.toString();
      if (customerId != currentId) {
        log('⚠️ Push notification customer ID mismatch, ignoring - '
            'Expected: $currentId, Received: $customerId');
        return;
      }

      User? customer =
          await FireStoreUtils.getCurrentUser(customerId.toString());
      User? restaurantUser =
          await FireStoreUtils.getCurrentUser(restaurantId.toString());

      if (customer == null || restaurantUser == null) {
        log('Could not fetch user data');
        return;
      }

      // Log rider message push notification receipt (safe logging - metadata only)
      if (isRiderChatNotification(data)) {
        log('📨 Rider message push notification received - '
            'Order: $orderId, '
            'CustomerId: $customerId, '
            'ChatType: $chatType');
      }

      push(
        context,
        ChatScreens(
          customerName: '${customer.firstName} ${customer.lastName}',
          restaurantName:
              '${restaurantUser.firstName} ${restaurantUser.lastName}',
          orderId: orderId,
          restaurantId: restaurantUser.userID,
          customerId: customer.userID,
          customerProfileImage: customer.profilePictureURL,
          restaurantProfileImage: restaurantUser.profilePictureURL,
          token: restaurantUser.fcmToken,
          chatType: chatType,
        ),
      );
    } catch (e) {
      log('Error navigating to chat: $e');
    }
  }

  Future<void> _ensureAndroidChatChannel() async {
    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      debugPrint('[FCM_DEBUG] _ensureAndroidChatChannel skipped (not Android)');
      return;
    }
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _chatChannelId,
      _chatChannelName,
      description: 'Driver chat notifications - enables pop-up banners',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      showBadge: true,
    );
    await androidPlugin.createNotificationChannel(channel);
    debugPrint('[FCM_DEBUG] notification channel created: $_chatChannelId');
  }

  Future<void> _ensureAndroidDefaultChannel() async {
    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance',
      description: 'Default high-importance notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin.createNotificationChannel(channel);
    debugPrint('[FCM_DEBUG] notification channel created: high_importance_channel');
  }

  Future<void> _ensureAndroidPromoChannel() async {
    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      _promoChannelId,
      _promoChannelName,
      description: 'Promo and system notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await androidPlugin.createNotificationChannel(channel);
  }

  Future<void> _ensureOrderStatusChannel() async {
    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _orderStatusChannelId,
      _orderStatusChannelName,
      description: 'Order status update notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin.createNotificationChannel(channel);
  }

  void _showAndroidChatSettingsPrompt() {
    if (_settingsPromptShown || !Platform.isAndroid) {
      return;
    }

    final BuildContext? context = navigatorKey.currentContext;
    if (context == null) return;

    _settingsPromptShown = true;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enable Chat Pop-ups'),
          content: const Text(
            'To show chat notifications as pop-ups, set the '
            '"Chat Messages" channel to High in your system settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  Future<void> setupInteractedMessage() async {
    // Guard against duplicate listener registration
    if (_listenersRegistered) return;

    // Cancel existing subscriptions before re-registering (defensive)
    _onMessageSubscription?.cancel();
    _onMessageOpenedAppSubscription?.cancel();

    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleInitialMessage(initialMessage);
    }

    _onMessageSubscription =
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // TEMP DIAGNOSTIC: full FCM payload in foreground
      debugPrint(
          '[FCM_TRACE] ========== onMessage TRIGGERED (foreground) ==========');
      debugPrint('[FCM_TRACE] messageId=${message.messageId}');
      debugPrint('[FCM_TRACE] notification=${message.notification != null}');
      if (message.notification != null) {
        debugPrint(
            '[FCM_TRACE] notification.title=${message.notification!.title}');
        debugPrint(
            '[FCM_TRACE] notification.body=${message.notification!.body}');
      }
      debugPrint('[FCM_TRACE] message.data=${message.data}');
      debugPrint('[FCM_TRACE] data keys=${message.data.keys.toList()}');
      debugPrint(
          '[FCM_DEBUG] onMessage TRIGGERED dataKeys=${message.data.keys.toList()} '
          'notification=${message.notification != null}');
      log("::::::::::::onMessage:::::::::::::::::");
      final isRider = isRiderChatNotification(message.data);
      _debugLog(
        'notification_service.dart:onMessage',
        'FCM onMessage received',
        {
          'dataKeys': message.data.keys.toList(),
          'isRiderChatNotification': isRider,
          'shouldShowPopup': shouldShowPopupForMessage(message),
        },
        'B_C',
      );
      if (shouldShowPopupForMessage(message)) {
        debugPrint(
            '[FCM_TRACE] ========== ABOUT TO CALL display(message) ==========');
        display(message);
        return;
      }
      if (isHappyHourNotification(message.data) ||
          _hasDisplayableNotification(message)) {
        _showPromoSystemNotification(message);
      }
    });

    _onMessageOpenedAppSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log("::::::::::::onMessageOpenedApp:::::::::::::::::");
      final data = message.data;
      final type = data['type']?.toString() ?? '';

      if (type.startsWith('ash_')) {
        final notificationId = data['notificationId']?.toString();
        if (notificationId != null && notificationId.isNotEmpty) {
          unawaited(AshNotificationHistory.markOpened(
              notificationId, action: 'opened'));
        }
        switch (type) {
          case 'ash_reorder':
            final vendorId = data['vendorId']?.toString();
            if (vendorId != null && vendorId.isNotEmpty) {
              unawaited(_navigateToReorderRestaurant(vendorId));
            } else {
              _navigateToOrders();
            }
            break;
          case 'ash_recommendation':
            unawaited(_navigateToRecommendation(
              vendorId: data['vendorId']?.toString(),
              productId: data['productId']?.toString(),
              notificationId: notificationId,
            ));
            break;
          case 'ash_cart':
          case 'ash_cart_urgent':
            _navigateToCart();
            break;
          case 'ash_hunger':
            _navigateToHome(
              highlightMealPeriod: data['mealPeriod']?.toString(),
            );
            break;
          case 'ash_order_recovery':
            _navigateToOrderRecovery(
              Map<String, dynamic>.from(data)
                ..['title'] = message.notification?.title ?? 'Order Recovery'
                ..['body'] = message.notification?.body ?? '',
            );
            break;
          default:
            _navigateToHome();
        }
        return;
      }
      if (isRiderChatNotification(data)) {
        final payloadCustomerId = data['customerId']?.toString();
        final currentId = MyAppState.currentUser?.userID.toString();
        if (MyAppState.currentUser != null &&
            payloadCustomerId != null &&
            payloadCustomerId != currentId) {
          log('⚠️ Message opened app customer ID mismatch, ignoring');
          return;
        }
        _navigateToChat(message.data);
      } else if (data['type'] == 'happy_hour') {
        _navigateToHome();
      } else if (isOrderUpdateNotification(data)) {
        final customerId = data['customerId']?.toString();
        final currentId = MyAppState.currentUser?.userID.toString();
        if (MyAppState.currentUser != null &&
            customerId != null &&
            customerId != currentId) {
          log('Order update customer ID mismatch, ignoring');
          return;
        }
        _navigateToOrderDetails(data);
      } else if (message.notification != null) {
        log(message.notification.toString());
        display(message);
      }
    });

    _listenersRegistered = true;
  }

  Future<void> _navigateToCart() async {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) {
        await Future.delayed(const Duration(seconds: 1));
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        pushAndRemoveUntil(
          ctx,
          ContainerScreen(
            user: MyAppState.currentUser,
            currentWidget: CartScreen(fromContainer: true),
          ),
          false,
        );
      } else {
        pushAndRemoveUntil(
          context,
          ContainerScreen(
            user: MyAppState.currentUser,
            currentWidget: CartScreen(fromContainer: true),
          ),
          false,
        );
      }
    } catch (e) {
      log('Error navigating to cart: $e');
    }
  }

  Future<void> _navigateToOrders() async {
    try {
      final context = navigatorKey.currentContext;
      if (context == null) {
        await Future.delayed(const Duration(seconds: 1));
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        pushAndRemoveUntil(
          ctx,
          ContainerScreen(
            user: MyAppState.currentUser,
            currentWidget: OrdersScreen(isAnimation: true),
          ),
          false,
        );
      } else {
        pushAndRemoveUntil(
          context,
          ContainerScreen(
            user: MyAppState.currentUser,
            currentWidget: OrdersScreen(isAnimation: true),
          ),
          false,
        );
      }
    } catch (e) {
      log('Error navigating to orders: $e');
    }
  }

  void _navigateToOrderRecovery(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      Future.delayed(const Duration(seconds: 1), () {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          push(ctx, OrderRecoveryScreen(data: data));
        }
      });
      return;
    }
    push(context, OrderRecoveryScreen(data: data));
  }

  Future<void> _navigateToReorderRestaurant(String vendorId) async {
    try {
      final vendor = await FireStoreUtils.getVendor(vendorId);
      if (vendor == null) {
        _navigateToOrders();
        return;
      }
      BuildContext? ctx = navigatorKey.currentContext;
      if (ctx == null) {
        await Future.delayed(const Duration(seconds: 1));
        ctx = navigatorKey.currentContext;
      }
      if (ctx == null) return;
      pushAndRemoveUntil(
        ctx,
        ContainerScreen(
          user: MyAppState.currentUser,
          currentWidget: NewVendorProductsScreen(
            vendorModel: vendor,
            showReorderBanner: true,
          ),
        ),
        false,
      );
    } catch (e) {
      log('Error navigating to reorder restaurant: $e');
      _navigateToOrders();
    }
  }

  Future<void> _navigateToRecommendation({
    String? vendorId,
    String? productId,
    String? notificationId,
  }) async {
    if (notificationId != null && notificationId.isNotEmpty) {
      unawaited(AshNotificationHistory.markOpened(
        notificationId,
        action: 'tapped',
      ));
    }
    BuildContext? ctx = navigatorKey.currentContext;
    if (ctx == null) {
      await Future.delayed(const Duration(seconds: 1));
      ctx = navigatorKey.currentContext;
    }
    if (ctx == null) return;

    if (vendorId != null && vendorId.isNotEmpty) {
      try {
        final vendor = await FireStoreUtils.getVendor(vendorId);
        if (vendor == null) {
          _navigateToHome();
          return;
        }
        pushAndRemoveUntil(
          ctx,
          ContainerScreen(user: MyAppState.currentUser),
          false,
        );
        final c = navigatorKey.currentContext;
        if (c == null) return;
        if (productId != null && productId.isNotEmpty) {
          try {
            final doc = await FirebaseFirestore.instance
                .collection(PRODUCTS)
                .doc(productId)
                .get();
            if (doc.exists && doc.data() != null) {
              final d = Map<String, dynamic>.from(doc.data()!);
              d['id'] = doc.id;
              final product = ProductModel.fromJson(d);
              if (product.vendorID == vendorId) {
                push(c, ProductDetailsScreen(
                  productModel: product,
                  vendorModel: vendor,
                ));
                return;
              }
            }
          } catch (_) {}
        }
        push(c, NewVendorProductsScreen(
          vendorModel: vendor,
          showReorderBanner: false,
        ));
      } catch (e) {
        log('Error navigating to recommendation: $e');
        _navigateToHome();
      }
    } else {
      _navigateToHome();
    }
  }

  void _handleInitialMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString() ?? '';

    if (type.startsWith('ash_')) {
      final notificationId = data['notificationId']?.toString();
      if (notificationId != null && notificationId.isNotEmpty) {
        unawaited(AshNotificationHistory.markOpened(
            notificationId, action: 'opened'));
      }
      Future.delayed(const Duration(seconds: 1), () {
        switch (type) {
          case 'ash_reorder':
            final vendorId = data['vendorId']?.toString();
            if (vendorId != null && vendorId.isNotEmpty) {
              _navigateToReorderRestaurant(vendorId);
            } else {
              _navigateToOrders();
            }
            break;
          case 'ash_recommendation':
            _navigateToRecommendation(
              vendorId: data['vendorId']?.toString(),
              productId: data['productId']?.toString(),
              notificationId: data['notificationId']?.toString(),
            );
            break;
          case 'ash_cart':
          case 'ash_cart_urgent':
            _navigateToCart();
            break;
          case 'ash_hunger':
            _navigateToHome(
              highlightMealPeriod: data['mealPeriod']?.toString(),
            );
            break;
          case 'ash_order_recovery':
            _navigateToOrderRecovery(
              Map<String, dynamic>.from(data)
                ..['title'] = message.notification?.title ?? 'Order Recovery'
                ..['body'] = message.notification?.body ?? '',
            );
            break;
          default:
            _navigateToHome();
        }
      });
      return;
    }
    if (isRiderChatNotification(data)) {
      final payloadCustomerId = data['customerId']?.toString();
      final currentId = MyAppState.currentUser?.userID.toString();
      if (MyAppState.currentUser != null &&
          payloadCustomerId != null &&
          payloadCustomerId != currentId) {
        log('⚠️ Initial message customer ID mismatch, ignoring');
        return;
      }

      Future.delayed(const Duration(seconds: 1), () {
        _navigateToChat(data);
      });
    } else if (data['type'] == 'happy_hour') {
      Future.delayed(const Duration(seconds: 1), () {
        _navigateToHome();
      });
    } else if (isOrderUpdateNotification(data)) {
      final payloadCustomerId = data['customerId']?.toString();
      final currentId = MyAppState.currentUser?.userID.toString();
      if (MyAppState.currentUser != null &&
          payloadCustomerId != null &&
          payloadCustomerId != currentId) {
        log('Order update initial message customer ID mismatch');
        return;
      }
      Future.delayed(const Duration(seconds: 1), () {
        _navigateToOrderDetails(data);
      });
    }
  }

  static Future<String?> getToken() async {
    return FireStoreUtils.safeGetFcmToken();
  }

  bool _hasDisplayableNotification(RemoteMessage message) {
    if (message.notification != null) {
      return true;
    }
    return message.data['title'] != null ||
        message.data['body'] != null ||
        message.data['message'] != null;
  }

  String _resolveTitle(RemoteMessage message, String fallback) {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        message.data['subject']?.toString();
    if (title == null || title.trim().isEmpty) {
      return fallback;
    }
    return title;
  }

  String _resolveBody(RemoteMessage message, String fallback) {
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        message.data['text']?.toString();
    if (body == null || body.trim().isEmpty) {
      return fallback;
    }
    return body;
  }

  Future<void> _showPromoSystemNotification(RemoteMessage message) async {
    final body = _resolveBody(message, 'You have a new update.');
    final title = _resolveTitle(message, body);
    await _showLocalNotification(
      channelId: _promoChannelId,
      channelName: _promoChannelName,
      channelDescription: 'Promo and system notifications',
      title: title,
      body: body,
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _showChatNotification(RemoteMessage message) async {
    // #region agent log
    _debugLog(
      'notification_service.dart:_showChatNotification',
      'showing chat notification',
      {'channelId': _chatChannelId},
      'E',
    );
    // #endregion
    final title = _resolveTitle(message, 'New message');
    final body = _resolveBody(
      message,
      'You have a new message from a rider.',
    );
    await _showLocalNotification(
      channelId: _chatChannelId,
      channelName: _chatChannelName,
      channelDescription: 'Notifications for driver messages',
      title: title,
      body: body,
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _showOrderUpdateNotification(RemoteMessage message) async {
    final title = _resolveTitle(message, 'Order Update');
    final body = _resolveBody(message, 'Your order status has been updated.');
    await _showLocalNotification(
      channelId: _orderStatusChannelId,
      channelName: _orderStatusChannelName,
      channelDescription: 'Order status update notifications',
      title: title,
      body: body,
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _showLocalNotification({
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      // Android: disable local notifications to avoid RemoteViews inflation
      // crashes ("Too many inflation attempts").
      if (Platform.isAndroid) return;
      final AndroidNotificationDetails notificationDetails =
          AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        ticker: 'ticker',
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.message,
      );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        presentBanner: true,
        presentList: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final NotificationDetails notificationDetailsBoth = NotificationDetails(
        android: notificationDetails,
        iOS: darwinNotificationDetails,
      );

      final notificationId =
          DateTime.now().millisecondsSinceEpoch.remainder(100000);

      debugPrint(
          '[FCM_TRACE] ========== ABOUT TO CALL flutterLocalNotificationsPlugin.show() ==========');
      debugPrint(
          '[FCM_TRACE] channelId=$channelId title=$title body=$body '
          'notificationId=$notificationId');
      debugPrint(
          '[FCM_DEBUG] flutterLocalNotificationsPlugin.show() EXECUTION '
          'channelId=$channelId notificationId=$notificationId title=$title');
      _debugLog(
        'notification_service.dart:_showLocalNotification',
        'calling flutterLocalNotificationsPlugin.show',
        {'channelId': channelId, 'title': title, 'notificationId': notificationId},
        'E',
      );
      await flutterLocalNotificationsPlugin.show(
        notificationId,
        title,
        body,
        notificationDetailsBoth,
        payload: payload,
      );
      debugPrint(
          '[FCM_DEBUG] flutterLocalNotificationsPlugin.show() COMPLETED '
          'channelId=$channelId');
      _debugLog(
        'notification_service.dart:_showLocalNotification',
        'show() completed successfully',
        {'channelId': channelId},
        'E',
      );
    } on Exception catch (e) {
      debugPrint('[FCM_DEBUG] flutterLocalNotificationsPlugin.show() FAILED $e');
      // #region agent log
      _debugLog(
        'notification_service.dart:_showLocalNotification',
        'show() threw exception',
        {'error': e.toString(), 'channelId': channelId},
        'E',
      );
      // #endregion
      log(e.toString());
    }
  }

  void display(RemoteMessage message) async {
    try {
      // TEMP DIAGNOSTIC: full payload at display() entry
      debugPrint('[FCM_TRACE] ========== display() ENTRY ==========');
      debugPrint('[FCM_TRACE] messageId=${message.messageId}');
      debugPrint('[FCM_TRACE] notification=${message.notification != null}');
      if (message.notification != null) {
        debugPrint(
            '[FCM_TRACE] notification.title=${message.notification!.title}');
        debugPrint(
            '[FCM_TRACE] notification.body=${message.notification!.body}');
      }
      debugPrint('[FCM_TRACE] message.data=${message.data}');
      debugPrint(
          '[FCM_DEBUG] display() ENTRY dataKeys=${message.data.keys.toList()}');
      _debugLog(
        'notification_service.dart:display',
        'display() called',
        {'dataKeys': message.data.keys.toList()},
        'D',
      );
      log('Got a message whilst in the foreground!');
      log('Message data: ${message.notification?.body ?? message.data['body'] ?? message.data['message']}');

      final payloadCustomerId = message.data['customerId']?.toString() ??
          message.data['customer_id']?.toString();
      final currentUserId = MyAppState.currentUser?.userID.toString();
      final isMismatch = MyAppState.currentUser != null &&
          payloadCustomerId != null &&
          payloadCustomerId != currentUserId;
      if (isMismatch) {
        log('⚠️ Foreground notification customer ID mismatch (showing popup '
            'anyway; tap navigation may skip). Expected: $currentUserId, '
            'Received: $payloadCustomerId');
      }
      if (isRiderChatNotification(message.data)) {
        log('📨 Rider message notification (foreground) - '
            'Order: ${message.data['orderId']}, '
            'CustomerId: ${message.data['customerId']}');
        await _showChatNotification(message);
      } else if (isOrderUpdateNotification(message.data)) {
        log('Order status update notification (foreground) - '
            'Order: ${message.data['orderId']}');
        await _showOrderUpdateNotification(message);
      } else {
        await _showChatNotification(message);
      }
    } on Exception catch (e) {
      debugPrint('[FCM_DEBUG] display() FAILED: $e');
      log('Notification display failed: $e');
    }
  }

  void dispose() {
    _onMessageSubscription?.cancel();
    _onMessageOpenedAppSubscription?.cancel();
    _onMessageSubscription = null;
    _onMessageOpenedAppSubscription = null;
    _listenersRegistered = false;
  }
}
