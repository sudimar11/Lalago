# AI Auto Dispatcher Setup Guide

## Overview

The AI Auto Dispatcher automatically assigns restaurant orders to the best available rider when order status becomes **'Order Accepted'**. The system uses AI prescription with a composite scoring algorithm that considers:

1. **ETA (50% weight)** - Distance/time from rider to restaurant
2. **ML Acceptance Probability (30% weight)** - Likelihood of rider accepting (Vertex AI - currently stubbed)
3. **Fairness Score (20% weight)** - Ensures equal distribution of orders among riders

## Quick Start

### 1. Prerequisites

- Firebase CLI installed: `npm install -g firebase-tools`
- Firebase project configured
- Node.js 18+ installed

### 2. Install Dependencies

```bash
cd "e:\ayos 5\Grading System\functions"
npm install
```

### 3. Login to Firebase

```bash
firebase login
```

### 4. Initialize Firebase Project (if not already done)

```bash
firebase use --add
# Select your Firebase project
```

### 5. Deploy the Function

```bash
firebase deploy --only functions:autoDispatcher
```

Or deploy all functions:

```bash
firebase deploy --only functions
```

### 6. Deploy Firestore Indexes

```bash
firebase deploy --only firestore:indexes
```

## Testing

### Local Emulator Testing

1. Start the emulator:

```bash
cd functions
npm run serve
```

2. The function will be available at `http://localhost:5001/YOUR_PROJECT/us-central1/autoDispatcher`

### Manual Testing

1. Create a test order in Firestore:

```javascript
// In Firebase Console or via app
db.collection("restaurant_orders").add({
  status: "Preparing", // Will change to 'Order Accepted' to trigger AI
  restaurantLocation: { lat: 14.5995, lng: 120.9842 },
  deliveryLocation: { lat: 14.6042, lng: 120.9822 },
  customerName: "Test Customer",
  items: ["Test Item"],
  totalAmount: 500,
  createdAt: firebase.firestore.FieldValue.serverTimestamp(),
});
```

2. Update the order status to 'Order Accepted' to trigger AI auto-dispatch:

```javascript
db.collection("restaurant_orders").doc("ORDER_ID").update({
  status: "Order Accepted",
});
```

3. Check the function logs:

```bash
firebase functions:log
```

## Data Requirements

### Rider Setup

Riders must have these fields in `users` collection:

```javascript
{
  userId: "rider123",
  role: "driver",
  active: true,
  isAvailable: true,
  firstName: "John",
  lastName: "Doe",
  currentLocation: {
    lat: 14.5995,
    lng: 120.9842
  },
  fcmToken: "fcm_token_here"  // For push notifications
}
```

### Order Setup

Orders must have these fields:

```javascript
{
  orderId: "order123",
  status: "Order Accepted",  // This triggers the AI auto-dispatcher
  restaurantLocation: {
    lat: 14.5995,
    lng: 120.9842
  },
  deliveryLocation: {
    lat: 14.6042,
    lng: 120.9822
  },
  createdAt: Timestamp
}
```

## Function Outputs

### Updated Order Fields

After successful AI auto-dispatch:

```javascript
{
  assignedDriverId: "rider123",
  assignedDriverName: "John Doe",
  estimatedETA: 15,  // minutes
  status: "Driver Assigned",  // Auto-assigned by AI
  assignedAt: Timestamp,
  dispatchStatus: "success",
  dispatchMethod: "AI Auto-Dispatch",
  dispatchMetrics: {
    eta: 15,
    mlAcceptanceProbability: 0.85,
    fairnessScore: 25,
    compositeScore: 42.5,
    alternativeDriversCount: 4
  }
}
```

### Assignment Log Entry

Created in `assignments_log` collection:

```javascript
{
  orderId: "order123",
  driverId: "rider123",
  driverName: "John Doe",
  assignedAt: Timestamp,
  metrics: {
    eta: 15,
    mlAcceptanceProbability: 0.85,
    fairnessScore: 25,
    compositeScore: 42.5
  },
  allDriverScores: [
    // Array of all candidate riders with their AI scores
  ],
  assignmentMethod: "AI Auto-Dispatch",
  restaurantLocation: { lat: 14.5995, lng: 120.9842 },
  deliveryLocation: { lat: 14.6042, lng: 120.9822 }
}
```

## Troubleshooting

### No Riders Available

If you see `dispatchStatus: 'no_drivers_available'` and status remains 'Order Accepted':

- Check that riders have `role: 'driver'`
- Ensure `active: true`
- Ensure `isAvailable: true`

### AI Auto-Dispatch Not Triggering

- Verify the order status changes from any status to 'Order Accepted'
- Check function logs: `firebase functions:log`
- Verify Firestore rules allow the function to read/write

### FCM Not Sending

- Ensure riders have valid `fcmToken` field
- Check FCM configuration in Firebase Console
- Verify Cloud Messaging API is enabled
- FCM notification will indicate "AI Auto-Dispatch" in the title

## Customization

### Adjust Scoring Weights

In `functions/index.js`, modify the `calculateCompositeScore()` function:

```javascript
const weights = {
  eta: 0.5, // Change these values
  ml: 0.3, // Total should equal 1.0
  fairness: 0.2,
};
```

### Change ETA Calculation

Modify the `calculateETA()` function to:

- Use Google Maps Distance Matrix API
- Account for traffic
- Use real-time routing

### Integrate Vertex AI

Replace the stubbed `getMLAcceptanceProbability()` function with actual Vertex AI calls (see functions/README.md for details).

## Monitoring

### View Logs

```bash
firebase functions:log --only autoDispatcher
```

### View in Firebase Console

1. Go to Firebase Console → Functions
2. Click on `autoDispatcher`
3. View metrics, logs, and performance

### Query Assignment Logs

```javascript
// Get all AI auto-dispatch assignments for a specific rider
db.collection("assignments_log")
  .where("driverId", "==", "rider123")
  .where("assignmentMethod", "==", "AI Auto-Dispatch")
  .orderBy("assignedAt", "desc")
  .limit(10)
  .get();

// Get AI assignments for date range
db.collection("assignments_log")
  .where("assignmentMethod", "==", "AI Auto-Dispatch")
  .where("assignedAt", ">=", startDate)
  .where("assignedAt", "<=", endDate)
  .get();
```

## Cost Considerations

- Function executes on every `restaurant_orders` update where status becomes 'Order Accepted'
- AI algorithm queries all active available riders
- Writes to 3 locations (order, rider, assignment_log)
- Sends 1 FCM message per AI auto-dispatch

Estimated cost per AI dispatch: ~$0.0001 - $0.001 depending on number of riders

## Next Steps

1. **Deploy indexes**: `firebase deploy --only firestore:indexes`
2. **Deploy function**: `firebase deploy --only functions:autoDispatcher`
3. **Test with sample data**
4. **Monitor logs and metrics**
5. **Integrate Vertex AI** when ready (see functions/README.md)
6. **Tune weights** based on real-world performance
7. **Add ML model** for acceptance prediction

## Support

For issues or questions, check:

- Function logs: `firebase functions:log`
- Firebase Console: https://console.firebase.google.com
- Firestore data in Firebase Console
