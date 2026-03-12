# Rider Time Settings Config

Firestore document: `config/rider_time_settings`

## Schema

Create manually in Firebase Console or let the Admin Rider Time Settings page create it on first save.

```json
{
  "inactivityTimeoutMinutes": 15,
  "checkIntervalMinutes": 5,
  "excludeWithActiveOrders": true
}
```

## Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| inactivityTimeoutMinutes | int | 15 | Minutes of no activity before auto-logout. Range: 1–60. |
| checkIntervalMinutes | int | 5 | How often the Cloud Function runs (for reference; schedule is hardcoded). |
| excludeWithActiveOrders | bool | true | If true, riders with active orders are never auto-logged out. |

## Manual creation (Firebase Console)

1. Go to Firestore Database
2. Create collection `config` if it does not exist
3. Add document with ID `rider_time_settings`
4. Add the fields above with desired values

If the document does not exist, the Cloud Function uses the defaults shown.
