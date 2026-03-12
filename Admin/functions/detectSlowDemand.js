/**
 * Demand anomaly detection.
 * detectSlowDemand: Runs every 15 minutes, compares recent orders to baseline.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const ORDERS = 'restaurant_orders';
const FORECAST_AGGREGATES = 'forecast_aggregates';
const DEMAND_ALERTS = 'demand_alerts';
const DEMAND_ACTION_SUGGESTIONS = 'demand_action_suggestions';
const DEMAND_MONITORING_STATE = 'demand_monitoring_state';

const FULFILLED_STATUSES = [
  'Order Completed',
  'order completed',
  'completed',
  'Completed',
  'Order Shipped',
  'Order Delivered',
  'In Transit',
];

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

/**
 * Get expected baseline: same hour(s) + same weekday, last 4 weeks.
 */
async function getExpectedBaseline(db, now, windowHours) {
  const currentHour = now.getHours();
  const currentDow = now.getDay();
  const baselineWeeks = 4;

  const expectedByHour = {};
  for (let h = 0; h < 24; h++) {
    expectedByHour[h] = [];
  }

  for (let w = 1; w <= baselineWeeks; w++) {
    const pastDate = new Date(now);
    pastDate.setDate(pastDate.getDate() - w * 7);
    if (pastDate.getDay() !== currentDow) continue;
    const dateKey = formatDateKey(pastDate);

    const snapshot = await db
      .collection(FORECAST_AGGREGATES)
      .where('date', '==', dateKey)
      .get();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const hb = data.hourlyBreakdown || {};
      for (let h = 0; h < 24; h++) {
        const hKey = String(h);
        const count = (hb[hKey]?.orderCount || 0);
        expectedByHour[h].push(count);
      }
    }
  }

  let expected = 0;
  for (let i = 0; i < windowHours; i++) {
    const h = (currentHour - i + 24) % 24;
    const vals = expectedByHour[h];
    if (vals.length > 0) {
      expected += Math.round(
        vals.reduce((a, b) => a + b, 0) / vals.length
      );
    }
  }
  return expected;
}

/**
 * Count actual orders in last N hours (fulfilled only).
 */
async function getActualOrders(db, hoursBack) {
  const now = new Date();
  const start = new Date(now.getTime() - hoursBack * 60 * 60 * 1000);
  const startTs = admin.firestore.Timestamp.fromDate(start);
  const endTs = admin.firestore.Timestamp.fromDate(now);

  const snapshot = await db
    .collection(ORDERS)
    .where('status', 'in', FULFILLED_STATUSES)
    .where('createdAt', '>=', startTs)
    .where('createdAt', '<', endTs)
    .get();

  return snapshot.docs.length;
}

function getSeverity(actual, expected) {
  if (expected <= 0) return 'info';
  const ratio = actual / expected;
  if (ratio < 0.5) return 'critical';
  if (ratio < 0.7) return 'warning';
  return 'info';
}

/**
 * Cloud Function: Detect slow demand.
 */
exports.detectSlowDemand = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 120, memory: '256MB' })
  .pubsub.schedule('every 15 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();

    const configSnap = await db
      .collection('config')
      .doc('demand_monitoring')
      .get();
    const config = configSnap.exists ? configSnap.data() : {};
    const thresholdPercent = config?.thresholdPercent ?? 0.7;
    const consecutivePeriods = config?.consecutivePeriods ?? 2;
    const windowHours = config?.windowHours ?? 2;
    const enabled = config?.enabled !== false;

    if (!enabled) {
      return null;
    }

    const now = new Date();
    const expected = await getExpectedBaseline(db, now, windowHours);
    const actual = await getActualOrders(db, windowHours);

    const stateRef = db.collection('config').doc(DEMAND_MONITORING_STATE);
    const stateSnap = await stateRef.get();
    const prevState = stateSnap.exists ? stateSnap.data() : {};
    const prevBelowThreshold = prevState.belowThreshold === true;
    const prevConsecutiveCount = prevState.consecutiveCount ?? 0;

    const belowThreshold = expected > 0 && actual < expected * thresholdPercent;
    const newConsecutiveCount = belowThreshold
      ? prevConsecutiveCount + 1
      : 0;

    await stateRef.set({
      belowThreshold,
      consecutiveCount: newConsecutiveCount,
      lastRun: admin.firestore.FieldValue.serverTimestamp(),
      lastActual: actual,
      lastExpected: expected,
    });

    if (
      belowThreshold &&
      newConsecutiveCount >= consecutivePeriods &&
      prevConsecutiveCount < consecutivePeriods
    ) {
      const severity = getSeverity(actual, expected);
      const alertRef = db.collection(DEMAND_ALERTS).doc();
      const suggestionRef = db.collection(DEMAND_ACTION_SUGGESTIONS).doc();
      await suggestionRef.set({
        alertId: alertRef.id,
        actionType: 'send_lapsed_user_promo',
        target: { segment: 'lapsed_7_days' },
        expectedImpact: Math.round((expected - actual) * 0.3),
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await alertRef.set({
        type: 'overall_drop',
        severity,
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        resolvedAt: null,
        metric: 'orders',
        expected,
        actual,
        suggestedActions: [suggestionRef.id],
        windowHours,
      });

      await db.collection('notifications').add({
        title: `Demand Alert: ${severity}`,
        message: `Order volume below expected. Actual: ${actual}, Expected: ${expected}`,
        type: 'demand_alert',
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { alertId: alertRef.id, severity, type: 'overall_drop' },
      });

      console.log(
        `[detectSlowDemand] Alert created: ${severity} drop, actual=${actual} expected=${expected}`
      );
    }

    return null;
  });
