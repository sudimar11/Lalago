const moment = require('moment-timezone');

async function calculateOptimalSendTime(userId, userTimezone, db) {
  const tz = userTimezone || 'Asia/Manila';
  const historySnapshot = await db
    .collection('ash_notification_history')
    .where('userId', '==', userId)
    .orderBy('sentAt', 'desc')
    .limit(50)
    .get();

  const opened = [];
  historySnapshot.docs.forEach((doc) => {
    const data = doc.data();
    const openedAt = data.openedAt;
    if (openedAt) {
      const sentAt = data.sentAt?.toDate?.();
      if (sentAt) {
        opened.push({ sentAt, openedAt: openedAt.toDate?.() || openedAt });
      }
    }
  });

  if (opened.length < 3) {
    return { bestHour: null, bestRate: 0, hourCounts: {}, hourOpens: {}, hasEnoughData: false };
  }

  const hourCounts = {};
  const hourOpens = {};

  historySnapshot.docs.forEach((doc) => {
    const data = doc.data();
    const sentAt = data.sentAt?.toDate?.();
    const openedAt = data.openedAt?.toDate?.();
    if (!sentAt) return;

    const sentHour = moment(sentAt).tz(tz).hour();
    hourCounts[sentHour] = (hourCounts[sentHour] || 0) + 1;
    if (openedAt) {
      const openHour = moment(openedAt).tz(tz).hour();
      hourOpens[openHour] = (hourOpens[openHour] || 0) + 1;
    }
  });

  const openRates = {};
  for (let hour = 0; hour < 24; hour++) {
    if ((hourCounts[hour] || 0) > 0) {
      const count = hourCounts[hour];
      const opens = hourOpens[hour] || 0;
      openRates[hour] = opens / count;
    }
  }

  let bestHour = null;
  let bestRate = 0;
  for (let hour = 0; hour < 24; hour++) {
    const count = hourCounts[hour] || 0;
    const rate = openRates[hour] || 0;
    if (count >= 3 && rate > bestRate) {
      bestRate = rate;
      bestHour = hour;
    }
  }

  return {
    bestHour,
    bestRate,
    hourCounts,
    hourOpens,
    hasEnoughData: bestHour !== null,
  };
}

async function updateUserOptimalTime(userId, db) {
  const userDoc = await db.collection('users').doc(userId).get();
  if (!userDoc.exists) return;

  const userData = userDoc.data();
  const userTimezone = userData.timezone || 'Asia/Manila';

  const optimal = await calculateOptimalSendTime(userId, userTimezone, db);

  if (optimal.hasEnoughData) {
    const admin = require('firebase-admin');
    await db.collection('users').doc(userId).update({
      'notificationPreferences.optimalSendHour': optimal.bestHour,
      'notificationPreferences.optimalSendRate': optimal.bestRate,
      'notificationPreferences.optimalSendUpdated': admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

async function batchUpdateOptimalTimes(db) {
  const usersSnapshot = await db
    .collection('users')
    .where('settings.ashRecommendations', '==', true)
    .limit(500)
    .get();

  let updatedCount = 0;
  for (const userDoc of usersSnapshot.docs) {
    await updateUserOptimalTime(userDoc.id, db);
    updatedCount++;
  }

  return updatedCount;
}

module.exports = {
  calculateOptimalSendTime,
  updateUserOptimalTime,
  batchUpdateOptimalTimes,
};
