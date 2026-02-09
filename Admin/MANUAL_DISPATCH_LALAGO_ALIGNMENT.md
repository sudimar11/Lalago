# Manual Dispatch AI - LalaGo-Restaurant Database Alignment

## Summary

Updated the Manual Dispatch (AI) feature to align with LalaGo-Restaurant database structure while maintaining AI-driven rider assignment functionality.

## Changes Made

### 1. **order_dispatcher.dart** - Flutter UI

#### Database Field Alignment

- **Driver ID Detection**: Now checks multiple field name variations
  ```dart
  final driverId = (data['driverId'] ??
                    data['driverID'] ??
                    data['driver_id'] ?? '') as String? ?? '';
  ```

#### Manual Dispatch Function Rewrite

**Previous Approach**: Attempted to trigger Cloud Function by toggling order status
**New Approach**: Direct driver assignment following LalaGo-Restaurant pattern

**Key Changes**:

1. **Driver Query**: Uses `isActive: true` (not `active` or `isAvailable`)

   ```dart
   .where('role', isEqualTo: 'driver')
   .where('isActive', isEqualTo: true)
   ```

2. **Distance Calculation**: Implements Haversine formula to find nearest driver

   ```dart
   double calculateDistance(lat1, lon1, lat2, lon2)
   ```

3. **Order Update**: Follows LalaGo-Restaurant schema

   ```dart
   await orderRef.update({
     'status': 'Driver Assigned',
     'driverID': driverId,
     'driverDistance': distance,
     'assignedAt': FieldValue.serverTimestamp(),
   });
   ```

4. **Driver Status Update**: Updates driver availability

   ```dart
   await FirebaseFirestore.instance.collection('users').doc(driverId).update({
     'isActive': false,
     'inProgressOrderID': FieldValue.arrayUnion([orderId]),
   });
   ```

5. **Assignment Logging**: Logs to `assignments_log` for AI monitoring
   ```dart
   await FirebaseFirestore.instance.collection('assignments_log').add({
     'order_id': orderId,
     'driverId': driverId,
     'status': 'accepted',
     'etaMinutes': (distance / 0.5).round(),
     'km': distance,
     'score': 1.0,
     'acceptanceProb': 1.0,
     'createdAt': FieldValue.serverTimestamp(),
     'manualDispatch': true,
   });
   ```

#### Rider Information Display for Completed Orders

- **New Widget**: `_RiderInfoWidget` displays rider name and GPS location
- **Conditions**: Only shows for orders with status "Order Completed" (status == 3)
- **Data Fetched**:
  - Rider name: `firstName` + `lastName` from `users` collection
  - GPS location: `location.latitude` and `location.longitude`
- **Visual Design**: Green container with delivery icon and location pin

### 2. **functions/index.js** - Cloud Function

#### Database Field Alignment

1. **Driver Query**: Changed from `active` and `isAvailable` to `isActive`

   ```javascript
   .where('role', '==', 'driver')
   .where('isActive', '==', true)  // Changed from 'active' and 'isAvailable'
   ```

2. **Order Assignment**: Added LalaGo-Restaurant fields

   ```javascript
   await change.after.ref.update({
     driverID: bestDriver.driverId,
     driverDistance: bestDriver.distance, // NEW
     assignedDriverName: bestDriver.driverName,
     estimatedETA: bestDriver.eta,
     status: "Driver Assigned",
     assignedAt: admin.firestore.FieldValue.serverTimestamp(),
     // ... AI metrics
   });
   ```

3. **Driver Status Update**: Follows LalaGo-Restaurant pattern
   ```javascript
   await db
     .collection("users")
     .doc(bestDriver.driverId)
     .update({
       isActive: false, // Changed from 'isAvailable'
       inProgressOrderID: admin.firestore.FieldValue.arrayUnion(orderId), // Changed from 'currentOrderId'
       lastAssignedAt: admin.firestore.FieldValue.serverTimestamp(),
     });
   ```

## Database Schema Alignment

### Order Document (`restaurant_orders` collection)

```javascript
{
  id: "order_id",
  status: "Order Accepted" | "Driver Assigned" | "Order Shipped" | "completed",
  driverID: "driver_user_id",          // Driver assignment
  driverDistance: 5.23,                 // Distance in km
  assignedAt: Timestamp,
  vendor: {
    latitude: 14.5995,
    longitude: 120.9842,
    // ... other vendor fields
  },
  // ... other order fields
}
```

### Driver Document (`users` collection)

```javascript
{
  id: "user_id",
  role: "driver",
  isActive: true,                       // Availability status
  inProgressOrderID: ["order1", "..."], // Array of active orders
  firstName: "John",
  lastName: "Doe",
  location: {
    latitude: 14.5995,
    longitude: 120.9842
  },
  // ... other driver fields
}
```

### Assignment Log (`assignments_log` collection)

```javascript
{
  order_id: "order_id",
  driverId: "driver_user_id",
  status: "accepted",
  etaMinutes: 15,
  km: 5.23,
  score: 1.0,
  acceptanceProb: 1.0,
  createdAt: Timestamp,
  manualDispatch: true  // Indicates manual trigger
}
```

## AI Prescription Maintained

### Distance-Based Selection

- **Algorithm**: Haversine formula for accurate distance calculation
- **Selection**: Nearest available driver is selected (AI prescription)
- **Scoring**: Distance is primary factor, with perfect score for manual dispatch

### Benefits

1. **Fast Assignment**: Direct database updates, no polling needed
2. **Consistent Schema**: Matches LalaGo-Restaurant exactly
3. **AI Monitoring**: All assignments logged for AI analysis
4. **Real-time Updates**: Uses Flutter streams for live UI updates

## Testing Checklist

- [ ] Test Manual Dispatch button appears on "Order Accepted" status
- [ ] Verify driver query finds active drivers with `isActive: true`
- [ ] Confirm order status changes to "Driver Assigned"
- [ ] Check `driverID` and `driverDistance` fields are set
- [ ] Verify driver `isActive` changes to `false`
- [ ] Confirm `inProgressOrderID` array updated
- [ ] Check assignment logged to `assignments_log`
- [ ] Test completed orders show rider name and location
- [ ] Verify GPS coordinates display correctly

## Files Modified

1. `lib/order_dispatcher.dart` - Manual dispatch logic + rider info display
2. `functions/index.js` - Cloud Function database alignment

## References

- LalaGo-Restaurant: `lib/ui/ordersScreen/OrdersScreen.dart` (lines 1354-1479)
- LalaGo-Restaurant: `lib/ui/ordersScreen/CompletedOrdersScreen.dart` (lines 415-725)
- LalaGo-Restaurant: `lib/model/OrderModel.dart`
