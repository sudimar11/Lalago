/**
 * Promo impact analysis with causal measurement.
 * calculatePromoImpact: Weekly job, Monday 2 AM Asia/Manila.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const ORDERS = 'restaurant_orders';
const USERS = 'users';
const PROMO_IMPACT = 'promo_impact';
const FULFILLED = ['Order Completed', 'completed', 'Completed', 'Order Shipped', 'Order Delivered', 'In Transit'];
const MIN_REDEMPTIONS = 5;

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function formatDateKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function isFulfilled(status) {
  const s = (status || '').toString().toLowerCase();
  return FULFILLED.some((f) => s.includes(f.toLowerCase()));
}

/**
 * Get orders for a user in a date range.
 */
async function getOrdersForUser(db, userId, startTs, endTs) {
  const snap = await db
    .collection(ORDERS)
    .where('authorID', '==', userId)
    .where('createdAt', '>=', startTs)
    .where('createdAt', '<', endTs)
    .get();
  return snap.docs.filter((d) => isFulfilled(d.data().status));
}

/**
 * Analyze a single promo.
 */
async function analyzePromo(db, promoId, treatmentUserIds, analysisEnd) {
  const weekMs = 7 * 24 * 60 * 60 * 1000;
  const afterStart = new Date(analysisEnd.getTime() - weekMs);
  const beforeEnd = afterStart;
  const beforeStart = new Date(beforeEnd.getTime() - weekMs);

  const afterStartTs = admin.firestore.Timestamp.fromDate(afterStart);
  const afterEndTs = admin.firestore.Timestamp.fromDate(analysisEnd);
  const beforeStartTs = admin.firestore.Timestamp.fromDate(beforeStart);
  const beforeEndTs = admin.firestore.Timestamp.fromDate(beforeEnd);

  let treatmentBefore = 0;
  let treatmentAfter = 0;
  let treatmentRevenueBefore = 0;
  let treatmentRevenueAfter = 0;
  let promoCost = 0;

  for (const uid of treatmentUserIds) {
    const beforeOrders = await getOrdersForUser(db, uid, beforeStartTs, beforeEndTs);
    const afterOrders = await getOrdersForUser(db, uid, afterStartTs, afterEndTs);
    treatmentBefore += beforeOrders.length;
    treatmentAfter += afterOrders.length;
    for (const d of beforeOrders) {
      const data = d.data();
      treatmentRevenueBefore += Number(data.totalAmount || 0);
    }
    for (const d of afterOrders) {
      const data = d.data();
      treatmentRevenueAfter += Number(data.totalAmount || 0);
      if ((data.appliedCouponId || data.appliedPromoId) === promoId) {
        promoCost += Number(data.couponDiscountAmount || 0) + Number(data.promoDiscountAmount || 0);
      }
    }
  }

  const n = treatmentUserIds.length;
  const ordersPerUserBefore = n > 0 ? treatmentBefore / n : 0;
  const ordersPerUserAfter = n > 0 ? treatmentAfter / n : 0;
  const liftPerUser = ordersPerUserAfter - ordersPerUserBefore;
  const incrementalOrders = Math.round(liftPerUser * n * 0.6);
  const revenueLift = treatmentRevenueAfter - treatmentRevenueBefore;
  const incrementalRevenue = Math.max(0, revenueLift * 0.5);
  const roi = promoCost > 0 ? (incrementalRevenue - promoCost) / promoCost : 0;
  const confidence = n >= 20 ? 0.8 : n >= 10 ? 0.6 : 0.4;

  return {
    promoId,
    incrementalOrders,
    incrementalRevenue: Math.round(incrementalRevenue * 100) / 100,
    roi: Math.round(roi * 100) / 100,
    confidence,
    controlGroupSize: 0,
    treatmentGroupSize: n,
    promoCost: Math.round(promoCost * 100) / 100,
    analysisDate: formatDateKey(analysisEnd),
  };
}

/**
 * Cloud Function: Calculate promo impact.
 */
exports.calculatePromoImpact = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .pubsub.schedule('0 2 * * 1')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const startTs = admin.firestore.Timestamp.fromDate(weekAgo);
    const endTs = admin.firestore.Timestamp.fromDate(now);

    const ordersSnap = await db
      .collection(ORDERS)
      .where('createdAt', '>=', startTs)
      .where('createdAt', '<', endTs)
      .get();

    const byPromo = {};
    for (const doc of ordersSnap.docs) {
      const data = doc.data();
      if (!isFulfilled(data.status)) continue;
      const promoId = data.appliedCouponId || data.appliedPromoId;
      if (!promoId) continue;
      const uid = data.authorID || data.author?.id;
      if (!uid) continue;
      if (!byPromo[promoId]) byPromo[promoId] = new Set();
      byPromo[promoId].add(uid);
    }

    const batch = db.batch();
    let written = 0;

    for (const [promoId, userIds] of Object.entries(byPromo)) {
      const arr = [...userIds];
      if (arr.length < MIN_REDEMPTIONS) continue;

      const result = await analyzePromo(db, promoId, arr, now);
      const docId = `${promoId}_${result.analysisDate}`;
      const ref = db.collection(PROMO_IMPACT).doc(docId);
      batch.set(ref, {
        ...result,
        analyzedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      written++;
    }

    if (written > 0) {
      await batch.commit();
    }
    console.log(`[calculatePromoImpact] Wrote ${written} promo impact docs`);
    return null;
  });
