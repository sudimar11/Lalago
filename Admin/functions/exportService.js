/**
 * Export and reporting service for analytics data.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { format } = require('fast-csv');

const ALLOWED_COLLECTIONS = [
  'notification_aggregates',
  'user_daily_metrics',
  'revenue_daily_metrics',
  'conversion_events',
  'ash_notification_history',
  'user_clicks',
  'notification_actions',
  'user_engagement',
];

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function serializeValue(v) {
  if (v == null) return '';
  if (typeof v === 'object' && v.toDate) return v.toDate().toISOString();
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

/**
 * Callable: Generate CSV export of analytics collection.
 */
exports.generateCSVExport = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const uid = context.auth.uid;
    const db = getDb();
    const userDoc = await db.collection('users').doc(uid).get();
    const userData = userDoc.data() || {};
    const role = userData.role || userData.userRole || '';
    const isAdmin = role === 'admin' || role === 'Admin';

    if (!isAdmin) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Admin only',
      );
    }

    const collection = data?.collection;
    const startDate = data?.startDate ? new Date(data.startDate) : null;
    const endDate = data?.endDate ? new Date(data.endDate) : null;
    const exportFormat = data?.format || 'csv';

    if (!collection || !ALLOWED_COLLECTIONS.includes(collection)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `Invalid collection. Allowed: ${ALLOWED_COLLECTIONS.join(', ')}`,
      );
    }

    let query = db.collection(collection);

    const tsField =
      collection === 'conversion_events'
        ? 'convertedAt'
        : collection === 'ash_notification_history'
          ? 'sentAt'
          : ['user_clicks', 'notification_actions', 'user_engagement'].includes(
              collection,
            )
            ? 'timestamp'
            : null;

    if (tsField && startDate) {
      query = query.where(
        tsField,
        '>=',
        admin.firestore.Timestamp.fromDate(startDate),
      );
    }
    if (tsField && endDate) {
      query = query.where(
        tsField,
        '<=',
        admin.firestore.Timestamp.fromDate(endDate),
      );
    }

    const snapshot = await query.limit(5000).get();
    const rows = snapshot.docs.map((doc) => {
      const d = doc.data();
      return { id: doc.id, ...d };
    });

    if (exportFormat === 'csv' && rows.length > 0) {
      return new Promise((resolve, reject) => {
        const chunks = [];
        const csvStream = format({ headers: true });
        csvStream.on('data', (chunk) => chunks.push(chunk));
        csvStream.on('end', () => {
          const csv = chunks.join('');
          const base64 = Buffer.from(csv, 'utf-8').toString('base64');
          resolve({ csvBase64: base64, rowCount: rows.length });
        });
        csvStream.on('error', reject);

        rows.forEach((row) => {
          const flat = {};
          for (const [k, v] of Object.entries(row)) {
            flat[k] = serializeValue(v);
          }
          csvStream.write(flat);
        });
        csvStream.end();
      });
    }

    return { data: rows, rowCount: rows.length };
  });

/**
 * Scheduled: Generate weekly report.
 * Runs every Monday at 8 AM Asia/Manila.
 */
exports.scheduleWeeklyReport = functions
  .region('us-central1')
  .pubsub.schedule('0 8 * * 1')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const weekStart = new Date(now);
    weekStart.setDate(weekStart.getDate() - 7);

    const report = {
      date: now.toISOString().split('T')[0],
      weekStart: weekStart.toISOString().split('T')[0],
      metrics: {},
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const dates = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart);
      d.setDate(d.getDate() + i);
      dates.push(d.toISOString().split('T')[0]);
    }

    const notifData = [];
    for (const dateStr of dates) {
      const doc = await db
        .collection('notification_aggregates')
        .doc(dateStr)
        .get();
      if (doc.exists) {
        notifData.push({ date: dateStr, ...doc.data() });
      }
    }
    report.metrics.notifications = notifData;

    let totalRevenue = 0;
    let totalOrders = 0;
    for (const dateStr of dates) {
      const doc = await db
        .collection('revenue_daily_metrics')
        .doc(dateStr)
        .get();
      if (doc.exists) {
        const d = doc.data();
        totalRevenue += d.totalRevenue || 0;
        totalOrders += d.orderCount || 0;
      }
    }
    report.metrics.totalRevenue = totalRevenue;
    report.metrics.totalOrders = totalOrders;

    await db.collection('weekly_reports').add(report);
    console.log('Weekly report generated');
    return null;
  });
