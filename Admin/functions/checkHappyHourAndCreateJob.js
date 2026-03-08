/**
 * Scheduled function: Check if Happy Hour should start and create a notification job.
 * Does NOT send notifications - processNotificationJob handles that on job creation.
 * Runs every 10 minutes in Asia/Manila timezone.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const moment = require('moment-timezone');

const TZ = 'Asia/Manila';
const SETTINGS_COLLECTION = 'settings';
const SETTINGS_DOC = 'happyHourSettings';
const JOBS_COLLECTION = 'notification_jobs';

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function parseTimeToMinutes(timeStr) {
  if (!timeStr || typeof timeStr !== 'string') return 0;
  const parts = timeStr.trim().split(':');
  if (parts.length < 2) return 0;
  const h = parseInt(parts[0], 10) || 0;
  const m = parseInt(parts[1], 10) || 0;
  return h * 60 + m;
}

exports.checkHappyHourAndCreateJob = functions
  .region('us-central1')
  .pubsub.schedule('*/10 * * * *')
  .timeZone(TZ)
  .onRun(async () => {
    const db = getDb();

    const settingsSnap = await db
      .collection(SETTINGS_COLLECTION)
      .doc(SETTINGS_DOC)
      .get();

    if (!settingsSnap.exists) {
      return null;
    }

    const settings = settingsSnap.data() || {};

    if (!settings.enabled || !settings.autoCreateNotification) {
      return null;
    }

    const template = settings.notificationTemplate || {};
    const title = String(template.title || '').trim();
    const body = String(template.body || '').trim();

    if (!title || !body) {
      return null;
    }

    const configs = settings.configs;
    if (!Array.isArray(configs) || configs.length === 0) {
      return null;
    }

    const nowManila = moment().tz(TZ);
    const currentDay = nowManila.day();
    const currentMinutes = nowManila.hour() * 60 + nowManila.minute();
    const startOfToday = nowManila.clone().startOf('day').toDate();
    const startOfTodayTs = admin.firestore.Timestamp.fromDate(startOfToday);

    for (let i = 0; i < configs.length; i++) {
      const config = configs[i];
      const configId =
        config.id || config.name || `config_${i}`;
      const activeDays = config.activeDays || [];
      const startTime = config.startTime || '00:00';
      const endTime = config.endTime || '23:59';

      if (!Array.isArray(activeDays) || !activeDays.includes(currentDay)) {
        continue;
      }

      const startMinutes = parseTimeToMinutes(startTime);
      const endMinutes = parseTimeToMinutes(endTime);

      if (currentMinutes < startMinutes || currentMinutes >= endMinutes) {
        continue;
      }

      const existingJobsSnap = await db
        .collection(JOBS_COLLECTION)
        .where('kind', '==', 'happy_hour')
        .where('payload.configId', '==', configId)
        .where('createdAt', '>=', startOfTodayTs)
        .limit(1)
        .get();

      if (!existingJobsSnap.empty) {
        continue;
      }

      const campaignId = `happy_hour_${configId}_${Date.now()}`;

      const payload = {
        title,
        body,
        type: 'happy_hour',
        configId,
        configName: config.name || 'Happy Hour',
        promoType: config.promoType || 'fixed_amount',
        promoValue: Number(config.promoValue) || 0,
        campaignId,
      };

      if (template.imageUrl && String(template.imageUrl).trim()) {
        payload.imageUrl = String(template.imageUrl).trim();
      }
      if (template.deepLink && String(template.deepLink).trim()) {
        payload.deepLink = String(template.deepLink).trim();
      }

      const jobDoc = {
        kind: 'happy_hour',
        status: 'queued',
        payload,
        triggeredBy: 'auto_schedule',
        triggeredAt: admin.firestore.FieldValue.serverTimestamp(),
        configSnapshot: { ...config },
        stats: {
          totalRecipients: 0,
          processedCount: 0,
          successfulDeliveries: 0,
          failedDeliveries: 0,
          percentComplete: 0,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db.collection(JOBS_COLLECTION).add(jobDoc);

      await db
        .collection(SETTINGS_COLLECTION)
        .doc(SETTINGS_DOC)
        .set(
          {
            lastTriggeredAt: admin.firestore.FieldValue.serverTimestamp(),
            lastTriggeredConfigId: configId,
          },
          { merge: true },
        );

      console.log(
        `[checkHappyHourAndCreateJob] Created job for config ${configId}`,
      );
    }

    return null;
  });
