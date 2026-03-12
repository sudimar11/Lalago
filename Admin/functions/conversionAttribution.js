/**
 * Conversion attribution: links notifications, recommendations, and
 * searches to actual orders. Tracks LTV.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const AnalyticsTracker = require('./analyticsTracker');
const ANALYTICS = require('./analyticsConstants');

const ATTRIBUTION_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const HUNGER_2H_WINDOW_MS = 2 * 60 * 60 * 1000;

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function isCompletedStatus(status) {
  const s = (status || '').toString();
  return ANALYTICS.COMPLETED_ORDER_STATUSES.some(
    (c) => c.toLowerCase() === s.toLowerCase(),
  );
}

/**
 * Firestore trigger: attribute order completion to source.
 */
exports.trackOrderAttribution = functions
  .region('us-central1')
  .firestore.document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};
    const orderId = context.params.orderId;

    const beforeCompleted = isCompletedStatus(before.status);
    const afterCompleted = isCompletedStatus(after.status);

    if (beforeCompleted || !afterCompleted) {
      return null;
    }

    const userId =
      after.authorID ||
      after.authorId ||
      after.customerId ||
      after.customerID ||
      '';
    const orderValue = Number(after.totalAmount || after.total || 0);

    if (!userId) {
      console.log(
        `[trackOrderAttribution] Skip: missing userId. orderId=${orderId}`,
      );
      return null;
    }

    const db = getDb();
    const orderCreatedAt = after.createdAt?.toDate?.() || new Date();

    try {
      const clickSnap = await db
        .collection('user_clicks')
        .where('orderId', '==', orderId)
        .where('convertedToOrder', '==', true)
        .limit(1)
        .get();

      if (!clickSnap.empty) {
        const clickDoc = clickSnap.docs[0];
        const clickData = clickDoc.data();
        const source = clickData.source || 'recommendation';
        await AnalyticsTracker.trackConversion(
          userId,
          'recommendation',
          clickDoc.id,
          orderId,
          orderValue,
        );
        console.log(
          `[trackOrderAttribution] Attributed order ${orderId} to ${source}`,
        );
        return null;
      }

      const twoHoursStart = new Date(
        orderCreatedAt.getTime() - HUNGER_2H_WINDOW_MS,
      );
      const twoHoursStartTs =
        admin.firestore.Timestamp.fromDate(twoHoursStart);

      const hunger2hSnap = await db
        .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_HISTORY)
        .where('userId', '==', userId)
        .where('type', '==', 'ash_hunger')
        .where('sentAt', '>=', twoHoursStartTs)
        .orderBy('sentAt', 'desc')
        .limit(5)
        .get();

      const hungerNotif = hunger2hSnap.docs.find((d) => {
        const sentAt = d.data().sentAt?.toDate?.();
        return (
          sentAt &&
          orderCreatedAt.getTime() - sentAt.getTime() <= HUNGER_2H_WINDOW_MS &&
          sentAt <= orderCreatedAt
        );
      });

      if (hungerNotif) {
        await AnalyticsTracker.trackConversion(
          userId,
          'notification',
          hungerNotif.id,
          orderId,
          orderValue,
        );
        await db
          .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_HISTORY)
          .doc(hungerNotif.id)
          .update({
            attributionWindow: '2h',
          });
        console.log(
          `[trackOrderAttribution] Attributed order ${orderId} to hunger notification (2h)`,
        );
        return null;
      }

      const windowStart = new Date(
        orderCreatedAt.getTime() - ATTRIBUTION_WINDOW_MS,
      );
      const windowStartTs =
        admin.firestore.Timestamp.fromDate(windowStart);

      const notifSnap = await db
        .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_HISTORY)
        .where('userId', '==', userId)
        .where('sentAt', '>=', windowStartTs)
        .orderBy('sentAt', 'desc')
        .limit(5)
        .get();

      if (!notifSnap.empty) {
        const lastNotif = notifSnap.docs[0];
        const sentAt = lastNotif.data().sentAt?.toDate?.();
        if (sentAt && orderCreatedAt.getTime() - sentAt.getTime() <= ATTRIBUTION_WINDOW_MS) {
          await AnalyticsTracker.trackConversion(
            userId,
            'notification',
            lastNotif.id,
            orderId,
            orderValue,
          );
          console.log(
            `[trackOrderAttribution] Attributed order ${orderId} to notification`,
          );
          return null;
        }
      }

      const recSnap = await db
        .collection('recommendation_feedback')
        .where('userId', '==', userId)
        .where('timestamp', '>=', windowStartTs)
        .orderBy('timestamp', 'desc')
        .limit(5)
        .get();

      if (!recSnap.empty) {
        const lastRec = recSnap.docs[0];
        const recTs = lastRec.data().timestamp?.toDate?.();
        if (recTs && orderCreatedAt.getTime() - recTs.getTime() <= ATTRIBUTION_WINDOW_MS) {
          await AnalyticsTracker.trackConversion(
            userId,
            'recommendation',
            lastRec.id,
            orderId,
            orderValue,
          );
          console.log(
            `[trackOrderAttribution] Attributed order ${orderId} to recommendation_feedback`,
          );
          return null;
        }
      }

      await AnalyticsTracker.trackConversion(
        userId,
        'direct',
        null,
        orderId,
        orderValue,
      );
      console.log(`[trackOrderAttribution] Attributed order ${orderId} to direct`);
    } catch (e) {
      console.error('[trackOrderAttribution] Error:', e);
    }
    return null;
  });

/**
 * Monthly LTV calculation.
 * Runs on the 1st of each month at 4 AM Asia/Manila.
 */
exports.calculateLTV = functions
  .region('us-central1')
  .pubsub.schedule('0 4 1 * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const oneYearAgo = new Date(now);
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);
    const oneYearAgoTs = admin.firestore.Timestamp.fromDate(oneYearAgo);

    console.log('Calculating LTV for active users...');

    const ordersSnap = await db
      .collection('restaurant_orders')
      .where('status', 'in', ANALYTICS.COMPLETED_ORDER_STATUSES)
      .where('completedAt', '>=', oneYearAgoTs)
      .limit(10000)
      .get();

    const userLtv = {};
    ordersSnap.docs.forEach((doc) => {
      const order = doc.data();
      const authorId =
        order.authorID || order.authorId || order.customerId || '';
      if (!authorId) return;
      const amount = Number(order.totalAmount || order.total || 0);
      userLtv[authorId] = (userLtv[authorId] || 0) + amount;
    });

    const dateStr = now.toISOString().split('T')[0];
    let ltvTotal = 0;
    let userCount = 0;

    const BATCH_SIZE = 400;
    const entries = Object.entries(userLtv);
    for (let i = 0; i < entries.length; i += BATCH_SIZE) {
      const batch = db.batch();
      const chunk = entries.slice(i, i + BATCH_SIZE);
      for (const [userId, ltv] of chunk) {
        const userRef = db.collection('users').doc(userId);
        batch.set(userRef, {
          ltv,
          ltvCalculatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        ltvTotal += ltv;
        userCount += 1;
      }
      await batch.commit();
    }

    if (userCount > 0) {
      const avgLTV = ltvTotal / userCount;
      await db.collection(ANALYTICS.COLLECTIONS.LTV_AGGREGATES).add({
        date: dateStr,
        averageLTV: avgLTV,
        totalLTV: ltvTotal,
        userCount,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(
        `Calculated LTV for ${userCount} users, avg: ${avgLTV.toFixed(2)}`,
      );
    }
    return null;
  });
