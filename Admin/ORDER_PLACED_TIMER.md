# Order Placed Timer Feature

## Summary

Added a real-time running timer for orders with "Order Placed" status, displayed in MM:SS format (00:00) to help track order response time.

## Feature Details

### Timer Display

- **Format**: `MM:SS` (e.g., 00:45, 03:15, 12:30)
- **Location**: Beside the status badge in the order card header
- **Visibility**: Only shows for "Order Placed" status
- **Updates**: Every second (real-time)

### Visual Design

#### Timer Colors (Based on Elapsed Time)

- **🟢 Green (0-2:59)**: Fresh order, within normal response time
- **🟠 Orange (3:00-5:59)**: Attention needed, getting delayed
- **🔴 Red (6:00+)**: Urgent! Order waiting too long

#### Timer Style

```
┌─────────────┐
│ ⏱️ 02:45    │  ← Timer chip with icon
└─────────────┘
```

## Visual Layout

### Order Card with Timer

```
┌─────────────────────────────────────────────────┐
│ 📋 Order #a1b2c3d4                              │
│    Oct 18, 2025 • 10:00 AM                      │
│                                                  │
│                         [Order Placed] ← Status │
│                         ⏱️ 02:45 ← Timer        │
├─────────────────────────────────────────────────┤
│ [Customer Info]                                 │
│ [Products]                                      │
│ [Manual Dispatch Button]                        │
└─────────────────────────────────────────────────┘
```

### Timer Examples

**Fresh Order (45 seconds)**

```
Status: [Order Placed]
Timer:  ⏱️ 00:45  (Green border & text)
```

**Getting Delayed (3 minutes 15 seconds)**

```
Status: [Order Placed]
Timer:  ⏱️ 03:15  (Orange border & text)
```

**Urgent (10 minutes 30 seconds)**

```
Status: [Order Placed]
Timer:  ⏱️ 10:30  (Red border & text)
```

## Technical Implementation

### Timer Widget

```dart
class _OrderPlacedTimer extends StatefulWidget {
  final Timestamp orderCreatedAt;
  // Updates every second
  // Shows elapsed time from creation
}
```

### Time Calculation

1. Gets current time: `DateTime.now()`
2. Gets order creation time: `orderCreatedAt.toDate()`
3. Calculates difference: `now.difference(created)`
4. Formats as MM:SS

### Format Logic

```dart
String _formatDuration() {
  final minutes = _elapsed.inMinutes;
  final seconds = _elapsed.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
```

**Examples**:

- 5 seconds → `00:05`
- 45 seconds → `00:45`
- 1 minute 30 seconds → `01:30`
- 15 minutes 7 seconds → `15:07`
- 2 hours 5 minutes → `125:00`

### Color Thresholds

```dart
Color _getTimerColor() {
  final minutes = _elapsed.inMinutes;
  if (minutes < 3) return Colors.green;   // 0-2:59
  if (minutes < 6) return Colors.orange;  // 3:00-5:59
  return Colors.red;                      // 6:00+
}
```

### Performance

- **Memory Efficient**: Timer only runs for visible "Order Placed" cards
- **Auto Cleanup**: Timer disposed when widget removed
- **Safe Updates**: Only updates if widget still mounted

## Use Cases

### 1. **Restaurant Staff Monitoring**

Staff can quickly see which orders need immediate attention:

- **Green timers**: Normal processing
- **Orange timers**: Need to expedite
- **Red timers**: Critical - respond immediately

### 2. **Performance Tracking**

Restaurant managers can monitor:

- Average response time to new orders
- Which orders are taking too long
- Staff efficiency during peak hours

### 3. **Customer Service**

Helps maintain quality:

- Respond to orders within target time (< 3 minutes ideal)
- Prevent customer complaints about slow service
- Improve order fulfillment speed

## Timer Lifecycle

### When Timer Starts

```
Order Status: "Order Placed"
↓
Timer Widget Created
↓
Calculates: Now - CreatedAt
↓
Updates Every Second
```

