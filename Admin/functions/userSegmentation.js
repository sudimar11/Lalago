const admin = require('firebase-admin');

const COMPLETED_STATUSES = [
  'Order Completed',
  'order completed',
  'completed',
  'Completed',
];

async function getNotificationEngagement(userId, db) {
  try {
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
  } catch (e) {
    console.log('Error fetching notifications for user', userId, e.message);
    return 0;
  }
}

/** Fetch all-time order stats from restaurant_orders when pref is missing. */
async function fetchOrderStatsFromOrders(userId, db) {
  try {
    const ordersSnap = await db
      .collection('restaurant_orders')
      .where('authorID', '==', userId)
      .get();

    const completed = ordersSnap.docs
      .map((d) => d.data())
      .filter((o) =>
        COMPLETED_STATUSES.some((s) =>
          (o.status || '').toString().toLowerCase().includes(s.toLowerCase())
        )
      );

    if (completed.length === 0) {
      return { totalOrders: 0, lastOrderDate: null };
    }

    const sorted = completed.sort((a, b) => {
      const dateA = a.createdAt?.toDate?.() || new Date(0);
      const dateB = b.createdAt?.toDate?.() || new Date(0);
      return dateB - dateA;
    });
    const lastOrderDate = sorted[0].createdAt?.toDate?.() || null;

    return { totalOrders: completed.length, lastOrderDate };
  } catch (e) {
    console.log('Error fetching order stats for user', userId, e.message);
    return { totalOrders: 0, lastOrderDate: null };
  }
}

/**
 * Segmentation rules (exact):
 * - New: totalOrders === 0 (No completed orders)
 * - Churned: daysSinceLastOrder > 90 (Last order > 90 days ago)
 * - Inactive: daysSinceLastOrder > 30 and ≤ 90 (Last order 31–90 days ago)
 * - Power User: totalOrders >= 10 and notificationOpenRate >= 50% and last order ≤ 30 days
 * - Regular: totalOrders >= 5 and last order ≤ 30 days (5–9 orders, or 10+ with <50% notif)
 * - Active: totalOrders >= 1 and < 5 and last order ≤ 30 days
 * - Unknown: segment null, empty, or invalid (returned on error)
 */
async function getUserSegment(userId, userData, db) {
  try {
    const pref = userData.preferenceProfile || {};
    let totalOrders =
      userData.totalCompletedOrders ?? pref.totalCompletedOrders ?? 0;
    let lastOrderRaw =
      userData.lastOrderCompletedAt ?? pref.lastOrderedAt ?? null;

    // Fallback: fetch from orders when pref has no data (e.g. user never in computeUserPreferences)
    const hasPrefData =
      (totalOrders > 0 || (lastOrderRaw != null && lastOrderRaw !== undefined));
    if (!hasPrefData) {
      const stats = await fetchOrderStatsFromOrders(userId, db);
      totalOrders = stats.totalOrders;
      lastOrderRaw = stats.lastOrderDate;
    }

    totalOrders = Number(totalOrders) || 0;

    let lastOrderDate = null;
    if (lastOrderRaw) {
      lastOrderDate = lastOrderRaw.toDate
        ? lastOrderRaw.toDate()
        : new Date(lastOrderRaw);
    }

    let daysSinceLastOrder = 999;
    if (lastOrderDate) {
      const now = new Date();
      daysSinceLastOrder = Math.ceil(
        (now.getTime() - lastOrderDate.getTime()) / (1000 * 60 * 60 * 24)
      );
    }

    const notificationOpenRate =
      (await getNotificationEngagement(userId, db)) * 100;

    let segment = 'new';

    if (totalOrders === 0) {
      segment = 'new';
    } else if (daysSinceLastOrder > 90) {
      segment = 'churned';
    } else if (daysSinceLastOrder > 30) {
      segment = 'inactive';
    } else {
      if (totalOrders >= 10 && notificationOpenRate >= 50) {
        segment = 'power_user';
      } else if (totalOrders >= 5) {
        segment = 'regular';
      } else {
        segment = 'active';
      }
    }

    console.log(
      `User ${userId} (${userData.email || 'no email'}): orders=${totalOrders}, ` +
        `daysSinceLastOrder=${daysSinceLastOrder}, notifRate=${notificationOpenRate.toFixed(0)}% → segment=${segment}`,
    );

    return segment;
  } catch (error) {
    console.error('Error in getUserSegment:', error);
    return 'unknown';
  }
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
    churned: {
      frequency: 'very_low',
      bestTimes: ['weekend'],
      personalization: 'low',
      channel: 'push',
    },
  };
  return strategies[segment] || strategies.active;
}

