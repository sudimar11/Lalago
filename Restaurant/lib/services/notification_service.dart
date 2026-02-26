import 'dart:convert';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  log("BackGround Message :: ${message.messageId}");
}

class NotificationService {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void Function(String orderId, String minutes)? onPrepTimeReminder;
  static void Function(String orderId)? onNewOrder;

  initInfo() async {
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
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

    if (request.authorizationStatus == AuthorizationStatus.authorized || request.authorizationStatus == AuthorizationStatus.provisional) {
      const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      var iosInitializationSettings = const DarwinInitializationSettings();
      final InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid, iOS: iosInitializationSettings);
      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          final payload = details.payload;
          if (payload != null && payload.startsWith('order_acceptance|')) {
            final orderId = payload.substring('order_acceptance|'.length);
            if (orderId.isNotEmpty) onNewOrder?.call(orderId);
          }
        },
      );
      final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'prep_reminders',
            'Preparation Time Reminders',
            description: 'Notifications for order preparation time',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'new_order_channel',
            'New Orders',
            description: 'New order notifications',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      }
      setupInteractedMessage();
    }
  }

  Future<void> setupInteractedMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      FirebaseMessaging.onBackgroundMessage((message) => firebaseMessageBackgroundHandle(message));
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log("::::::::::::onMessage:::::::::::::::::");
      if (message.notification != null) {
        log(message.notification.toString());
        display(message);
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      log("::::::::::::onMessageOpenedApp:::::::::::::::::");
      if (message.notification != null) {
        log(message.notification.toString());
        display(message);
      }
    });
    log("::::::::::::Permission authorized:::::::::::::::::");
    await FirebaseMessaging.instance.subscribeToTopic("QuicklAI");
  }

  static getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    return token!;
  }

  void display(RemoteMessage message) async {
    final data = message.data;
    if (data['type'] == 'prep_time_reminder') {
      final orderId = data['orderId'] ?? '';
      final minutes = data['minutesLeft'] ?? data['minutesUntilReady'] ?? '';
      onPrepTimeReminder?.call(orderId, minutes);
    }
    if (data['type'] == 'new_order') {
      final orderId = (data['orderId'] ?? '').toString();
      if (orderId.isNotEmpty) {
        onNewOrder?.call(orderId);
      }
    }
    log('Got a message whilst in the foreground!');
    log('Message data: ${message.notification?.body.toString() ?? ''}');
    try {
      final isPrepReminder = data['type'] == 'prep_time_reminder';
      final isNewOrder = data['type'] == 'new_order';
      const prepChannel = AndroidNotificationChannel(
        'prep_reminders',
        'Preparation Time Reminders',
        description: 'Notifications for order preparation time',
        importance: Importance.high,
      );
      const newOrderChannel = AndroidNotificationChannel(
        'new_order_channel',
        'New Orders',
        description: 'New order notifications',
        importance: Importance.max,
      );
      final defaultChannel = AndroidNotificationChannel(
        '0',
        'foodie-customer',
        description: 'Show Foodie Notification',
        importance: Importance.max,
      );
      final AndroidNotificationChannel channelToUse = isPrepReminder
          ? prepChannel
          : (isNewOrder ? newOrderChannel : defaultChannel);
      AndroidNotificationDetails notificationDetails =
          AndroidNotificationDetails(
        channelToUse.id,
        channelToUse.name,
        channelDescription: channelToUse.description,
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
      String? payload = jsonEncode(data);
      if (data['type'] == 'new_order' && data['orderId'] != null) {
        payload = 'order_acceptance|${data['orderId']}';
      }
      await FlutterLocalNotificationsPlugin().show(
        (message.data['orderId']?.hashCode ?? 0) & 0x7FFFFFFF,
        message.notification?.title ?? 'Notification',
        message.notification?.body ?? '',
        notificationDetailsBoth,
        payload: payload,
      );
    } on Exception catch (e) {
      log(e.toString());
    }
  }
}
