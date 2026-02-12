# Laravel Backend Integration for Manual Dispatch (AI)

## Overview

The Manual Dispatch (AI) button now integrates with your existing Laravel backend notification system. This guide shows how to enable the Laravel backend call after AI assigns a rider.

## Current Flow

```
User Clicks "Manual Dispatch (AI)"
         ↓
Status: "Preparing" (temporary)
         ↓
Status: "Order Accepted" (triggers Cloud Function)
         ↓
AI Cloud Function Executes
  • Calculates best rider
  • Assigns rider
  • Sends FCM notification
  • Updates status to "Driver Assigned"
         ↓
Flutter App Polls for Assignment (max 10 seconds)
         ↓
Gets Assigned Driver ID & FCM Token
         ↓
[OPTIONAL] Calls Laravel Backend
         ↓
Shows Success Message with Driver Name
```

## Enable Laravel Backend Call

### Step 1: Add HTTP Package to Flutter

Add to `pubspec.yaml`:

```yaml
dependencies:
  http: ^1.1.0
```

Run:
```bash
flutter pub get
```

### Step 2: Add Import to `order_dispatcher.dart`

Add at the top of the file:

```dart
import 'package:http/http.dart' as http;
import 'dart:convert';
```

### Step 3: Configure Laravel Backend URL

In `order_dispatcher.dart`, find the commented section (around line 374) and replace:

```dart
/*
final response = await http.post(
  Uri.parse('YOUR_LARAVEL_URL/foodie_admin/order/$orderId/assign-rider'),
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  },
  body: jsonEncode({
    'driver_id': assignedDriverId,
    'fcm_token': fcmToken,
  }),
);

if (response.statusCode != 200) {
  throw Exception('Backend notification failed: ${response.body}');
}
*/
```

With:

```dart
// Call Laravel backend to send additional notification
final response = await http.post(
  Uri.parse('https://yourdomain.com/foodie_admin/order/$orderId/assign-rider'),
  headers: {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  },
  body: jsonEncode({
    'driver_id': assignedDriverId,
    'fcm_token': fcmToken,
  }),
).timeout(
  const Duration(seconds: 15),
  onTimeout: () {
    // Return a fake response on timeout
    throw Exception('Laravel backend timeout');
  },
);

if (response.statusCode != 200) {
  throw Exception('Backend notification failed: ${response.body}');
}

final result = jsonDecode(response.body);
if (result['assigned'] != true) {
  throw Exception('Backend assignment failed');
}
```

### Step 4: Update Your Laravel Backend URL

Replace `https://yourdomain.com` with your actual Laravel backend URL.

Example:
```dart
Uri.parse('https://api.yourdomain.com/foodie_admin/order/$orderId/assign-rider')
```

## Laravel Backend Endpoint

Your existing Laravel endpoint should already handle this:

```php
// Route: POST /foodie_admin/order/{orderId}/assign-rider
// File: app/Http/Controllers/OrderController.php

public function assignRider(Request $request, $orderId)
{
    $validated = $request->validate([
        'driver_id' => 'required|string',
        'fcm_token' => 'required|string',
    ]);

    try {
        // 1. Update Firestore (optional, already done by Cloud Function)
        // Your existing code...

        // 2. Send FCM notification via Laravel
        $notification = [
            'title' => 'New Order Assignment (AI Auto-Dispatch)',
            'body' => "You have been automatically assigned order #{$orderId} by AI"
        ];

        $data = [
            'orderId' => $orderId,
            'type' => 'order_assignment',
            'dispatchMethod' => 'AI Auto-Dispatch'
        ];

        // Send via Firebase Cloud Messaging
        $this->sendFCM($validated['fcm_token'], $notification, $data);

        return response()->json([
            'assigned' => true,
            'notified' => true,
            'driver_id' => $validated['driver_id'],
            'order_id' => $orderId
        ]);

    } catch (\Exception $e) {
        return response()->json([
            'assigned' => false,
            'error' => $e->getMessage()
        ], 500);
    }
}
```

## Data Flow Comparison

### Your Original Manual Assignment (from Blade code)

```javascript
// JavaScript (Blade template)
assignDriver(orderId, driverId)
  ↓
Update Firestore: driverID, status = 'Driver Assigned'
  ↓
Fetch driver FCM token
  ↓
Call Laravel: /order/{orderId}/assign-rider
  ↓
Laravel sends FCM notification
  ↓
Success/Error alert
```

### New AI Manual Dispatch (Flutter)

```dart
// Flutter (order_dispatcher.dart)
_manualDispatch(context, orderId, data)
  ↓
Trigger AI Cloud Function
  ↓
Cloud Function AI selects best rider
  ↓
Cloud Function updates Firestore + sends FCM
  ↓
Flutter polls for assignment result
  ↓
[OPTIONAL] Call Laravel backend for additional notification
  ↓
Show success with driver name
```

## Benefits of This Approach

### 1. **AI-Powered Selection**
- Uses the existing AI prescription algorithm
- Considers ETA, ML acceptance probability, and fairness
- No manual driver selection needed

### 2. **Dual Notification System**
- Cloud Function sends immediate FCM
- Laravel backend can send additional notifications (SMS, email, etc.)

### 3. **Consistent with Your Code**
- Uses your existing Laravel endpoint
- Same notification format
- Compatible with your current infrastructure

