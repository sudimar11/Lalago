const functions = require('firebase-functions');
const admin = require('firebase-admin');
const loyaltyHelpers = require('./loyaltyHelpers');

if (!admin.apps.length) {
  admin.initializeApp();
}

function getDb() {
  return admin.firestore();
}

/**
 * Quarterly reset of loyalty cycles.
 * Runs on the first day of each quarter (Jan 1, Apr 1, Jul 1, Oct 1) at midnight Asia/Manila.
 * Archives current cycle data and resets tokens for the new quarter.
 */
exports.resetLoyaltyCycles = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '512MB' })
  .pubsub.schedule('0 0 1 1,4,7,10 *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();

    const configSnap = await db.collection('settings').doc('loyaltyConfig').get();
    if (!configSnap.exists || !configSnap.data()?.enabled) {
      console.log('[resetLoyaltyCycles] Loyalty disabled or not configured, skipping');
      return null;
    }

    const config = configSnap.data();
    const tz = (config.cycles && config.cycles.timezone) || 'Asia/Manila';
    const now = new Date();
    const newCycle = loyaltyHelpers.getCurrentCycle(now, config);
    const { start, end } = loyaltyHelpers.getCycleDateRange(newCycle, tz);

    const BATCH_SIZE = 300;
    let lastDoc = null;
    let processedCount = 0;
    let errorCount = 0;

    console.log(`[resetLoyaltyCycles] Starting reset for cycle ${newCycle}`);

    try {
      while (true) {
        let query = db
          .collection('users')
          .where('role', '==', 'customer')
          .orderBy('__name__')
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();
        if (snapshot.empty) break;

        const batch = db.batch();

        for (const doc of snapshot.docs) {
          const data = doc.data();
          const loyalty = data.loyalty;
          if (!loyalty || typeof loyalty !== 'object') continue;

          const currentCycle = loyalty.currentCycle || '';
          const tokensThisCycle = Number(loyalty.tokensThisCycle || 0);
          const currentTier = loyalty.currentTier || 'bronze';
          const rewardsClaimed = Array.isArray(loyalty.rewardsClaimed)
            ? loyalty.rewardsClaimed
            : [];

          const nowMs = Date.now();
          const filteredRewards = rewardsClaimed.filter((r) => {
            const exp = r.expiresAt;
            if (!exp) return true;
            const expMs = exp._seconds
              ? exp._seconds * 1000
              : (exp.seconds || 0) * 1000;
            return expMs > nowMs;
          });

          const loyaltyUpdate = {
            ...loyalty,
            previousCycle: currentCycle || null,
            previousTier: currentTier,
            previousTokens: tokensThisCycle,
            currentCycle: newCycle,
            cycleStartDate: admin.firestore.Timestamp.fromDate(start),
            cycleEndDate: admin.firestore.Timestamp.fromDate(end),
            tokensThisCycle: 0,
            currentTier: 'bronze',
            lifetimeTokens: Number(loyalty.lifetimeTokens || 0),
            rewardsClaimed: filteredRewards,
          };

          batch.update(doc.ref, { loyalty: loyaltyUpdate });
          processedCount++;
        }

        await batch.commit();
        lastDoc = snapshot.docs[snapshot.docs.length - 1];

        if (processedCount % 500 === 0) {
          console.log(`[resetLoyaltyCycles] Processed ${processedCount} users`);
        }
      }

      console.log(`[resetLoyaltyCycles] Done. Processed ${processedCount} users`);
    } catch (error) {
      console.error('[resetLoyaltyCycles] Error:', error);
      throw error;
    }

    return null;
  });
