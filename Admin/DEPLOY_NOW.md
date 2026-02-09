# Deploy AI Auto-Dispatcher - Quick Guide

## What Changed

✅ **Cloud Function now works with YOUR database structure**:
- Reads location from `vendor.latitude/longitude`
- Reads delivery from `address.location` or `author.location`
- Saves to `driverID` field (your database field name)
- Handles driver location from `location.latitude/longitude`

## Deploy Steps

### Step 1: Deploy Cloud Function

**Option A: Using Firebase CLI (if installed)**
```powershell
cd "E:\ayos 5\Grading System\functions"
firebase deploy --only functions:autoDispatcher
```

**Option B: Deploy all functions**
```powershell
cd "E:\ayos 5\Grading System\functions"
firebase deploy --only functions
```

### Step 2: Create a Test Driver

Go to **Firebase Console → Firestore Database**:

1. Click `users` collection
2. Click "+ Add document"
3. Use "Auto-ID" for document ID
4. Add these fields:

| Field Name | Type | Value |
|-----------|------|-------|
| `role` | string | `driver` |
| `active` | boolean | `true` |
| `isAvailable` | boolean | `true` |
| `firstName` | string | `Juan` |
| `lastName` | string | `Cruz` |
| `location` | map | *create a map* |
| `location.latitude` | number | `6.0567071` |
| `location.longitude` | number | `121.0083779` |
| `fcmToken` | string | *copy from a real device* |
| `wallet_amount` | number | `100` |

5. Click "Save"

### Step 3: Test in Your Flutter App

1. **Hot restart** your Flutter app:
   ```
   Press R (capital R) in terminal
   ```

2. Go to **Order Dispatcher** tab

3. Find an order with status **"Order Accepted"**

4. Click **"⚡ Manual Dispatch (AI)"** button

5. Watch the logs in your terminal:
   ```
   [Manual Dispatch] Waiting for AI assignment...
   [Manual Dispatch] Poll 0: Status = Order Accepted
   [Manual Dispatch] Poll 1: Status = Order Accepted
   [Manual Dispatch] Poll 2: Status = Driver Assigned
   [Manual Dispatch] Driver assigned! ID: DRIVER_ID
   ```

6. Should show success: **"✅ AI assigned Juan Cruz to order!"**

## Verify It Worked

### Check the Order in Firestore:

```javascript
// In Firebase Console, check your order document
// Should have these new fields:

{
  status: "Driver Assigned",
  driverID: "DRIVER_DOC_ID",
  assignedDriverId: "DRIVER_DOC_ID",
  assignedDriverName: "Juan Cruz",
  dispatchMethod: "AI Auto-Dispatch",
  dispatchStatus: "success",
  estimatedETA: 5,
  dispatchMetrics: {
    eta: 5,
    mlAcceptanceProbability: 0.85,
    fairnessScore: 0,
    compositeScore: 23.5
  }
}
```

### Check Assignment Logs:

```javascript
// Look in assignments_log collection
// Should have a new document with:

{
  orderId: "YOUR_ORDER_ID",
  driverId: "DRIVER_DOC_ID",
  driverName: "Juan Cruz",
  assignmentMethod: "AI Auto-Dispatch",
  metrics: { ... },
  allDriverScores: [ ... ]
}
```

## If It Still Times Out

### Debug Checklist:

1. **Is Cloud Function deployed?**
   ```powershell
   firebase functions:list
   ```
   Should show: `autoDispatcher (asia-southeast1)`

2. **Is there an available driver?**
   - In Firestore, check `users` collection
   - Find user with `role: "driver"`
   - Check `isAvailable: true`
   - Check `active: true`

3. **Check Flutter logs:**
   ```
   [Manual Dispatch] Poll 0: Status = Order Accepted
   [Manual Dispatch] Poll 1: Status = Order Accepted
   ...
   ```
   
   If stuck on "Order Accepted":
   - Cloud Function not triggering
   - Check Firebase Functions logs: `firebase functions:log`

4. **Check Firebase Functions logs:**
   ```powershell
   firebase functions:log --only autoDispatcher --limit 20
   ```
   
   Look for:
   - `[AI AutoDispatcher] Processing order...`
   - `[AI AutoDispatcher] No available riders...` (means no drivers)
   - `[AI AutoDispatcher] Error...` (shows specific error)

## Quick Test Without Flutter App

You can test the Cloud Function directly via Firebase Console:

1. Go to Firestore Database
2. Find an order document
3. Set status to something else first: `status: "Preparing"`
4. Wait 2 seconds
5. Change status to: `status: "Order Accepted"`
6. Watch the document update in real-time
7. Should change to `status: "Driver Assigned"` within 5 seconds

## Database Region

Your database is in: **asia-southeast1**

Make sure your Cloud Function is also deployed to the same region. Check `firebase.json`:

```json
{
  "functions": {
    "source": "functions",
    "runtime": "nodejs18"
  }
}
```

## Emergency: Manual Assignment

If AI keeps failing, manually assign via Firestore Console:

1. Open the order document
2. Click "Edit"
3. Add/update these fields:
   - `driverID`: *paste driver document ID*
   - `status`: `"Driver Assigned"`
   - `assignedAt`: *click "timestamp" and set to now*
4. Click "Save"

## Success Indicators

✅ Order status changes to "Driver Assigned"
✅ `driverID` field is populated
✅ `dispatchMethod` = "AI Auto-Dispatch"
✅ New document in `assignments_log` collection
✅ Flutter app shows success message with driver name

## Files Updated

- ✅ `functions/index.js` - Works with YOUR database structure
- ✅ `lib/order_dispatcher.dart` - Checks `driverID` field
- ✅ `DATABASE_SETUP_GUIDE.md` - Setup instructions
- ✅ `DEPLOY_NOW.md` - This deployment guide

## Next: Deploy Now!

```powershell
cd "E:\ayos 5\Grading System\functions"
firebase deploy --only functions:autoDispatcher
```

Then test in your Flutter app! 🚀

