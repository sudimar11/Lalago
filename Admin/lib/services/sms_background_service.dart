import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

import 'package:brgy/constants.dart';

// Top-level background message handler
@pragma('vm:entry-point')
Future<void> smsBgHandler(RemoteMessage message) async {
  // Handle background SMS messages here
  // DO NOT make any UI calls or use BuildContext
  // Only perform data processing, logging, or database operations

  try {
    // Log the received message
    print('Background SMS message received: ${message.messageId}');
    print('From: ${message.from}');
    print('Data: ${message.data}');
    print('Notification: ${message.notification?.title}');

    // Process the SMS message data
    await _processBackgroundSMS(message);
  } catch (e) {
    print('Error handling background SMS message: $e');
  }
}

// Process background SMS message
Future<void> _processBackgroundSMS(RemoteMessage message) async {
  try {
    // Extract SMS data
    final data = message.data;
    final sender = data['sender'] ?? data['from'] ?? 'Unknown';
    final content = data['content'] ?? data['body'] ?? data['message'] ?? '';
    final timestamp = data['timestamp'] ?? DateTime.now().toIso8601String();

    // Save to local database for later retrieval
    await _saveSMSMessage(sender, content, timestamp, 'received');

    print('Background SMS saved: $sender - $content');
  } catch (e) {
    print('Error processing background SMS: $e');
  }
}

// Save SMS message to local database
Future<void> _saveSMSMessage(
    String sender, String content, String timestamp, String type) async {
  try {
    // Get database path
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'brgy_database.db');

    // Open database
    final database = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        // Create SMS messages table if it doesn't exist
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sms_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sender TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            type TEXT NOT NULL,
            isRead INTEGER DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');
      },
    );

    // Insert SMS message
    await database.insert('sms_messages', {
      'sender': sender,
      'content': content,
      'timestamp': timestamp,
      'type': type,
      'isRead': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await database.close();
  } catch (e) {
    print('Error saving SMS message to database: $e');
  }
}

// SMS Background Service class for managing background SMS operations
class SMSBackgroundService {
  static final SMSBackgroundService _instance =
      SMSBackgroundService._internal();
  factory SMSBackgroundService() => _instance;
  SMSBackgroundService._internal();

  // Initialize the service
  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request notification permissions
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('User granted permission: ${settings.authorizationStatus}');

      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(smsBgHandler);

      // Configure foreground message handling
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Foreground SMS message received: ${message.messageId}');
        _handleForegroundSMS(message);
      });

      // Handle when app is opened from notification
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('App opened from SMS notification: ${message.messageId}');
        _handleNotificationTap(message);
      });

      // Get the token for this device
      String? token = await messaging.getToken();
      if (token != null) {
        print('FCM Token: $token');
        await _saveFCMToken(token);
      }

      // Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        print('FCM Token refreshed: $newToken');
        _saveFCMToken(newToken);
      });
    } catch (e) {
      print('Error initializing SMS Background Service: $e');
    }
  }

  // Handle foreground SMS messages
  void _handleForegroundSMS(RemoteMessage message) {
    try {
      final data = message.data;
      final sender = data['sender'] ?? data['from'] ?? 'Unknown';
      final content = data['content'] ?? data['body'] ?? data['message'] ?? '';

      print('Foreground SMS from $sender: $content');

      // You can trigger UI updates here since this is in foreground
      // For example, show a snackbar or update a stream
    } catch (e) {
      print('Error handling foreground SMS: $e');
    }
  }

  // Handle notification tap
  void _handleNotificationTap(RemoteMessage message) {
    try {
      final data = message.data;
      print('Notification tapped for SMS: ${data['sender']}');

      // Navigate to specific screen or handle the message
      // This will be handled by the app's navigation system
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  // Save FCM Token
  Future<void> _saveFCMToken(String token) async {
    try {
      final uid = auth.FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        print('FCM Token not saved: no signed-in admin user');
        return;
      }

      await FirebaseFirestore.instance.collection(USERS).doc(uid).set(
        {
          'fcmToken': token,
          'fcmTokens': FieldValue.arrayUnion([token]),
          'lastTokenUpdate': FieldValue.serverTimestamp(),
          'role': 'admin',
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      print('FCM Token saved to Firestore for admin user: $uid');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  // Get all SMS messages from local database
  Future<List<Map<String, dynamic>>> getSMSMessages() async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'brgy_database.db');

      final database = await openDatabase(path);

      final List<Map<String, dynamic>> messages = await database.query(
        'sms_messages',
        orderBy: 'createdAt DESC',
      );

      await database.close();
      return messages;
    } catch (e) {
      print('Error getting SMS messages: $e');
      return [];
    }
  }

  // Mark SMS message as read
  Future<void> markSMSAsRead(int messageId) async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'brgy_database.db');

      final database = await openDatabase(path);

      await database.update(
        'sms_messages',
        {'isRead': 1},
        where: 'id = ?',
        whereArgs: [messageId],
      );

      await database.close();
    } catch (e) {
      print('Error marking SMS as read: $e');
    }
  }

  // Delete SMS message
  Future<void> deleteSMSMessage(int messageId) async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'brgy_database.db');

      final database = await openDatabase(path);

      await database.delete(
        'sms_messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );

      await database.close();
    } catch (e) {
      print('Error deleting SMS message: $e');
    }
  }

  // Clear all SMS messages
  Future<void> clearAllSMSMessages() async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'brgy_database.db');

      final database = await openDatabase(path);

      await database.delete('sms_messages');

      await database.close();
    } catch (e) {
      print('Error clearing SMS messages: $e');
    }
  }
}
