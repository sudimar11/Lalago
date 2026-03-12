/**
 * Unified analytics tracking service for Ash.
 * All apps and functions use this to track analytics events.
 */
const admin = require('firebase-admin');
const ANALYTICS = require('./analyticsConstants');

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

class AnalyticsTracker {
  /**
   * Track a notification event
   */
  static async trackNotificationEvent(
    notificationData,
    eventType,
    additionalData = {},
  ) {
    const db = getDb();
    const { notificationId, userId, type } = notificationData;

    const event = {
      eventType,
      notificationId,
      userId,
      notificationType: type,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ...additionalData,
    };

    await db
      .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_ACTIONS)
      .add(event);

    return event;
  }

  /**
   * Track a conversion event (notification → order)
   */
  static async trackConversion(
    userId,
    sourceType,
    sourceId,
    orderId,
    orderValue,
  ) {
    const db = getDb();

    const conversion = {
      userId,
      sourceType,
      sourceId,
      orderId,
      orderValue,
      convertedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    await db
      .collection(ANALYTICS.COLLECTIONS.CONVERSIONS)
      .add(conversion);

    if (sourceType === 'notification' && sourceId) {
      const historyRef = db
        .collection(ANALYTICS.COLLECTIONS.NOTIFICATION_HISTORY)
        .doc(sourceId);
      const historyDoc = await historyRef.get();
      if (historyDoc.exists) {
        await historyRef.update({
          converted: true,
          convertedOrderId: orderId,
          convertedAt: admin.firestore.FieldValue.serverTimestamp(),
          conversionValue: orderValue,
        });
      }
    }

    return conversion;
  }

  /**
   * Track a funnel step
   */
  static async trackFunnelStep(userId, sessionId, stage, metadata = {}) {
    const db = getDb();

    const step = {
      userId,
      sessionId,
      stage,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ...metadata,
    };

    await db.collection(ANALYTICS.COLLECTIONS.FUNNEL_STEPS).add(step);
  }

  /**
   * Track user engagement
   */
  static async trackUserEngagement(userId, eventType, metadata = {}) {
    const db = getDb();
    const date = new Date().toISOString().split('T')[0];

    const event = {
      userId,
      eventType,
      date,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ...metadata,
    };

    await db
      .collection(ANALYTICS.COLLECTIONS.USER_ENGAGEMENT)
      .add(event);

    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    if (userDoc.exists) {
      await userRef.update({
        lastActiveAt: admin.firestore.FieldValue.serverTimestamp(),
        [`engagement.${date}`]: admin.firestore.FieldValue.increment(1),
      });
    }

    return event;
  }
}

module.exports = AnalyticsTracker;
