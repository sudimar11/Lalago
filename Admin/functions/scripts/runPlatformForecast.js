/**
 * One-off script to run generatePlatformForecast logic and capture debug output.
 * Run: node scripts/runPlatformForecast.js
 */
const admin = require('firebase-admin');
const path = require('path');

if (!admin.apps.length) {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'lalago-v2';
  admin.initializeApp({ projectId });
}

const db = admin.firestore();

const FORECAST_AGGREGATES = 'forecast_aggregates';
const ORDER_FORECASTS = 'order_forecasts';
const ORDERS = 'restaurant_orders';
const DAYS_TO_READ = 120;
const DAYS_TO_FORECAST = 7;
const FULFILLED_ORDER_STATUSES = [
  'Order Completed', 'order completed', 'completed', 'Completed',
  'Order Shipped', 'order shipped', 'Order Delivered', 'order delivered',
  'In Transit', 'in transit',
];

function formatDateKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function parseDateKey(key) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d);
}

function getDayOfWeek(d) {
  return d.getDay();
}

function isFulfilled(status) {
  if (!status) return false;
  const s = String(status).toLowerCase();
  return FULFILLED_ORDER_STATUSES.some((f) => s.includes(String(f).toLowerCase()));
}

function aggregatePlatformDaily(aggDocs) {
  const byDate = {};
  for (const doc of aggDocs) {
    const data = doc.data();
    const date = data.date;
    const orders = data.totalDailyOrders || 0;
    if (!date) continue;
    byDate[date] = (byDate[date] || 0) + orders;
  }
  return byDate;
}

async function aggregateFromRestaurantOrders(db, startKey, endKey) {
  const startDate = parseDateKey(startKey);
  const endDate = parseDateKey(endKey);
  const startTs = admin.firestore.Timestamp.fromDate(startDate);
  const endTs = admin.firestore.Timestamp.fromDate(endDate);
  const byDate = {};
  let lastDoc = null;
  let totalFetched = 0;

  while (true) {
    let query = db.collection(ORDERS)
      .where('status', 'in', FULFILLED_ORDER_STATUSES)
      .where('createdAt', '>=', startTs)
      .where('createdAt', '<=', endTs)
      .orderBy('createdAt', 'asc')
      .limit(500);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      if (!isFulfilled(data.status)) continue;
      const createdAt = data.createdAt?.toDate?.();
      if (!createdAt) continue;
      const dateKey = formatDateKey(createdAt);
      byDate[dateKey] = (byDate[dateKey] || 0) + 1;
    }
    totalFetched += snapshot.docs.length;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.docs.length < 500) break;
  }

  console.log(`[DBG] aggregateFromRestaurantOrders: fetched ${totalFetched} orders, ${Object.keys(byDate).length} unique dates`);
  return byDate;
}

function computeForecast(dailyTotals) {
  const dates = Object.keys(dailyTotals).sort();
  if (dates.length < 7) {
    console.log(`[DBG] computeForecast: only ${dates.length} dates, need 7`);
    return { predictions: [], stdDevByDow: {} };
  }
  const byDow = {};
  for (let i = 0; i < 7; i++) byDow[i] = [];
  for (const d of dates) {
    const dt = parseDateKey(d);
    byDow[getDayOfWeek(dt)].push(dailyTotals[d]);
  }
  const avgByDow = {};
  const stdDevByDow = {};
  for (let dow = 0; dow < 7; dow++) {
    const vals = byDow[dow];
    const mean = vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : 0;
    avgByDow[dow] = mean;
    stdDevByDow[dow] = vals.length
      ? Math.sqrt(vals.reduce((s, v) => s + (v - mean) ** 2, 0) / vals.length) || 0
      : 0;
  }
  const overallMean = dates.reduce((s, d) => s + dailyTotals[d], 0) / dates.length;
  const overallStd = Math.sqrt(
    dates.reduce((s, d) => s + (dailyTotals[d] - overallMean) ** 2, 0) / dates.length
  ) || 0;
  const predictions = [];
  const lastDate = parseDateKey(dates[dates.length - 1]);
  for (let i = 1; i <= DAYS_TO_FORECAST; i++) {
    const forecastDate = new Date(lastDate);
    forecastDate.setDate(forecastDate.getDate() + i);
    const dateKey = formatDateKey(forecastDate);
    const dow = getDayOfWeek(forecastDate);
    const predicted = Math.round(avgByDow[dow] || overallMean);
    const stdDev = stdDevByDow[dow] > 0 ? stdDevByDow[dow] : overallStd;
    const z = 1.28;
    const margin = z * stdDev;
    predictions.push({
      forecastDate: dateKey,
      predictedOrders: predicted,
      lowerBound: Math.max(0, Math.round(predicted - margin)),
      upperBound: Math.round(predicted + margin),
    });
  }
  return { predictions };
}

async function main() {
  const now = new Date();
  const startDate = new Date(now);
  startDate.setDate(startDate.getDate() - DAYS_TO_READ);
  const startKey = formatDateKey(startDate);
  const endKey = formatDateKey(now);

  console.log(`[DBG] startKey=${startKey} endKey=${endKey}`);

  const snapshot = await db
    .collection(FORECAST_AGGREGATES)
    .where('date', '>=', startKey)
    .where('date', '<=', endKey)
    .get();

  let dailyTotals = aggregatePlatformDaily(snapshot.docs);
  const aggDates = Object.keys(dailyTotals).sort();
  console.log(`[DBG] forecast_aggregates: docs=${snapshot.docs.length} dailyTotalsDates=${aggDates.length} sample=${aggDates.slice(0, 5).join(',')}`);

  if (aggDates.length < 7) {
    console.log('[DBG] Using fallback: restaurant_orders');
    dailyTotals = await aggregateFromRestaurantOrders(db, startKey, endKey);
  }

  const { predictions } = computeForecast(dailyTotals);
  console.log(`[DBG] predictions count=${predictions.length}`);
  if (predictions.length > 0) {
    console.log(`[DBG] sample: ${JSON.stringify(predictions[0])}`);
  }

  if (predictions.length > 0) {
    const batch = db.batch();
    for (const p of predictions) {
      const ref = db.collection(ORDER_FORECASTS).doc(p.forecastDate);
      batch.set(ref, {
        forecastDate: p.forecastDate,
        predictedOrders: p.predictedOrders,
        lowerBound: p.lowerBound,
        upperBound: p.upperBound,
        modelVersion: '1.0',
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    console.log(`[DBG] Wrote ${predictions.length} forecasts to order_forecasts`);
  } else {
    console.log('[DBG] No predictions to write');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error('[DBG] Error:', err);
  process.exit(1);
});
