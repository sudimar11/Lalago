async function getNotificationEngagement(userId, db) {
  const historySnapshot = await db
    .collection('ash_notification_history')
    .where('userId', '==', userId)
    .orderBy('sentAt', 'desc')
    .limit(20)
    .get();

  if (historySnapshot.empty) return 0;

  const notifications = historySnapshot.docs.map((d) => d.data());
  const sent = notifications.length;
  const opened = notifications.filter((n) => n.openedAt).length;

  return sent > 0 ? opened / sent : 0;
}

async function getUserSegment(userId, userData, db) {
  const pref = userData.preferenceProfile || {};
  const totalOrders = pref.totalCompletedOrders || 0;
  const engagement = await getNotificationEngagement(userId, db);

  if (totalOrders >= 20 && engagement > 0.3) return 'power_user';
  if (totalOrders >= 10) return 'regular';
  if (totalOrders >= 3) return 'active';
  if (totalOrders > 0) return 'new';
  return 'inactive';
}

function getStrategyForSegment(segment) {
  const strategies = {
    power_user: {
      frequency: 'moderate',
      bestTimes: ['lunch', 'dinner'],
      personalization: 'high',
      channel: 'all',
    },
    regular: {
      frequency: 'moderate',
      bestTimes: ['dinner'],
      personalization: 'medium',
      channel: 'push',
    },
    active: {
      frequency: 'low',
      bestTimes: ['weekend'],
      personalization: 'medium',
      channel: 'push',
    },
    new: {
      frequency: 'high',
      bestTimes: ['lunch'],
      personalization: 'low',
      channel: 'push',
    },
    inactive: {
      frequency: 'very_low',
      bestTimes: ['weekend'],
      personalization: 'low',
      channel: 'push',
    },
  };
  return strategies[segment] || strategies.active;
}

module.exports = {
  getNotificationEngagement,
  getUserSegment,
  getStrategyForSegment,
};
