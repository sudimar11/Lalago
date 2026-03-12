/**
 * Platform-level daily order forecasting.
 * generatePlatformForecast: Nightly job at 3 AM Asia/Manila.
 * Reads forecast_aggregates, produces order_forecasts with confidence intervals.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const FORECAST_AGGREGATES = 'forecast_aggregates';
const ORDER_FORECASTS = 'order_forecasts';
const ORDERS = 'restaurant_orders';
const DAYS_TO_READ = 120;
const DAYS_TO_FORECAST = 7;

const FULFILLED_ORDER_STATUSES = [
  'Order Completed',
  'order completed',
  'completed',
  'Completed',
  'Order Shipped',
  'order shipped',
  'Order Delivered',
  'order delivered',
  'In Transit',
  'in transit',
];

function isFulfilled(status) {
  if (!status) return false;
  const s = String(status).toLowerCase();
  return FULFILLED_ORDER_STATUSES.some(
    (f) => s.includes(String(f).toLowerCase())
  );
}
const MODEL_VERSION = '1.0';
const CONFIDENCE_LEVEL = 0.8;

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

function parseDateKey(key) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d);
}

function getDayOfWeek(d) {
  return d.getDay();
}

/**
 * Aggregate platform daily totals from forecast_aggregates.
 */
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

/**
 * Fallback: aggregate platform daily totals from restaurant_orders when
 * forecast_aggregates is empty.
 */
async function aggregateFromRestaurantOrders(db, startKey, endKey) {
  const startDate = parseDateKey(startKey);
  const endDate = parseDateKey(endKey);
  const startTs = admin.firestore.Timestamp.fromDate(startDate);
  const endTs = admin.firestore.Timestamp.fromDate(endDate);

  const byDate = {};
  let lastDoc = null;

  while (true) {
    let query = db
      .collection(ORDERS)
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
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.docs.length < 500) break;
  }

  return byDate;
}

/**
 * Compute 7-day moving average with day-of-week weighting.
 * Returns { predictions, stdDevByDow } for confidence intervals.
 */
function computeForecast(dailyTotals) {
  const dates = Object.keys(dailyTotals).sort();
  if (dates.length < 7) {
    return { predictions: [], stdDevByDow: {} };
  }

  const byDow = {};
  for (let i = 0; i < 7; i++) {
    byDow[i] = [];
  }
  for (const d of dates) {
    const dt = parseDateKey(d);
    const dow = getDayOfWeek(dt);
    byDow[dow].push(dailyTotals[d]);
  }

  const avgByDow = {};
  const stdDevByDow = {};
  for (let dow = 0; dow < 7; dow++) {
    const vals = byDow[dow];
    if (vals.length === 0) {
      avgByDow[dow] = 0;
      stdDevByDow[dow] = 0;
      continue;
    }
    const mean = vals.reduce((a, b) => a + b, 0) / vals.length;
    avgByDow[dow] = mean;
    const variance =
      vals.reduce((s, v) => s + (v - mean) ** 2, 0) / vals.length;
    stdDevByDow[dow] = Math.sqrt(variance) || 0;
  }

  const overallMean =
    dates.reduce((s, d) => s + dailyTotals[d], 0) / dates.length;
  const overallStd =
    Math.sqrt(
      dates.reduce((s, d) => s + (dailyTotals[d] - overallMean) ** 2, 0) /
        dates.length
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
    const lowerBound = Math.max(0, Math.round(predicted - margin));
    const upperBound = Math.round(predicted + margin);

    predictions.push({
      forecastDate: dateKey,
      predictedOrders: predicted,
      lowerBound,
      upperBound,
    });
  }

  return { predictions };
}

/**
 * Cloud Function: Generate platform-level order forecasts.
 * Runs at 3 AM Asia/Manila (after aggregateForecastData at 2 AM).
 */
exports.generatePlatformForecast = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .pubsub.schedule('0 3 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const startDate = new Date(now);
    startDate.setDate(startDate.getDate() - DAYS_TO_READ);

    const startKey = formatDateKey(startDate);
    const endKey = formatDateKey(now);

    const snapshot = await db
      .collection(FORECAST_AGGREGATES)
      .where('date', '>=', startKey)
      .where('date', '<=', endKey)
      .get();

    let dailyTotals = aggregatePlatformDaily(snapshot.docs);

    if (Object.keys(dailyTotals).length < 7) {
      console.log(
        '[generatePlatformForecast] forecast_aggregates empty, fallback to restaurant_orders'
      );
      dailyTotals = await aggregateFromRestaurantOrders(db, startKey, endKey);
    }

    const { predictions } = computeForecast(dailyTotals);

    const batch = db.batch();
    for (const p of predictions) {
      const ref = db.collection(ORDER_FORECASTS).doc(p.forecastDate);
      batch.set(ref, {
        forecastDate: p.forecastDate,
        predictedOrders: p.predictedOrders,
        lowerBound: p.lowerBound,
        upperBound: p.upperBound,
        modelVersion: MODEL_VERSION,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    console.log(
      `[generatePlatformForecast] Wrote ${predictions.length} platform forecasts`
    );
    return null;
  });
