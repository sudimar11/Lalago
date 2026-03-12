/**
 * Demand forecasting data pipeline.
 * aggregateForecastData: Daily job to aggregate historical order data per vendor.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const ORDERS = 'restaurant_orders';
const FORECAST_AGGREGATES = 'forecast_aggregates';
const BATCH_SIZE = 500;

/** Only fulfilled orders contribute to forecast baseline. */
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

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function parsePreparationMinutes(prepTimeStr) {
  if (!prepTimeStr) return 30;
  const str = prepTimeStr.toString().toLowerCase().trim();
  const minMatch = str.match(/(\d+)\s*min/);
  if (minMatch) return Math.min(120, Math.max(5, parseInt(minMatch[1], 10)));
  const colonMatch = str.match(/(\d+):(\d+)/);
  if (colonMatch) {
    const hours = parseInt(colonMatch[1], 10);
    const minutes = parseInt(colonMatch[2], 10);
    return Math.min(120, Math.max(5, hours * 60 + minutes));
  }
  const numMatch = str.match(/(\d+)/);
  if (numMatch) return Math.min(120, Math.max(5, parseInt(numMatch[1], 10)));
  return 30;
}

function formatDateKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * Aggregate orders for a single vendor for a single date.
 */
function aggregateVendorDate(vendorId, dateKey, ordersForVendorDate) {
  const hourlyBreakdown = {};
  for (let h = 0; h < 24; h++) {
    hourlyBreakdown[String(h)] = { orderCount: 0, productSales: {} };
  }

  let totalRevenue = 0;
  let totalPrepMinutes = 0;
  let prepCount = 0;

  for (const order of ordersForVendorDate) {
    const createdAt = order.createdAt?.toDate?.() || new Date();
    const hour = createdAt.getHours();
    const hourKey = String(hour);
    hourlyBreakdown[hourKey].orderCount += 1;

    const amount = order.totalAmount ?? 0;
    totalRevenue += typeof amount === 'number' ? amount : parseFloat(amount) || 0;

    const prepStr = order.estimatedTimeToPrepare || order.preparationTime;
    const prepMins = parsePreparationMinutes(prepStr);
    totalPrepMinutes += prepMins;
    prepCount += 1;

    const products = order.products || [];
    for (const p of products) {
      const productId = (p.id || p['id'] || '').toString().split('~')[0];
      if (!productId) continue;
      const qty = p.quantity ?? 1;
      const qtyNum = typeof qty === 'number' ? qty : parseInt(qty, 10) || 1;
      hourlyBreakdown[hourKey].productSales[productId] =
        (hourlyBreakdown[hourKey].productSales[productId] || 0) + qtyNum;
    }
  }

  const totalDailyOrders = ordersForVendorDate.length;
  const avgOrderValue = totalDailyOrders > 0 ? totalRevenue / totalDailyOrders : 0;
  const avgPrepMinutes = prepCount > 0 ? totalPrepMinutes / prepCount : 0;

  const hourCounts = Object.entries(hourlyBreakdown)
    .map(([h, data]) => ({ hour: parseInt(h, 10), count: data.orderCount }))
    .filter((x) => x.count > 0)
    .sort((a, b) => b.count - a.count);
  const peakHours = hourCounts.slice(0, 3).map((x) => x.hour);

  return {
    vendorId,
    date: dateKey,
    hourlyBreakdown,
    totalDailyOrders,
    totalRevenue,
    avgOrderValue,
    avgPrepMinutes,
    peakHours,
  };
}

/**
 * Daily Cloud Function: Aggregate order data for demand forecasting.
 * Runs at 2 AM Asia/Manila.
 */
exports.aggregateForecastData = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .pubsub.schedule('0 2 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const ninetyDaysAgo = new Date(now);
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

    const startTs = admin.firestore.Timestamp.fromDate(ninetyDaysAgo);
    const endTs = admin.firestore.Timestamp.fromDate(now);

    const vendorDateOrders = {};

    let lastDoc = null;
    let totalFetched = 0;

    while (true) {
      let query = db
        .collection(ORDERS)
        .where('status', 'in', FULFILLED_ORDER_STATUSES)
        .where('createdAt', '>=', startTs)
        .where('createdAt', '<', endTs)
        .orderBy('createdAt', 'asc')
        .limit(BATCH_SIZE);

      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();
      if (snapshot.empty) break;

      for (const doc of snapshot.docs) {
        const data = doc.data();
        const vendorId = (data.vendorID || data.vendor?.id || '').toString();
        if (!vendorId) continue;

        const createdAt = data.createdAt?.toDate?.() || new Date();
        const dateKey = formatDateKey(createdAt);

        const key = `${vendorId}_${dateKey}`;
        if (!vendorDateOrders[key]) {
          vendorDateOrders[key] = { vendorId, dateKey, orders: [] };
        }
        vendorDateOrders[key].orders.push(data);
      }

      totalFetched += snapshot.docs.length;
      lastDoc = snapshot.docs[snapshot.docs.length - 1];

      if (snapshot.docs.length < BATCH_SIZE) break;
    }

    const batch = db.batch();
    let writeCount = 0;

    for (const key of Object.keys(vendorDateOrders)) {
      const { vendorId, dateKey, orders } = vendorDateOrders[key];
      const agg = aggregateVendorDate(vendorId, dateKey, orders);
      const docId = `${vendorId}_${dateKey}`;
      const ref = db.collection(FORECAST_AGGREGATES).doc(docId);
      batch.set(ref, agg);
      writeCount += 1;
    }

    await batch.commit();
    console.log(
      `[aggregateForecastData] Processed ${totalFetched} orders, wrote ${writeCount} aggregates`
    );
    return null;
  });
