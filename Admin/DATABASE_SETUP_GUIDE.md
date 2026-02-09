# Database Setup for AI Auto-Dispatcher

## Your Current Database Structure

Based on your Firestore data in **asia-southeast1**, here's what you need:

## 1. Create Driver/Rider Documents

Your `users` collection needs driver documents with this structure:

```javascript
{
  // Required for AI Dispatcher
  role: "driver",  // MUST be exactly "driver" (lowercase)
  active: true,
  isAvailable: true,  // Set to true when driver is available for orders
  
  // Driver info
  firstName: "Juan",
  lastName: "Dela Cruz",
  email: "driver@example.com",
  phoneNumber: "+639123456789",
  
  // Location (REQUIRED for ETA calculation)
  location: {
    latitude: 6.0567071,   // Current driver location
    longitude: 121.0083779
  },
  
  // FCM token for notifications
  fcmToken: "driver_fcm_token_here",
  
  // Optional but useful
  wallet_amount: 100,
  createdAt: firebase.firestore.FieldValue.serverTimestamp(),
  lastOnlineTimestamp: firebase.firestore.FieldValue.serverTimestamp(),
  profilePictureURL: "",
  
  // Other fields from your customer structure
  appIdentifier: "Flutter Uber Eats Driver android",
  settings: {
    pushNewMessages: true,
    orderUpdates: true,
    newArrivals: true,
    promotions: true
  }
}
```

## 2. Convert Existing Customer to Driver (For Testing)

If you want to test, you can temporarily change a customer to driver:

### Via Firebase Console:
1. Go to Firestore Database
2. Find a user in `users` collection
3. Edit the document:
   - Change `role` from `"customer"` to `"driver"`
   - Add field `isAvailable` = `true`
   - Make sure `active` = `true`
   - Ensure `location` field has `latitude` and `longitude`

### Via Code:
```javascript
db.collection('users').doc('USER_ID').update({
  role: 'driver',
  isAvailable: true,
  active: true,
  location: {
    latitude: 6.0567071,
    longitude: 121.0083779
  }
});
```

## 3. Order Structure (Already Correct)

Your orders already have the right structure:

```javascript
{
  status: "Order Accepted",  // Triggers AI when set to this
  driverID: "...",  // Will be filled by AI
  
  // Customer info
  author: {
    firstName: "Ada",
    lastName: "Asari",
    location: {
      latitude: 6.0567071,
      longitude: 121.0083779
    },
    fcmToken: "..."
  },
  
  // Restaurant info
  vendor: {
    title: "SNEAK N' SNACK",
    latitude: 6.0416973,  // Restaurant location
    longitude: 121.0070786,
    // ... other vendor fields
  },
  
  // Delivery address
  address: {
    location: {
      latitude: 6.0567071,
      longitude: 121.0083779
    },
    landmark: "...",
    locality: "..."
  }
}
```

## 4. Deploy the Updated Cloud Function

```bash
cd "Grading System/functions"
firebase deploy --only functions:autoDispatcher
```

## 5. Test the Setup

### Step 1: Verify You Have a Driver

```javascript
// In Firebase Console > Firestore > Query
db.collection('users')
  .where('role', '==', 'driver')
  .where('active', '==', true)
  .where('isAvailable', '==', true)
  .get();
```

Should return at least 1 driver.

### Step 2: Create Test Order (or use existing)

```javascript
db.collection('restaurant_orders').add({
  status: 'Preparing',  // Start with this
  
  author: {
    firstName: "Test",
    lastName: "Customer",
    id: "test_customer_id",
    location: {
      latitude: 6.0567071,
      longitude: 121.0083779
    },
    fcmToken: "test_token"
  },
  
  vendor: {
    title: "Test Restaurant",
    latitude: 6.0416973,
    longitude: 121.0070786,
    id: "test_vendor_id"
  },
  
  address: {
    location: {
      latitude: 6.0567071,
      longitude: 121.0083779
    },
    landmark: "Test location",
    locality: "Jolo, Sulu"
  },
  
  products: [
    {
      name: "Test Product",
      price: "100",
      quantity: 1
    }
  ],
  
  deliveryCharge: "50.00",
  createdAt: firebase.firestore.FieldValue.serverTimestamp()
});
```

