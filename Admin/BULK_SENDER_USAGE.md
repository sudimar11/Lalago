# Bulk SMS Sender Usage Guide

## Overview

The `BulkSender` class provides a robust solution for sending bulk SMS messages with paginated Firestore queries, throttled sending, progress tracking, and cancellation support. It's designed to prevent UI hangs and provide real-time feedback during large SMS campaigns.

## Features

✅ **Paginated Firestore Queries**: Efficiently loads recipients using `limit()` and `startAfterDocument()`
✅ **Throttled Sending**: Configurable delays between SMS and batches
✅ **Progress Tracking**: Real-time progress callbacks for UI updates
✅ **Cancellation Support**: Cancel operations at any time
✅ **Retry Logic**: Automatic retries for failed SMS
✅ **Firestore Logging**: Comprehensive logging of campaigns and results
✅ **Batch Processing**: Process recipients in configurable batches
✅ **Error Handling**: Robust error handling and recovery

## Quick Start

### 1. Basic Usage

```dart
import 'package:brgy/bulk_sender.dart';

// Create bulk sender instance
final bulkSender = BulkSender();

// Initialize
await bulkSender.initialize();

// Send to all active users
final stats = await bulkSender.sendToUsers(
  message: 'Hello from your app!',
  progressCallback: (current, total, status) {
    print('Progress: $current/$total - $status');
  },
);

print('Sent: ${stats.totalSent}, Failed: ${stats.totalFailed}');
```

### 2. Advanced Configuration

```dart
// Custom configuration
final config = BulkSMSConfig(
  pageSize: 100,           // Load 100 recipients per Firestore query
  batchSize: 20,           // Process 20 SMS per batch
  perSMSDelay: Duration(milliseconds: 1000),  // 1 second between SMS
  perBatchPause: Duration(seconds: 5),        // 5 seconds between batches
  maxRetries: 3,           // Retry failed SMS up to 3 times
  useFallback: true,       // Use fallback SMS method if primary fails
);

final stats = await bulkSender.sendToUsers(
  message: 'Custom configured message',
  config: config,
  progressCallback: (current, total, status) {
    // Update UI progress
  },
  batchProgressCallback: (batchNum, totalBatches, batchCurrent, batchTotal) {
    // Update batch progress
  },
);
```

### 3. Send to Specific Collections

```dart
// Send to students in a specific class
final stats = await bulkSender.sendToStudents(
  message: 'Grade notification for Math 101',
  classId: 'math_101_2024',
  config: BulkSMSConfig(batchSize: 10),
);

// Send to custom collection with filters
final stats = await bulkSender.sendBulkSMS(
  collection: 'custom_recipients',
  message: 'Custom message',
  filters: {
    'status': 'active',
    'region': 'north',
  },
);
```

## Configuration Options

### BulkSMSConfig

| Parameter       | Type     | Default | Description                                      |
| --------------- | -------- | ------- | ------------------------------------------------ |
| `pageSize`      | int      | 50      | Number of recipients to load per Firestore query |
| `batchSize`     | int      | 10      | Number of SMS to send per batch                  |
| `perSMSDelay`   | Duration | 500ms   | Delay between individual SMS                     |
| `perBatchPause` | Duration | 2s      | Pause between batches                            |
| `maxRetries`    | int      | 3       | Maximum retry attempts for failed SMS            |
| `useFallback`   | bool     | true    | Use fallback SMS method if primary fails         |

## Progress Tracking

### Progress Callbacks

```dart
// Overall progress callback
void progressCallback(int current, int total, String status) {
  // current: Number of recipients processed
  // total: Total number of recipients
  // status: Current status message
}

// Batch progress callback
void batchProgressCallback(int batchNumber, int totalBatches, int batchCurrent, int batchTotal) {
  // batchNumber: Current batch (1-based)
  // totalBatches: Total number of batches
  // batchCurrent: Current SMS in batch
  // batchTotal: Total SMS in current batch
}
```

