import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:foodie_driver/services/audio_service.dart';
import 'package:foodie_driver/services/food_ready_highlight_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:foodie_driver/model/notification_model.dart';
import 'package:foodie_driver/services/notification_action_handler.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  log("BackGround Message :: ${message.messageId}");
  final isChat = NotificationService._isChatMessage(message.data);
  if (isChat) {
    log("RIDER: Chat message received (background/terminated) - showing notification");
  }
  await NotificationService.showBackgroundNotification(message);
}

class NotificationService {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin? _backgroundPlugin;
  static bool _notificationPermissionDialogShown = false;

  /// Called when user taps an order action from notification (accept/decline/view).
  static void Function(String orderId, String action)? onOrderActionFromNotification;

  /// Called when user taps a PAUTOS assignment notification.
  static void Function(String orderId)? onPautosAssignmentTap;
  static void Function(String orderId)? onOpenOrderCommunication;
  static void Function(String initialTab, String orderId)?
      onOpenUnifiedCommunicationHub;

  static Future<bool> isNotificationPermissionGranted() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      return status.isGranted;
    }
    final settings =
        await FirebaseMessaging.instance.getNotificationSettings();
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
            'To receive order alerts and chat messages, '
            'please enable notifications for this app.',
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

  /// Call from background message handler to show notification from FCM data.
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    final type = message.data['type']?.toString() ?? '';
    if (type == 'order_reassigned') {
      await _showReassignBackgroundNotification(message);
      return;
    }
    final isChat = _isChatMessage(message.data);
    final title = _resolveTitle(
      message,
      isChat ? 'New message' : 'Notification',
    );
    final body = _resolveBody(
      message,
      isChat
          ? 'You have a new message from a customer.'
          : 'You have a new update.',
    );
    _backgroundPlugin ??= FlutterLocalNotificationsPlugin();
    final plugin = _backgroundPlugin!;
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initIos =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: initAndroid,
      iOS: initIos,
    );
    await plugin.initialize(initSettings);
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelChat,
        'Chat Messages',
        description: 'Notifications when customer sends a message',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
    final id = idChat +
        DateTime.now().millisecondsSinceEpoch.remainder(100000);
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelChat,
      'Chat Messages',
      channelDescription: 'Customer chat messages',
      importance: Importance.max,
      priority: Priority.high,
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(message.data),
    );
  }

  static Future<void> _showReassignBackgroundNotification(
      RemoteMessage message) async {
    _backgroundPlugin ??= FlutterLocalNotificationsPlugin();
    final plugin = _backgroundPlugin!;
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initIos =
        DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: initAndroid,
      iOS: initIos,
    );
    await plugin.initialize(initSettings);
    if (Platform.isAndroid) {
      final AndroidNotificationChannel channel = AndroidNotificationChannel(
        channelReassign,
        'Order Reassigned',
        description: 'Notifications when an order is reassigned due to timeout',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('reassign'),
      );
      await plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
    final id = idReassign +
        DateTime.now().millisecondsSinceEpoch.remainder(100000);
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelReassign,
      'Order Reassigned',
      channelDescription: 'Order reassigned due to timeout',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('reassign'),
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'reassign.wav',
    );
    await plugin.show(
      id,
      'Order Reassigned',
      'An order was reassigned due to timeout.',
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: jsonEncode(message.data),
    );
  }

  // Notification channel IDs
  static const String channelOrder = 'order_notifications';
  static const String channelEarning = 'earning_notifications';
  static const String channelPerformance = 'performance_notifications';
  static const String channelReminder = 'reminder_notifications';
  static const String channelChat = 'chat_messages';
  static const String channelReassign = 'order_reassigned';

  // Notification IDs for different types
  static const int idOrder = 1000;
  static const int idEarning = 2000;
  static const int idPerformance = 3000;
  static const int idReminder = 4000;
  static const int idChat = 5000;
  static const int idReassign = 6000;

  /// Request notification permission if not yet granted. Call early so
  /// getToken() can succeed on iOS. Safe to call multiple times.
  Future<void> requestPermissionIfNeeded() async {
    final settings =
        await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      log('Notification permission already granted');
      return;
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
    log('Notification permission request result: ${request.authorizationStatus}');
  }

  initInfo() async {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    var request = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // Always initialize plugin, channels, and FCM onMessage listener so we
    // receive and show chat messages even if permission was previously denied.
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    var iosInitializationSettings = const DarwinInitializationSettings();
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: iosInitializationSettings,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) async {
        final payload = response.payload;
        final actionId = response.actionId;
        if (payload != null && payload.isNotEmpty) {
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>?;
            if (actionId != null && actionId.isNotEmpty) {
              await NotificationActionHandler.handleAction(actionId, data);
              return;
            }
            final type = data?['type']?.toString() ?? '';
            if (type == 'food_ready') {
              final orderId = data?['orderId']?.toString();
              if (orderId != null && orderId.isNotEmpty) {
                FoodReadyHighlightService.instance.setHighlighted(orderId);
              }
            }
            if (type == 'pautos_assignment') {
              final orderId = data?['orderId']?.toString();
              if (orderId != null && orderId.isNotEmpty) {
                onPautosAssignmentTap?.call(orderId);
              }
            }
            final compatOrderId = _normalizedCommunicationOrderId(data);
            if (compatOrderId != null) {
              onOpenUnifiedCommunicationHub?.call('restaurants', compatOrderId);
              onOpenOrderCommunication?.call(compatOrderId);
              return;
            }
            final chatTarget = _normalizedUnifiedHubTarget(data);
            if (chatTarget != null) {
              onOpenUnifiedCommunicationHub?.call(
                chatTarget.$1,
                chatTarget.$2,
              );
            }
          } catch (_) {}
        }
      },
    );
    _createNotificationChannels();
    setupInteractedMessage();

    if (request.authorizationStatus == AuthorizationStatus.authorized ||
        request.authorizationStatus == AuthorizationStatus.provisional) {
      log("::::::::::::Permission authorized:::::::::::::::::");
    } else {
      log(
          "::::::::::::Permission status: ${request.authorizationStatus} - "
          "onMessage still registered for chat notifications:::::::::::::::::");
    }
  }

  Future<void> _createNotificationChannels() async {
    // Order notifications channel (high priority)
    const AndroidNotificationChannel orderChannel = AndroidNotificationChannel(
      channelOrder,
      'New Orders',
      description: 'Notifications for new order requests',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    // Earning notifications channel (normal priority)
    const AndroidNotificationChannel earningChannel =
        AndroidNotificationChannel(
      channelEarning,
      'Earning Milestones',
      description: 'Notifications for earning milestones and achievements',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Performance notifications channel (high priority)
    const AndroidNotificationChannel performanceChannel =
        AndroidNotificationChannel(
      channelPerformance,
      'Performance Alerts',
      description: 'Notifications for performance warnings and alerts',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Reminder notifications channel (normal priority)
    const AndroidNotificationChannel reminderChannel =
        AndroidNotificationChannel(
      channelReminder,
      'Reminders',
      description: 'Scheduled reminders and notifications',
      importance: Importance.defaultImportance,
      playSound: true,
      enableVibration: false,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(orderChannel);
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(earningChannel);
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(performanceChannel);
    const AndroidNotificationChannel chatChannel =
        AndroidNotificationChannel(
      channelChat,
      'Chat Messages',
      description: 'Notifications when customer sends a message',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    final AndroidNotificationChannel reassignChannel =
        AndroidNotificationChannel(
      channelReassign,
      'Order Reassigned',
      description: 'Notifications when an order is reassigned due to timeout',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('reassign'),
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(reminderChannel);
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(chatChannel);
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(reassignChannel);
  }

  static String _resolveTitle(RemoteMessage message, String fallback) {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        message.data['subject']?.toString();
    if (title == null || title.trim().isEmpty) return fallback;
    return title;
  }

  static String _resolveBody(RemoteMessage message, String fallback) {
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        message.data['text']?.toString();
    if (body == null || body.trim().isEmpty) return fallback;
    return body;
  }

  static bool _isChatMessage(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final messageType = data['messageType']?.toString() ?? '';
    return type == 'chat_message' ||
        type == 'order_communication' ||
        type == 'order_message' ||
        type == 'admin_driver_chat' ||
        messageType == 'chat';
  }

  static String? _normalizedCommunicationOrderId(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final type = data['type']?.toString() ?? '';
    if (type != 'order_communication' && type != 'order_message') {
      return null;
    }
    final orderId = data['orderId']?.toString() ?? '';
    return orderId.isNotEmpty ? orderId : null;
  }

  static (String, String)? _normalizedUnifiedHubTarget(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final type = data['type']?.toString() ?? '';
    final orderId = data['orderId']?.toString() ?? '';
    if (type == 'order_communication' || type == 'order_message') {
      return ('restaurants', orderId);
    }
    if (type == 'admin_driver_chat') {
      return ('support', orderId);
    }
    if (type == 'chat_message') {
      return ('customers', orderId);
    }
    return null;
  }

  Future<void> setupInteractedMessage() async {
    final initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(seconds: 1), () {
        _handleInitialOrOpenedMessage(initialMessage);
      });
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log("::::::::::::onMessage:::::::::::::::::");
      log(message.notification?.toString() ?? 'data: ${message.data}');
      if (_isChatMessage(message.data)) {
        log("RIDER: Chat message received (foreground) - showing local notification");
      }
      final type = message.data['type']?.toString() ?? '';
      if (type == 'food_ready') {
        final orderId = message.data['orderId']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          FoodReadyHighlightService.instance.setHighlighted(orderId);
        }
      }
      if (type == 'order_reassigned') {
        final orderId = message.data['orderId']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          AudioService.instance.playReassignSound(orderId: orderId);
        }
      }
      if (type == 'pautos_assignment') {
        final orderId = message.data['orderId']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          AudioService.instance.playNewOrderSound(orderId: orderId);
        }
      }
      if (type == 'order' || type == 'new_order' || type == 'order_update') {
        final orderId = message.data['orderId']?.toString();
        if (orderId != null && orderId.isNotEmpty) {
          AudioService.instance.playNewOrderSound(orderId: orderId);
        }
      }
      display(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log("::::::::::::onMessageOpenedApp:::::::::::::::::");
      _handleInitialOrOpenedMessage(message);
    });
    log("RIDER: FCM onMessage listener registered for chat notifications");
    await FirebaseMessaging.instance.subscribeToTopic("QuicklAI");
  }

  void _handleInitialOrOpenedMessage(RemoteMessage message) {
    final type = message.data['type']?.toString() ?? '';
    final orderId = message.data['orderId']?.toString();
    if (type == 'food_ready' && orderId != null && orderId.isNotEmpty) {
      FoodReadyHighlightService.instance.setHighlighted(orderId);
    }
    if (type == 'order_reassigned' && orderId != null && orderId.isNotEmpty) {
      AudioService.instance.playReassignSound(orderId: orderId);
    }
    if ((type == 'order' || type == 'new_order' || type == 'order_update') &&
        orderId != null &&
        orderId.isNotEmpty) {
      AudioService.instance.playNewOrderSound(orderId: orderId);
      onOrderActionFromNotification?.call(orderId, 'view');
      return;
    }
    if (type == 'pautos_assignment' && orderId != null && orderId.isNotEmpty) {
      AudioService.instance.playNewOrderSound(orderId: orderId);
      onPautosAssignmentTap?.call(orderId);
      return;
    }
    final communicationOrderId = _normalizedCommunicationOrderId(message.data);
    if (communicationOrderId != null) {
      onOpenUnifiedCommunicationHub?.call(
        'restaurants',
        communicationOrderId,
      );
      onOpenOrderCommunication?.call(communicationOrderId);
      return;
    }
    final chatTarget = _normalizedUnifiedHubTarget(message.data);
    if (chatTarget != null) {
      onOpenUnifiedCommunicationHub?.call(
        chatTarget.$1,
        chatTarget.$2,
      );
      return;
    }
    display(message);
  }

  static getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    return token!;
  }

  void display(RemoteMessage message) async {
    log('Got a message whilst in the foreground!');
    final type = message.data['type']?.toString() ?? '';
    if (type == 'order_reassigned') {
      final orderId = message.data['orderId']?.toString();
      if (orderId != null && orderId.isNotEmpty) {
        AudioService.instance.playReassignSound(orderId: orderId);
      }
    }
    if (type == 'order' || type == 'new_order' || type == 'order_update') {
      final orderId = message.data['orderId']?.toString();
      if (orderId != null && orderId.isNotEmpty) {
        AudioService.instance.playNewOrderSound(orderId: orderId);
      }
    }
    final title = type == 'order_reassigned'
        ? 'Order Reassigned'
        : _resolveTitle(
            message,
            _isChatMessage(message.data) ? 'New message' : 'Notification',
          );
    final body = type == 'order_reassigned'
        ? 'An order was reassigned due to timeout.'
        : _resolveBody(
            message,
            _isChatMessage(message.data)
                ? 'You have a new message from a customer.'
                : 'You have a new update.',
          );
    log('Message title: $title body: $body');
    try {
      if (type == 'order_reassigned') {
        final AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
          channelReassign,
          'Order Reassigned',
          channelDescription: 'Order reassigned due to timeout',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          sound: RawResourceAndroidNotificationSound('reassign'),
        );
        const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'reassign.wav',
        );
        final int id = idReassign +
            DateTime.now().millisecondsSinceEpoch.remainder(100000);
        await flutterLocalNotificationsPlugin.show(
          id,
          title,
          body,
          NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          ),
          payload: jsonEncode(message.data),
        );
        return;
      }
      final bool isChat = _isChatMessage(message.data);
      final bool isOrderType = type == 'order' ||
          type == 'new_order' ||
          type == 'order_update' ||
          type == 'pautos_assignment';
      final String channelId =
          isChat ? channelChat : (isOrderType ? channelOrder : '0');
      final String channelName = isChat
          ? 'Chat Messages'
          : (isOrderType ? 'New Orders' : 'foodie-driver');
      final AndroidNotificationChannel channel =
          AndroidNotificationChannel(
        channelId,
        channelName,
        description: isChat
            ? 'Notifications when customer sends a message'
            : (isOrderType
                ? 'Notifications for new order requests'
                : 'Show foodie Notification'),
        importance: Importance.max,
      );
      AndroidNotificationDetails notificationDetails =
          AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: isChat
            ? 'Customer chat messages'
            : (isOrderType
                ? 'Notifications for new order requests'
                : 'your channel Description'),
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
        actions: isOrderType
            ? <AndroidNotificationAction>[
                const AndroidNotificationAction(
                  'accept_order',
                  'Accept',
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
                const AndroidNotificationAction(
                  'decline_order',
                  'Decline',
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
              ]
            : null,
      );
      DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: isOrderType ? 'order_notification' : null,
      );
      NotificationDetails notificationDetailsBoth = NotificationDetails(
        android: notificationDetails,
        iOS: darwinNotificationDetails,
      );
      final int id = _isChatMessage(message.data)
          ? idChat + DateTime.now().millisecondsSinceEpoch.remainder(100000)
          : 0;
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetailsBoth,
        payload: jsonEncode(message.data),
      );
    } on Exception catch (e) {
      log(e.toString());
    }
  }

  /// Show a local notification with custom data
  Future<void> showNotification(NotificationData notificationData) async {
    try {
      String channelId;
      String channelName;
      Importance importance;
      Priority priority;

      switch (notificationData.type) {
        case NotificationType.order:
          channelId = channelOrder;
          channelName = 'New Orders';
          importance = Importance.max;
          priority = Priority.high;
          break;
        case NotificationType.earning:
          channelId = channelEarning;
          channelName = 'Earning Milestones';
          importance = Importance.high;
          priority = Priority.high;
          break;
        case NotificationType.performance:
          channelId = channelPerformance;
          channelName = 'Performance Alerts';
          importance = notificationData.priority == NotificationPriority.critical
              ? Importance.max
              : Importance.high;
          priority = notificationData.priority == NotificationPriority.critical
              ? Priority.max
              : Priority.high;
          break;
        case NotificationType.reminder:
          channelId = channelReminder;
          channelName = 'Reminders';
          importance = Importance.defaultImportance;
          priority = Priority.defaultPriority;
          break;
      }

      final int notificationId = notificationData.notificationId ??
          _getNotificationIdForType(notificationData.type);

      AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notification channel for $channelName',
        importance: importance,
        priority: priority,
        playSound: true,
        enableVibration: importance == Importance.max,
        ongoing: notificationData.priority == NotificationPriority.critical,
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        notificationId,
        notificationData.title,
        notificationData.body,
        details,
        payload: notificationData.payload != null
            ? jsonEncode(notificationData.payload)
            : null,
      );

      log('✅ Notification shown: ${notificationData.title}');
    } catch (e) {
      log('❌ Error showing notification: $e');
    }
  }

  /// Schedule a notification for a specific time
  Future<void> scheduleNotification(
    NotificationData notificationData,
    DateTime scheduledDate,
  ) async {
    try {
      // Calculate delay from now
      final now = DateTime.now();
      if (scheduledDate.isBefore(now)) {
        log('⚠️ Scheduled date is in the past, showing immediately');
        await showNotification(notificationData);
        return;
      }

      final delay = scheduledDate.difference(now);

      // For now, use Future.delayed as a workaround
      // Note: This only works when app is running
      // For true background scheduling, you'd need timezone package
      Future.delayed(delay, () async {
        await showNotification(notificationData);
      });

      log('✅ Notification scheduled: ${notificationData.title} at $scheduledDate');
    } catch (e) {
      log('❌ Error scheduling notification: $e');
    }
  }

  /// Cancel a scheduled notification
  Future<void> cancelNotification(int notificationId) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(notificationId);
      log('✅ Notification cancelled: $notificationId');
    } catch (e) {
      log('❌ Error cancelling notification: $e');
    }
  }

  /// Cancel all notifications of a specific type
  Future<void> cancelNotificationsByType(NotificationType type) async {
    try {
      final int baseId = _getNotificationIdForType(type);
      // Cancel a range of IDs (assuming max 100 notifications per type)
      for (int i = 0; i < 100; i++) {
        await flutterLocalNotificationsPlugin.cancel(baseId + i);
      }
      log('✅ Cancelled all notifications of type: $type');
    } catch (e) {
      log('❌ Error cancelling notifications by type: $e');
    }
  }

  int _getNotificationIdForType(NotificationType type) {
    switch (type) {
      case NotificationType.order:
        return idOrder;
      case NotificationType.earning:
        return idEarning;
      case NotificationType.performance:
        return idPerformance;
      case NotificationType.reminder:
        return idReminder;
    }
  }
}