### 4. **Graceful Degradation**
- Works even if Laravel backend is down (Cloud Function FCM still sent)
- Shows appropriate error messages

## Testing

### Test 1: AI Dispatch Without Laravel Backend

1. Keep the Laravel call commented out
2. Click "Manual Dispatch (AI)" button
3. Should show: "✅ AI assigned [Driver Name] to order! Rider notified."
4. FCM sent by Cloud Function

### Test 2: AI Dispatch With Laravel Backend

1. Uncomment the Laravel call
2. Update the URL to your backend
3. Click "Manual Dispatch (AI)" button
4. Should show same success message
5. Both Cloud Function FCM AND Laravel notification sent

### Test 3: Error Handling

1. Use invalid backend URL
2. Click button
3. Should show error message
4. But order still assigned by AI (Cloud Function succeeded)

## Configuration Options

### Option A: Cloud Function Only (Default)

```dart
// Keep Laravel call commented out
// Fastest, simplest, single notification via Cloud Function
```

### Option B: Both Cloud Function + Laravel

```dart
// Uncomment Laravel call
// Dual notifications, integrates with existing system
// Slower but more comprehensive
```

### Option C: Laravel Fallback

```dart
// Try Cloud Function first
// If FCM fails, call Laravel as backup
try {
  // Cloud Function executes
} catch (e) {
  // Call Laravel backend as fallback
}
```

## Monitoring

### View AI Assignments

```javascript
// Firebase Console or Firebase Admin SDK
db.collection('assignments_log')
  .where('assignmentMethod', '==', 'AI Auto-Dispatch')
  .where('manualDispatchRequested', '==', true)
  .orderBy('assignedAt', 'desc')
  .get();
```

### Check Laravel Logs

```bash
# Laravel logs
tail -f storage/logs/laravel.log

# Look for:
# - POST /foodie_admin/order/{orderId}/assign-rider
# - FCM notification success/failure
# - Response times
```

## Troubleshooting

### Problem: "AI dispatch timeout - no driver assigned"

**Causes:**
- No available riders
- Cloud Function not deployed
- Firestore rules blocking function

**Solution:**
- Check Cloud Function logs: `firebase functions:log`
- Verify riders are active and available
- Check Firestore security rules

### Problem: "Backend notification failed"

**Causes:**
- Laravel backend down
- Invalid URL
- CORS issues
- Network timeout

**Solution:**
- Verify Laravel backend is running
- Check URL is correct
- Test endpoint with Postman
- Check CORS headers in Laravel

### Problem: Driver notified twice

**Cause:**
- Both Cloud Function FCM AND Laravel FCM sent

**Solution:**
- This is expected behavior if both are enabled
- Choose one notification method or deduplicate on driver app

## Next Steps

1. **Add HTTP package** to `pubspec.yaml`
2. **Add import** to `order_dispatcher.dart`
3. **Uncomment Laravel call** (optional)
4. **Update Laravel URL** to your domain
5. **Test with sample order**
6. **Monitor logs** for errors
7. **Adjust based on your needs** (Cloud Function only vs. dual notification)

## Example: Complete Function with Laravel Integration

```dart
Future<void> _manualDispatch(
    BuildContext context, String orderId, Map<String, dynamic> data) async {
  setState(() => _dispatching.add(orderId));

  try {
    final orderRef = FirebaseFirestore.instance
        .collection('restaurant_orders')
        .doc(orderId);

    // Trigger AI Cloud Function
    await orderRef.update({'status': 'Preparing'});
    await Future.delayed(const Duration(milliseconds: 800));
    await orderRef.update({'status': 'Order Accepted'});

    // Wait for AI assignment
    String? assignedDriverId;
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final doc = await orderRef.get();
      final data = doc.data();
      
      if (data?['status'] == 'Driver Assigned') {
        assignedDriverId = data?['assignedDriverId'] ?? data?['driverID'];
        break;
      }
    }

    if (assignedDriverId == null) {
      throw Exception('AI dispatch timeout');
    }

    // Get driver info
    final driverDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(assignedDriverId)
        .get();
    
    final driverData = driverDoc.data();
    final fcmToken = driverData?['fcmToken'] ?? '';

    // Call Laravel backend (OPTIONAL)
    if (fcmToken.isNotEmpty) {
      final response = await http.post(
        Uri.parse('https://yourdomain.com/foodie_admin/order/$orderId/assign-rider'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'driver_id': assignedDriverId,
          'fcm_token': fcmToken,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        // Non-fatal error - Cloud Function already sent FCM
        print('Laravel notification failed: ${response.body}');
      }
    }

    // Show success
    if (context.mounted) {
      final driverName = '${driverData?['firstName']} ${driverData?['lastName'] ?? ''}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ AI assigned $driverName to order!'),
          backgroundColor: Colors.green,
        ),
      );
    }

  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI Dispatch failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _dispatching.remove(orderId));
    }
  }
}
```

## Summary

✅ **AI automatically selects best rider**  
✅ **Uses existing Cloud Function (ETA + ML + Fairness)**  
✅ **Compatible with your Laravel backend**  
✅ **Graceful error handling**  
✅ **Dual notification support (optional)**  
✅ **Shows driver name on success**  
✅ **10-second timeout for AI assignment**  
✅ **Integrates seamlessly with your existing code**

