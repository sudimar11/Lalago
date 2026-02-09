# AI Learning System - Driver Response Tracking

## Overview
This system tracks every driver accept/reject decision and logs it to the `assignments_log` collection. The AI can use this historical data to learn which drivers are more likely to accept specific orders based on various factors like distance, time of day, driver location, etc.

## How It Works

### 1. **Order Assignment Logging**
When an order is dispatched (manually or automatically):
1. An entry is created in `assignments_log` with initial status: `'offered'`
2. A real-time listener is set up to monitor the order status
3. The system tracks which driver was offered the order

### 2. **Driver Response Tracking**
The system monitors for two outcomes:

#### ✅ **Driver Accepts**
When order status changes to:
- `'Driver Accepted'`
- `'driver accepted'`
- `'Order Shipped'`
- `'order shipped'`

The assignment log is updated with:
```dart
{
  'status': 'accepted',
  'acceptedAt': [timestamp],
  'responseTime': [timestamp]
}
```

#### ❌ **Driver Rejects**
When order status changes to:
- `'Driver Rejected'`
- `'driver rejected'`
- `'Order Rejected'`
- `'order rejected'`

The assignment log is updated with:
```dart
{
  'status': 'rejected',
  'rejectedAt': [timestamp],
  'responseTime': [timestamp]
}
```

### 3. **Automatic Cleanup**
- Listeners are automatically canceled after the driver responds
- Prevents duplicate logging
- Efficient memory management

## Assignment Log Structure

### Initial Entry (When Order is Dispatched)
```dart
{
  'order_id': 'abc123',
  'driverId': 'driver_xyz',
  'status': 'offered',           // Initial status
  'etaMinutes': 15,               // Estimated time to vendor
  'km': 2.5,                      // Distance to vendor
  'score': 1.0,                   // AI score
  'acceptanceProb': 0.85,         // ML predicted probability
  'createdAt': Timestamp,         // When offered
  'offeredAt': Timestamp,         // When offered (same as createdAt)
  'manualDispatch': true,         // true if manually dispatched
  'autoReassigned': false,        // true if auto-reassigned after rejection
}
```

### After Driver Accepts
```dart
{
  // ... all initial fields plus:
  'status': 'accepted',           // Updated status
  'acceptedAt': Timestamp,        // When driver accepted
  'responseTime': Timestamp,      // Same as acceptedAt
}
```

### After Driver Rejects
```dart
{
  // ... all initial fields plus:
  'status': 'rejected',           // Updated status
  'rejectedAt': Timestamp,        // When driver rejected
  'responseTime': Timestamp,      // Same as rejectedAt
}
```

## AI/ML Applications

### 1. **Acceptance Probability Prediction**
The AI can train on this data to predict:
- Which drivers are more likely to accept based on distance
- Time-based acceptance patterns (rush hour, late night, etc.)
- Driver-specific behavior patterns
- Order type preferences

### 2. **Smart Driver Selection**
Using the historical data:
```python
# Example ML features
features = {
    'distance_km': 2.5,
    'time_of_day': 18,  # 6 PM
    'day_of_week': 5,   # Friday
    'driver_avg_acceptance_rate': 0.82,
    'driver_avg_distance': 3.2,
    'order_value': 450,
    'vendor_category': 'fast_food'
}

# Model predicts acceptance probability
acceptance_prob = model.predict(features)
```

### 3. **Driver Ranking Algorithm**
Combine multiple factors:
```dart
final score = (
  (1 / distance) * 0.4 +           // Closer is better (40% weight)
  acceptance_prob * 0.3 +           // ML prediction (30% weight)
  driver_rating * 0.2 +             // Driver rating (20% weight)
  (1 / response_time_avg) * 0.1    // Faster response (10% weight)
);
```

