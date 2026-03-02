const DEFAULTS = {
  MAX_PER_DAY: 3,
  MIN_HOURS_BETWEEN: 2,
  PER_TYPE_LIMITS: {
    ash_reorder: { days: 1, max: 1 },
    ash_recommendation: { days: 3, max: 1 },
    ash_cart: { days: 1, max: 1 },
    ash_hunger: { days: 1, max: 2 },
  },
};

/**
 * Check if user has exceeded frequency limits
 */
async function canSendNotification(userId, type, db) {
  const now = new Date();
  const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);

  const recentSnapshot = await db
    .collection('ash_notification_history')
    .where('userId', '==', userId)
    .where('sentAt', '>=', oneDayAgo)
    .orderBy('sentAt', 'desc')
    .get();

  if (recentSnapshot.empty) return true;

  const notifications = recentSnapshot.docs.map((d) => d.data());

  const typeLimit = DEFAULTS.PER_TYPE_LIMITS[type];
  if (typeLimit) {
    const typeCount = notifications.filter((n) => n.type === type).length;
    if (typeCount >= typeLimit.max) {
      return false;
    }
  }

  if (notifications.length >= DEFAULTS.MAX_PER_DAY) {
    return false;
  }

  if (notifications.length > 0) {
    const lastSent = notifications[0].sentAt?.toDate?.() || new Date(0);
    const hoursSinceLast = (now - lastSent) / (1000 * 60 * 60);
    if (hoursSinceLast < DEFAULTS.MIN_HOURS_BETWEEN) {
      return false;
    }
  }

  return true;
}

/**
 * Get next available send time respecting frequency limits
 */
async function getNextAvailableTime(userId, preferredTime, db) {
  const recentSnapshot = await db
    .collection('ash_notification_history')
    .where('userId', '==', userId)
    .orderBy('sentAt', 'desc')
    .limit(1)
    .get();

  if (recentSnapshot.empty) return preferredTime;

  const lastSent = recentSnapshot.docs[0].data().sentAt?.toDate?.();
  if (!lastSent) return preferredTime;

  const minNextTime = new Date(
    lastSent.getTime() + DEFAULTS.MIN_HOURS_BETWEEN * 60 * 60 * 1000,
  );

  const pref = preferredTime instanceof Date ? preferredTime : new Date(preferredTime);
  return pref < minNextTime ? minNextTime : pref;
}

module.exports = {
  canSendNotification,
  getNextAvailableTime,
  DEFAULTS,
};
