# Firebase Cloud Functions - AI Auto Dispatcher

## Overview

The `autoDispatcher` Cloud Function automatically assigns orders to the best available rider using **AI prescription** when order status becomes **'Order Accepted'**. The AI algorithm considers multiple factors:

1. **ETA (50% weight)** - Distance/time from rider to restaurant
2. **ML Acceptance Probability (30% weight)** - Predicted likelihood of rider accepting (Vertex AI - currently stubbed)
3. **Fairness Score (20% weight)** - Ensures equitable distribution of orders among riders

## Function Details

### Trigger

- **Type**: Firestore Document Update
- **Collection**: `restaurant_orders`
- **Trigger Condition**: When order status changes to **'Order Accepted'**

### AI Prescription Algorithm

1. **Find Available Riders**

   - Queries users with `role=driver`, `active=true`, `isAvailable=true`

2. **Calculate AI Scores**

   - **ETA**: Haversine distance formula (straight-line) with 30 km/h average speed
   - **ML Probability**: Vertex AI prediction (stubbed - returns simulated value)
   - **Fairness**: Based on completed orders today (fewer orders = lower score)

3. **AI Composite Score Calculation**

   ```
   Score = (ETA × 0.5) + (ML × 0.3) + (Fairness × 0.2)
   ```

   Lower score = better match (AI prescription)

4. **Automatic Assignment**
   - AI selects rider with lowest composite score
   - Updates order with rider info and status to **'Driver Assigned'**
   - Sets rider as unavailable
   - Sends FCM notification with "AI Auto-Dispatch" indicator
   - Logs to `assignments_log` collection with method **'AI Auto-Dispatch'**

## Data Structures

### Order Document (`restaurant_orders/{orderId}`)

```javascript
{
  status: 'Order Accepted' | 'Driver Assigned' | 'Completed',
  assignedDriverId: string,
  assignedDriverName: string,
  estimatedETA: number,
  assignedAt: Timestamp,
  dispatchStatus: 'success' | 'error' | 'no_drivers_available',
  dispatchMethod: 'AI Auto-Dispatch',
  dispatchMetrics: {
    eta: number,
    mlAcceptanceProbability: number,
    fairnessScore: number,
    compositeScore: number,
    alternativeDriversCount: number
  },
  restaurantLocation: { lat: number, lng: number },
  deliveryLocation: { lat: number, lng: number }
}
```

### Rider Document (`users/{userId}`)

```javascript
{
  role: 'driver',
  active: boolean,
  isAvailable: boolean,
  currentLocation: { lat: number, lng: number },
  currentOrderId: string,
  fcmToken: string,
  lastAssignedAt: Timestamp
}
```

### Assignment Log (`assignments_log/{logId}`)

```javascript
{
  orderId: string,
  driverId: string,
  driverName: string,
  assignedAt: Timestamp,
  metrics: {
    eta: number,
    mlAcceptanceProbability: number,
    fairnessScore: number,
    compositeScore: number
  },
  allDriverScores: Array<DriverScore>,
  assignmentMethod: 'AI Auto-Dispatch',
  restaurantLocation: { lat: number, lng: number },
  deliveryLocation: { lat: number, lng: number }
}
```

## Setup

### 1. Install Dependencies

```bash
cd functions
npm install
```

### 2. Deploy

```bash
firebase deploy --only functions
```

### 3. Test Locally

```bash
npm run serve
```

## ML Integration (TODO)

The `getMLAcceptanceProbability()` function is currently stubbed. To integrate with Vertex AI:

1. Train a model on historical rider acceptance data
2. Deploy model to Vertex AI
3. Update function to call prediction endpoint:

```javascript
const { PredictionServiceClient } = require("@google-cloud/aiplatform");
const client = new PredictionServiceClient();

async function getMLAcceptanceProbability(driver, order, eta) {
  const endpoint = `projects/${PROJECT_ID}/locations/${LOCATION}/endpoints/${ENDPOINT_ID}`;

  const instance = {
    driverId: driver.id,
    eta: eta,
    timeOfDay: new Date().getHours(),
    dayOfWeek: new Date().getDay(),
    historicalAcceptanceRate: driver.acceptanceRate || 0.7,
    orderValue: order.totalAmount || 0,
  };

  const [response] = await client.predict({
    endpoint,
    instances: [instance],
  });

  return response.predictions[0].probability;
}
```

## Monitoring

View logs:

```bash
firebase functions:log
```

## AI Weights Tuning

Adjust the AI scoring weights in `calculateCompositeScore()` based on your business needs:

- `eta`: 0.5 (50%) - Prioritize proximity
- `ml`: 0.3 (30%) - Consider acceptance likelihood
- `fairness`: 0.2 (20%) - Ensure fair distribution

## Notes

- Minimum ETA is capped at 1 minute
- Fairness score: 0-20 orders/day → 0-100 score
- FCM errors are logged but don't fail the assignment
- All rider scores are logged for analysis
- AI auto-dispatch triggers when status becomes **'Order Accepted'**
- Successfully assigned orders have status **'Driver Assigned'**
- Assignment logs include `assignmentMethod: 'AI Auto-Dispatch'`
