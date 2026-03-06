const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { updateUserSegment } = require('./userSegmentation');

if (!admin.apps.length) {
  admin.initializeApp();
}

function getDb() {
  return admin.firestore();
}

/**
 * Scheduled function to update all active customer segments.
 * Runs daily at 2 AM - PROCESSES IN BATCHES TO AVOID TIMEOUT
 */
exports.updateUserSegments = functions
  .region('us-central1')
  .pubsub.schedule('0 2 * * *')
  .timeZone('America/New_York')
  .onRun(async () => {
    const db = getDb();
    const BATCH_SIZE = 300;
    let processedCount = 0;
    let errorCount = 0;
    let lastDoc = null;
    let hasMore = true;
    let batchNumber = 1;

    const startTime = Date.now();
    console.log(
      'Starting batched segment update for all active customers...',
    );

    try {
      while (hasMore) {
        let query = db
          .collection('users')
          .where('role', '==', 'customer')
          .where('active', '==', true)
          .orderBy('__name__')
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();

        if (snapshot.empty) {
          hasMore = false;
          break;
        }

        console.log(
          `Batch ${batchNumber}: Processing ${snapshot.size} users...`,
        );

        for (const doc of snapshot.docs) {
          try {
            const userData = doc.data();
            await updateUserSegment(doc.id, userData, db);
            processedCount++;

            if (processedCount % 100 === 0) {
              const elapsedMinutes = (
                (Date.now() - startTime) /
                60000
              ).toFixed(2);
              console.log(
                `Progress: ${processedCount} users processed in ${elapsedMinutes} minutes`,
              );
            }
          } catch (error) {
            console.error(
              `Failed to update user ${doc.id}:`,
              error.message,
            );
            errorCount++;
          }
        }

        console.log(
          `Batch ${batchNumber} complete. Total so far: ${processedCount}`,
        );

        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        await new Promise((resolve) => setTimeout(resolve, 1000));
        batchNumber++;

        if (processedCount >= 7000) {
          console.log(
            'Processed over 7000 users, stopping as safety measure',
          );
          hasMore = false;
        } else {
          hasMore = snapshot.size === BATCH_SIZE;
        }
      }

      const totalTime = ((Date.now() - startTime) / 60000).toFixed(2);
      console.log('SEGMENT UPDATE COMPLETE');
      console.log(`Processed: ${processedCount} users`);
      console.log(`Errors: ${errorCount}`);
      console.log(`Total time: ${totalTime} minutes`);
    } catch (error) {
      console.error('Fatal error in updateUserSegments:', error);
    }

    return null;
  });

/**
 * Manual trigger for testing - processes in smaller batches
 * Call with ?limit=50 to test
 */
exports.manualUpdateUserSegments = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const authHeader = req.headers.authorization;
    if (
      authHeader &&
      authHeader !== 'Bearer your-secret-token'
    ) {
      return res.status(403).json({ error: 'Unauthorized' });
    }

    const db = getDb();
    const limit = req.query.limit ? parseInt(req.query.limit, 10) : 50;
    const effectiveLimit = Math.min(limit, 50);

    const startTime = Date.now();
    console.log(
      `Manual segment update triggered for ${effectiveLimit} users...`,
    );

    try {
      const snapshot = await db
        .collection('users')
        .where('role', '==', 'customer')
        .where('active', '==', true)
        .limit(effectiveLimit)
        .get();

      if (snapshot.empty) {
        return res.json({
          success: false,
          error: 'No active customers found',
        });
      }

      const results = [];
      let successCount = 0;
      let errorCount = 0;
      let usersWithOrders = 0;

      for (const doc of snapshot.docs) {
        try {
          const userData = doc.data();
          const pref = userData.preferenceProfile || {};
          const totalOrders = pref.totalCompletedOrders ?? 0;
          if (totalOrders > 0) usersWithOrders++;

          const segment = await updateUserSegment(
            doc.id,
            userData,
            db,
          );

          results.push({
            id: doc.id,
            email: userData.email || 'no email',
            phone: userData.phoneNumber || 'no phone',
            segment,
            hasPreferenceProfile: !!userData.preferenceProfile,
            totalOrders,
            lastOrder: pref.lastOrderedAt ?? null,
          });
          successCount++;
        } catch (error) {
          console.error(
            `Error processing user ${doc.id}:`,
            error.message,
          );
          errorCount++;
          results.push({
            id: doc.id,
            error: error.message,
          });
        }
      }

      const timeSeconds = (
        (Date.now() - startTime) /
        1000
      ).toFixed(2);

      res.json({
        success: true,
        summary: {
          requested: limit,
          processed: snapshot.size,
          successful: successCount,
          errors: errorCount,
          usersWithOrders,
          timeSeconds,
        },
        results,
      });
    } catch (error) {
      console.error('Fatal error in manual update:', error);
      res.status(500).json({
        success: false,
        error: error.message,
      });
    }
  });

