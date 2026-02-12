import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:foodie_driver/model/notification_model.dart';
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

  /// Call from background message handler to show notification from FCM data.
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
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

  // Notification channel IDs
  static const String channelOrder = 'order_notifications';
  static const String channelEarning = 'earning_notifications';
  static const String channelPerformance = 'performance_notifications';
  static const String channelReminder = 'reminder_notifications';
  static const String channelChat = 'chat_messages';

  // Notification IDs for different types
  static const int idOrder = 1000;
  static const int idEarning = 2000;
  static const int idPerformance = 3000;
  static const int idReminder = 4000;
  static const int idChat = 5000;

  static bool _notificationPermissionDialogShown = false;

  /// Returns true if notification permission is granted (enables pop-up display).
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
  /// Call when the app has context (e.g. from ContainerScreen).
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
            'To receive pop-up notifications when customers send you chat '
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
      onDidReceiveNotificationResponse: (payload) {},
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

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(reminderChannel);
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(chatChannel);
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
        type == 'admin_driver_chat' ||
        messageType == 'chat';
  }

  Future<void> setupInteractedMessage() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log("::::::::::::onMessage:::::::::::::::::");
      log(message.notification?.toString() ?? 'data: ${message.data}');
      if (_isChatMessage(message.data)) {
        log("RIDER: Chat message received (foreground) - showing local notification");
      }
      display(message);
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log("::::::::::::onMessageOpenedApp:::::::::::::::::");
      log(message.notification?.toString() ?? 'data: ${message.data}');
      display(message);
    });
    log("RIDER: FCM onMessage listener registered for chat notifications");
    await FirebaseMessaging.instance.subscribeToTopic("QuicklAI");
  }

  static getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    return token!;
  }

  void display(RemoteMessage message) async {
    log('Got a message whilst in the foreground!');
    final title = _resolveTitle(
      message,
      _isChatMessage(message.data) ? 'New message' : 'Notification',
    );
    final body = _resolveBody(
      message,
      _isChatMessage(message.data)
          ? 'You have a new message from a customer.'
          : 'You have a new update.',
    );
    log('Message title: $title body: $body');
    try {
      final bool isChat = _isChatMessage(message.data);
      final String channelId = isChat ? channelChat : '0';
      final String channelName = isChat ? 'Chat Messages' : 'foodie-driver';
      final AndroidNotificationChannel channel =
          AndroidNotificationChannel(
        channelId,
        channelName,
        description: isChat
            ? 'Notifications when customer sends a message'
            : 'Show foodie Notification',
        importance: Importance.max,
      );
      AndroidNotificationDetails notificationDetails =
          AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: isChat
            ? 'Customer chat messages'
            : 'your channel Description',
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
      );
      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
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
