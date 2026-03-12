/**
 * A/B test optimizer: evaluates active tests and selects winners.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const ANALYTICS = require('./analyticsConstants');

const DEFAULT_MIN_DAYS = 14;
const DEFAULT_MIN_SAMPLE = 1000;
const IMPROVEMENT_THRESHOLD = 1.1;

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

async function implementWinner(db, testName, winner, config) {
  await db.collection('ab_tests').doc(testName).update({
    status: 'completed',
    implementedVariant: winner,
    implementedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`Implemented winner ${winner} for test ${testName}`);
}

exports.evaluateABTests = functions
  .region('us-central1')
  .pubsub.schedule('0 5 * * 1')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();

    console.log('Evaluating active A/B tests...');

    const testsSnap = await db
      .collection('ab_tests')
      .where('status', '==', 'active')
      .get();

    for (const testDoc of testsSnap.docs) {
      const test = testDoc.data();
      const testName = testDoc.id;

      const startDate = test.startDate?.toDate?.() || test.createdAt?.toDate?.();
      if (!startDate) {
        console.log(`Test ${testName}: no startDate, skipping`);
        continue;
      }

      const minDays = test.minDays ?? DEFAULT_MIN_DAYS;
      const daysRunning = Math.floor(
        (Date.now() - startDate.getTime()) / (24 * 60 * 60 * 1000),
      );
      if (daysRunning < minDays) {
        console.log(
          `Test ${testName}: running ${daysRunning} days, need ${minDays}`,
        );
        continue;
      }

      const minSample = test.minSampleSize ?? DEFAULT_MIN_SAMPLE;
      const startTs = admin.firestore.Timestamp.fromDate(startDate);

      const historySnap = await db
        .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_HISTORY)
        .where('sentAt', '>=', startTs)
        .limit(10000)
        .get();

      const abNotifs = historySnap.docs.filter((doc) => {
        const d = doc.data();
        const abTest = d.data?.abTest || d.abTest;
        return abTest === testName;
      });

      if (abNotifs.length < minSample) {
        console.log(
          `Test ${testName}: ${abNotifs.length} samples, need ${minSample}`,
        );
        continue;
      }

      const variantStats = {};
      abNotifs.forEach((doc) => {
        const d = doc.data();
        const variant = d.data?.abVariant || d.abVariant || 'control';

        if (!variantStats[variant]) {
          variantStats[variant] = { sent: 0, opened: 0, converted: 0 };
        }
        variantStats[variant].sent += 1;
        if (d.openedAt != null) variantStats[variant].opened += 1;
        if (d.converted) variantStats[variant].converted += 1;
      });

      for (const v of Object.keys(variantStats)) {
        const s = variantStats[v];
        s.openRate = s.sent > 0 ? s.opened / s.sent : 0;
        s.conversionRate = s.sent > 0 ? s.converted / s.sent : 0;
      }

      let winner = null;
      let highestRate = 0;
      for (const v of Object.keys(variantStats)) {
        const rate = variantStats[v].conversionRate;
        if (rate > highestRate) {
          highestRate = rate;
          winner = v;
        }
      }

      const control = variantStats.control || { conversionRate: 0 };
      const winnerStats = variantStats[winner];

      if (
        control.conversionRate > 0 &&
        winnerStats.conversionRate >=
          control.conversionRate * IMPROVEMENT_THRESHOLD
      ) {
        const improvement =
          ((winnerStats.conversionRate - control.conversionRate) /
            control.conversionRate) *
          100;

        console.log(
          `Test ${testName} winner: ${winner} with ${(winnerStats.conversionRate * 100).toFixed(2)}% conversion`,
        );

        await db
          .collection(ANALYTICS.COLLECTIONS.AB_TEST_RESULTS)
          .doc(testName)
          .set({
            testName,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
            winner,
            stats: variantStats,
            controlRate: control.conversionRate,
            winnerRate: winnerStats.conversionRate,
            improvement: Number(improvement.toFixed(2)),
          });

        if (test.autoImplement === true) {
          await implementWinner(db, testName, winner, test.config);
        }
      }
    }
    return null;
  });