/**
 * One-time migration function to process ALL users in batches.
 * Call this to fix all existing users.
 * Protected by secret key for security.
 */
exports.migrateAllUserSegments = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const secret = req.query.secret;
    if (secret !== 'lalago-migration-2026') {
      return res.status(403).json({ error: 'Invalid secret' });
    }

    const db = getDb();
    const BATCH_SIZE = 300;
    let processedCount = 0;
    let errorCount = 0;
    let lastDoc = null;
    let hasMore = true;
    let batchNumber = 1;

    const startTime = Date.now();

    res.json({
      success: true,
      message: 'Migration started in background',
      total_users_estimate: 6923,
    });

    console.log('MIGRATION: Starting full user segment migration...');

    try {
      while (hasMore) {
        let query = db
          .collection('users')
          .where('role', '==', 'customer')
          .where('active', '==', true)
          .orderBy('__name__')
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const snapshot = await query.get();

        if (snapshot.empty) {
          hasMore = false;
          break;
        }

        console.log(
          `Migration Batch ${batchNumber}: Processing ${snapshot.size} users...`,
        );

        for (const doc of snapshot.docs) {
          try {
            const userData = doc.data();
            await updateUserSegment(doc.id, userData, db);
            processedCount++;

            if (processedCount % 500 === 0) {
              console.log(
                `Migration progress: ${processedCount} users processed`,
              );
            }
          } catch (error) {
            console.error(
              `Migration failed for user ${doc.id}:`,
              error.message,
            );
            errorCount++;
          }
        }

        lastDoc = snapshot.docs[snapshot.docs.length - 1];
        await new Promise((resolve) => setTimeout(resolve, 1000));
        batchNumber++;
        hasMore = snapshot.size === BATCH_SIZE;
      }

      const totalTime = (
        (Date.now() - startTime) /
        60000
      ).toFixed(2);
      console.log('MIGRATION COMPLETE');
      console.log(`Processed: ${processedCount} users`);
      console.log(`Errors: ${errorCount}`);
      console.log(`Total time: ${totalTime} minutes`);
    } catch (error) {
      console.error('Fatal migration error:', error);
    }
  });

/**
 * Debug function to check if users have segment fields.
 */
exports.checkSegmentFields = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const db = getDb();

    try {
      const snapshot = await db
        .collection('users')
        .where('role', '==', 'customer')
        .where('active', '==', true)
        .limit(10)
        .get();

      const results = [];
      snapshot.forEach((doc) => {
        const data = doc.data();
        const pref = data.preferenceProfile || {};
        results.push({
          id: doc.id,
          hasSegment: Object.prototype.hasOwnProperty.call(
            data,
            'segment',
          ),
          segment: data.segment ?? 'not set',
          hasEngagementScore: Object.prototype.hasOwnProperty.call(
            data,
            'engagementScore',
          ),
          engagementScore: data.engagementScore ?? 'not set',
          hasPreferenceProfile: Object.prototype.hasOwnProperty.call(
            data,
            'preferenceProfile',
          ),
          totalCompletedOrdersPref:
            pref.totalCompletedOrders ?? 'not set',
          totalCompletedOrdersTop:
            data.totalCompletedOrders ?? 'not set',
        });
      });

      res.json({ total: snapshot.size, results });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

/**
 * Simple test - verify functions run.
 */
exports.testFunctionWorks = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    console.log(
      'TEST FUNCTION RAN SUCCESSFULLY at',
      new Date().toISOString(),
    );
    res.json({
      success: true,
      message: 'Function is working',
      timestamp: new Date().toISOString(),
    });
  });

/**
 * Debug single user - run segmentation and show before/after.
 */