### 4. **Pattern Analysis**
Query assignment logs to discover patterns:
```dart
// Find drivers with high acceptance rate for long distances
final query = await FirebaseFirestore.instance
    .collection('assignments_log')
    .where('driverId', isEqualTo: driverId)
    .where('km', isGreaterThan: 5.0)
    .where('status', isEqualTo: 'accepted')
    .get();

final acceptanceRate = acceptedOrders / totalOfferedOrders;
```

## Data Analysis Queries

### 1. **Driver Acceptance Rate**
```dart
// Get all offers to a specific driver
final allOffers = await FirebaseFirestore.instance
    .collection('assignments_log')
    .where('driverId', isEqualTo: driverId)
    .get();

final accepted = allOffers.docs.where((d) => d['status'] == 'accepted').length;
final rejected = allOffers.docs.where((d) => d['status'] == 'rejected').length;
final rate = accepted / (accepted + rejected);

print('Driver acceptance rate: ${(rate * 100).toStringAsFixed(1)}%');
```

### 2. **Distance-Based Acceptance**
```dart
// Analyze acceptance by distance ranges
final ranges = {
  '0-2km': {'accepted': 0, 'rejected': 0},
  '2-5km': {'accepted': 0, 'rejected': 0},
  '5+km': {'accepted': 0, 'rejected': 0},
};

for (var doc in assignmentLogs) {
  final km = doc['km'] as double;
  final status = doc['status'] as String;
  
  String range;
  if (km < 2) range = '0-2km';
  else if (km < 5) range = '2-5km';
  else range = '5+km';
  
  if (status == 'accepted') ranges[range]!['accepted']++;
  else if (status == 'rejected') ranges[range]!['rejected']++;
}
```

### 3. **Time-Based Patterns**
```dart
// Analyze acceptance by time of day
final morning = [], afternoon = [], evening = [], night = [];

for (var doc in assignmentLogs) {
  final timestamp = (doc['offeredAt'] as Timestamp).toDate();
  final hour = timestamp.hour;
  
  if (hour >= 6 && hour < 12) morning.add(doc);
  else if (hour >= 12 && hour < 18) afternoon.add(doc);
  else if (hour >= 18 && hour < 22) evening.add(doc);
  else night.add(doc);
}
```

### 4. **Response Time Analysis**
```dart
// Calculate average response time
for (var doc in assignmentLogs) {
  final offered = (doc['offeredAt'] as Timestamp).toDate();
  final response = (doc['responseTime'] as Timestamp?)?.toDate();
  
  if (response != null) {
    final duration = response.difference(offered);
    print('Response time: ${duration.inSeconds} seconds');
  }
}
```

## Real-Time Monitoring

### Console Logs
When the system is running, you'll see detailed logs:

**When Order is Dispatched:**
```
[Manual Dispatch AI] Assignment logged with ID: log_abc123
[Driver Response] Setting up listener for order order_xyz (driver: driver_123)
[Driver Response] Listener active for order order_xyz
```

**When Driver Accepts:**
```
[Driver Response] Order order_xyz status: Driver Accepted
[Driver Response] ✅ Driver driver_123 ACCEPTED order order_xyz
[Driver Response] Updated assignment log with ACCEPTANCE
```

**When Driver Rejects:**
```
[Driver Response] Order order_xyz status: Driver Rejected
[Driver Response] ❌ Driver driver_123 REJECTED order order_xyz
[Driver Response] Updated assignment log with REJECTION
```

## Benefits for AI/ML

### ✅ **Complete Historical Data**
- Every dispatch attempt is logged
- Both acceptances and rejections tracked
- Timestamps for time-based analysis

### ✅ **Rich Feature Set**
- Distance (km)
- Estimated time (etaMinutes)
- Driver ID
- Order ID
- Response time
- Manual vs. auto dispatch
- Reassignment flags

### ✅ **Real-Time Updates**
- Immediate logging of driver responses
- No delay in data collection
- Live monitoring capabilities

