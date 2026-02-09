# AI Auto-Dispatch Flow

## Overview

The AI Auto-Dispatcher automatically assigns the best available rider to orders using machine learning prescription when the order status becomes **'Order Accepted'**.

## Trigger Event

```
Order Status Changes → 'Order Accepted'
```

## AI Prescription Flow

```
1. Order Status = 'Order Accepted'
   ↓
2. AI AutoDispatcher Triggered
   ↓
3. Query Available Riders
   (role=driver, active=true, isAvailable=true)
   ↓
4. Calculate AI Scores for Each Rider
   • ETA (50% weight)
   • ML Acceptance Probability (30% weight) [Vertex AI - stubbed]
   • Fairness Score (20% weight)
   ↓
5. AI Composite Score Calculation
   Score = (ETA × 0.5) + (ML × 0.3) + (Fairness × 0.2)
   ↓
6. Select Best Rider (Lowest Score)
   ↓
7. Update Order Status → 'Driver Assigned'
   + Add rider info
   + Add dispatchMethod: 'AI Auto-Dispatch'
   + Add AI metrics
   ↓
8. Mark Rider as Unavailable
   ↓
9. Send FCM Notification
   "New Order Assignment (AI Auto-Dispatch)"
   ↓
10. Log to assignments_log
    assignmentMethod: 'AI Auto-Dispatch'
```

## Status States

| Status          | Description                                 |
| --------------- | ------------------------------------------- |
| Order Accepted  | Triggers AI auto-dispatch                   |
| Driver Assigned | Successfully assigned by AI                 |
| Order Accepted  | Kept if no riders available or error occurs |

## Key Fields

### Order Document After AI Assignment

```javascript
{
  status: 'Driver Assigned',          // Changed by AI
  assignedDriverId: 'rider123',       // AI selected
  assignedDriverName: 'John Doe',     // AI selected
  estimatedETA: 15,                   // Calculated
  dispatchMethod: 'AI Auto-Dispatch', // AI indicator
  dispatchStatus: 'success',
  dispatchMetrics: {
    eta: 15,
    mlAcceptanceProbability: 0.85,
    fairnessScore: 25,
    compositeScore: 42.5,
    alternativeDriversCount: 4
  }
}
```

### Assignment Log

```javascript
{
  assignmentMethod: 'AI Auto-Dispatch',
  allDriverScores: [/* All candidates with AI scores */],
  metrics: {/* Winning rider's AI scores */}
}
```

## AI Scoring Breakdown

### ETA Score (50% weight)

- Haversine distance calculation
- Assumes 30 km/h average speed
- Lower distance = lower score = better

### ML Acceptance Probability (30% weight)

- Vertex AI prediction (currently stubbed)
- Predicts likelihood of rider accepting
- Higher probability = lower score = better

### Fairness Score (20% weight)

- Based on completed orders today
- 0-20 orders → 0-100 score
- Fewer orders = lower score = better

### Composite Score

```
Final Score = (Normalized ETA × 0.5) +
              (Normalized ML × 0.3) +
              (Normalized Fairness × 0.2)
```

**Lower score wins** = AI prescription

## Error Handling

### No Riders Available

```javascript
{
  status: 'Order Accepted',  // Kept unchanged
  dispatchStatus: 'no_drivers_available',
  dispatchAttemptedAt: Timestamp
}
```

### Error During Dispatch

```javascript
{
  status: 'Order Accepted',  // Kept unchanged
  dispatchStatus: 'error',
  dispatchError: 'Error message',
  dispatchAttemptedAt: Timestamp
}
```

## Testing the AI Auto-Dispatch

### 1. Create Order

```javascript
db.collection("restaurant_orders").add({
  status: "Preparing",
  restaurantLocation: { lat: 14.5995, lng: 120.9842 },
  deliveryLocation: { lat: 14.6042, lng: 120.9822 },
  // ... other fields
});
```

### 2. Trigger AI Auto-Dispatch

```javascript
db.collection("restaurant_orders").doc("ORDER_ID").update({
  status: "Order Accepted", // This triggers AI
});
```

### 3. Verify Result

```javascript
// Check order document
// status should be 'Driver Assigned'
// dispatchMethod should be 'AI Auto-Dispatch'

// Check assignments_log
// assignmentMethod should be 'AI Auto-Dispatch'
```

## Monitoring AI Performance

### View AI Dispatch Logs

```bash
firebase functions:log --only autoDispatcher
```

### Query AI Assignments

```javascript
db.collection("assignments_log")
  .where("assignmentMethod", "==", "AI Auto-Dispatch")
  .orderBy("assignedAt", "desc")
  .get();
```

### Analyze AI Metrics

```javascript
// Get all AI scores for analysis
db.collection("assignments_log")
  .where("assignmentMethod", "==", "AI Auto-Dispatch")
  .get()
  .then((snapshot) => {
    snapshot.forEach((doc) => {
      const data = doc.data();
      console.log("Winning Score:", data.metrics.compositeScore);
      console.log("All Candidates:", data.allDriverScores);
    });
  });
```

## Key Points

✅ **Automatic**: No manual intervention needed  
✅ **AI-Powered**: Uses machine learning prescription  
✅ **Fair**: Distributes orders equitably  
✅ **Fast**: Real-time assignment on status change  
✅ **Transparent**: All scores logged for analysis  
✅ **Scalable**: Handles multiple riders efficiently

## Next Steps

1. Deploy function: `firebase deploy --only functions:autoDispatcher`
2. Test with sample orders
3. Monitor AI performance
4. Integrate Vertex AI for ML predictions
5. Tune weights based on business needs
6. Analyze assignment logs for optimization
