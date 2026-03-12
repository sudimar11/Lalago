import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:foodie_restaurant/services/notification_action_handler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> firebaseMessageBackgroundHandle(RemoteMessage message) async {
  log("BackGround Message :: ${message.messageId}");
}

class NotificationService {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static void Function(String orderId, String minutes)? onPrepTimeReminder;
  static void Function(String orderId)? onNewOrder;
  static void Function(String orderId)? onDeclineOrder;
  static void Function(String orderId)? onOpenOrderCommunication;
  static bool _notificationPermissionDialogShown = false;

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
            'To receive new order alerts and messages, '
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
        onDidReceiveNotificationResponse: (details) async {
          final payload = details.payload;
          final actionId = details.actionId;
          if (payload == null || payload.isEmpty) return;
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>?;
            if (actionId != null && actionId.isNotEmpty) {
              await NotificationActionHandler.handleAction(
                null,
                actionId,
                data,
              );
              return;
            }
            if (payload.startsWith('order_acceptance|')) {
              final orderId = payload.substring('order_acceptance|'.length);
              if (orderId.isNotEmpty) onNewOrder?.call(orderId);
            }
            final orderId = data?['orderId']?.toString() ?? '';
            final type = data?['type']?.toString() ?? '';
            if (type == 'order_communication' && orderId.isNotEmpty) {
              onOpenOrderCommunication?.call(orderId);
            }
          } catch (_) {
            if (payload.startsWith('order_acceptance|')) {
              final orderId = payload.substring('order_acceptance|'.length);
              if (orderId.isNotEmpty) onNewOrder?.call(orderId);
            }
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
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'actionable_notifications',
            'Actionable Notifications',
            description: 'Notifications with action buttons',
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
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      Future.delayed(const Duration(seconds: 1), () {
        _handleOpenedMessage(initialMessage!);
      });
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
      _handleOpenedMessage(message);
    });
    log("::::::::::::Permission authorized:::::::::::::::::");
    await FirebaseMessaging.instance.subscribeToTopic("QuicklAI");
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString() ?? '';
    if (type == 'new_order') {
      final orderId = (data['orderId'] ?? '').toString();
      if (orderId.isNotEmpty) onNewOrder?.call(orderId);
    } else if (type == 'prep_time_reminder') {
      final orderId = (data['orderId'] ?? '').toString();
      final minutes =
          data['minutesLeft']?.toString() ?? data['minutesUntilReady'] ?? '';
      if (orderId.isNotEmpty) onPrepTimeReminder?.call(orderId, minutes);
    } else if (type == 'order_communication') {
      final orderId = (data['orderId'] ?? '').toString();
      if (orderId.isNotEmpty) onOpenOrderCommunication?.call(orderId);
    } else {
      display(message);
    }
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
    if (data['type'] == 'order_communication') {
      final orderId = (data['orderId'] ?? '').toString();
      if (orderId.isNotEmpty) {
        onOpenOrderCommunication?.call(orderId);
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
      final hasActions = data['actions'] != null && isNewOrder;
      AndroidNotificationDetails notificationDetails =
          AndroidNotificationDetails(
        hasActions ? 'actionable_notifications' : channelToUse.id,
        channelToUse.name,
        channelDescription: channelToUse.description,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'ticker',
        actions: isNewOrder
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
        categoryIdentifier: isNewOrder ? 'order_notification' : null,
      );
      NotificationDetails notificationDetailsBoth = NotificationDetails(
        android: notificationDetails,
        iOS: darwinNotificationDetails,
      );
      final String payload = jsonEncode(data);
      await flutterLocalNotificationsPlugin.show(
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