### When Timer Stops

```
Status Changes (e.g., to "Order Accepted")
↓
Timer Widget Disposed
↓
Timer Cancelled
↓
Resources Freed
```

### Timer Update Cycle

```
Every 1 Second:
1. Check if widget still mounted
2. Calculate new elapsed time
3. Update display (setState)
4. Change color if threshold crossed
```

## Benefits

### ✅ For Restaurant Staff

1. **Visual Priority**: Instantly see which orders are urgent
2. **Better Time Management**: Allocate resources efficiently
3. **Reduced Stress**: Clear indicators instead of manual checking

### ✅ For Managers

1. **Performance Metrics**: Track average response times
2. **Quality Control**: Ensure timely order processing
3. **Staff Training**: Identify improvement areas

### ✅ For Customers

1. **Faster Service**: Staff responds to orders quickly
2. **Better Experience**: Reduced wait times
3. **Higher Satisfaction**: Orders handled efficiently

## Example Scenarios

### Scenario 1: Lunch Rush

```
10 orders with "Order Placed" status:

Order #abc123   ⏱️ 00:30  🟢  ← Just arrived
Order #def456   ⏱️ 01:15  🟢  ← Normal
Order #ghi789   ⏱️ 02:45  🟢  ← Still good
Order #jkl012   ⏱️ 03:30  🟠  ← Getting delayed
Order #mno345   ⏱️ 04:15  🟠  ← Need attention
Order #pqr678   ⏱️ 07:22  🔴  ← URGENT!

Staff Priority: Handle red first, then orange, then green
```

### Scenario 2: Post-Lunch Monitoring

```
Order #xyz999   ⏱️ 00:15  🟢
↓ (Staff accepts order)
Status → "Order Accepted"
Timer disappears ✓
```

## Configuration

### Time Thresholds (Customizable)

```dart
// Current settings
Green:  0-2:59  (< 3 minutes)
Orange: 3:00-5:59  (3-6 minutes)
Red:    6:00+  (≥ 6 minutes)

// Can be adjusted based on restaurant needs
```

### Update Frequency

```dart
Timer.periodic(const Duration(seconds: 1), ...)
// Updates every 1 second
// Can be changed if needed (e.g., every 5 seconds for performance)
```

## Files Modified

1. **`lib/order_dispatcher.dart`**
   - Added `dart:async` import (line 1)
   - Added timer display in order header (line 284-287)
   - Added `_OrderPlacedTimer` widget (lines 957-1040)

## Testing Checklist

- [x] Timer displays for "Order Placed" orders
- [x] Timer format is MM:SS (00:00)
- [x] Timer starts from 0 and counts up
- [x] Timer updates every second
- [x] Green color for 0-2:59 minutes
- [x] Orange color for 3:00-5:59 minutes
- [x] Red color for 6:00+ minutes
- [x] Timer disappears when status changes
- [x] No timer for other statuses
- [x] No performance issues with multiple timers
- [x] Timer properly disposed when card removed

## Future Enhancements

Consider adding:

- **Sound Alert**: Beep when timer turns red
- **Push Notification**: Alert staff of delayed orders
- **Analytics Dashboard**: Average response time metrics
- **Configurable Thresholds**: Adjust color change times per restaurant
- **Timer History**: Track how long each order waited
- **Batch Actions**: "Accept all red timer orders" button

## Best Practices for Restaurant Staff

### Response Time Goals

- **Ideal**: Accept order within 2 minutes (green)
- **Acceptable**: Accept within 3-5 minutes (orange)
- **Needs Improvement**: Over 6 minutes (red)

### During Rush Hours

1. Check for red timers first
2. Process orange timers next
3. Handle green timers in order
4. Consider using "Manual Dispatch (AI)" for faster assignment

### Monitoring Tips

- Keep Orders tab open during service hours
- Pull to refresh periodically
- Train staff to recognize color codes
- Set internal SLA (e.g., "No order should turn red")