### Example UI Integration

```dart
class BulkSMSWidget extends StatefulWidget {
  @override
  _BulkSMSWidgetState createState() => _BulkSMSWidgetState();
}

class _BulkSMSWidgetState extends State<BulkSMSWidget> {
  final BulkSender _bulkSender = BulkSender();
  double _progress = 0.0;
  String _status = 'Ready';
  bool _isRunning = false;

  void _updateProgress(int current, int total, String status) {
    setState(() {
      _progress = total > 0 ? current / total : 0.0;
      _status = status;
    });
  }

  Future<void> _startSending() async {
    setState(() => _isRunning = true);

    try {
      final stats = await _bulkSender.sendToUsers(
        message: 'Test message',
        progressCallback: _updateProgress,
      );

      // Show results
      _showResults(stats);
    } catch (e) {
      // Handle error
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(value: _progress),
        Text('Status: $_status'),
        ElevatedButton(
          onPressed: _isRunning ? null : _startSending,
          child: Text(_isRunning ? 'Sending...' : 'Start'),
        ),
        if (_isRunning)
          ElevatedButton(
            onPressed: () => _bulkSender.cancel(),
            child: Text('Cancel'),
          ),
      ],
    );
  }
}
```

## Cancellation

```dart
// Cancel at any time
bulkSender.cancel();

// Check if cancelled
if (bulkSender.isCancelled) {
  print('Operation was cancelled');
}

// Check if running
if (bulkSender.isRunning) {
  print('Bulk sending in progress');
}
```

## Firestore Logging

### Automatic Logging

The bulk sender automatically logs results to Firestore:

```dart
// Log results to Firestore
await bulkSender.logResultsToFirestore(
  campaignId: 'campaign_123',
  message: 'Original message',
);
```

### Logged Data

**Campaign Summary** (`sms_campaigns` collection):

```json
{
  "message": "Original SMS message",
  "stats": {
    "totalRecipients": 150,
    "totalSent": 145,
    "totalFailed": 3,
    "totalSkipped": 2,
    "successRate": 96.7,
    "duration": 125,
    "startTime": "2024-01-15T10:30:00Z",
    "endTime": "2024-01-15T10:32:05Z"
  },
  "timestamp": "2024-01-15T10:32:05Z",
  "status": "completed"
}
```

**Individual Results** (`sms_results` collection):

```json
{
  "campaignId": "campaign_123",
  "recipientId": "user_456",
  "phoneNumber": "+639123456789",
  "success": true,
  "method": "telephony",
  "timestamp": "2024-01-15T10:30:15Z"
}
```

## Error Handling

### Common Errors

1. **Permission Denied**: SMS permissions not granted
2. **Network Error**: Firestore connection issues
3. **Invalid Phone Numbers**: Recipients with empty/invalid phone numbers
4. **Rate Limiting**: Carrier rate limits exceeded

### Error Recovery

```dart
try {
  final stats = await bulkSender.sendToUsers(message: 'Test');
} catch (e) {
  if (e.toString().contains('PERMISSION_DENIED')) {
    // Request SMS permissions
  } else if (e.toString().contains('NETWORK')) {
    // Retry with exponential backoff
  } else {
    // Handle other errors
  }
}
```

## Performance Optimization

### Recommended Settings

**For Small Campaigns (< 100 recipients):**

```dart
BulkSMSConfig(
  pageSize: 50,
  batchSize: 10,
  perSMSDelay: Duration(milliseconds: 500),
  perBatchPause: Duration(seconds: 2),
)
```

**For Large Campaigns (> 1000 recipients):**

```dart
BulkSMSConfig(
  pageSize: 100,
  batchSize: 20,
  perSMSDelay: Duration(milliseconds: 1000),
  perBatchPause: Duration(seconds: 5),
)
```

**For High-Volume Campaigns:**

