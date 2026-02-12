import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';


class TimerPage extends StatefulWidget {
  const TimerPage({Key? key}) : super(key: key);

  @override
  _TimerPageState createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Timer? _timer; // Countdown timer
  int _remainingSeconds = 300; // Example: 5 minutes (300 seconds)

  bool isPop = false;

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _requestNotificationPermission();
    _startTimer(); // Start the countdown timer
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  void setPop(bool value) {
    setState(() {
      isPop = value;
    });
  }

  // Request notification permission
  Future<void> _requestNotificationPermission() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
  }

  // Initialize local notifications
  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'timer_channel',
      'Timer Notifications',
      description: 'Notifications for the timer',
      importance: Importance.max,
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // Start the countdown timer
  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _showTimerEndNotification(); // Notify user when the timer ends
      }
    });
  }

  // Show notification when the timer ends
  Future<void> _showTimerEndNotification() async {
    try {
      // Android: disable flutter_local_notifications to avoid
      // "Too many inflation attempts" SIGABRT crashes.
      if (Platform.isAndroid) return;
      await flutterLocalNotificationsPlugin.show(
        1,
        'Timer Ended',
        'Your timer has completed!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'timer_channel',
            'Timer Notifications',
            channelDescription: 'Notifications for the timer',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      print('Notification Error: $e');
    }
  }

  // Show remaining time on notification when app is closed
  Future<void> _showRemainingTimeNotification() async {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    try {
      // Android: disable flutter_local_notifications to avoid
      // "Too many inflation attempts" SIGABRT crashes.
      if (Platform.isAndroid) return;
      await flutterLocalNotificationsPlugin.show(
        2,
        'Timer Paused',
        'Remaining time: $minutes:${seconds.toString().padLeft(2, '0')}',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'timer_channel',
            'Timer Notifications',
            channelDescription: 'Notifications for the timer',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      print('Notification Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: PopScope(
        onPopInvokedWithResult: (isPop, dyanmic) async {
          _showRemainingTimeNotification(); // Show notification on app close
          return setPop(true); // Allow app to close
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Timer Page'),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Remaining Time:',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_remainingSeconds ~/ 60}:${(_remainingSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      fontSize: 48, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
