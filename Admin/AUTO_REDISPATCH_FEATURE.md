# Auto Re-Dispatch After Driver Rejection

## Overview

This feature automatically finds another rider when a driver rejects an order. If all riders are offline, it waits until a rider comes online and then automatically dispatches the order.

## How It Works

### 1. **Automatic Detection**

- The system continuously monitors orders in the `restaurant_orders` collection
- When an order status changes to "Driver Rejected" or "Order Rejected", the auto-dispatch is triggered immediately

### 2. **Finding Another Rider**

When a driver rejects an order, the system:

1. Extracts the rejected driver's ID to exclude them from future searches
2. Queries all active drivers with `isActive: true`
3. Calculates the distance from each driver to the vendor location using the Haversine formula
4. Sorts drivers by proximity and selects the nearest available driver
5. Automatically assigns the order to the new driver

### 3. **Waiting for Offline Riders**

If no active riders are available:

1. A notification appears: **"⏳ All riders offline. Waiting for a rider to come online..."**
2. The system sets up a real-time listener on the `users` collection
3. When any driver goes online (`isActive: true`), the listener is triggered
4. The order is automatically dispatched to the nearest available driver
5. A success notification appears: **"✅ Rider came online! Auto-dispatched to [Driver Name]"**

### 4. **Smart Exclusion**

- The driver who rejected the order is **automatically excluded** from the next assignment
- This prevents reassigning the same order to the driver who just rejected it

## Database Updates

### Order Document (`restaurant_orders`)

When auto-dispatch succeeds, the order is updated with:

```dart
{
  'status': 'Driver Assigned',
  'driverID': [new_driver_id],
  'driverDistance': [distance_in_km],
  'assignedAt': [server_timestamp],
  'autoReassigned': true  // NEW: Marks this as auto-reassigned
}
```

### Driver Document (`users`)

The assigned driver is updated with:

```dart
{
  'isActive': false,
  'inProgressOrderID': [order_id]  // Added to array
}
```

### Assignment Log (`assignments_log`)

A new entry is created with:

```dart
{
  'order_id': [order_id],
  'driverId': [driver_id],
  'status': 'accepted',
  'etaMinutes': [calculated_eta],
  'km': [distance],
  'score': 1.0,
  'acceptanceProb': 1.0,
  'createdAt': [server_timestamp],
  'autoReassigned': true  // NEW: Marks this as auto-reassigned
}
```

## User Experience

### For Admin Dashboard

1. **Driver Rejects Order** → Order status changes to "Driver Rejected"
2. **Immediate Feedback**:
   - If another rider is available: **"✅ Auto-dispatched to John Doe (2.5 km away)"**
   - If all riders offline: **"⏳ All riders offline. Waiting for a rider to come online..."**
3. **Background Monitoring**: The system continuously waits for riders
4. **Success Notification**: When a rider comes online, admin sees **"✅ Rider came online! Auto-dispatched to Jane Smith"**

### Console Logs

Detailed logs help track the process:

```
[Auto Re-Dispatch] Driver rejected order abc123, searching for another rider...
[Auto Re-Dispatch] Skipping rejected driver: driver_xyz
[Auto Re-Dispatch] Found driver: John Doe (driver_789) at 2.34 km
[Auto Re-Dispatch] Updated order with driver assignment
[Auto Re-Dispatch] Updated driver status
```

If no drivers available:

```
[Auto Re-Dispatch] No active riders available. Setting up listener to wait for online riders...
[Auto Re-Dispatch] Listener setup for order abc123
[Auto Re-Dispatch] Active driver detected for order abc123. Attempting assignment...
```

## Technical Details

### Listener Management

- Each waiting order has its own listener stored in `_driverListeners` map
- Listeners are automatically canceled when:
  - A driver is successfully assigned
  - The widget is disposed
- Prevents memory leaks and duplicate assignments

### AI Integration

- Uses the same distance-based AI algorithm as manual dispatch
- Prioritizes nearest available driver for optimal delivery time
- Logs all assignments to `assignments_log` for AI monitoring and improvement

### Performance

- Real-time Firebase listeners provide instant detection
- Efficient Firestore queries with indexed fields (`role`, `isActive`)
- Minimal network overhead with targeted updates

## Configuration

### No Additional Setup Required!

This feature works automatically with your existing:

- Firebase Firestore database
- User collection with driver roles
- Restaurant orders collection
- Current AI dispatch logic

## Testing the Feature

### Test Scenario 1: Another Rider Available

1. Have at least 2 active riders
2. Manually dispatch an order to Rider A
3. Have Rider A reject the order (change status to "Driver Rejected")
4. ✅ System should immediately assign to Rider B

### Test Scenario 2: All Riders Offline

1. Set all riders to `isActive: false`
2. Manually dispatch an order
3. Have the driver reject it
4. See the "Waiting for rider..." message
5. Set one rider to `isActive: true`
6. ✅ Order should auto-assign immediately

### Test Scenario 3: Rejected Driver Excluded

1. Have 3 riders: A, B, C
2. Rider A is nearest, B is second, C is farthest
3. Assign order to A
4. A rejects the order
5. ✅ System should skip A and assign to B (not A again)

## Benefits

✅ **Zero Manual Intervention**: Orders automatically find new riders
✅ **Smart Exclusion**: Rejected drivers won't get the same order twice
✅ **Real-Time Monitoring**: Detects online riders instantly
✅ **Persistent Waiting**: Keeps trying until a rider is found
✅ **Complete Logging**: All reassignments tracked in assignments_log
✅ **User-Friendly Feedback**: Clear notifications for admins

## Future Enhancements

Potential improvements:

- Add timeout after X minutes of waiting
- Send push notifications to offline riders
- Priority queue for urgent orders
- Machine learning to predict which rider will accept
- Multi-attempt logic (try top 3 nearest riders)

---

**Status**: ✅ Fully Implemented and Ready to Use
**Last Updated**: October 18, 2025

