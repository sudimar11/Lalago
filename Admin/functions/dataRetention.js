/**
 * Data retention and privacy: cleanup old data, anonymize on user delete.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');

const RETENTION_DAYS = {
  ash_notification_history: 90,
  notification_actions: 90,
  user_engagement: 180,
  conversion_events: 365,
  order_failures: 365,
  search_analytics: 30,
  user_clicks: 90,
};

const TIMESTAMP_FIELDS = {
  ash_notification_history: 'sentAt',
  notification_actions: 'timestamp',
  user_engagement: 'timestamp',
  conversion_events: 'convertedAt',
  order_failures: 'createdAt',
  search_analytics: 'timestamp',
  user_clicks: 'timestamp',
};

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

/**
 * Weekly cleanup of old analytics data.
 * Runs Sunday at 2 AM Asia/Manila.
 */
exports.cleanupOldData = functions
  .region('us-central1')
  .pubsub.schedule('0 2 * * 0')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();

    for (const [collection, days] of Object.entries(RETENTION_DAYS)) {
      const cutoff = new Date(now);
      cutoff.setDate(cutoff.getDate() - days);
      const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);
      const tsField = TIMESTAMP_FIELDS[collection] || 'timestamp';

      const snapshot = await db
        .collection(collection)
        .where(tsField, '<', cutoffTs)
        .limit(500)
        .get();

      if (snapshot.empty) continue;

      const batch = db.batch();
      snapshot.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      console.log(`Cleaned ${snapshot.size} docs from ${collection}`);
    }
    return null;
  });

/**
 * On user delete: anonymize their data in analytics collections.
 */
exports.anonymizeUserData = functions
  .region('us-central1')
  .firestore.document('users/{userId}')
  .onDelete(async (snap, context) => {
    const userId = context.params.userId;
    const db = getDb();

    const collections = [
      'ash_notification_history',
      'notification_actions',
      'user_engagement',
      'conversion_events',
      'order_failures',
    ];

    for (const coll of collections) {
      const snapshot = await db
        .collection(coll)
        .where('userId', '==', userId)
        .limit(500)
        .get();

      if (snapshot.empty) continue;

      const batch = db.batch();
      snapshot.docs.forEach((doc) => {
        batch.update(doc.ref, {
          userId: 'anonymized',
          userAnonymizedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      await batch.commit();
      console.log(`Anonymized ${snapshot.size} records in ${coll}`);
    }
    return null;
  });
