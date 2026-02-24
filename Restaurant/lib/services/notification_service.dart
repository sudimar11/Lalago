import 'dart:convert';
import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  log("BackGround Message :: ${message.messageId}");
}

class NotificationService {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static void Function(String orderId, String minutes)? onPrepTimeReminder;

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
      await flutterLocalNotificationsPlugin.initialize(initializationSettings, onDidReceiveNotificationResponse: (payload) {});
      final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
          'prep_reminders',
          'Preparation Time Reminders',
          description: 'Notifications for order preparation time',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ));
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
    log('Got a message whilst in the foreground!');
    log('Message data: ${message.notification?.body.toString() ?? ''}');
    try {
      final isPrepReminder = data['type'] == 'prep_time_reminder';
      const channel = AndroidNotificationChannel(
        'prep_reminders',
        'Preparation Time Reminders',
        description: 'Notifications for order preparation time',
        importance: Importance.high,
      );
      final defaultChannel = AndroidNotificationChannel(
        '0',
        'foodie-customer',
        description: 'Show Foodie Notification',
        importance: Importance.max,
      );
      final channelToUse = isPrepReminder ? channel : defaultChannel;
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
      await FlutterLocalNotificationsPlugin().show(
        0,
        message.notification?.title ?? 'Notification',
        message.notification?.body ?? '',
        notificationDetailsBoth,
        payload: jsonEncode(data),
      );
    } on Exception catch (e) {
      log(e.toString());
    }
  }
}
