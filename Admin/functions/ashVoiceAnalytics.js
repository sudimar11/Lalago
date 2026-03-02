/**
 * Ash Voice Analytics - Track and analyze notification tone performance.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

function getDb() {
  if (!admin.apps.length) admin.initializeApp();
  return admin.firestore();
}

/**
 * Firestore trigger: Log each Ash notification to ash_voice_metrics.
 */
exports.trackAshNotificationMetrics = functions
  .region('us-central1')
  .firestore.document('ash_notification_history/{notificationId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const title = (data.title || '').toString();
    const body = (data.body || '').toString();

    const hasAshPrefix = title.startsWith('Ash:');
    const firstName = (data.data?.firstName || data.firstName || '').toString();
    const hasPersonalization =
      firstName.length > 0 && body.includes(firstName);
    const emojiRegex = /[\u{1F300}-\u{1F9FF}]/gu;
    const hasEmoji = (title.match(emojiRegex) || []).length > 0;

    await getDb().collection('ash_voice_metrics').add({
      type: data.type || 'unknown',
      title,
      body,
      hasAshPrefix,
      hasPersonalization,
      hasEmoji,
      sentAt: data.sentAt || admin.firestore.FieldValue.serverTimestamp(),
      userId: data.userId || '',
      notificationId: context.params.notificationId,
    });
  });

/**
 * Scheduled: Daily aggregation of Ash voice performance.
 * Runs at 2 AM Asia/Manila.
 */
exports.analyzeAshVoice = functions
  .region('us-central1')
  .pubsub.schedule('0 2 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    const sevenDaysAgoTs = admin.firestore.Timestamp.fromDate(sevenDaysAgo);

    const metricsSnap = await db
      .collection('ash_notification_history')
      .where('sentAt', '>=', sevenDaysAgoTs)
      .limit(5000)
      .get();

    const analysis = {
      withAshPrefix: { sent: 0, opened: 0 },
      withoutAshPrefix: { sent: 0, opened: 0 },
      withPersonalization: { sent: 0, opened: 0 },
      withoutPersonalization: { sent: 0, opened: 0 },
      withEmoji: { sent: 0, opened: 0 },
      withoutEmoji: { sent: 0, opened: 0 },
    };

    const byType = {};

    for (const doc of metricsSnap.docs) {
      const d = doc.data();
      const opened = d.openedAt != null;

      if ((d.title || '').startsWith('Ash:')) {
        analysis.withAshPrefix.sent++;
        if (opened) analysis.withAshPrefix.opened++;
      } else {
        analysis.withoutAshPrefix.sent++;
        if (opened) analysis.withoutAshPrefix.opened++;
      }

      const firstName = (d.data?.firstName || d.firstName || '').toString();
      const hasPers =
        firstName.length > 0 && (d.body || '').includes(firstName);
      if (hasPers) {
        analysis.withPersonalization.sent++;
        if (opened) analysis.withPersonalization.opened++;
      } else {
        analysis.withoutPersonalization.sent++;
        if (opened) analysis.withoutPersonalization.opened++;
      }

      const emojiRegex = /[\u{1F300}-\u{1F9FF}]/gu;
      const hasEm = ((d.title || '').match(emojiRegex) || []).length > 0;
      if (hasEm) {
        analysis.withEmoji.sent++;
        if (opened) analysis.withEmoji.opened++;
      } else {
        analysis.withoutEmoji.sent++;
        if (opened) analysis.withoutEmoji.opened++;
      }

      const type = d.type || 'unknown';
      if (!byType[type]) byType[type] = { sent: 0, opened: 0 };
      byType[type].sent++;
      if (opened) byType[type].opened++;
    }

    await db.collection('ash_voice_analysis').add({
      date: new Date().toISOString().split('T')[0],
      analysis,
      byType,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return null;
  });
