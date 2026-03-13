const functions = require('firebase-functions');
const admin = require('firebase-admin');

module.exports = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    try {
      const db = admin.firestore();
      const dryRun = String(req.query.dryRun || 'false') === 'true';
      const limit = Math.min(
        Math.max(parseInt(String(req.query.limit || '2000'), 10) || 2000, 1),
        10000,
      );
      const batchSize = Math.min(
        Math.max(parseInt(String(req.query.batchSize || '300'), 10) || 300, 1),
        450,
      );

      const driversSnap = await db
        .collection('users')
        .where('role', '==', 'driver')
        .limit(limit)
        .get();

      let processed = 0;
      let updated = 0;
      let writeBatch = db.batch();
      let inBatch = 0;

      for (const doc of driversSnap.docs) {
        processed++;
        const data = doc.data() || {};

        const checkedOut =
          data.checkedOutToday === true ||
          (data.todayCheckOutTime != null &&
            String(data.todayCheckOutTime || '').trim() !== '');
        const hasOrders = Array.isArray(data.inProgressOrderID) &&
          data.inProgressOrderID.length > 0;
        const legacyOnline = data.isOnline === true ||
          data.checkedInToday === true ||
          data.isActive === true ||
          data.active === true;

        let isOnline = false;
        let riderAvailability = 'offline';
        if (checkedOut) {
          isOnline = false;
          riderAvailability = 'offline';
        } else if (hasOrders) {
          isOnline = true;
          const maxOrders = Math.max(1, Math.floor(
            Number(data.maxOrders || 0) || (data.multipleOrders ? 2 : 1)
          ));
          const activeCount = (data.inProgressOrderID || []).length;
          riderAvailability = (activeCount < maxOrders) ? 'available' : 'on_delivery';
        } else if (legacyOnline) {
          isOnline = true;
          riderAvailability = data.riderAvailability === 'on_break'
            ? 'on_break'
            : 'available';
        }

        const nextMaxOrders = Number(data.maxOrders || 0) > 0
          ? Number(data.maxOrders)
          : (Number(data.multipleOrders ? 2 : 1));

        const updates = {
          statusSchemaVersion: 2,
          isOnline,
          riderAvailability,
          maxOrders: Math.max(1, Math.floor(nextMaxOrders)),
        };
        if (!data.lastActivityTimestamp) {
          if (data.locationUpdatedAt) {
            updates.lastActivityTimestamp = data.locationUpdatedAt;
          } else {
            updates.lastActivityTimestamp =
              admin.firestore.FieldValue.serverTimestamp();
          }
        }

        if (!dryRun) {
          writeBatch.update(doc.ref, updates);
          inBatch++;
          updated++;
          if (inBatch >= batchSize) {
            await writeBatch.commit();
            writeBatch = db.batch();
            inBatch = 0;
          }
        } else {
          updated++;
        }
      }

      if (!dryRun && inBatch > 0) {
        await writeBatch.commit();
      }

      return res.json({
        success: true,
        dryRun,
        processed,
        updated,
        limit,
      });
    } catch (error) {
      console.error('[migrateRiderStatusSchemaV2] error:', error);
      return res.status(500).json({
        success: false,
        error: error.message || String(error),
      });
    }
  });