exports.debugSingleUser = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const db = getDb();
    let userId = req.query.userId;

    try {
      let userDoc;

      if (userId) {
        userDoc = await db.collection('users').doc(userId).get();
        userId = userDoc.id;
      } else {
        const snapshot = await db
          .collection('users')
          .where('role', '==', 'customer')
          .where('active', '==', true)
          .limit(1)
          .get();

        if (snapshot.empty) {
          return res.json({ error: 'No active customers found' });
        }
        userDoc = snapshot.docs[0];
        userId = userDoc.id;
      }

      if (!userDoc.exists) {
        return res.json({ error: 'User not found' });
      }

      const userData = userDoc.data();
      const pref = userData.preferenceProfile || {};

      console.log('DEBUGGING USER:', userId);
      console.log('Email:', userData.email);
      console.log('Has preferenceProfile:', !!userData.preferenceProfile);
      console.log('preferenceProfile keys:', Object.keys(pref));
      console.log(
        'totalCompletedOrders in pref:',
        pref.totalCompletedOrders,
      );
      console.log('lastOrderedAt in pref:', pref.lastOrderedAt);
      console.log(
        'top level lastOrderCompletedAt:',
        userData.lastOrderCompletedAt,
      );

      console.log('Running updateUserSegment...');
      const segment = await updateUserSegment(userId, userData, db);
      console.log('Segment returned:', segment);

      const updatedDoc = await db.collection('users').doc(userId).get();
      const updatedData = updatedDoc.data();

      res.json({
        success: true,
        userId,
        before: {
          hasSegment: Object.prototype.hasOwnProperty.call(
            userData,
            'segment',
          ),
          segment: userData.segment || 'none',
          hasPrefProfile: !!userData.preferenceProfile,
          totalOrdersInPref: pref.totalCompletedOrders || 0,
        },
        after: {
          hasSegment: Object.prototype.hasOwnProperty.call(
            updatedData || {},
            'segment',
          ),
          segment: (updatedData || {}).segment || 'none',
          segmentUpdatedAt:
            (updatedData || {}).segmentUpdatedAt || null,
        },
        calculatedSegment: segment,
        logs: 'Check Firebase logs for detailed output',
      });
    } catch (error) {
      console.error('Error in debugSingleUser:', error);
      res.status(500).json({
        error: error.message,
        stack: error.stack,
      });
    }
  });

/**
 * Check notification history access for a user.
 */
exports.checkNotificationAccess = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const db = getDb();
    const userId = req.query.userId;

    if (!userId) {
      return res.json({ error: 'Need userId parameter' });
    }

    try {
      const notificationsSnapshot = await db
        .collection('ash_notification_history')
        .where('userId', '==', userId)
        .orderBy('sentAt', 'desc')
        .limit(20)
        .get();

      const notifications = [];
      notificationsSnapshot.forEach((doc) => {
        const d = doc.data();
        notifications.push({
          id: doc.id,
          hasOpenedAt: !!d.openedAt,
          sentAt: d.sentAt,
        });
      });

      const userDoc = await db.collection('users').doc(userId).get();
      const userData = userDoc.exists ? userDoc.data() : null;

      res.json({
        success: true,
        userId,
        notificationCount: notifications.length,
        openedCount: notifications.filter((n) => n.hasOpenedAt)
          .length,
        notifications,
        userHasPrefProfile: !!userData?.preferenceProfile,
      });
    } catch (error) {
      res.status(500).json({
        error: error.message,
        code: error.code,
      });
    }
  });

/**
 * Test segmentation without notifications (isolate notification issue).
 */
exports.testSegmentationNoNotifications = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const db = getDb();
    const limit = req.query.limit ? parseInt(req.query.limit, 10) : 5;

    try {
      const snapshot = await db
        .collection('users')
        .where('role', '==', 'customer')
        .where('active', '==', true)
        .limit(limit)
        .get();

      const results = [];

      for (const doc of snapshot.docs) {
        const userData = doc.data();
        const pref = userData.preferenceProfile || {};
        const totalOrders = pref.totalCompletedOrders || 0;

        let segment = 'new';
        if (totalOrders > 0) {
          if (totalOrders >= 10) segment = 'power_user';
          else if (totalOrders >= 5) segment = 'regular';
          else segment = 'active';
        }

        await db
          .collection('users')
          .doc(doc.id)
          .update({
            segment,
            segmentUpdatedAt:
              admin.firestore.FieldValue.serverTimestamp(),
            debug_run_at: new Date().toISOString(),
          });

        results.push({
          id: doc.id,
          email: userData.email,
          orders: totalOrders,
          assignedSegment: segment,
        });
      }

      res.json({
        success: true,
        processed: results.length,
        results,
      });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

/**
 * Check Firestore write permissions.
 */
exports.checkFirestorePermissions = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    const db = getDb();

    try {
      const testDoc = db.collection('_test_').doc('permission-test');
      await testDoc.set({
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        message: 'Testing write permissions',
      });

      const readBack = await testDoc.get();
      await testDoc.delete();

      res.json({
        success: true,
        message: 'Firestore read/write working',
        readData: readBack.exists ? readBack.data() : null,
      });
    } catch (error) {
      res.status(500).json({
        success: false,
        error: error.message,
        code: error.code,
      });
    }
  });
