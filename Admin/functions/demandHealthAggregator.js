/**
 * Demand health score aggregation.
 * Runs hourly, computes weighted health score and writes to demand_health.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const ORDERS = 'restaurant_orders';
const ORDER_FORECASTS = 'order_forecasts';
const PROMO_IMPACT = 'promo_impact';
const DEMAND_HEALTH = 'demand_health';
const FOODS_REVIEW = 'foods_review';
const FULFILLED = ['Order Completed', 'completed', 'Completed', 'Order Shipped', 'Order Delivered', 'In Transit'];

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

function getStartOfWeek(d) {
  const x = new Date(d);
  const day = x.getDay();
  const diff = x.getDate() - day + (day === 0 ? -6 : 1);
  x.setDate(diff);
  x.setHours(0, 0, 0, 0);
  return x;
}

async function componentOrderVsForecast(db, today) {
  const forecastDoc = await db.collection(ORDER_FORECASTS).doc(formatDateKey(today)).get();
  const startOfDay = new Date(today);
  startOfDay.setHours(0, 0, 0, 0);
  const endOfDay = new Date(today);
  endOfDay.setHours(23, 59, 59, 999);
  const startTs = admin.firestore.Timestamp.fromDate(startOfDay);
  const endTs = admin.firestore.Timestamp.fromDate(endOfDay);

  const ordersSnap = await db
    .collection(ORDERS)
    .where('createdAt', '>=', startTs)
    .where('createdAt', '<=', endTs)
    .get();
  const actual = ordersSnap.docs.filter((d) => isFulfilled(d.data().status)).length;
  const predicted = forecastDoc.exists
    ? (forecastDoc.data()?.predictedOrders || 0)
    : actual;

  if (predicted <= 0) return { score: 100, value: 1, label: 'On track' };
  const ratio = actual / predicted;
  const score = Math.min(100, Math.round(ratio * 100));
  return { score, value: ratio, label: `${actual}/${predicted}` };
}

async function componentWowGrowth(db, now) {
  const thisWeekStart = getStartOfWeek(now);
  const lastWeekStart = new Date(thisWeekStart);
  lastWeekStart.setDate(lastWeekStart.getDate() - 7);
  const lastWeekEnd = new Date(thisWeekStart);
  lastWeekEnd.setMilliseconds(-1);

  const thisStartTs = admin.firestore.Timestamp.fromDate(thisWeekStart);
  const thisEndTs = admin.firestore.Timestamp.fromDate(now);
  const lastStartTs = admin.firestore.Timestamp.fromDate(lastWeekStart);
  const lastEndTs = admin.firestore.Timestamp.fromDate(lastWeekEnd);

  const [thisSnap, lastSnap] = await Promise.all([
    db.collection(ORDERS).where('createdAt', '>=', thisStartTs).where('createdAt', '<=', thisEndTs).get(),
    db.collection(ORDERS).where('createdAt', '>=', lastStartTs).where('createdAt', '<=', lastEndTs).get(),
  ]);
  const thisCount = thisSnap.docs.filter((d) => isFulfilled(d.data().status)).length;
  const lastCount = lastSnap.docs.filter((d) => isFulfilled(d.data().status)).length;

  if (lastCount <= 0) return { score: 100, value: 1, label: 'N/A' };
  const ratio = thisCount / lastCount;
  const score = Math.min(100, Math.round(ratio * 100));
  return { score, value: ratio, label: `${thisCount}/${lastCount}` };
}

async function componentRestaurantAvailability(db) {
  const vendorsSnap = await db.collection('vendors').get();
  let active = 0;
  for (const d of vendorsSnap.docs) {
    if (d.data()?.reststatus === true) active++;
  }
  const total = vendorsSnap.size || 1;
  const score = Math.round((active / total) * 100);
  return { score, value: active / total, label: `${active}/${total}` };
}

async function componentRiderAvailability(db) {
  const ridersSnap = await db.collection('users').where('role', '==', 'driver').get();
  let available = 0;
  for (const d of ridersSnap.docs) {
    const data = d.data();
    const avail = (data.riderAvailability || '').toString();
    if (['available', 'on_delivery', 'on_break'].includes(avail) && data.isOnline === true) {
      available++;
    }
  }
  const total = ridersSnap.size || 1;
  const score = Math.min(100, Math.round((available / Math.max(1, total * 0.3)) * 100));
  return { score: Math.min(100, score), value: available / total, label: `${available}/${total}` };
}

async function componentPromoEffectiveness(db) {
  const weekAgo = new Date();
  weekAgo.setDate(weekAgo.getDate() - 7);
  const snap = await db
    .collection(PROMO_IMPACT)
    .where('analysisDate', '>=', formatDateKey(weekAgo))
    .get();

  if (snap.empty) return { score: 75, value: 0.75, label: 'N/A' };
  let totalRoi = 0;
  let count = 0;
  for (const d of snap.docs) {
    const roi = d.data()?.roi;
    if (typeof roi === 'number') {
      totalRoi += roi;
      count++;
    }
  }
  const avgRoi = count > 0 ? totalRoi / count : 0;
  const score = Math.min(100, Math.round(50 + avgRoi * 50));
  return { score: Math.max(0, score), value: avgRoi, label: avgRoi.toFixed(2) };
}

async function componentCustomerSatisfaction(db) {
  const snap = await db.collection(FOODS_REVIEW).limit(200).get();
  if (snap.empty) return { score: 75, value: 0.75, label: 'N/A' };
  let sum = 0;
  let n = 0;
  for (const d of snap.docs) {
    const rating = d.data()?.rating ?? d.data()?.Rating;
    if (typeof rating === 'number' && rating >= 0 && rating <= 5) {
      sum += rating;
      n++;
    }
  }
  const avg = n > 0 ? sum / n : 4;
  const score = Math.round((avg / 5) * 100);
  return { score: Math.min(100, score), value: avg / 5, label: avg.toFixed(1) };
}

const WEIGHTS = {
  orderVsForecast: 0.3,
  wowGrowth: 0.2,
  restaurantAvailability: 0.15,
  riderAvailability: 0.15,
  promoEffectiveness: 0.1,
  customerSatisfaction: 0.1,
};

exports.demandHealthAggregator = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 120, memory: '512MB' })
  .pubsub.schedule('0 * * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();

    const [c1, c2, c3, c4, c5, c6] = await Promise.all([
      componentOrderVsForecast(db, now),
      componentWowGrowth(db, now),
      componentRestaurantAvailability(db),
      componentRiderAvailability(db),
      componentPromoEffectiveness(db),
      componentCustomerSatisfaction(db),
    ]);

    const components = {
      orderVsForecast: c1,
      wowGrowth: c2,
      restaurantAvailability: c3,
      riderAvailability: c4,
      promoEffectiveness: c5,
      customerSatisfaction: c6,
    };

    const overallScore = Math.round(
      c1.score * WEIGHTS.orderVsForecast +
        c2.score * WEIGHTS.wowGrowth +
        c3.score * WEIGHTS.restaurantAvailability +
        c4.score * WEIGHTS.riderAvailability +
        c5.score * WEIGHTS.promoEffectiveness +
        c6.score * WEIGHTS.customerSatisfaction
    );

    await db.collection(DEMAND_HEALTH).add({
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      overallScore: Math.min(100, Math.max(0, overallScore)),
      components,
    });
    console.log(`[demandHealthAggregator] Wrote health score: ${overallScore}`);
    return null;
  });
