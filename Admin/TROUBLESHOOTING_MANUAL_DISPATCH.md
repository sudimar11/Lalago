# Troubleshooting: AI Dispatch Timeout

## Error: "AI dispatch timeout"

This error means the Cloud Function didn't assign a driver within the expected time. Here's how to fix it.

## Quick Checklist

### 1. Is the Cloud Function Deployed?

**Check if deployed:**
```bash
cd "Grading System/functions"
firebase functions:list
```

**Deploy if needed:**
```bash
cd "Grading System/functions"
npm install
firebase deploy --only functions:autoDispatcher
```

### 2. Are There Available Riders?

**Check in Firebase Console:**
1. Go to Firestore Database
2. Open `users` collection
3. Find users where:
   - `role` = `"driver"`
   - `active` = `true`
   - `isAvailable` = `true`

**Or via code:**
```javascript
db.collection('users')
  .where('role', '==', 'driver')
  .where('active', '==', true)
  .where('isAvailable', '==', true)
  .get()
  .then(snapshot => {
    console.log('Available riders:', snapshot.size);
  });
```

**If NO riders available:**
- Set at least one rider to `isAvailable: true`
- Set `active: true` on rider accounts
- Ensure `role: "driver"` (not "Driver")

### 3. Check Cloud Function Logs

**View logs:**
```bash
firebase functions:log --only autoDispatcher
```

**Look for:**
- `[AI AutoDispatcher] Processing order...`
- `[AI AutoDispatcher] No available riders...`
- `[AI AutoDispatcher] Error processing order...`

### 4. Use Debug Mode

**Check Flutter logs** after clicking "Manual Dispatch (AI)":

```bash
flutter logs
```

**You should see:**
```
[Manual Dispatch] Waiting for AI assignment...
[Manual Dispatch] Poll 0: Status = Order Accepted
[Manual Dispatch] Poll 1: Status = Order Accepted
[Manual Dispatch] Poll 2: Status = Order Accepted
...
[Manual Dispatch] Poll 5: Status = Driver Assigned
[Manual Dispatch] Driver assigned! ID: rider123
```

**If stuck on "Order Accepted":**
- Cloud Function is NOT triggering
- Check deployment and Firestore rules

### 5. Check Firestore Rules

Ensure Cloud Function can write:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow Cloud Functions full access
    match /{document=**} {
      allow read, write: if request.time < timestamp.date(2099, 1, 1);
    }
  }
}
```

## Common Issues & Solutions

### Issue 1: Cloud Function Not Deployed

**Symptoms:**
- Status stays "Order Accepted"
- No logs in Firebase Functions

**Solution:**
```bash
cd "Grading System/functions"
firebase deploy --only functions:autoDispatcher
```

**Verify deployment:**
```bash
firebase functions:list
```

Should show:
```
autoDispatcher (us-central1)
```

### Issue 2: No Available Riders

**Symptoms:**
- Logs show: "No available riders"
- Error message: "No available riders found"

**Solution:**

Update at least one rider in Firestore:

```javascript
db.collection('users').doc('RIDER_ID').update({
  role: 'driver',
  active: true,
  isAvailable: true,
  currentLocation: {
    lat: 14.5995,
    lng: 120.9842
  },
  fcmToken: 'valid_fcm_token_here'
});
```

### Issue 3: Status Field Mismatch

**Symptoms:**
- Function runs but Flutter can't detect it
- Timeout after checking status multiple times

**Check status values match:**

**In Cloud Function (index.js line 119):**
```javascript
status: 'Driver Assigned'
```

**In Flutter (order_dispatcher.dart line 330):**
```dart
if (currentStatus == 'Driver Assigned')
```

**Fix:** Ensure both use exact same string (case-sensitive)

### Issue 4: Firestore Security Rules Block

**Symptoms:**
- Cloud Function deployed but not running
- Permission denied errors in logs

**Solution:**

Temporarily allow all access for testing:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;  // TEMP: Allow all for testing
    }
  }
}
```

⚠️ **Security Warning**: Use proper security rules in production!

### Issue 5: Trigger Not Working

**Symptoms:**
- Function deployed but never triggers
- No logs when order status changes

**Check trigger condition:**

In `functions/index.js` line 26:
```javascript
if (beforeData.status !== 'Order Accepted' && afterData.status === 'Order Accepted')
```

**Verify:**
1. Order status CHANGES to "Order Accepted"
2. Not already "Order Accepted" before
3. Status change is detected by Firestore

**Test manually:**
```javascript
// Set to something else first
db.collection('restaurant_orders').doc('ORDER_ID').update({
  status: 'Preparing'
});

// Wait 1 second

// Then change to Order Accepted
db.collection('restaurant_orders').doc('ORDER_ID').update({
  status: 'Order Accepted'
});
```