### Step 3: Trigger AI Dispatcher

Change the order status:

```javascript
db.collection('restaurant_orders').doc('ORDER_ID').update({
  status: 'Order Accepted'
});
```

OR use the "Manual Dispatch (AI)" button in your Flutter app!

### Step 4: Verify Assignment

After a few seconds, check the order:

```javascript
db.collection('restaurant_orders').doc('ORDER_ID').get()
  .then(doc => {
    const data = doc.data();
    console.log('Status:', data.status);  // Should be "Driver Assigned"
    console.log('Driver ID:', data.driverID);
    console.log('Dispatch Method:', data.dispatchMethod);  // "AI Auto-Dispatch"
    console.log('Metrics:', data.dispatchMetrics);
  });
```

## 6. Check Assignment Logs

```javascript
db.collection('assignments_log')
  .orderBy('assignedAt', 'desc')
  .limit(10)
  .get()
  .then(snapshot => {
    snapshot.forEach(doc => {
      console.log('Assignment:', doc.data());
    });
  });
```

## Common Field Names in Your Database

| What It Is | Your Field Name | Cloud Function Looks For |
|-----------|----------------|------------------------|
| Driver ID | `driverID` | `driverID` ✅ |
| Driver location | `location.latitude/longitude` | `location` ✅ |
| Restaurant location | `vendor.latitude/longitude` | `vendor.latitude` ✅ |
| Delivery location | `address.location.latitude/longitude` | `address.location` ✅ |
| Customer location | `author.location.latitude/longitude` | `author.location` ✅ |

## Quick Checklist

- [ ] At least one user has `role: "driver"`
- [ ] Driver has `isAvailable: true`
- [ ] Driver has `active: true`
- [ ] Driver has `location` with `latitude` and `longitude`
- [ ] Driver has valid `fcmToken`
- [ ] Cloud Function deployed: `firebase deploy --only functions:autoDispatcher`
- [ ] Order has `status: "Order Accepted"` to trigger
- [ ] Order has `vendor` with `latitude` and `longitude`
- [ ] Order has `address` or `author` with location data

## Create a Driver via Firebase Console

**Easy way:**

1. Go to Firebase Console → Firestore Database
2. Click `users` collection
3. Click "+ Add document"
4. Use Auto-ID
5. Add these fields:

| Field | Type | Value |
|-------|------|-------|
| role | string | driver |
| active | boolean | true |
| isAvailable | boolean | true |
| firstName | string | Test |
| lastName | string | Driver |
| email | string | driver@test.com |
| phoneNumber | string | +639123456789 |
| location | map | (create map) |
| location.latitude | number | 6.0567071 |
| location.longitude | number | 121.0083779 |
| fcmToken | string | test_fcm_token |
| wallet_amount | number | 100 |
| createdAt | timestamp | (use Firebase timestamp) |

6. Click "Save"

## Verify Everything is Ready

Run this in Firebase Console (in the "Query" section):

```javascript
// Check drivers
db.collection('users')
  .where('role', '==', 'driver')
  .where('active', '==', true)
  .where('isAvailable', '==', true)
  .get()
  .then(snapshot => {
    console.log('Available drivers:', snapshot.size);
    snapshot.forEach(doc => {
      const d = doc.data();
      console.log('- Driver:', d.firstName, d.lastName);
      console.log('  Location:', d.location);
      console.log('  FCM Token:', d.fcmToken ? 'Yes' : 'No');
    });
  });
```

Expected output:
```
Available drivers: 1
- Driver: Test Driver
  Location: {latitude: 6.0567071, longitude: 121.0083779}
  FCM Token: Yes
```

If you see this, you're ready to test the AI Auto-Dispatcher!

