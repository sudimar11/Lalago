# Heat Zones Cloud Function

## Overview

This Cloud Function generates heat zones for the driver app based on actual order data from the last 30 days. It processes completed orders from the `restaurant_orders` collection and creates heat zones in the `driver_heat_zones` collection.

## Setup

### 1. Install Dependencies

```bash
cd functions
npm install
```

### 2. Deploy Function

```bash
# From project root
firebase deploy --only functions:generateHeatZones
```

Or from functions directory:
```bash
cd functions
npm run deploy
```

## Usage

### Manual Trigger

After deployment, you'll get a URL like:
```
https://YOUR-REGION-YOUR-PROJECT.cloudfunctions.net/generateHeatZones
```

**Trigger via curl:**
```bash
curl -X POST https://YOUR-REGION-YOUR-PROJECT.cloudfunctions.net/generateHeatZones
```

**Trigger via browser:**
Just open the URL in your browser (GET request also works)

**Trigger via Postman/Insomnia:**
- Method: POST or GET
- URL: Your function URL

### Expected Response

```json
{
  "success": true,
  "zonesCreated": 15,
  "ordersProcessed": 234,
  "dateRange": {
    "from": "2024-11-18",
    "to": "2024-12-18"
  },
  "breakdown": {
    "lunch": 6,
    "dinner": 7,
    "all": 2
  },
  "weightDistribution": {
    "weight1": 2,
    "weight2": 3,
    "weight3": 4,
    "weight4": 3,
    "weight5": 3
  }
}
```

## How It Works

1. **Queries** `restaurant_orders` collection for orders with:
   - `status == 'Order Completed'`
   - `createdAt` within last 30 days

2. **Groups** restaurants by proximity (within 500m radius)

3. **Calculates** weight based on order count:
   - 1-5 orders = weight 1 (green)
   - 6-10 orders = weight 2 (green)
   - 11-20 orders = weight 3 (orange)
   - 21-30 orders = weight 4 (orange)
   - 31+ orders = weight 5 (red)

4. **Determines** time slot based on order timestamps:
   - 60%+ orders 11:00-15:00 → `lunch`
   - 60%+ orders 17:00-22:00 → `dinner`
   - Otherwise → `all`

5. **Writes** to `driver_heat_zones` collection (replaces all existing zones)

## Testing Locally (Optional)

```bash
cd functions
npm run serve
```

Then trigger at: `http://localhost:5001/YOUR-PROJECT/us-central1/generateHeatZones`

## Troubleshooting

### Function not found
- Make sure you're logged in: `firebase login`
- Check project: `firebase use YOUR-PROJECT-ID`

### Permission denied
- Ensure Firestore rules allow Cloud Functions (admin SDK bypasses rules)
- Check Firebase project permissions

### No zones created
- Verify you have completed orders in last 30 days
- Check that orders have `vendor.latitude` and `vendor.longitude` fields
- Check function logs: `firebase functions:log`

## Notes

- Function processes all orders in one batch (may take time for large datasets)
- Existing heat zones are deleted before writing new ones
- Location-agnostic: works anywhere (Jolo, Manila, etc.) based on actual order data