## Step-by-Step Debug Process

### Step 1: Run App in Debug Mode

```bash
flutter run
```

### Step 2: Click "Manual Dispatch (AI)" Button

Watch for logs:
```
[Manual Dispatch] Waiting for AI assignment...
[Manual Dispatch] Poll 0: Status = Order Accepted
[Manual Dispatch] Poll 1: Status = Order Accepted
...
```

### Step 3: Check Firebase Console

1. Open Firestore in Firebase Console
2. Navigate to `restaurant_orders` > your order
3. Watch the `status` field update in real-time
4. Should change from "Order Accepted" → "Driver Assigned"

### Step 4: Check Cloud Function Logs

```bash
firebase functions:log --only autoDispatcher --limit 50
```

Look for:
```
[AI AutoDispatcher] Processing order ORDER_ID for automatic rider assignment
[AI AutoDispatcher] Best rider assigned by AI for order ORDER_ID
[AI AutoDispatcher] FCM sent to rider RIDER_ID
[AI AutoDispatcher] Successfully dispatched order ORDER_ID to rider RIDER_ID using AI prescription
```

### Step 5: If Still Failing

Check the specific error in Flutter logs:

**"Status stuck at: Order Accepted"**
→ Cloud Function not triggering

**"Status stuck at: Preparing"**
→ Second update not completing

**"No available riders found"**
→ Add available riders to Firestore

**"Cloud Function error: [message]"**
→ Check specific error in Firebase logs

## Testing Solution

### Create Test Data

**1. Add Test Rider:**
```javascript
db.collection('users').add({
  role: 'driver',
  active: true,
  isAvailable: true,
  firstName: 'Test',
  lastName: 'Rider',
  currentLocation: {
    lat: 14.5995,
    lng: 120.9842
  },
  fcmToken: 'test_token',
  wallet_amount: 100
});
```

**2. Add Test Order:**
```javascript
db.collection('restaurant_orders').add({
  status: 'Preparing',  // Will change to Order Accepted
  restaurantLocation: { lat: 14.5995, lng: 120.9842 },
  deliveryLocation: { lat: 14.6042, lng: 120.9822 },
  createdAt: firebase.firestore.FieldValue.serverTimestamp(),
  vendor: { title: 'Test Restaurant' }
});
```

**3. Test Manual Dispatch:**
- Find the test order in app
- Click "Manual Dispatch (AI)"
- Watch logs and Firebase Console

## Firebase Console Navigation

1. **Go to Firebase Console**: https://console.firebase.google.com
2. **Select your project**
3. **Left menu > Functions** - View deployed functions and logs
4. **Left menu > Firestore Database** - View real-time data changes
5. **Left menu > Build > Functions > Logs** - View detailed function execution logs

## Emergency Workaround

If AI dispatch keeps failing, you can manually assign:

**Via Firebase Console:**
1. Open the order in Firestore
2. Add these fields:
   ```
   assignedDriverId: "RIDER_ID"
   status: "Driver Assigned"
   assignedAt: [current timestamp]
   ```

**Via code (JavaScript in browser console on Firebase Console):**
```javascript
db.collection('restaurant_orders').doc('ORDER_ID').update({
  driverID: 'RIDER_ID',
  assignedDriverId: 'RIDER_ID',
  status: 'Driver Assigned',
  assignedAt: firebase.firestore.FieldValue.serverTimestamp()
});
```

## Enhanced Debug Version

If you still can't figure it out, add this temporary code to see EVERYTHING:

**In `order_dispatcher.dart` after line 313:**

```dart
// TEMP DEBUG: Log everything
print('=== MANUAL DISPATCH DEBUG ===');
print('Order ID: $orderId');
print('Current data: ${data}');

final testDoc = await orderRef.get();
print('Order exists: ${testDoc.exists}');
print('Order data: ${testDoc.data()}');

final ridersQuery = await FirebaseFirestore.instance
    .collection('users')
    .where('role', '==', 'driver')
    .where('active', '==', true)
    .where('isAvailable', '==', true)
    .get();
    
print('Available riders count: ${ridersQuery.docs.length}');
ridersQuery.docs.forEach((doc) {
  print('Rider: ${doc.id} - ${doc.data()['firstName']}');
});
print('=== END DEBUG ===');
```

## Need More Help?

**Provide these details:**

1. **Flutter logs** (all `[Manual Dispatch]` lines)
2. **Firebase Function logs** (`firebase functions:log`)
3. **Screenshot of Firestore** showing:
   - Order document with all fields
   - At least one rider document
4. **Cloud Function deployment status** (`firebase functions:list`)

## Next Steps After Fix

Once working:
1. Remove temporary debug logs
2. Restore proper Firestore security rules
3. Test with multiple orders
4. Test with multiple riders
5. Monitor assignment logs for AI performance

