# Smart Hunger Notifications System

## Overview

Smart Hunger Notifications automatically send personalized, timing-optimized push notifications to users during three natural hunger windows: lunch (11:00 AM–12:30 PM), afternoon snack (3:00 PM–4:30 PM), and dinner (5:30 PM–7:30 PM). The system uses behavioral data to learn individual ordering patterns and deliver messages when users are most receptive to food-related content.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Scheduled Cloud Function (10:30, 14:30, 17:00 Asia/Manila)     │
│  sendSmartHungerReminders                                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Eligibility Checks                                              │
│  • settings.ashHungerReminders == true                           │
│  • reorderEligible == true                                       │
│  • lastOnlineTimestamp >= 30 days                                │
│  • Not ordered today (HungerDetection.hasOrderedToday)           │
│  • FrequencyManager.canSendNotification('ash_hunger')            │
│  • Quiet hours not active                                        │
│  • Admin window toggle for current window is enabled             │
│  • Admin frequency mode: 'less' -> max 1 per day                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  Message Builder (ashNotificationBuilder.getSmartHungerContent)  │
│  • Window-specific templates (lunch/snack/dinner)                │
│  • Personalization: firstName, favoriteRestaurant                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  FCM Send + ash_notification_history Log                         │
└─────────────────────────────────────────────────────────────────┘
```

## Data Schema

### Admin Settings (`config/smart_hunger_settings`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| enabled | bool | true | Master switch for Smart Hunger |
| frequencyMode | string | 'recommended' | 'recommended' (up to 2/day) or 'less' (1/day) |
| windows | map | {lunch: true, snack: true, dinner: true} | Per-window admin toggles |
| updatedAt | Timestamp | n/a | Last config update time |

### Preference Profile (users.preferenceProfile)

| Field | Type | Description |
|-------|------|-------------|
| typicalLunchHour | int? | Median hour (0–23) of lunch orders (11–16) |
| typicalDinnerHour | int? | Median hour of dinner orders (16–22) |
| typicalSnackHour | int? | Median hour of snack orders (14–17) |
| favoriteRestaurants | string[] | Top 5 vendor IDs |
| preferredTimes | string[] | breakfast, lunch, dinner, late_night |

### Notification History (ash_notification_history)

| Field | Type | Description |
|-------|------|-------------|
| userId | string | User ID |
| type | string | 'ash_hunger' |
| window | string | 'lunch', 'snack', or 'dinner' |
| title | string | Notification title |
| body | string | Notification body |
| sentAt | Timestamp | When sent |
| openedAt | Timestamp? | When user tapped |
| converted | bool? | Order attributed |
| convertedOrderId | string? | Attributed order ID |
| conversionValue | number? | Order value |
| attributionWindow | string? | '2h' for 2-hour attribution |

## Message Template Library

### Lunch Window
- "Lunch time! Let LalaGO bring your meal today."
- "Hungry? Restaurants near you are ready to deliver."
- "Take a break from cooking. Order lunch now."

### Snack Window
- "Afternoon snack? Drinks, desserts, and more."
- "Energy boost? Coffee and snacks delivered fast."
- "Midday craving? Treat yourself."

### Dinner Window
- "Too tired to cook? LalaGO delivers dinner fast."
- "Dinner time! Your favorites are just a tap away."
- "End the day with a great meal. Order now."

### Personalization
- With firstName: "It's [Name]'s lunch time!"
- With restaurantName: "Ready to order from [Restaurant]?"

## Schedule

| Window | Cron Execution | Asia/Manila Time |
|--------|----------------|------------------|
| Lunch | :30 at hour 10 | 10:30 AM |
| Snack | :30 at hour 14 | 2:30 PM |
| Dinner | :00 at hour 17 | 5:00 PM |

The function runs every 30 minutes and only executes logic at these three times.

## Conversion Attribution

- **2-hour window**: For `ash_hunger` notifications, orders placed within 2 hours of the notification are attributed with high confidence. Stored with `attributionWindow: '2h'`.
- **7-day window**: General notification attribution for other types.

## Analytics Dashboard

The Admin app's Hunger Reminder Analytics page (`hunger_reminder_analytics.dart`) shows:

- **Summary Metrics**: Sent count, open rate, conversion rate, revenue per notification
- **Performance by Window**: Lunch, snack, dinner breakdown (open rate, conversions)
- **Performance by Time of Day**: Hourly open rates
- **Recent Reminders**: Latest 50 notifications

## Key Files

| Purpose | File |
|---------|------|
| Cloud Function | Admin/functions/index.js (`sendSmartHungerReminders`) |
| Message templates | Admin/functions/ashNotificationBuilder.js |
| Eligibility logic | Admin/functions/hungerDetection.js |
| Frequency limits | Admin/functions/frequencyManager.js |
| User preferences | Admin/functions/computeUserPreferences.js |
| Conversion attribution | Admin/functions/conversionAttribution.js |
| Admin control UI | Admin/lib/pages/notification_management_page.dart |
| User model | Customer/lib/model/User.dart |
| Analytics dashboard | Admin/lib/pages/hunger_reminder_analytics.dart |

## Success Metrics

| Metric | Target |
|--------|--------|
| Open rate | >15% |
| Conversion (2h) | >8% |
| Opt-out rate | <5% |
| DAU impact | +10% |
| Order frequency | +15% |

## Monitoring

Configure alerts for:
- Open rate < 10% for 3 consecutive days
- Opt-out rate > 5% in a day
- Function duration > 30 seconds
- Function errors

## Happy Hour Auto-Send Checklist (3 Points)

Use this quick checklist to confirm Happy Hour can send automatically
without your presence:

1. **Happy Hour settings are enabled**
   - Firestore path: `settings/happyHourSettings`
   - Required flags:
     - `enabled: true`
     - `autoCreateNotification: true`

2. **Template + schedule config is valid**
   - `notificationTemplate.title` and `notificationTemplate.body` are not empty
   - At least one entry exists in `configs` with:
     - current day included in `activeDays`
     - current time between `startTime` and `endTime`

3. **Background job flow is running**
   - Scheduled function `checkHappyHourAndCreateJob` runs every 10 minutes
   - New docs appear in `notification_jobs` with `kind: "happy_hour"`
   - Job progresses to successful delivery (or shows failures you can inspect)
