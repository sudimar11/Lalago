/**
 * Driver performance analytics.
 * processDriverMetrics: Hourly job to compute per-driver metrics.
 * calculateDriverIncentives: Weekly job to evaluate incentive rules.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const ORDERS = 'restaurant_orders';
const ASSIGNMENTS_LOG = 'assignments_log';
const DRIVER_PERFORMANCE = 'driver_performance_history';
const FOODS_REVIEW = 'foods_review';
const INCENTIVE_RULES = 'incentive_rules';
const DRIVER_INCENTIVES = 'driver_incentives';

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function toMs(ts) {
  if (!ts) return null;
  if (ts._seconds != null) return ts._seconds * 1000;
  if (ts.seconds != null) return ts.seconds * 1000;
  if (ts.toMillis) return ts.toMillis();
  return null;
}

function formatDateKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * processDriverMetrics: Pub/Sub hourly.
 * For each driver with completed orders in last 24h, compute metrics and store.
 */
exports.processDriverMetrics = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('every 1 hours')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const todayKey = formatDateKey(now);

    const completedOrdersSnap = await db
      .collection(ORDERS)
      .where('status', 'in', ['Order Completed', 'order completed', 'completed', 'Completed'])
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(oneDayAgo))
      .get();

    const driverVendorMap = {};
    for (const doc of completedOrdersSnap.docs) {
      const order = doc.data();
      const driverId = String(order.driverID || order.driverId || '').trim();
      const vendorId = String(order.vendorID || order.vendorId || '').trim();
      if (!driverId) continue;

      const key = vendorId ? `${driverId}|${vendorId}` : driverId;
      if (!driverVendorMap[key]) {
        driverVendorMap[key] = { driverId, vendorId: vendorId || null, orders: [] };
      }
      driverVendorMap[key].orders.push({
        id: doc.id,
        ...order,
      });
    }

    const batch = db.batch();

    for (const { driverId, vendorId, orders } of Object.values(driverVendorMap)) {
      const deliveryTimes = [];
      const BUFFER_MINUTES = 5;
      const DEFAULT_DELIVERY_MIN = 20;

      for (const order of orders) {
        const readyAt = order.readyAt;
        const shippedAt = order.shippedAt;
        const completedAt = order.completedAt;

        let completedMs = toMs(completedAt);
        if (!completedMs && shippedAt) {
          completedMs = toMs(shippedAt) + DEFAULT_DELIVERY_MIN * 60 * 1000;
        }
        const readyMs = toMs(readyAt) || toMs(shippedAt);
        if (readyMs && completedMs) {
          const minutes = (completedMs - readyMs) / 60000;
          if (minutes > 0 && minutes < 120) deliveryTimes.push(minutes);
        }
      }

      const averageDeliveryTime =
        deliveryTimes.length > 0
          ? deliveryTimes.reduce((a, b) => a + b, 0) / deliveryTimes.length
          : null;

      const assignmentsSnap = await db
        .collection(ASSIGNMENTS_LOG)
        .where('driverId', '==', driverId)
        .limit(100)
        .get();

      let accepted = 0;
      let rejected = 0;
      let timeout = 0;
      let totalWithOutcome = 0;

      for (const d of assignmentsSnap.docs) {
        const status = (d.data().status || '').toLowerCase();
        if (['accepted', 'completed'].includes(status)) {
          accepted++;
          totalWithOutcome++;
        } else if (status === 'rejected') {
          rejected++;
          totalWithOutcome++;
        } else if (status === 'timeout') {
          timeout++;
          totalWithOutcome++;
        }
      }

      const acceptanceRate =
        totalWithOutcome > 0 ? (accepted / totalWithOutcome) * 100 : 100;

      const onTimeCount = deliveryTimes.filter(
        (m) => m <= (averageDeliveryTime || DEFAULT_DELIVERY_MIN) + BUFFER_MINUTES
      ).length;
      const onTimePercentage =
        deliveryTimes.length > 0 ? (onTimeCount / deliveryTimes.length) * 100 : 100;

      const reviewSnap = await db
        .collection(FOODS_REVIEW)
        .where('driverId', '==', driverId)
        .limit(50)
        .get();

      let ratingSum = 0;
      let ratingCount = 0;
      for (const r of reviewSnap.docs) {
        const rating = r.data().rating ?? r.data().Rating;
        if (typeof rating === 'number' && rating >= 0) {
          ratingSum += rating;
          ratingCount++;
        }
      }
      const customerRating = ratingCount > 0 ? ratingSum / ratingCount : null;

      const wAccept = 0.25;
      const wOnTime = 0.3;
      const wDelivery = 0.25;
      const wRating = 0.2;

      let efficiencyScore = 50;
      efficiencyScore += (acceptanceRate / 100) * 25 * wAccept;
      efficiencyScore += (onTimePercentage / 100) * 25 * wOnTime;
      if (averageDeliveryTime != null) {
        const deliveryScore = Math.max(0, 100 - averageDeliveryTime * 2);
        efficiencyScore += (deliveryScore / 100) * 25 * wDelivery;
      }
      if (customerRating != null) {
        efficiencyScore += (customerRating / 5) * 25 * wRating;
      }
      efficiencyScore = Math.round(Math.min(100, Math.max(0, efficiencyScore)));

      const docId = vendorId
        ? `${driverId}_${vendorId}_${todayKey}`.replace(/\//g, '_')
        : `${driverId}_${todayKey}`;
      const ref = db.collection(DRIVER_PERFORMANCE).doc(docId);
      batch.set(ref, {
        driverId,
        date: todayKey,
        vendorId: vendorId || null,
        averageDeliveryTime: averageDeliveryTime != null
          ? Math.round(averageDeliveryTime * 10) / 10
          : null,
        acceptanceRate: Math.round(acceptanceRate * 10) / 10,
        onTimePercentage: Math.round(onTimePercentage * 10) / 10,
        customerRating: customerRating != null
          ? Math.round(customerRating * 10) / 10
          : null,
        efficiencyScore,
        assignmentsCount: orders.length,
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    console.log(
      `[processDriverMetrics] Wrote ${Object.keys(driverOrderMap).length} driver records for ${todayKey}`
    );
  });

/**
 * calculateDriverIncentives: Pub/Sub weekly (Sunday 4 AM Asia/Manila).
 * Evaluate incentive_rules against driver_performance_history and create driver_incentives.
 */
exports.calculateDriverIncentives = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('0 4 * * 0')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);

    const rulesSnap = await db
      .collection(INCENTIVE_RULES)
      .where('active', '==', true)
      .get();

    if (rulesSnap.empty) {
      console.log('[calculateDriverIncentives] No active incentive rules');
      return null;
    }

    const sevenDaysAgoKey = formatDateKey(sevenDaysAgo);
    const perfSnap = await db
      .collection(DRIVER_PERFORMANCE)
      .where('date', '>=', sevenDaysAgoKey)
      .get();

    const driverPerfByDriver = {};
    for (const d of perfSnap.docs) {
      const data = d.data();
      const driverId = data.driverId;
      if (!driverId) continue;
      if (!driverPerfByDriver[driverId]) {
        driverPerfByDriver[driverId] = [];
      }
      driverPerfByDriver[driverId].push(data);
    }

    const batch = db.batch();
    const periodKey = `${now.getFullYear()}-W${Math.ceil(now.getDate() / 7)}`;

    for (const ruleDoc of rulesSnap.docs) {
      const rule = ruleDoc.data();
      const vendorId = rule.vendorId || null;
      const condition = rule.condition || {};
      const metric = condition.metric || '';
      const operator = condition.operator || '>=';
      const value = parseFloat(condition.value) || 0;
      const bonusAmount = parseFloat(rule.bonusAmount) || 0;
      if (bonusAmount <= 0) continue;

      for (const [driverId, perfs] of Object.entries(driverPerfByDriver)) {
        const filtered = vendorId
          ? perfs.filter((p) => p.vendorId === vendorId)
          : perfs;
        if (filtered.length === 0) continue;

        const latest = filtered[0];
        const val = parseFloat(
          latest[metric] ?? latest[metric.replace(/([A-Z])/g, '_$1').toLowerCase()]
        );
        if (Number.isNaN(val)) continue;

        let passes = false;
        if (operator === '>=') passes = val >= value;
        else if (operator === '>') passes = val > value;
        else if (operator === '<=') passes = val <= value;
        else if (operator === '<') passes = val < value;
        else if (operator === '==') passes = Math.abs(val - value) < 0.01;

        if (!passes) continue;

        const incentiveId = `${driverId}_${ruleDoc.id}_${periodKey}`;
        const ref = db.collection(DRIVER_INCENTIVES).doc(incentiveId);
        batch.set(ref, {
          driverId,
          vendorId: vendorId || latest.vendorId,
          ruleId: ruleDoc.id,
          amount: bonusAmount,
          period: periodKey,
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }

    await batch.commit();
    console.log(
      `[calculateDriverIncentives] Processed ${rulesSnap.size} rules`
    );
  });
