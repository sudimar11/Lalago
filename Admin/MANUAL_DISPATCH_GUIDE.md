# Manual Dispatch Button Guide

## Overview

The Manual Dispatch button allows administrators to manually trigger the AI auto-dispatcher for orders that have status **"Order Accepted"**. This uses the same AI prescription algorithm as the automatic dispatcher.

## Location

**Navigation Path**: Order Dispatcher → Recent Orders Tab

The button appears on order cards in the "Recent Orders" tab.

## Visibility

The "Manual Dispatch (AI)" button **only appears** when:
- Order status = **"Order Accepted"**

The button is **hidden** for all other order statuses.

## How It Works

### 1. User Clicks Button

When clicked, the button:
- Shows a loading indicator: "Dispatching..."
- Disables the button to prevent duplicate clicks
- Triggers the AI prescription algorithm

### 2. Behind the Scenes

The manual dispatch function performs these steps:

```dart
// Step 1: Temporarily change status to "Preparing"
// This resets the Cloud Function trigger
await orderRef.update({
  'status': 'Preparing',
  'manualDispatchRequested': true,
  'manualDispatchRequestedAt': Timestamp
});

// Step 2: Brief delay (800ms)
await Future.delayed(Duration(milliseconds: 800));

// Step 3: Change status back to "Order Accepted"
// This triggers the AI auto-dispatcher Cloud Function
await orderRef.update({
  'status': 'Order Accepted',
  'lastUpdated': Timestamp
});
```

### 3. AI Auto-Dispatcher Executes

The Cloud Function is triggered and:
1. Finds all available riders
2. Calculates AI scores (ETA + ML + Fairness)
3. Selects the best rider
4. Updates order status to "Driver Assigned"
5. Sends FCM notification to rider
6. Logs assignment to `assignments_log`

### 4. User Feedback

**Success:**
```
✅ AI Dispatch triggered! Assigning best rider...
```

**Error:**
```
❌ Dispatch failed: [error message]
```

## Visual Design

### Button Appearance

```
┌────────────────────────────────────────┐
│  ⚡ Manual Dispatch (AI)               │
└────────────────────────────────────────┘
```

- **Color**: Orange background, white text
- **Icon**: Lightning bolt (⚡) - represents AI power
- **Full Width**: Spans the card width
- **Padding**: 16px horizontal, 12px bottom

### During Dispatch

```
┌────────────────────────────────────────┐
│  ◌ Dispatching...                      │
└────────────────────────────────────────┘
```

- Shows circular progress indicator
- Button disabled (grayed out)
- Prevents multiple clicks

## Use Cases

### 1. Initial Testing
Test the AI auto-dispatcher manually before enabling automatic triggering.

### 2. Retry Failed Assignments
If automatic dispatch fails (no riders available), retry manually after riders become available.

### 3. Override Automatic Timing
Manually trigger dispatch at a specific time instead of waiting for automatic trigger.

### 4. Troubleshooting
Test the AI algorithm with specific orders to verify rider selection.

## Order Status Flow

### Manual Dispatch Flow

```
Order Accepted
      ↓
[User Clicks Button]
      ↓
Preparing (temporary)
      ↓
Order Accepted (re-trigger)
      ↓
[AI Auto-Dispatcher]
      ↓
Driver Assigned ✓
```

### Without Manual Dispatch

```
Order Accepted
      ↓
[Automatic Trigger]
      ↓
[AI Auto-Dispatcher]
      ↓
Driver Assigned ✓
```

## Fields Added to Order

When manual dispatch is triggered, these fields are added:

```javascript
{
  manualDispatchRequested: true,
  manualDispatchRequestedAt: Timestamp,
  lastUpdated: Timestamp
}
```

After AI assignment succeeds:

```javascript
{
  status: 'Driver Assigned',
  assignedDriverId: 'rider123',
  assignedDriverName: 'John Doe',
  dispatchMethod: 'AI Auto-Dispatch',
  dispatchStatus: 'success',
  dispatchMetrics: {
    eta: 15,
    mlAcceptanceProbability: 0.85,
    fairnessScore: 25,
    compositeScore: 42.5
  }
}
```