async function updateUserSegment(userId, userData, db) {
  try {
    const segment = await getUserSegment(userId, userData, db);

    const pref = userData.preferenceProfile || {};
    const totalOrders =
      userData.totalCompletedOrders ??
      pref.totalCompletedOrders ??
      0;

    console.log(
      `Writing segment "${segment}" to user ${userId} (orders: ${totalOrders})`,
    );

    let engagementScore = userData.engagementScore;
    if (engagementScore == null) {
      const totalSpend = userData.totalSpend ?? 0;
      const orderFrequencyDays = userData.orderFrequencyDays ?? 30;

      engagementScore = Math.round(
        totalOrders * 10 +
          totalSpend / 100 +
          (orderFrequencyDays ? 100 / orderFrequencyDays : 0),
      );
    }

    const updateData = {
      segment,
      segmentUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSegmentCalculation:
        admin.firestore.FieldValue.serverTimestamp(),
    };
    if (engagementScore != null) {
      updateData.engagementScore = engagementScore;
    }

    await db.collection('users').doc(userId).set(updateData, { merge: true });

    return segment;
  } catch (error) {
    console.error(
      `Error in updateUserSegment for user ${userId}:`,
      error,
    );
    throw error;
  }
}

/** Same as getUserSegment but returns { segment, totalOrders, daysSinceLastOrder, notificationOpenRate, branch } for debugging. */
async function getUserSegmentDebug(userId, userData, db) {
  const pref = userData.preferenceProfile || {};
  let totalOrders =
    userData.totalCompletedOrders ?? pref.totalCompletedOrders ?? 0;
  let lastOrderRaw =
    userData.lastOrderCompletedAt ?? pref.lastOrderedAt ?? null;

  const hasPrefData =
    totalOrders > 0 || (lastOrderRaw != null && lastOrderRaw !== undefined);
  let usedFallback = false;
  if (!hasPrefData) {
    const stats = await fetchOrderStatsFromOrders(userId, db);
    totalOrders = stats.totalOrders;
    lastOrderRaw = stats.lastOrderDate;
    usedFallback = true;
  }

  totalOrders = Number(totalOrders) || 0;

  let lastOrderDate = null;
  if (lastOrderRaw) {
    lastOrderDate = lastOrderRaw.toDate
      ? lastOrderRaw.toDate()
      : new Date(lastOrderRaw);
  }

  let daysSinceLastOrder = 999;
  if (lastOrderDate) {
    const now = new Date();
    daysSinceLastOrder = Math.ceil(
      (now.getTime() - lastOrderDate.getTime()) / (1000 * 60 * 60 * 24)
    );
  }

  const notificationOpenRate =
    (await getNotificationEngagement(userId, db)) * 100;

  let segment = 'new';
  let branch = '';

  if (totalOrders === 0) {
    segment = 'new';
    branch = 'totalOrders===0';
  } else if (daysSinceLastOrder > 90) {
    segment = 'churned';
    branch = 'daysSinceLastOrder>90';
  } else if (daysSinceLastOrder > 30) {
    segment = 'inactive';
    branch = '30<days<=90';
  } else {
    if (totalOrders >= 10 && notificationOpenRate >= 50) {
      segment = 'power_user';
      branch = '10+orders,50%+notif,last30d';
    } else if (totalOrders >= 5) {
      segment = 'regular';
      branch = '5+orders,last30d';
    } else {
      segment = 'active';
      branch = '1-4orders,last30d';
    }
  }

  return {
    segment,
    totalOrders,
    daysSinceLastOrder,
    notificationOpenRate: Math.round(notificationOpenRate * 100) / 100,
    branch,
    usedFallback,
    lastOrderDate: lastOrderDate ? lastOrderDate.toISOString() : null,
  };
}

module.exports = {
  getNotificationEngagement,
  getUserSegment,
  getUserSegmentDebug,
  getStrategyForSegment,
  updateUserSegment,
  fetchOrderStatsFromOrders,
};