### ✅ **Scalable Design**
- Efficient listeners with automatic cleanup
- No duplicate entries
- Memory-efficient implementation

## Future ML Enhancements

### 1. **Predictive Model Training**
```python
# Example TensorFlow/scikit-learn model
from sklearn.ensemble import RandomForestClassifier

# Features from assignment_log
X = df[['distance_km', 'eta_minutes', 'hour_of_day', 'day_of_week', 
        'driver_avg_acceptance', 'order_value']]
y = df['status'].map({'accepted': 1, 'rejected': 0})

model = RandomForestClassifier(n_estimators=100)
model.fit(X, y)

# Predict acceptance probability for new orders
prob = model.predict_proba(new_order_features)
```

### 2. **Driver Behavior Clustering**
Group drivers by behavior patterns:
- Fast responders with high acceptance
- Distance-sensitive drivers
- Time-of-day preferences
- Order value sensitivity

### 3. **Dynamic Scoring**
Update driver scores based on real-time performance:
```dart
final recentPerformance = await getRecentAssignments(driverId, days: 7);
final recentAcceptanceRate = calculateAcceptanceRate(recentPerformance);

// Adjust future dispatch priority
final adjustedScore = baseScore * recentAcceptanceRate;
```

### 4. **A/B Testing**
Test different dispatch algorithms:
- Compare manual vs. auto dispatch success rates
- Test different distance weights
- Optimize ML model parameters

## Database Indexes (Recommended)

To optimize queries on `assignments_log`:

```javascript
// Firestore indexes
{
  "collectionGroup": "assignments_log",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "driverId", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}

{
  "collectionGroup": "assignments_log",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "km", "order": "ASCENDING" }
  ]
}

{
  "collectionGroup": "assignments_log",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "driverId", "order": "ASCENDING" },
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

## Testing the System

### Test Scenario 1: Track Acceptance
1. Manually dispatch an order to a driver
2. Check console: Should see "Listener active for order..."
3. Driver accepts the order in their app
4. Check console: Should see "✅ Driver ACCEPTED order..."
5. Verify in Firestore: `assignments_log` entry updated with `status: 'accepted'`

### Test Scenario 2: Track Rejection
1. Dispatch an order to a driver
2. Driver rejects the order
3. Check console: Should see "❌ Driver REJECTED order..."
4. Verify in Firestore: `assignments_log` entry updated with `status: 'rejected'`
5. Auto-dispatch should trigger (from previous feature)

### Test Scenario 3: Multiple Reassignments
1. Dispatch order → Driver A rejects → Auto-assign to Driver B
2. Check `assignments_log`: Should have TWO entries
   - First entry: Driver A, status 'rejected'
   - Second entry: Driver B, status 'offered' (or 'accepted' if accepted)

## Data Export for ML Training

Export assignment logs for external ML training:

```dart
// Export to CSV for ML training
final logs = await FirebaseFirestore.instance
    .collection('assignments_log')
    .get();

final csv = StringBuffer();
csv.writeln('order_id,driver_id,distance_km,eta_minutes,status,hour_of_day,day_of_week,response_time_seconds');

for (var doc in logs.docs) {
  final data = doc.data();
  final offeredAt = (data['offeredAt'] as Timestamp?)?.toDate();
  final responseTime = (data['responseTime'] as Timestamp?)?.toDate();
  
  if (offeredAt != null && responseTime != null) {
    final responseSeconds = responseTime.difference(offeredAt).inSeconds;
    
    csv.writeln([
      data['order_id'],
      data['driverId'],
      data['km'],
      data['etaMinutes'],
      data['status'],
      offeredAt.hour,
      offeredAt.weekday,
      responseSeconds,
    ].join(','));
  }
}

// Save or send CSV data
```

---

**Status**: ✅ Fully Implemented and Ready for AI/ML Integration
**Last Updated**: October 18, 2025
**Next Steps**: Collect data for 2-4 weeks, then train ML acceptance prediction model

