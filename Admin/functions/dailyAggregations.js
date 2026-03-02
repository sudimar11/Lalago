/**
 * Daily aggregation Cloud Functions for Ash analytics.
 * Aggregates raw data into daily snapshots for efficient querying.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const ANALYTICS = require('./analyticsConstants');
const { getUserSegment } = require('./userSegmentation');

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function getYesterdayRange() {
  const now = new Date();
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  const dateStr = yesterday.toISOString().split('T')[0];
  const startOfDay = new Date(yesterday);
  startOfDay.setHours(0, 0, 0, 0);
  const endOfDay = new Date(yesterday);
  endOfDay.setHours(23, 59, 59, 999);
  return { dateStr, startOfDay, endOfDay };
}

/**
 * Aggregate notifications sent yesterday.
 * Runs at 1 AM Asia/Manila.
 */
exports.aggregateDailyNotifications = functions
  .region('us-central1')
  .pubsub.schedule('0 1 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const { dateStr, startOfDay, endOfDay } = getYesterdayRange();

    console.log(`Aggregating notifications for ${dateStr}...`);

    const notificationsSnap = await db
      .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_HISTORY)
      .where('sentAt', '>=', admin.firestore.Timestamp.fromDate(startOfDay))
      .where('sentAt', '<=', admin.firestore.Timestamp.fromDate(endOfDay))
      .get();

    const aggregates = {
      date: dateStr,
      total: notificationsSnap.size,
      byType: {},
      byAction: {},
      conversions: 0,
      conversionValue: 0,
      opened: 0,
    };

    notificationsSnap.docs.forEach((doc) => {
      const data = doc.data();
      const type = data.type || 'unknown';

      aggregates.byType[type] = (aggregates.byType[type] || 0) + 1;

      if (data.actionTaken) {
        aggregates.byAction[data.actionTaken] =
          (aggregates.byAction[data.actionTaken] || 0) + 1;
      }

      if (data.openedAt != null) {
        aggregates.opened += 1;
      }

      if (data.converted) {
        aggregates.conversions += 1;
        aggregates.conversionValue += data.conversionValue || 0;
      }
    });

    aggregates.openRate =
      aggregates.total > 0
        ? Number(((aggregates.opened / aggregates.total) * 100).toFixed(2))
        : 0;
    aggregates.conversionRate =
      aggregates.total > 0 && aggregates.conversions > 0
        ? Number(
            ((aggregates.conversions / aggregates.total) * 100).toFixed(2),
          )
        : 0;

    await db
      .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_AGGREGATES)
      .doc(dateStr)
      .set(aggregates);

    console.log(
      `Aggregated ${aggregates.total} notifications for ${dateStr}`,
    );
    return null;
  });

/**
 * Aggregate user metrics for yesterday.
 * Runs at 2 AM Asia/Manila.
 */
exports.aggregateDailyUserMetrics = functions
  .region('us-central1')
  .pubsub.schedule('0 2 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const { dateStr, startOfDay } = getYesterdayRange();

    console.log(`Aggregating user metrics for ${dateStr}...`);

    const startTs = admin.firestore.Timestamp.fromDate(startOfDay);
    const usersSnap = await db
      .collection('users')
      .where('lastOnlineTimestamp', '>=', startTs)
      .limit(5000)
      .get();

    const metrics = {
      date: dateStr,
      activeUsers: usersSnap.size,
      newUsers: 0,
      bySegment: {},
    };

    const yesterdayStr = startOfDay.toISOString().split('T')[0];

    for (const userDoc of usersSnap.docs) {
      const userData = userDoc.data();
      const createdAt = userData.createdAt?.toDate?.();
      if (
        createdAt &&
        createdAt.toISOString().split('T')[0] === yesterdayStr
      ) {
        metrics.newUsers += 1;
      }

      const segment = await getUserSegment(userDoc.id, userData, db);
      metrics.bySegment[segment] = (metrics.bySegment[segment] || 0) + 1;
    }

    await db
      .collection(ANALYTICS.COLLECTIONS.USER_DAILY_METRICS)
      .doc(dateStr)
      .set(metrics);

    console.log(`Aggregated metrics for ${metrics.activeUsers} active users`);
    return null;
  });

/**
 * Aggregate revenue for yesterday.
 * Runs at 3 AM Asia/Manila.
 */
exports.aggregateDailyRevenue = functions
  .region('us-central1')
  .pubsub.schedule('0 3 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const { dateStr, startOfDay, endOfDay } = getYesterdayRange();

    console.log(`Aggregating revenue for ${dateStr}...`);

    const startTs = admin.firestore.Timestamp.fromDate(startOfDay);
    const endTs = admin.firestore.Timestamp.fromDate(endOfDay);

    const ordersSnap = await db
      .collection('restaurant_orders')
      .where('status', 'in', ANALYTICS.COMPLETED_ORDER_STATUSES)
      .where('completedAt', '>=', startTs)
      .where('completedAt', '<=', endTs)
      .get();

    let totalRevenue = 0;
    const byRestaurant = {};
    const byHour = Array(24)
      .fill(0)
      .map(() => 0);

    ordersSnap.docs.forEach((doc) => {
      const order = doc.data();
      const amount = Number(order.totalAmount || 0);
      totalRevenue += amount;

      const vendorId = order.vendorID || order.vendorId || 'unknown';
      byRestaurant[vendorId] = (byRestaurant[vendorId] || 0) + amount;

      const completedAt = order.completedAt?.toDate?.();
      if (completedAt) {
        const hour = completedAt.getHours();
        byHour[hour] = (byHour[hour] || 0) + amount;
      }
    });

    const revenueMetrics = {
      date: dateStr,
      totalRevenue,
      orderCount: ordersSnap.size,
      averageOrderValue:
        ordersSnap.size > 0 ? totalRevenue / ordersSnap.size : 0,
      byRestaurant,
      byHour,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db
      .collection(ANALYTICS.COLLECTIONS.REVENUE_DAILY_METRICS)
      .doc(dateStr)
      .set(revenueMetrics);

    console.log(
      `Aggregated revenue: ${totalRevenue} from ${ordersSnap.size} orders`,
    );
    return null;
  });
