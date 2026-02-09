# SMS Background Message Handler Setup

This document explains how to set up and use the SMS background message handler in the Brgy application.

## Overview

The application now includes a top-level `@pragma('vm:entry-point') smsBgHandler` that can receive SMS messages in the background without crashing the app. This handler is configured with `FirebaseMessaging.onBackgroundMessage()` and `listenInBackground: true`.

## Key Features

- **Background SMS Handling**: Receives SMS messages even when the app is not in the foreground
- **No UI Calls**: Prevents crashes by avoiding any UI-related operations in background mode
- **Local Database Storage**: Automatically saves received messages to SQLite database
- **Foreground Integration**: Seamlessly integrates with the existing Receive SMS UI

## Setup Instructions

### 1. Dependencies

The following dependencies have been added to `pubspec.yaml`:

```yaml
dependencies:
  firebase_messaging: ^14.7.20
```

Run `flutter pub get` to install the new dependency.

### 2. Firebase Configuration

Ensure your Firebase project has:
- Firebase Cloud Messaging (FCM) enabled
- Proper notification permissions configured
- `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) files in place

### 3. Android Manifest Permissions

Add the following permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
```

### 4. iOS Configuration

For iOS, ensure you have:
- Push notification capability enabled in Xcode
- Proper notification permissions in `Info.plist`

## How It Works

### Background Message Handler

```dart
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
```

### Key Points

1. **`@pragma('vm:entry-point')`**: This annotation ensures the function is not removed during compilation
2. **No UI Calls**: The handler only performs data operations, logging, and database saves
3. **Error Handling**: Comprehensive error handling prevents crashes
4. **Async Operations**: Properly handles asynchronous database operations

### Message Processing

When a background SMS is received:

1. **Message Extraction**: Extracts sender, content, and timestamp from the FCM message
2. **Database Storage**: Saves the message to local SQLite database
3. **Logging**: Logs the operation for debugging purposes
4. **No UI Updates**: Avoids any UI-related operations that could cause crashes

## Database Schema

The SMS messages are stored in a table called `sms_messages` with the following structure:

```sql
CREATE TABLE sms_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sender TEXT NOT NULL,
  content TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  type TEXT NOT NULL,
  isRead INTEGER DEFAULT 0,
  createdAt TEXT NOT NULL
);
```

## Integration with UI

### Receive SMS Card

The existing Receive SMS card in `adddashboard.dart` now:

- **Loads Real Messages**: Fetches messages from the SMS background service database
- **Fallback to Demo**: Shows sample messages if no real messages exist
- **Database Operations**: Integrates with the background service for clearing and managing messages

### Key Methods

- `_refreshInbox()`: Loads messages from the background service database
- `_clearInbox()`: Clears both UI and database messages
- `_simulateIncomingSMS()`: Creates test messages and saves them to database

## Testing

### 1. Test SMS Button

Use the "Test SMS" button in the Receive SMS card to:
- Generate random test messages
- Verify database storage
- Test UI integration

### 2. Background Testing

To test background message handling:

1. Send a test FCM message to your device
2. Ensure the app is in the background
3. Check logs for background handler execution
4. Verify message storage in database

### 3. Foreground Testing

To test foreground message handling:

1. Keep the app in foreground
2. Send test FCM messages
3. Verify immediate UI updates
4. Check notification handling

## Troubleshooting

### Common Issues

1. **Messages Not Appearing**: Check database permissions and table creation
2. **Background Handler Not Working**: Verify `@pragma('vm:entry-point')` annotation
3. **Permission Errors**: Ensure proper notification permissions are granted
4. **Database Errors**: Check SQLite configuration and table schema

### Debug Information

The service provides comprehensive logging:

```dart
print('Background SMS message received: ${message.messageId}');
print('From: ${message.from}');
print('Data: ${message.data}');
print('Notification: ${message.notification?.title}');
```

### Error Handling

All operations are wrapped in try-catch blocks:

```dart
try {
  // Operation code
} catch (e) {
  print('Error handling background SMS message: $e');
}
```

## Security Considerations

1. **Message Validation**: Always validate incoming message data
2. **Database Security**: Use proper SQL injection prevention
3. **Permission Management**: Request only necessary permissions
4. **Error Logging**: Avoid logging sensitive information

## Performance Optimization

1. **Database Operations**: Use efficient queries and indexing
2. **Message Limits**: Implement message count limits to prevent memory issues
3. **Background Processing**: Minimize background processing time
4. **Resource Management**: Properly close database connections

## Future Enhancements

Potential improvements include:

1. **Message Encryption**: Encrypt sensitive message content
2. **Cloud Sync**: Sync messages with Firebase Firestore
3. **Advanced Filtering**: Implement message filtering and search
4. **Notification Customization**: Customize notification appearance
5. **Message Categories**: Organize messages by type or sender

## Support

For issues or questions:

1. Check the console logs for error messages
2. Verify Firebase configuration
3. Test with simple FCM messages first
4. Ensure all dependencies are properly installed

## Conclusion

The SMS background message handler provides a robust, crash-free way to receive SMS messages in the background. By following the setup instructions and best practices, you can ensure reliable message delivery and storage without compromising app stability.