## Monitoring

### View Manual Dispatch Logs

```javascript
// Query orders with manual dispatch flag
db.collection('restaurant_orders')
  .where('manualDispatchRequested', '==', true)
  .orderBy('manualDispatchRequestedAt', 'desc')
  .get();
```

### View Assignment Results

```javascript
// Check if manual dispatch succeeded
db.collection('assignments_log')
  .where('orderId', '==', 'ORDER_ID')
  .where('assignmentMethod', '==', 'AI Auto-Dispatch')
  .get();
```

## Error Handling

### Possible Errors

1. **No Riders Available**
   - Status remains "Order Accepted"
   - `dispatchStatus: 'no_drivers_available'`
   - User can retry later

2. **Network Error**
   - Shows error snackbar
   - Button re-enabled for retry

3. **Permission Error**
   - Shows error snackbar
   - Check Firestore security rules

4. **Cloud Function Error**
   - Status remains "Order Accepted"
   - `dispatchStatus: 'error'`
   - Check Firebase Functions logs

## Best Practices

### ✅ Do

- Wait for the success message before navigating away
- Check the Recent Orders list to verify status change to "Driver Assigned"
- Review assignment logs after manual dispatch
- Use pull-to-refresh to see updated order status

### ❌ Don't

- Click the button multiple times rapidly
- Navigate away during dispatch (wait for feedback)
- Manually dispatch orders that already have a driver assigned
- Use for orders with status other than "Order Accepted"

## Technical Details

### State Management

```dart
final Set<String> _dispatching = {};

// Tracks which orders are currently being dispatched
// Prevents duplicate operations on the same order
```

### Timing

- **Temporary Status Duration**: 800ms
- **Success Message**: 3 seconds
- **Error Message**: 3 seconds
- **Total Process Time**: ~2-4 seconds

### Dependencies

- `cloud_firestore`: For Firestore operations
- `flutter/material.dart`: For UI components
- Cloud Function: `autoDispatcher`

## Testing Manual Dispatch

### 1. Setup Test Order

```javascript
db.collection('restaurant_orders').add({
  status: 'Order Accepted',
  restaurantLocation: { lat: 14.5995, lng: 120.9842 },
  deliveryLocation: { lat: 14.6042, lng: 120.9822 },
  createdAt: firebase.firestore.FieldValue.serverTimestamp(),
  vendor: {
    title: 'Test Restaurant'
  }
});
```

### 2. Verify Button Appears

- Navigate to Order Dispatcher → Recent Orders
- Find the test order
- Confirm "Manual Dispatch (AI)" button is visible

### 3. Click and Monitor

- Click the button
- Watch for "Dispatching..." state
- Wait for success message
- Pull to refresh to see status change to "Driver Assigned"

### 4. Verify Results

```javascript
// Check order was assigned
db.collection('restaurant_orders')
  .doc('ORDER_ID')
  .get()
  .then(doc => {
    console.log('Status:', doc.data().status);
    console.log('Driver:', doc.data().assignedDriverName);
  });

// Check assignment log
db.collection('assignments_log')
  .where('orderId', '==', 'ORDER_ID')
  .get();
```

## Future Enhancements

Potential improvements for manual dispatch:

1. **Confirmation Dialog**: Ask user to confirm before dispatching
2. **Rider Preview**: Show which rider will be selected before confirming
3. **Batch Dispatch**: Dispatch multiple orders at once
4. **Schedule Dispatch**: Delay dispatch to a specific time
5. **Custom Weights**: Adjust AI weights before dispatching
6. **Rider Selection**: Override AI and manually select a specific rider

## Support

If manual dispatch isn't working:

1. Check Firebase Functions logs: `firebase functions:log`
2. Verify Cloud Function is deployed
3. Check order status in Firestore
4. Verify riders are available and active
5. Review Firestore security rules
6. Check network connectivity

