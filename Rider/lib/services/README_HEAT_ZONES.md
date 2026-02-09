# Heat Zones Service - Hotspots Feature

## Overview
The `HeatZoneService` manages the driver heat map data for the **Hotspots** feature in the LalaGo Driver app.

## Auto-Initialization

The service **automatically initializes** on app startup via `main.dart`:
- Checks if `driver_heat_zones` Firestore collection is empty
- If empty, creates **10 sample heat zones** with Manila area coordinates
- Sample data is spread over the last 7-10 days
- **Non-blocking** - app continues even if initialization fails

## Sample Data Created

The service creates sample zones for:
1. Makati CBD (weight: 5, timeSlot: all)
2. Ortigas Center (weight: 4, timeSlot: lunch)
3. BGC (weight: 3, timeSlot: dinner)
4. Eastwood City (weight: 4, timeSlot: all)
5. Quezon City Circle (weight: 5, timeSlot: dinner)
6. Makati Avenue (weight: 3, timeSlot: lunch)
7. Manila Bay Area (weight: 2, timeSlot: all)
8. SM North EDSA (weight: 4, timeSlot: dinner)
9. Rockwell Center (weight: 3, timeSlot: lunch)
10. Cubao (weight: 2, timeSlot: all)

## Firestore Collection Structure

**Collection:** `driver_heat_zones`

**Document Fields:**
```dart
{
  "lat": 14.5995,              // double - latitude
  "lng": 120.9842,             // double - longitude
  "weight": 5,                 // int (1-5) - heat intensity
  "timeSlot": "all",           // string - "lunch", "dinner", or "all"
  "lastUpdated": Timestamp,    // Timestamp - for filtering old data
  "description": "Makati CBD", // string (optional) - for reference
  "createdAt": Timestamp       // Timestamp - server timestamp
}
```

## How Drivers See It

1. **Hotspots Tab** - New bottom navigation item (heat map icon)
2. **Heat Map Colors:**
   - 🟢 Green = Low demand (weight 1-2)
   - 🟠 Orange = Medium demand (weight 3-4)
   - 🔴 Red = High demand (weight 5)
3. **Toggle** - Can show/hide heat map layer
4. **Auto-hide** - Heat map automatically hides when driver has active order
5. **Time-based** - Shows zones relevant to current time (lunch/dinner/all)

## Future Enhancements (Optional)

### Building Real Heat Map from Order Data

You can optionally call `addHeatZoneFromOrder()` after an order is completed to build real heat map data:

```dart
// Example: After order completion
import 'package:foodie_driver/services/heat_zone_service.dart';

// In your order completion handler:
await HeatZoneService.addHeatZoneFromOrder(
  lat: restaurantLocation.latitude,
  lng: restaurantLocation.longitude,
  timeSlot: HeatZoneService.getCurrentTimeSlot(), // 'lunch', 'dinner', or 'all'
  weight: 1, // Start with weight 1, will auto-increment on repeated orders
);
```

**Benefits:**
- Automatically merges nearby zones (within ~500m)
- Increments weight for frequently ordered locations
- Caps weight at 5 (max intensity)
- Updates `lastUpdated` timestamp

### Cleanup Old Data

Run periodically (e.g., weekly) to remove zones older than 30 days:

```dart
await HeatZoneService.cleanupOldHeatZones();
```

## Testing

### First Run
1. Restart the app
2. Check console logs for: `✅ Created 10 sample heat zones`
3. Go to **Hotspots** tab in bottom navigation
4. You should see colored circles on the map

### Verify Data in Firebase Console
1. Open Firebase Console → Firestore Database
2. Look for `driver_heat_zones` collection
3. Should contain 10 documents with sample data

### Troubleshooting

**No circles showing:**
- Check if toggle is ON ("Show Heat Map")
- Make sure you don't have an active order (heat map auto-hides)
- Check time slot filtering (some zones only show during lunch/dinner)
- Verify your location is within Manila area (or adjust coordinates in service)

**Console shows errors:**
- Check Firebase permissions for `driver_heat_zones` collection
- Ensure Firestore is initialized before heat zone service

## Technical Details

- **Load Strategy:** Data loads once per screen open (cached with `_dataLoaded` flag)
- **No Real-time Updates:** Static data, no Firestore listeners
- **No Location Tracking:** Uses driver's current location only for map centering
- **No API Calls:** No Directions/Routes API calls
- **Historical Data Only:** Shows data from last 7-14 days
- **Privacy-Safe:** No personal data, no real-time driver/customer locations

## Adjusting Coordinates

To change sample coordinates for your city, edit `lib/services/heat_zone_service.dart`:

```dart
final List<Map<String, dynamic>> sampleZones = [
  {
    'lat': YOUR_LATITUDE,   // Change these
    'lng': YOUR_LONGITUDE,  // Change these
    'weight': 5,
    'timeSlot': 'all',
    'description': 'Your Location Name',
  },
  // ... add more zones
];
```

## Performance Impact

- **Minimal** - Service is non-blocking
- Runs in background during app initialization
- Does not affect app startup time
- Heat map rendering is lightweight (circles, no complex polygons)
- No continuous polling or real-time updates

