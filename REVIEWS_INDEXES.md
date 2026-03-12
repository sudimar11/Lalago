# Firestore Indexes for Reviews Hub

This document describes the composite indexes required for the `foods_review` collection to support efficient queries across the Reviews Hub.

## Indexes

| Purpose | Collection | Fields | Query Scope |
|---------|------------|--------|-------------|
| Restaurant review lists | foods_review | VendorId ASC, createdAt DESC | COLLECTION |
| Product-specific reviews | foods_review | productId ASC, createdAt DESC | COLLECTION |
| Rider reviews | foods_review | driverId ASC, createdAt DESC | COLLECTION |
| Admin moderation queue | foods_review | status ASC, createdAt DESC | COLLECTION |
| Filtered restaurant views | foods_review | VendorId ASC, status ASC, createdAt DESC | COLLECTION |

## Deploying Indexes

### Option 1: Firebase CLI

From the project root (or Admin directory containing firestore.indexes.json):

```bash
firebase deploy --only firestore:indexes
```

### Option 2: Firebase Console

1. Open [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Go to Firestore Database > Indexes
4. Add each composite index manually using the fields above

### Verification

After deployment, indexes may take several minutes to build. Check the Firebase Console for build status. Queries will fail with a "requires an index" error if the index is not yet ready; the error message typically includes a link to create the index automatically.
