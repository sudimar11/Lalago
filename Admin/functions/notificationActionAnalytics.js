const functions = require('firebase-functions');
const admin = require('firebase-admin');
const AnalyticsTracker = require('./analyticsTracker');

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

/**
 * Firestore trigger on ash_notification_history update.
 * When actionTaken is set, writes to action_analytics and updates action_stats.
 */
exports.trackNotificationAction = functions
  .region('us-central1')
  .firestore.document('ash_notification_history/{notificationId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (!before || !after) return null;
    if (before.actionTaken === after.actionTaken) return null;
    if (!after.actionTaken) return null;

    const db = getDb();
    const notificationId = context.params.notificationId;

    try {
      const sentAt = after.sentAt?.toDate?.();
      const actionTimestamp = after.actionTimestamp?.toDate?.();
      const timeToAction = sentAt && actionTimestamp
        ? actionTimestamp.getTime() - sentAt.getTime()
        : null;

      await db.collection('action_analytics').add({
        notificationId,
        userId: after.userId || null,
        action: after.actionTaken,
        type: after.type || null,
        timeToAction: timeToAction,
        converted: after.converted || false,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      const date = new Date().toISOString().split('T')[0];
      const statId = `${after.type || 'unknown'}_${after.actionTaken}_${date}`;

      await db.collection('action_stats').doc(statId).set({
        type: after.type || 'unknown',
        action: after.actionTaken,
        date,
        count: admin.firestore.FieldValue.increment(1),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      await AnalyticsTracker.trackNotificationEvent(
        {
          notificationId,
          userId: after.userId || null,
          type: after.type || null,
        },
        'notification_action',
        {
          action: after.actionTaken,
          timeToAction: sentAt && actionTimestamp
            ? actionTimestamp.getTime() - sentAt.getTime()
            : null,
          converted: after.converted || false,
        },
      );

      console.log(`[trackNotificationAction] Logged action ${after.actionTaken} for ${notificationId}`);
    } catch (e) {
      console.error('[trackNotificationAction] Error:', e);
    }
    return null;
  });
