const admin = require('firebase-admin');

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

async function getUserSegment(userId, userData, db) {
  try {
    const pref = userData.preferenceProfile || {};
    const totalOrders =
      userData.totalCompletedOrders ?? pref.totalCompletedOrders ?? 0;
    const lastOrderRaw =
      userData.lastOrderCompletedAt ?? pref.lastOrderedAt ?? null;

    let lastOrderDate = null;
    if (lastOrderRaw) {
      lastOrderDate = lastOrderRaw.toDate
        ? lastOrderRaw.toDate()
        : new Date(lastOrderRaw);
    }

    let daysSinceLastOrder = 999;
    if (lastOrderDate) {
      const now = new Date();
      const diffTime = Math.abs(now - lastOrderDate);
      daysSinceLastOrder = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
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

    await db.collection('users').doc(userId).update(updateData);

    return segment;
  } catch (error) {
    console.error(
      `Error in updateUserSegment for user ${userId}:`,
      error,
    );
    throw error;
  }
}

module.exports = {
  getNotificationEngagement,
  getUserSegment,
  getStrategyForSegment,
  updateUserSegment,
};
