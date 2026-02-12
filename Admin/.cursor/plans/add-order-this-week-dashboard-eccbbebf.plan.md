<!-- eccbbebf-ff2b-49a1-b90b-68dbb8a56b32 b20f2f2a-6f98-43ad-abc2-565e879baee3 -->
# Add "Active Customers Today" to Dashboard

## Overview

Add a new statistics card on the dashboard that displays the count of unique customers who were active today. A customer is considered active if they either:

1. Placed at least one order today, OR
2. Logged in/used the app today (based on lastOnlineTimestamp)

## Implementation Details

### 1. Create ActiveCustomersTodayCard widget

- Create a new `ActiveCustomersTodayCard` widget (similar to `OrdersTodayCard`)
- This will be a StatefulWidget since we need to combine data from two different Firestore queries
- Use StreamBuilder to listen to both:
  - Orders from today (to extract unique customer IDs from `author.id`)
  - Users with role='customer' and lastOnlineTimestamp from today
- Combine the two sets of customer IDs and count unique customers
- Display:
  - Icon (e.g., `Icons.people` or `Icons.person`)
  - Label: "Active Customers Today"
  - Count of unique active customers

### 2. Add queries for active customers today

- In `_DashboardBlankPageState.build()` method, add queries:
  - Reuse `ordersTodayQuery` (already exists) to get orders from today
  - Add query for customers who logged in today:
    ```dart
    final Query activeCustomersTodayQuery = FirebaseFirestore.instance
        .collection(USERS)
        .where('role', isEqualTo: USER_ROLE_CUSTOMER)
        .where('lastOnlineTimestamp', 
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('lastOnlineTimestamp', 
            isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    ```


### 3. Add card to dashboard layout

- In the dashboard layout, add the new card
- Place it in a new row or alongside existing customer/order cards
- Follow the same layout pattern (Row with Expanded widgets)

## Files to Modify

- `lib/dashboard.dart`: Create `ActiveCustomersTodayCard` widget, add queries, and integrate into dashboard layout

### To-dos

- [ ] Add helper function to calculate start of week (Monday) and end of week (Sunday) with proper UTC conversion
- [ ] Create OrdersThisWeekCard widget similar to OrdersTodayCard that displays order count for the current week
- [ ] Add Firestore query for orders this week in the dashboard build method
- [ ] Add OrdersThisWeekCard to the dashboard layout UI
- [ ] Add helper function to calculate start of week (Monday) and end of week (Sunday) with proper UTC conversion
- [ ] Create OrdersThisWeekCard widget similar to OrdersTodayCard that displays order count for the current week
- [ ] Add Firestore query for orders this week in the dashboard build method
- [ ] Add OrdersThisWeekCard to the dashboard layout UI