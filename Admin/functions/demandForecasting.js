/**
 * Demand forecasting model.
 * generateDemandForecasts: Daily job to predict order volume and product demand.
 * Uses 7-day moving average fallback; Vertex AI path can be added when model is trained.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const FORECAST_AGGREGATES = 'forecast_aggregates';
const DEMAND_FORECASTS = 'demand_forecasts';
const VENDOR_PRODUCTS = 'vendor_products';
const DAYS_TO_READ = 90;
const DAYS_TO_FORECAST = 7;
const TOP_PRODUCTS = 20;

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

/**
 * Compute 7-day moving average per hour from aggregates.
 */
function movingAverageForecast(aggregates) {
  const hourlySums = {};
  const hourlyCounts = {};
  for (let h = 0; h < 24; h++) {
    hourlySums[String(h)] = 0;
    hourlyCounts[String(h)] = 0;
  }

  const productSums = {};
  const productCounts = {};

  for (const agg of aggregates) {
    const hb = agg.hourlyBreakdown || {};
    for (let h = 0; h < 24; h++) {
      const hKey = String(h);
      const data = hb[hKey];
      if (data && data.orderCount > 0) {
        hourlySums[hKey] += data.orderCount;
        hourlyCounts[hKey] += 1;

        const sales = data.productSales || {};
        for (const [pid, qty] of Object.entries(sales)) {
          if (!productSums[pid]) {
            productSums[pid] = 0;
            productCounts[pid] = 0;
          }
          productSums[pid] += qty;
          productCounts[pid] += 1;
        }
      }
    }
  }

  const hourlyPredictions = {};
  for (let h = 0; h < 24; h++) {
    const hKey = String(h);
    const count = hourlyCounts[hKey] || 0;
    const sum = hourlySums[hKey] || 0;
    const avg = count > 0 ? Math.round(sum / count) : 0;
    hourlyPredictions[hKey] = avg;
  }

  const productPredictions = {};
  const productList = Object.entries(productSums)
    .map(([pid, sum]) => {
      const count = productCounts[pid] || 1;
      return { id: pid, predictedQty: Math.round(sum / count), total: sum };
    })
    .sort((a, b) => b.total - a.total)
    .slice(0, TOP_PRODUCTS);

  productList.forEach((p, idx) => {
    productPredictions[p.id] = { predictedQty: p.predictedQty, rank: idx + 1 };
  });

  return { hourlyPredictions, productPredictions };
}

/**
 * Try Vertex AI forecasting (stub - requires trained model).
 * Returns null to trigger fallback.
 */
async function tryVertexAIForecast(aggregates, vendorId) {
  try {
    if (!process.env.GCLOUD_PROJECT && !process.env.GCP_PROJECT) {
      return null;
    }
    return null;
  } catch (e) {
    console.warn('[generateDemandForecasts] Vertex AI error:', e.message);
    return null;
  }
}

/**
 * Generate forecasts for a single vendor.
 */
async function forecastForVendor(db, vendorId) {
  const now = new Date();
  const startDate = new Date(now);
  startDate.setDate(startDate.getDate() - DAYS_TO_READ);

  const snapshot = await db
    .collection(FORECAST_AGGREGATES)
    .where('vendorId', '==', vendorId)
    .where('date', '>=', formatDateKey(startDate))
    .where('date', '<=', formatDateKey(now))
    .orderBy('date', 'desc')
    .limit(DAYS_TO_READ)
    .get();

  const aggregates = snapshot.docs.map((d) => d.data());
  if (aggregates.length === 0) {
    return null;
  }

  let result = await tryVertexAIForecast(aggregates, vendorId);
  if (!result) {
    result = movingAverageForecast(aggregates);
  }

  return result;
}

/**
 * Get product names for productPredictions.
 */
async function enrichProductNames(db, productPredictions) {
  const enriched = {};
  const ids = Object.keys(productPredictions);
  if (ids.length === 0) return productPredictions;

  for (let i = 0; i < ids.length; i += 10) {
    const batch = ids.slice(i, i + 10);
    const snaps = await Promise.all(
      batch.map((id) => db.collection(VENDOR_PRODUCTS).doc(id).get())
    );
    for (let j = 0; j < batch.length; j++) {
      const id = batch[j];
      const snap = snaps[j];
      const data = productPredictions[id];
      const name = snap?.exists && snap.data()
        ? (snap.data().name || 'Unknown').toString()
        : 'Unknown';
      enriched[id] = { ...data, productName: name };
    }
  }
  return enriched;
}

/**
 * Daily Cloud Function: Generate demand forecasts for all vendors.
 * Runs at 5 AM Asia/Manila (after aggregateForecastData).
 */
exports.generateDemandForecasts = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .pubsub.schedule('0 5 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();

    const vendorsSnap = await db.collection('vendors').get();
    const vendorIds = vendorsSnap.docs.map((d) => d.id).filter(Boolean);

    const now = new Date();
    const batch = db.batch();
    let written = 0;

    for (const vendorId of vendorIds) {
      for (let d = 1; d <= DAYS_TO_FORECAST; d++) {
        const forecastDate = new Date(now);
        forecastDate.setDate(forecastDate.getDate() + d);
        const dateKey = formatDateKey(forecastDate);

        const result = await forecastForVendor(db, vendorId);
        if (!result) continue;

        const productPredictions = await enrichProductNames(
          db,
          result.productPredictions
        );

        const doc = {
          vendorId,
          forecastDate: dateKey,
          hourlyPredictions: result.hourlyPredictions,
          productPredictions,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        const ref = db
          .collection(DEMAND_FORECASTS)
          .doc(`${vendorId}_${dateKey}`);
        batch.set(ref, doc);
        written += 1;
      }
    }

    await batch.commit();
    console.log(
      `[generateDemandForecasts] Generated ${written} forecast docs for ${vendorIds.length} vendors`
    );
    return null;
  });