```dart
BulkSMSConfig(
  pageSize: 200,
  batchSize: 50,
  perSMSDelay: Duration(milliseconds: 2000),
  perBatchPause: Duration(seconds: 10),
)
```

### Best Practices

1. **Start Small**: Begin with small batch sizes and increase gradually
2. **Monitor Progress**: Always implement progress callbacks
3. **Handle Cancellation**: Provide cancel functionality for long campaigns
4. **Log Results**: Always log results to Firestore for tracking
5. **Test First**: Test with a small subset before large campaigns
6. **Respect Rate Limits**: Use appropriate delays to avoid carrier limits

## Integration Examples

### 1. Grade Notifications

```dart
Future<void> sendGradeNotifications(String classId, String subject) async {
  final bulkSender = BulkSender();
  await bulkSender.initialize();

  final message = '''
Grade Update for $subject:
Your grades have been updated. Please check the portal for details.
Thank you!
  '''.trim();

  final stats = await bulkSender.sendToStudents(
    message: message,
    classId: classId,
    config: BulkSMSConfig(
      batchSize: 15,
      perSMSDelay: Duration(milliseconds: 1000),
    ),
  );

  print('Grade notifications sent: ${stats.totalSent}/${stats.totalRecipients}');
}
```

### 2. Emergency Notifications

```dart
Future<void> sendEmergencyNotification(String message) async {
  final bulkSender = BulkSender();
  await bulkSender.initialize();

  final stats = await bulkSender.sendToUsers(
    message: 'URGENT: $message',
    config: BulkSMSConfig(
      batchSize: 25,
      perSMSDelay: Duration(milliseconds: 500),
      maxRetries: 5,
    ),
  );

  // Log emergency notification
  await bulkSender.logResultsToFirestore(
    campaignId: 'emergency_${DateTime.now().millisecondsSinceEpoch}',
    message: message,
  );
}
```

### 3. Scheduled Campaigns

```dart
class ScheduledCampaign {
  final BulkSender _bulkSender = BulkSender();

  Future<void> runScheduledCampaign() async {
    await _bulkSender.initialize();

    // Load campaign from Firestore
    final campaign = await loadCampaignFromFirestore();

    final stats = await _bulkSender.sendBulkSMS(
      collection: campaign.collection,
      message: campaign.message,
      filters: campaign.filters,
      config: campaign.config,
    );

    // Update campaign status
    await updateCampaignStatus(campaign.id, stats);
  }
}
```

## Troubleshooting

### Common Issues

1. **UI Freezes**: Ensure you're using progress callbacks and not blocking the main thread
2. **Memory Issues**: For very large campaigns, consider processing in smaller chunks
3. **Firestore Timeouts**: Increase `pageSize` and add retry logic
4. **SMS Failures**: Check permissions and phone number formats

### Debug Information

```dart
// Enable debug logging
bulkSender.stats.results.forEach((result) {
  print('${result.phoneNumber}: ${result.success ? "SUCCESS" : "FAILED"} - ${result.error}');
});

// Check statistics
print('Success Rate: ${bulkSender.stats.successRate}%');
print('Duration: ${bulkSender.stats.duration}');
```

## API Reference

### BulkSender Methods

- `initialize()`: Initialize the bulk sender
- `sendToUsers()`: Send to users collection
- `sendToStudents()`: Send to students collection
- `sendBulkSMS()`: Send to custom collection
- `cancel()`: Cancel current operation
- `logResultsToFirestore()`: Log results to Firestore
- `dispose()`: Clean up resources

### Properties

- `isRunning`: Check if bulk sending is in progress
- `isCancelled`: Check if operation was cancelled
- `stats`: Access sending statistics

### Data Models

- `BulkSMSConfig`: Configuration options
- `SMSRecipient`: Recipient data model
- `SMSResult`: Individual SMS result
- `BulkSMSStats`: Overall statistics
