const functions = require('firebase-functions');
const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const TimezoneUtils = require('./timezoneUtils');
const FrequencyManager = require('./frequencyManager');
const { handlePaymentFailure } = require('./paymentFailureWebhook');
const OrderRecoveryService = require('./orderRecoveryService');
const ABTestingService = require('./abTesting');
const EngagementAnalytics = require('./engagementAnalytics');
const NotificationBuilder = require('./notificationBuilder');
const AshNotificationBuilder = require('./ashNotificationBuilder');
const { trackNotificationAction } = require('./notificationActionAnalytics');
const loyaltyHelpers = require('./loyaltyHelpers');
const giftCardFunctions = require('./giftCardFunctions');
const migrateRiderStatusSchemaV2 = require('./migrations/migrateRiderStatusSchemaV2');

exports.trackNotificationAction = trackNotificationAction;
exports.createGiftCard = giftCardFunctions.createGiftCard;
exports.validateGiftCard = giftCardFunctions.validateGiftCard;
exports.redeemGiftCard = giftCardFunctions.redeemGiftCard;
exports.claimGiftCard = giftCardFunctions.claimGiftCard;
exports.migrateLegacyGiftCards = giftCardFunctions.migrateLegacyGiftCards;
exports.processExpiredGiftCards = giftCardFunctions.processExpiredGiftCards;
exports.refundGiftCard = giftCardFunctions.refundGiftCard;
exports.migrateRiderStatusSchemaV2 = migrateRiderStatusSchemaV2;

// Lazy initialization functions - only called inside Cloud Functions
function initializeAdmin() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
}

function getDb() {
  initializeAdmin();
  return admin.firestore();
}

function getMessaging() {
  initializeAdmin();
  return admin.messaging();
}

function parsePreparationMinutes(prepTimeStr) {
  if (!prepTimeStr) return 30;
  const str = prepTimeStr.toString().toLowerCase().trim();
  const minMatch = str.match(/(\d+)\s*min/);
  if (minMatch) return Math.min(120, Math.max(5, parseInt(minMatch[1], 10)));
  const colonMatch = str.match(/(\d+):(\d+)/);
  if (colonMatch) {
    const hours = parseInt(colonMatch[1], 10);
    const minutes = parseInt(colonMatch[2], 10);
    return Math.min(120, Math.max(5, hours * 60 + minutes));
  }
  const numMatch = str.match(/(\d+)/);
  if (numMatch) return Math.min(120, Math.max(5, parseInt(numMatch[1], 10)));
  return 30;
}

function setCors(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.set('Access-Control-Max-Age', '86400');
}

function handleCors(req, res) {
  setCors(res);
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return true;
  }
  return false;
}

/**
 * Shared helper: send FCM notification to a single token.
 * Reused by sendIndividualNotification (HTTP) and testAshNotification (callable).
 */
async function _sendFcmToToken(token, title, body, data = {}, options = {}) {
  const msgData = {
    timestamp: Date.now().toString(),
    ...Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v)])
    ),
  };
  if (options.deepLink) msgData.deepLink = String(options.deepLink);
  const message = {
    token,
    notification: { title, body },
    data: msgData,
    android: {
      priority: 'high',
      notification: { sound: 'default' },
    },
    apns: {
      payload: { aps: { sound: 'default' } },
    },
  };
  if (options.imageUrl && typeof options.imageUrl === 'string' && options.imageUrl.trim()) {
    message.notification.imageUrl = options.imageUrl.trim();
  }
  return await getMessaging().send(message);
}

/**
 * Returns array of FCM tokens for a user. Prefers fcmTokens array,
 * falls back to single fcmToken for backward compatibility.
 */
async function _getUserFcmTokens(db, userId) {
  const doc = await db.collection('users').doc(userId).get();
  if (!doc.exists) return [];
  const data = doc.data() || {};
  const arr = data.fcmTokens;
  if (Array.isArray(arr) && arr.length > 0) {
    return arr.filter(t => typeof t === 'string' && t.trim().length > 0).map(t => t.trim());
  }
  const single = data.fcmToken;
  if (single && typeof single === 'string' && single.trim().length > 0) {
    return [single.trim()];
  }
  return [];
}

function _extractUserFcmTokensFromData(data) {
  if (!data || typeof data !== 'object') return [];
  const arr = data.fcmTokens;
  if (Array.isArray(arr) && arr.length > 0) {
    return arr
      .filter((t) => typeof t === 'string' && t.trim().length > 0)
      .map((t) => t.trim());
  }
  const single = data.fcmToken;
  if (single && typeof single === 'string' && single.trim().length > 0) {
    return [single.trim()];
  }
  return [];
}

/**
 * Returns array of FCM tokens for a vendor. Prefers fcmTokens array,
 * falls back to single fcmToken.
 */
async function _getVendorFcmTokens(db, vendorId) {
  const doc = await db.collection('vendors').doc(vendorId).get();
  if (!doc.exists) return [];
  const data = doc.data() || {};
  const arr = data.fcmTokens;
  if (Array.isArray(arr) && arr.length > 0) {
    return arr.filter(t => typeof t === 'string' && t.trim().length > 0).map(t => t.trim());
  }
  const single = data.fcmToken;
  if (single && typeof single === 'string' && single.trim().length > 0) {
    return [single.trim()];
  }
  return [];
}

function _sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function _sendMulticastWithSingleRetry(multicastMessage, contextLabel) {
  const first = await getMessaging().sendEachForMulticast(multicastMessage);
  const failedTokens = [];
  first.responses.forEach((response, index) => {
    if (!response.success) {
      failedTokens.push(multicastMessage.tokens[index]);
    }
  });

  if (failedTokens.length === 0) {
    return first;
  }

  console.warn(
    `[${contextLabel}] first attempt had ${failedTokens.length} failures; retrying`
  );
  await _sleep(800);
  const retry = await getMessaging().sendEachForMulticast({
    ...multicastMessage,
    tokens: failedTokens,
  });
  console.log(
    `[${contextLabel}] retry success=${retry.successCount}/${failedTokens.length}`
  );
  return first;
}

/**
 * Firestore Trigger: Notify recipient when rider/restaurant sends quick message.
 * Triggered on order_messages/{orderId}/messages/{messageId} document create.
 */
exports.notifyOnOrderMessage = functions
  .region('us-central1')
  .runWith({ memory: '512MB', timeoutSeconds: 60 })
  .firestore.document('order_messages/{orderId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const messageId = context.params.messageId;
    const msg = snap.data() || {};
    const senderType = String(msg.senderType || '');
    const messageText = String(msg.messageText || 'New message');

    try {
      const db = getDb();
      const orderSnap = await db.collection('restaurant_orders').doc(orderId).get();
      if (!orderSnap.exists) {
        console.warn(
          `[notifyOnOrderMessage] order not found orderId=${orderId}`
        );
        return null;
      }

      const order = orderSnap.data() || {};
      const vendorID = order.vendorID || order.vendor?.id || '';
      const driverID = order.driverID || '';
      const vendorName =
        String(order.vendor?.title || order.vendor?.name || '').trim();

      let tokens = [];
      let title = 'Order Message';
      let bodyPrefix = '';

      if (senderType === 'rider') {
        tokens = await _getVendorFcmTokens(db, vendorID);
        title = 'Rider Message';
        bodyPrefix = 'Rider: ';
      } else if (senderType === 'restaurant') {
        if (!driverID || String(driverID).trim().isEmpty) {
          console.warn(
            `[notifyOnOrderMessage] missing driverID orderId=${orderId}, messageId=${messageId}`
          );
          return null;
        }
        tokens = await _getUserFcmTokens(db, driverID);
        title = vendorName ? `${vendorName} sent a message` : 'Restaurant Message';
        bodyPrefix = vendorName ? `${vendorName}: ` : 'Restaurant: ';
      }

      if (tokens.length === 0) {
        console.warn(
          `[notifyOnOrderMessage] no tokens senderType=${senderType} orderId=${orderId}`
        );
        return null;
      }

      const messagePreview =
        messageText.length > 100 ? messageText.substring(0, 97) + '...' : messageText;
      const body = `${bodyPrefix}${messagePreview}`.trim();
      const messagePayload = {
        notification: { title, body },
        data: {
          type: 'order_communication',
          orderId: String(orderId),
          messageId: String(messageId),
          target: 'communicationPanel',
        },
        android: {
          priority: 'high',
        },
        apns: {
          headers: { 'apns-priority': '10' },
        },
      };
      const multicastMessage = { ...messagePayload, tokens };
      await _sendMulticastWithSingleRetry(
        multicastMessage,
        'notifyOnOrderMessage'
      );
    } catch (e) {
      console.error('[notifyOnOrderMessage] Error:', e);
    }
    return null;
  });

/**
 * Temporary transition bridge:
 * Mirror canonical read state to legacy order_messages read state.
 * Remove after full migration to order_communications.
 */
exports.syncLegacyReadReceiptFromCanonical = functions
  .region('us-central1')
  .runWith({ memory: '512MB', timeoutSeconds: 60 })
  .firestore.document('order_communications/{orderId}/messages/{messageId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};
    const orderId = context.params.orderId;
    const becameRead = beforeData.isRead !== true && afterData.isRead === true;
    if (!becameRead) return null;

    const db = getDb();
    const legacyParent = db.collection('order_messages').doc(orderId);
    const legacyRefId = String(afterData.legacyMessageId || '');
    const senderRole = String(afterData.senderRole || '');
    const senderType = senderRole === 'restaurant' ? 'restaurant' : 'rider';

    try {
      if (legacyRefId) {
        await legacyParent.collection('messages').doc(legacyRefId).set(
          {
            isRead: true,
            readAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return null;
      }

      const text = String(afterData.text || afterData.messageText || '').trim();
      const messageKey = String(afterData.messageKey || '').trim();
      const createdAt = afterData.createdAt;
      const fallbackSnap = await legacyParent
        .collection('messages')
        .where('senderType', '==', senderType)
        .where('isRead', '==', false)
        .orderBy('createdAt', 'desc')
        .limit(20)
        .get();

      const targetMillis = createdAt && createdAt.toDate
        ? createdAt.toDate().getTime()
        : null;

      let matchedRef = null;
      fallbackSnap.docs.forEach((doc) => {
        if (matchedRef) return;
        const d = doc.data() || {};
        const legacyText = String(d.messageText || '').trim();
        const legacyKey = String(d.messageKey || '').trim();
        const legacyTs = d.createdAt && d.createdAt.toDate
          ? d.createdAt.toDate().getTime()
          : null;
        const textMatch = text && legacyText && text === legacyText;
        const keyMatch = messageKey && legacyKey && messageKey === legacyKey;
        const timeMatch = targetMillis != null && legacyTs != null
          ? Math.abs(targetMillis - legacyTs) <= 120000
          : true;
        if ((textMatch || keyMatch) && timeMatch) {
          matchedRef = doc.ref;
        }
      });

      if (matchedRef) {
        await matchedRef.set(
          {
            isRead: true,
            readAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    } catch (e) {
      console.error(
        `[syncLegacyReadReceiptFromCanonical] order=${orderId} error`,
        e
      );
    }
    return null;
  });

/**
 * Firestore Trigger: Notify customer when driver sends a chat message
 *
 * Triggered on chat_driver/{orderId}/thread/{messageId} document create.
 * Sends an FCM message with a notification payload so Android can display it
 * without relying on local notifications from a background isolate.
 */
exports.notifyCustomerOnDriverChatMessage = functions
  .region('us-central1')
  .firestore.document('chat_driver/{orderId}/thread/{messageId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const messageData = snap.data() || {};

    try {
      const senderRole = String(messageData.senderRole || '');
      const senderId = String(messageData.senderId || '');
      const receiverId = String(messageData.receiverId || '');
      const messageType = String(messageData.messageType || 'text');

      // Only notify for driver-originated messages.
      // (Some clients may omit senderRole; fall back to comparing receiverId.)
      if (senderRole && senderRole !== 'rider' && senderRole !== 'driver') {
        return null;
      }

      const db = getDb();
      const inboxRef = db.collection('chat_driver').doc(orderId);
      const inboxSnap = await inboxRef.get();
      const inboxData = inboxSnap.exists ? inboxSnap.data() : null;

      const customerId = String(
        inboxData?.customerId || messageData.customerId || receiverId || ''
      );
      if (!customerId) {
        console.log(
          `[notifyCustomerOnDriverChatMessage] Missing customerId for order ${orderId}`
        );
        return null;
      }

      // If sender is the customer, don't notify.
      if (senderId && senderId === customerId) {
        return null;
      }

      // Read customer tokens (supports fcmTokens array and fcmToken fallback)
      const customerTokens = await _getUserFcmTokens(db, customerId);

      if (customerTokens.length === 0) {
        console.log(
          `[notifyCustomerOnDriverChatMessage] No FCM token for customer ${customerId}`
        );
        return null;
      }

      // Resolve driver name (best-effort)
      let driverName = 'Driver';
      if (senderId) {
        try {
          const driverSnap = await db.collection('users').doc(senderId).get();
          if (driverSnap.exists) {
            const d = driverSnap.data() || {};
            const first = String(d.firstName || '').trim();
            const last = String(d.lastName || '').trim();
            const full = `${first} ${last}`.trim();
            if (full) driverName = full;
          }
        } catch (e) {
          console.error(
            `[notifyCustomerOnDriverChatMessage] Failed to load driver name:`,
            e
          );
        }
      }

      // Message preview
      const rawText = String(messageData.message || '');
      let body = rawText;
      if (messageType === 'image') body = 'Sent an image';
      if (messageType === 'video') body = 'Sent a video';
      if (!body) body = 'New message';

      // Increment unread count (best-effort; keep existing fields intact)
      try {
        await inboxRef.set(
          {
            orderId: orderId,
            customerId: customerId,
            unreadCount: admin.firestore.FieldValue.increment(1),
            lastMessage: body,
            lastSenderId: senderId || null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      } catch (e) {
        console.error(
          `[notifyCustomerOnDriverChatMessage] Failed updating inbox:`,
          e
        );
      }

      const messagePayload = {
        notification: {
          title: `New message from ${driverName}`,
          body: body,
        },
        data: {
          type: 'chat_message',
          orderId: String(orderId),
          customerId: String(customerId),
          senderRole: senderRole || 'rider',
          messageType: messageType || 'chat',
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'chat_messages',
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      };

      const multicastMessage = { ...messagePayload, tokens: customerTokens };
      const resp = await getMessaging().sendEachForMulticast(multicastMessage);
      console.log(
        `[notifyCustomerOnDriverChatMessage] Sent FCM for order ${orderId}: ${resp.successCount}/${customerTokens.length}`
      );
      return null;
    } catch (error) {
      console.error(
        `[notifyCustomerOnDriverChatMessage] Error for order ${orderId}:`,
        error
      );
      return null;
    }
  });

/**
 * Firestore Trigger: Notify rider/admins for private admin↔driver chat
 *
 * Triggered on chat_admin_driver/{orderId}/thread/{messageId} document create.
 * - If senderRole == 'admin' -> notify assigned driver (single token)
 * - If senderRole == 'driver' -> notify all admins (multicast)
 */
exports.notifyOnAdminDriverChatMessage = functions
  .region('us-central1')
  .firestore.document('chat_admin_driver/{orderId}/thread/{messageId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const messageData = snap.data() || {};

    try {
      const db = getDb();

      const senderRole = String(messageData.senderRole || '');
      const receiverRole = String(messageData.receiverRole || '');
      const senderId = String(messageData.senderId || '');
      const receiverId = String(messageData.receiverId || '');
      const messageType = String(messageData.messageType || 'text');

      const rawText = String(messageData.message || '');
      let body = rawText;
      if (messageType === 'image') body = 'Sent an image';
      if (messageType === 'video') body = 'Sent a video';
      if (!body) body = 'New message';

      // Update metadata doc (best-effort) + maintain unread counters
      try {
        const metaPatch = {
          orderId: String(orderId),
          lastMessage: body,
          lastSenderId: senderId || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (senderRole === 'admin') {
          metaPatch.unreadForDriver = admin.firestore.FieldValue.increment(1);
        }
        if (senderRole === 'driver') {
          metaPatch.unreadForAdmin = admin.firestore.FieldValue.increment(1);
        }

        await db.collection('chat_admin_driver').doc(orderId).set(metaPatch, {
          merge: true,
        });
      } catch (e) {
        console.error(
          `[notifyOnAdminDriverChatMessage] Failed updating metadata for order ${orderId}:`,
          e
        );
      }

      // Admin -> Driver notification
      if (senderRole === 'admin' || receiverRole === 'driver') {
        let driverId = receiverId;

        if (!driverId) {
          try {
            const metaSnap = await db.collection('chat_admin_driver').doc(orderId).get();
            if (metaSnap.exists) {
              const meta = metaSnap.data() || {};
              driverId = String(meta.driverId || meta.driverID || '');
            }
          } catch (e) {
            console.error(
              `[notifyOnAdminDriverChatMessage] Failed resolving driverId for order ${orderId}:`,
              e
            );
          }
        }

        if (!driverId) {
          console.log(
            `[notifyOnAdminDriverChatMessage] Missing driverId for order ${orderId}`
          );
          return null;
        }

        // Persist resolved driverId on metadata (best-effort)
        try {
          await db.collection('chat_admin_driver').doc(orderId).set(
            {
              driverId: String(driverId),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
        } catch (_) {}

        const driverSnap = await db.collection('users').doc(driverId).get();
        const driverToken = driverSnap.exists ? driverSnap.data()?.fcmToken : null;
        if (!driverToken) {
          console.log(
            `[notifyOnAdminDriverChatMessage] No FCM token for driver ${driverId} (order ${orderId})`
          );
          return null;
        }

        const message = {
          token: driverToken,
          notification: {
            title: 'Admin',
            body: body,
          },
          data: {
            type: 'admin_driver_chat',
            orderId: String(orderId),
            senderRole: 'admin',
            messageType: messageType || 'chat',
          },
          android: {
            priority: 'high',
            notification: {
              channelId: 'chat_messages',
              sound: 'default',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        };

        const resp = await getMessaging().send(message);
        console.log(
          `[notifyOnAdminDriverChatMessage] Sent FCM to driver ${driverId} for order ${orderId}: ${resp}`
        );
        return null;
      }

      // Driver -> Admin notification (multicast)
      if (senderRole === 'driver' || receiverRole === 'admin') {
        // Resolve driver display name (best-effort)
        let driverName = 'Rider';
        if (senderId) {
          try {
            const driverSnap = await db.collection('users').doc(senderId).get();
            if (driverSnap.exists) {
              const d = driverSnap.data() || {};
              const first = String(d.firstName || '').trim();
              const last = String(d.lastName || '').trim();
              const full = `${first} ${last}`.trim();
              if (full) driverName = full;
            }
          } catch (e) {
            console.error(
              `[notifyOnAdminDriverChatMessage] Failed to load driver name:`,
              e
            );
          }
        }

        const adminsSnap = await db
          .collection('users')
          .where('role', '==', 'admin')
          .get();

        const adminTokens = [];
        for (const doc of adminsSnap.docs) {
          const data = doc.data() || {};
          const token = data.fcmToken;
          if (token && typeof token === 'string' && token.trim().length > 0) {
            adminTokens.push(token.trim());
          }
        }

        if (adminTokens.length === 0) {
          console.log(
            `[notifyOnAdminDriverChatMessage] No admin FCM tokens found (order ${orderId})`
          );
          return null;
        }

        const BATCH_SIZE = 500;
        for (let i = 0; i < adminTokens.length; i += BATCH_SIZE) {
          const batch = adminTokens.slice(i, i + BATCH_SIZE);

          const multicast = {
            notification: {
              title: `New message from ${driverName}`,
              body: body,
            },
            data: {
              type: 'admin_driver_chat',
              orderId: String(orderId),
              senderRole: 'driver',
              messageType: messageType || 'chat',
              timestamp: Date.now().toString(),
            },
            tokens: batch,
            android: {
              priority: 'high',
              notification: {
                channelId: 'chat_messages',
                sound: 'default',
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: 'default',
                },
              },
            },
          };

          const resp = await getMessaging().sendEachForMulticast(multicast);
          console.log(
            `[notifyOnAdminDriverChatMessage] Admin multicast batch: ${resp.successCount} sent, ${resp.failureCount} failed (order ${orderId})`
          );
        }
      }

      return null;
    } catch (error) {
      console.error(
        `[notifyOnAdminDriverChatMessage] Error for order ${orderId}:`,
        error
      );
      return null;
    }
  });

/**
 * AI Auto Dispatcher Cloud Function
 * 
 * Triggers on restaurant_orders document changes when status becomes 'Order Accepted'
 * - Automatically assigns best available rider using AI prescription
 * - AI scoring algorithm: ETA (50%) + ML acceptance probability (30%) + fairness (20%)
 * - Sends FCM notification to rider
 * - Logs assignment to assignments_log collection
 */
exports.autoDispatcher = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const orderId = context.params.orderId;
    const beforeData = change.before.data();
    const afterData = change.after.data();

    // Only trigger when order status changes to 'Order Accepted' (ready for AI auto-dispatch)
    if (beforeData.status !== 'Order Accepted' && afterData.status === 'Order Accepted') {
        try {
          // Check global auto-dispatch toggle
          const settingsSnap = await getDb().collection('config').doc('dispatch_settings').get();
          const settings = settingsSnap.exists ? settingsSnap.data() : {};
          if (settings.autoDispatchEnabled === false) {
            console.log(`[AI AutoDispatcher] Auto-dispatch is disabled, skipping order ${orderId}`);
            return null;
          }

          // Restaurant-first model: dispatch all orders reaching 'Order Accepted'.
          if (afterData?.driverID) {
            console.log(
              `[AI AutoDispatcher] Skipping order ${orderId} (driver already assigned)`
            );
            return null;
          }

          // Guard: batched orders are dispatched by orderBatchingCron.
          if (afterData?.batch?.batchId) {
            console.log(
              `[AI AutoDispatcher] Skipping order ${orderId} (part of batch ${afterData.batch.batchId})`
            );
            return null;
          }

          console.log(`[AI AutoDispatcher] Processing order ${orderId} for automatic rider assignment`);

          // Phase 1A: Acquire dispatch lock to prevent race conditions
          const orderRef = change.after.ref;
          const lockAcquired = await getDb().runTransaction(async (tx) => {
            const snap = await tx.get(orderRef);
            const d = snap.data() || {};
            const lock = d?.dispatch?.lock;
            const lockExpires = d?.dispatch?.lockExpiresAt;
            const tsNow = admin.firestore.Timestamp.now();
            if (lock === true && lockExpires && lockExpires.seconds > tsNow.seconds) {
              return false;
            }
            tx.update(orderRef, {
              'dispatch.lock': true,
              'dispatch.lockHolder': 'cloud_function',
              'dispatch.lockAcquiredAt': admin.firestore.FieldValue.serverTimestamp(),
              'dispatch.lockExpiresAt': _addSeconds(tsNow, 60),
            });
            return true;
          });

          if (!lockAcquired) {
            console.log(`[AI AutoDispatcher] Skipping order ${orderId} (dispatch lock held by another path)`);
            return null;
          }

          // 1. Get order details
        // Extract restaurant location from vendor data
        const restaurantLocation = {
          lat: afterData.vendor?.latitude || afterData.vendor?.g?.geopoint?._latitude || 0,
          lng: afterData.vendor?.longitude || afterData.vendor?.g?.geopoint?._longitude || 0
        };

        // Extract delivery location from address or author location
        const deliveryLocation = {
          lat: afterData.address?.location?.latitude || 
               afterData.author?.location?.latitude || 0,
          lng: afterData.address?.location?.longitude || 
               afterData.author?.location?.longitude || 0
        };

        console.log(`[AI AutoDispatcher] Restaurant location:`, restaurantLocation);
        console.log(`[AI AutoDispatcher] Delivery location:`, deliveryLocation);

        // Zone capacity check
        if (deliveryLocation.lat && deliveryLocation.lng) {
          const capCheck = await _checkZoneCapacity(
            deliveryLocation.lat,
            deliveryLocation.lng,
          );
          if (capCheck.atCapacity) {
            console.log(
              `[AI AutoDispatcher] Zone at capacity for order ${orderId}: ` +
              `${capCheck.currentCount}/${capCheck.maxRiders} in ${capCheck.zoneName}`
            );
            await change.after.ref.update({
              status: 'Order Accepted',
              dispatchStatus: 'zone_at_capacity',
              dispatchZoneId: capCheck.zoneId,
              dispatchZoneName: capCheck.zoneName,
              dispatchCapacityCurrent: capCheck.currentCount,
              dispatchCapacityMax: capCheck.maxRiders,
              dispatchAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            return null;
          }
        }

        const order = {
          id: orderId,
          ...afterData,
          restaurantLocation,
          deliveryLocation,
          createdAt: afterData.createdAt || admin.firestore.Timestamp.now(),
        };

        // Search radius expansion based on rejection/retry attempts
        const dispatchData = afterData?.dispatch || {};
        const rejectionCount = _asNumber(dispatchData.rejectionCount) || 0;
        const retryCount = _asNumber(dispatchData.retryCount) || 0;
        const totalAttempts = rejectionCount + retryCount;

        let searchRadiusKm = 3;
        if (totalAttempts >= 5) {
          searchRadiusKm = 10;
          console.log(
            `[AI AutoDispatcher] Order ${orderId} has ${totalAttempts} attempts, ` +
            `expanding search to ${searchRadiusKm}km`
          );
        } else if (totalAttempts >= 3) {
          searchRadiusKm = 7;
        } else if (totalAttempts >= 1) {
          searchRadiusKm = 5;
        }

        // 2. Find available drivers
        const driversSnapshot = await getDb().collection('users')
          .where('role', '==', 'driver')
          .get();

        if (driversSnapshot.empty) {
          console.log(`[AI AutoDispatcher] No available riders for order ${orderId}`);
          await change.after.ref.update({
            status: 'Order Accepted',  // Keep status as Order Accepted
            dispatchStatus: 'no_drivers_available',
            dispatchAttemptedAt: admin.firestore.FieldValue.serverTimestamp()
          });
          return null;
        }

        // 3. Load dispatch weights and calculate scores for each driver
        const weights = await _loadDispatchWeights();

        // Prefer historical average prep time over restaurant-entered estimate
        let prepMinutes = 0;
        const vendorId = afterData.vendorID || afterData.vendor?.id || '';
        if (vendorId) {
          try {
            const statsSnap = await getDb()
              .collection('vendors')
              .doc(vendorId)
              .collection('restaurant_stats')
              .doc('prep_times')
              .get();
            if (statsSnap.exists) {
              const avg = statsSnap.data()?.averagePrepTimeMinutes;
              if (avg && avg > 0) {
                prepMinutes = avg;
                console.log(`[AI AutoDispatcher] Using historical prep time for ${vendorId}: ${avg}m`);
              }
            }
          } catch (statsErr) {
            console.error('[AI AutoDispatcher] Failed to load prep stats:', statsErr);
          }
        }
        if (!prepMinutes) {
          prepMinutes = _asNumber(
            afterData.estimatedTimeToPrepare ||
            afterData.preparationTime ||
            0
          );
        }
        const driverScores = [];
        const excludedIds = new Set(afterData?.dispatch?.excludedDriverIds || []);

        // Pass 1: filter eligible drivers and collect IDs for batch queries
        const eligibleDrivers = [];
        for (const driverDoc of driversSnapshot.docs) {
          const driver = { id: driverDoc.id, ...driverDoc.data() };
          if (excludedIds.has(driver.id)) continue;
          if (!_isDriverEligibleBase(driver)) continue;
          
          const driverLocation = _extractDriverLocation(driver);
          if (!driverLocation.lat && !driverLocation.lng) continue;
          
          const activeOrders = _activeOrdersCount(driver);
          const effectiveCap = _calculateDynamicCapacity(driver, weights);
          if (activeOrders >= effectiveCap) continue;
          
          const eta = calculateETA(driverLocation, order.restaurantLocation);
          const distanceKm = _distanceMeters(driverLocation, order.restaurantLocation) / 1000;

          if (distanceKm > searchRadiusKm) continue;

          const headingMatch = _calculateDriverHeading(driver, driverLocation, order.restaurantLocation);

          eligibleDrivers.push({
            driver,
            driverLocation,
            activeOrders,
            effectiveCap,
            eta,
            distanceKm,
            headingMatch,
          });
        }

        // Pass 2: batch acceptance probability and fairness queries
        const eligibleIds = eligibleDrivers.map(d => d.driver.id);
        const [batchBaseRates, batchFairness] = await Promise.all([
          getMLAcceptanceProbabilityBatch(eligibleIds),
          Promise.resolve(calculateFairnessScoreBatch(eligibleDrivers.map(d => d.driver))),
        ]);

        const hour = new Date().getHours();
        const timeBonus = (hour >= 10 && hour <= 21) ? 0.05 : 0;

        // Pass 3: score each driver using batched data
        for (const e of eligibleDrivers) {
          const baseRate = batchBaseRates[e.driver.id] || 0.7;
          const distancePenalty = Math.min(e.eta / 60, 0.3);
          const workloadPenalty = e.activeOrders * 0.15;
          const mlAcceptanceProbability = Math.max(0.05, Math.min(0.95,
            baseRate - distancePenalty - workloadPenalty + timeBonus
          ));
          const fairnessScore = batchFairness[e.driver.id] || 50;

          const compositeScore = calculateCompositeScore({
            eta: e.eta,
            mlAcceptanceProbability,
            effectiveCapacity: e.effectiveCap,
            fairnessScore,
            headingMatch: e.headingMatch,
            currentOrders: e.activeOrders,
            restaurantPrepMinutes: prepMinutes,
          });

          driverScores.push({
            driverId: e.driver.id,
            driverName: `${e.driver.firstName || ''} ${e.driver.lastName || ''}`.trim(),
            fcmToken: e.driver.fcmToken,
            driverLocation: e.driverLocation,
            activeOrders: e.activeOrders,
            eta: e.eta,
            distance: e.distanceKm,
            mlAcceptanceProbability,
            fairnessScore,
            headingMatch: e.headingMatch,
            compositeScore,
            routingSource: 'haversine',
          });
        }

        // 4. Sort by composite score (lower is better)
        driverScores.sort((a, b) => a.compositeScore - b.compositeScore);

        // 4b. Two-pass: refine top candidates with road-network ETA
        const TOP_N = Math.min(8, driverScores.length);
        if (TOP_N > 0) {
          const topCandidates = driverScores.slice(0, TOP_N);
          try {
            const destinations = [order.restaurantLocation];
            const driverLocs = topCandidates.map(d => d.driverLocation);
            const routePromises = driverLocs.map(loc =>
              _getRouteDataSingle(loc, order.restaurantLocation)
            );
            const routeResults = await Promise.all(routePromises);
            for (let ri = 0; ri < topCandidates.length; ri++) {
              const route = routeResults[ri];
              topCandidates[ri].routingSource = route.isFallback ? 'haversine' : 'google_distance_matrix';
              topCandidates[ri].compositeScore = calculateCompositeScore({
                eta: route.durationMinutes,
                mlAcceptanceProbability: topCandidates[ri].mlAcceptanceProbability,
                fairnessScore: topCandidates[ri].fairnessScore,
                headingMatch: topCandidates[ri].headingMatch,
                currentOrders: topCandidates[ri].activeOrders || 0,
                restaurantPrepMinutes: prepMinutes,
              });
              topCandidates[ri].eta = route.durationMinutes;
              topCandidates[ri].distance = route.roadDistanceKm;
            }
            topCandidates.sort((a, b) => a.compositeScore - b.compositeScore);
            driverScores.splice(0, TOP_N, ...topCandidates);
          } catch (routeErr) {
            console.warn('[AI AutoDispatcher] Road-network refinement failed, using Haversine:', routeErr.message || routeErr);
          }
        }

        const bestDriver = driverScores[0];
        
        console.log(`[AI AutoDispatcher] Best rider assigned by AI for order ${orderId}:`, {
          driverId: bestDriver.driverId,
          driverName: bestDriver.driverName,
          eta: bestDriver.eta,
          routingSource: bestDriver.routingSource || 'haversine',
          mlAcceptanceProbability: bestDriver.mlAcceptanceProbability,
          fairnessScore: bestDriver.fairnessScore,
          compositeScore: bestDriver.compositeScore
        });

        // 5. Assign rider to order using AI prescription (LalaGo-Restaurant pattern)
        const riderTimeoutSec = await _getRiderTimeoutSeconds();
        const riderDeadline = _addSeconds(_nowTimestamp(), riderTimeoutSec);
        await change.after.ref.update({
          driverID: bestDriver.driverId,
          driverDistance: bestDriver.distance,
          assignedDriverName: bestDriver.driverName,
          estimatedETA: bestDriver.eta,
          status: 'Driver Assigned',
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
          dispatchStatus: 'success',
          dispatchMethod: 'AI Auto-Dispatch',
          'dispatch.lock': false,
          'dispatch.riderAcceptDeadline': riderDeadline,
          'dispatch.attemptCount': admin.firestore.FieldValue.increment(1),
          dispatchMetrics: {
            eta: bestDriver.eta,
            distance: bestDriver.distance,
            mlAcceptanceProbability: bestDriver.mlAcceptanceProbability,
            fairnessScore: bestDriver.fairnessScore,
            compositeScore: bestDriver.compositeScore,
            alternativeDriversCount: driverScores.length - 1
          }
        });

        // 6. Update driver status
        const driverRef = getDb().collection('users').doc(bestDriver.driverId);
        const driverSnap = await driverRef.get();
        const driverDataForStatus = driverSnap.exists ? driverSnap.data() : {};
        const updatedDriverData = {
          ...driverDataForStatus,
          inProgressOrderID: [
            ...(driverDataForStatus.inProgressOrderID || []),
            orderId,
          ],
        };
        const { riderAvailability: newAvail, riderDisplayStatus: newDisplay } =
          _computeRiderStatus(updatedDriverData);
        await driverRef.update({
          isActive: false,
          inProgressOrderID: admin.firestore.FieldValue.arrayUnion(orderId),
          lastAssignedAt: admin.firestore.FieldValue.serverTimestamp(),
          riderAvailability: newAvail,
          riderDisplayStatus: newDisplay,
        });

        // 7. Send FCM notification to rider
        if (bestDriver.fcmToken) {
          try {
            await getMessaging().send({
              token: bestDriver.fcmToken,
              notification: {
                title: 'New Order Assignment (AI Auto-Dispatch)',
                body: `You have been automatically assigned order #${orderId.substring(0, 8)} by AI. ETA: ${Math.round(bestDriver.eta)} mins`
              },
              data: {
                orderId: orderId,
                type: 'order_assignment',
                dispatchMethod: 'AI Auto-Dispatch',
                eta: bestDriver.eta.toString(),
                restaurantLat: order.restaurantLocation.lat.toString(),
                restaurantLng: order.restaurantLocation.lng.toString(),
                deliveryLat: order.deliveryLocation.lat.toString(),
                deliveryLng: order.deliveryLocation.lng.toString()
              }
            });
            console.log(`[AI AutoDispatcher] FCM sent to rider ${bestDriver.driverId}`);
          } catch (fcmError) {
            console.error(`[AI AutoDispatcher] FCM error for rider ${bestDriver.driverId}:`, fcmError);
          }
        }

        // 8. Log to assignments_log
        await getDb().collection('assignments_log').add({
          orderId: orderId,
          driverId: bestDriver.driverId,
          driverName: bestDriver.driverName,
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
          metrics: {
            eta: bestDriver.eta,
            mlAcceptanceProbability: bestDriver.mlAcceptanceProbability,
            fairnessScore: bestDriver.fairnessScore,
            compositeScore: bestDriver.compositeScore
          },
          allDriverScores: driverScores.map(d => ({
            driverId: d.driverId,
            driverName: d.driverName,
            eta: d.eta,
            mlAcceptanceProbability: d.mlAcceptanceProbability,
            fairnessScore: d.fairnessScore,
            compositeScore: d.compositeScore
          })),
          assignmentMethod: 'AI Auto-Dispatch',
          restaurantLocation: order.restaurantLocation,
          deliveryLocation: order.deliveryLocation
        });

        // Phase 4: Enhanced dispatch event logging
        await _logDispatchEvent({
          type: 'auto_dispatch_assigned',
          orderId,
          riderId: bestDriver.driverId,
          factors: {
            distanceKm: bestDriver.distance || 0,
            etaMinutes: bestDriver.eta,
            riderCurrentOrders: _activeOrdersCount(
              driversSnapshot.docs.find((d) => d.id === bestDriver.driverId)?.data() || {},
            ),
            riderHeadingMatch: bestDriver.headingMatch || 0,
            predictedAcceptanceProb: bestDriver.mlAcceptanceProbability,
            restaurantPrepMinutes: prepMinutes,
            zoneId: afterData?.zoneId || afterData?.vendorID || '',
            routingSource: bestDriver.routingSource || 'haversine',
          },
          totalScore: bestDriver.compositeScore,
          scoringComponents: {
            eta: bestDriver.eta,
            fairness: bestDriver.fairnessScore,
            headingMatch: bestDriver.headingMatch,
            acceptance: bestDriver.mlAcceptanceProbability,
          },
          alternativeRiders: driverScores.slice(1, 6).map((d) => ({
            riderId: d.driverId,
            score: d.compositeScore,
            distance: d.distance,
          })),
          activeWeights: {
            weightETA: weights.weightETA,
            weightWorkload: weights.weightWorkload,
            weightDirection: weights.weightDirection,
            weightAcceptanceProb: weights.weightAcceptanceProb,
            weightFairness: weights.weightFairness,
          },
        });

        console.log(`[AI AutoDispatcher] Successfully dispatched order ${orderId} to rider ${bestDriver.driverId} using AI prescription`);
        return { success: true, driverId: bestDriver.driverId };

      } catch (error) {
        console.error(`[AI AutoDispatcher] Error processing order ${orderId}:`, error);
        
        // Release dispatch lock on error
        await change.after.ref.update({
          status: 'Order Accepted',
          dispatchStatus: 'error',
          dispatchError: error.message,
          'dispatch.lock': false,
          dispatchAttemptedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return { success: false, error: error.message };
      }
    }

    return null;
  });

// =========================
// placeOrderWithDispatch - Unified order placement with atomic driver check
// =========================

const IDEMPOTENCY_TTL_HOURS = 24;

/**
 * Check if a restaurant is open based on working hours and reststatus.
 * Replicates Customer app restaurant_processing logic.
 */
function _checkRestaurantOpen(vendorData) {
  if (!vendorData || vendorData.reststatus !== true) return false;
  const workingHours = vendorData.workingHours || [];
  // Restaurant workingHours are stored in local PH time.
  const now = new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Manila' }));
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const day = dayNames[now.getDay()];
  const nowMinutes = now.getHours() * 60 + now.getMinutes();

  for (const wh of workingHours) {
    if (String(wh.day || '').trim() !== day) continue;
    const timeslots = wh.timeslot || [];
    for (const slot of timeslots) {
      const fromStr = (slot.from || slot.from || '00:00').toString().trim();
      const toStr = (slot.to || slot.to || '23:59').toString().trim();
      try {
        const [fromH, fromM] = fromStr.split(':').map(Number);
        const [toH, toM] = toStr.split(':').map(Number);
        const fromMinutes = (fromH || 0) * 60 + (fromM || 0);
        const toMinutes = (toH || 23) * 60 + (toM || 59);

        // Normal slot (e.g. 09:00-18:00)
        if (fromMinutes <= toMinutes) {
          if (nowMinutes >= fromMinutes && nowMinutes <= toMinutes) {
            return true;
          }
        } else {
          // Overnight slot (e.g. 22:00-02:00)
          if (nowMinutes >= fromMinutes || nowMinutes <= toMinutes) {
            return true;
          }
        }
      } catch (_) { /* skip invalid slot */ }
    }
  }
  return false;
}

/**
 * Convert client-serialized data for Firestore (Timestamps, etc.)
 */
function _normalizeOrderForFirestore(orderPayload) {
  const out = { ...orderPayload };
  if (out.createdAt && typeof out.createdAt === 'object') {
    if (out.createdAt._seconds != null) {
      out.createdAt = new admin.firestore.Timestamp(
        out.createdAt._seconds,
        out.createdAt._nanoseconds || 0
      );
    } else {
      out.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }
  } else {
    out.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }
  if (out.scheduleTime && typeof out.scheduleTime === 'object' && out.scheduleTime._seconds != null) {
    out.scheduleTime = new admin.firestore.Timestamp(
      out.scheduleTime._seconds,
      out.scheduleTime._nanoseconds || 0
    );
  }
  return out;
}

/**
 * placeOrderWithDispatch: Single source of truth for order creation + driver assignment.
 * Returns { success, orderId?, driverAssigned?, code?, message? }
 */
exports.placeOrderWithDispatch = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 60, memory: '512MB' })
  .https.onCall(async (data, context) => {
    const customerId = context.auth?.uid;
    const idempotencyKey = (data?.idempotencyKey || '').toString().trim();
    const orderPayload = data?.order;

    if (!customerId) {
      console.log('[placeOrderWithDispatch] Unauthenticated request');
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Login required to place an order'
      );
    }

    // 1. Idempotency check (before any validation or writes)
    const db = getDb();
    if (idempotencyKey) {
      const idemRef = db.collection('idempotency_keys').doc(idempotencyKey);
      const idemSnap = await idemRef.get();
      if (idemSnap.exists) {
        const stored = idemSnap.data()?.result;
        if (stored) {
          console.log('[placeOrderWithDispatch] Idempotent return for key:', idempotencyKey);
          return stored;
        }
      }
    }

    if (!orderPayload || typeof orderPayload !== 'object') {
      const err = { success: false, code: 'VALIDATION_ERROR', message: 'Invalid order payload' };
      console.log('[placeOrderWithDispatch] Validation failed: missing order');
      return err;
    }

    const vendorId = orderPayload.vendorID || orderPayload.vendor?.id || '';
    const deliveryLat = _asNumber(orderPayload.address?.location?.latitude) ||
      _asNumber(orderPayload.author?.location?.latitude);
    const deliveryLng = _asNumber(orderPayload.address?.location?.longitude) ||
      _asNumber(orderPayload.author?.location?.longitude);
    const orderTotal = _asNumber(orderPayload.totalAmount) || _asNumber(orderPayload.total) || 0;

    console.log('[placeOrderWithDispatch] customerId=', customerId, 'vendorId=', vendorId,
      'orderTotal=', orderTotal);

    // 2. Restaurant open check
    const vendorSnap = await db.collection('vendors').doc(vendorId).get();
    if (!vendorSnap.exists) {
      const err = {
        success: false,
        code: 'VALIDATION_ERROR',
        message: 'Restaurant not found',
      };
      console.log('[placeOrderWithDispatch] Restaurant not found:', vendorId);
      return err;
    }
    const vendorData = vendorSnap.data() || {};
    if (!_checkRestaurantOpen(vendorData)) {
      const err = {
        success: false,
        code: 'RESTAURANT_CLOSED',
        message: 'The restaurant is currently closed. Please try during operating hours.',
      };
      console.log('[placeOrderWithDispatch] Restaurant closed:', vendorId);
      return err;
    }

    // 3. Zone capacity check
    if (deliveryLat && deliveryLng) {
      const capCheck = await _checkZoneCapacity(deliveryLat, deliveryLng);
      if (capCheck.atCapacity) {
        const err = {
          success: false,
          code: 'ZONE_AT_CAPACITY',
          message: 'Delivery area is at full capacity. Please try again in a few minutes.',
        };
        console.log('[placeOrderWithDispatch] Zone at capacity:',
          capCheck.zoneName, capCheck.currentCount, '/', capCheck.maxRiders);
        return err;
      }
    }

    // Read bypass rider check setting
    const dispatchSettingsSnap = await db.collection('config').doc('dispatch_settings').get();
    const dispatchSettings = dispatchSettingsSnap.exists ? dispatchSettingsSnap.data() : {};
    const bypassRiderCheck = dispatchSettings.bypassRiderCheck === true;

    // 4. Build order context for driver selection
    const restaurantLocation = _extractRestaurantLocation(orderPayload);
    const deliveryLocation = {
      lat: deliveryLat || 0,
      lng: deliveryLng || 0,
    };
    const orderForDispatch = {
      id: null,
      ...orderPayload,
      restaurantLocation,
      deliveryLocation,
      vendorID: vendorId,
    };

    // 5. Find best driver (skip if bypass is active)
    let bestDriver = null;
    if (!bypassRiderCheck) {
      const searchRadiusKm = 3;
      const driversSnapshot = await db.collection('users')
        .where('role', '==', 'driver')
        .get();

      if (!driversSnapshot.empty) {
        const weights = await _loadDispatchWeights();
        const eligibleDrivers = [];
        for (const driverDoc of driversSnapshot.docs) {
          const driver = { id: driverDoc.id, ...driverDoc.data() };
          if (!_isDriverEligibleBase(driver)) continue;
          const driverLocation = _extractDriverLocation(driver);
          if (!driverLocation.lat && !driverLocation.lng) continue;
          const activeOrders = _activeOrdersCount(driver);
          const effectiveCap = _calculateDynamicCapacity(driver, weights);
          if (activeOrders >= effectiveCap) continue;
          const distanceKm = _distanceMeters(driverLocation, restaurantLocation) / 1000;
          if (distanceKm > searchRadiusKm) continue;
          const eta = calculateETA(driverLocation, restaurantLocation);
          const headingMatch = _calculateDriverHeading(driver, driverLocation, restaurantLocation);
          eligibleDrivers.push({
            driver,
            driverLocation,
            activeOrders,
            effectiveCap,
            eta,
            distanceKm,
            headingMatch,
          });
        }

        if (eligibleDrivers.length > 0) {
          const eligibleIds = eligibleDrivers.map(d => d.driver.id);
          const [batchBaseRates, batchFairness] = await Promise.all([
            getMLAcceptanceProbabilityBatch(eligibleIds),
            Promise.resolve(calculateFairnessScoreBatch(eligibleDrivers.map(d => d.driver))),
          ]);
          const hour = new Date().getHours();
          const timeBonus = (hour >= 10 && hour <= 21) ? 0.05 : 0;

          let bestScore = Infinity;
          for (const e of eligibleDrivers) {
            const baseRate = batchBaseRates[e.driver.id] || 0.7;
            const distancePenalty = Math.min(e.eta / 60, 0.3);
            const workloadPenalty = e.activeOrders * 0.15;
            const mlAcceptanceProbability = Math.max(0.05, Math.min(0.95,
              baseRate - distancePenalty - workloadPenalty + timeBonus
            ));
            const fairnessScore = batchFairness[e.driver.id] || 50;
            const compositeScore = calculateCompositeScore({
              eta: e.eta,
              mlAcceptanceProbability,
              effectiveCapacity: e.effectiveCap,
              fairnessScore,
              headingMatch: e.headingMatch,
              currentOrders: e.activeOrders,
              restaurantPrepMinutes: 0,
            });
            if (compositeScore < bestScore) {
              bestScore = compositeScore;
              bestDriver = {
                driverId: e.driver.id,
                driverName: `${e.driver.firstName || ''} ${e.driver.lastName || ''}`.trim(),
                fcmToken: e.driver.fcmToken,
                driverLocation: e.driverLocation,
                eta: e.eta,
                distance: e.distanceKm,
              };
            }
          }
        }
      }

      console.log('[placeOrderWithDispatch] Drivers considered:', driversSnapshot.size,
        'bestDriver:', bestDriver ? bestDriver.driverId : 'none');
    } else {
      console.log('[placeOrderWithDispatch] Bypass active – skipping driver search');
    }

    if (!bypassRiderCheck && !bestDriver) {
      console.log('[placeOrderWithDispatch] No drivers, bypass off – returning NO_DRIVERS_AVAILABLE');
      return {
        success: false,
        code: 'NO_DRIVERS_AVAILABLE',
        message: 'No delivery partners are available right now. Please try again in a few minutes.',
      };
    }

    // 6. Atomic transaction: create order and optionally assign driver
    const orderRef = db.collection('restaurant_orders').doc();
    const orderId = orderRef.id;

    const orderData = _normalizeOrderForFirestore({
      ...orderPayload,
      id: orderId,
      status: 'Order Placed',
      authorID: customerId,
    });

    if (bestDriver) {
      orderData.driverID = bestDriver.driverId;
      orderData.assignedDriverName = bestDriver.driverName;
      orderData.driverDistance = bestDriver.distance;
      orderData.estimatedETA = bestDriver.eta;
      orderData.dispatchStatus = 'success';
      orderData.placementMethod = 'placeOrderWithDispatch';
    } else {
      orderData.dispatchStatus = 'no_drivers_at_placement';
      orderData.placementMethod = 'placeOrderWithDispatch';
      if (bypassRiderCheck) {
        orderData.bypassedDriverCheck = true;
        console.log('[placeOrderWithDispatch] Bypass active – order created without driver: ' + orderId);
      }
    }

    try {
      await db.runTransaction(async (tx) => {
        if (bestDriver) {
          const driverRef = db.collection('users').doc(bestDriver.driverId);
          const driverSnap = await tx.get(driverRef);
          if (!driverSnap.exists) throw new Error('DRIVER_NOT_FOUND');
          const d = driverSnap.data() || {};
          if (d.riderAvailability !== 'available') throw new Error('DRIVER_TAKEN');
          const activeOrders = _activeOrdersCount(d);
          const weights = await _loadDispatchWeights();
          const cap = _calculateDynamicCapacity(d, weights);
          if (activeOrders >= cap) throw new Error('DRIVER_TAKEN');

          tx.set(orderRef, orderData);
          tx.update(driverRef, {
            inProgressOrderID: admin.firestore.FieldValue.arrayUnion(orderId),
            lastAssignedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          const updatedData = {
            ...d,
            inProgressOrderID: [...(d.inProgressOrderID || []), orderId],
          };
          const { riderAvailability, riderDisplayStatus } = _computeRiderStatus(updatedData, weights);
          tx.update(driverRef, { riderAvailability, riderDisplayStatus });
        } else {
          tx.set(orderRef, orderData);
        }
      });

      const driverAssigned = !!bestDriver;
      const result = {
        success: true,
        orderId,
        driverAssigned,
      };

      if (driverAssigned && bestDriver?.fcmToken) {
        try {
          await getMessaging().send({
            token: bestDriver.fcmToken,
            notification: {
              title: 'New Order Assigned (Place Order)',
              body: `Order #${orderId.substring(0, 8)} assigned. ETA: ${Math.round(bestDriver.eta)} mins`,
            },
            data: {
              orderId,
              type: 'order_assignment',
              eta: String(bestDriver.eta),
              restaurantLat: String(restaurantLocation.lat),
              restaurantLng: String(restaurantLocation.lng),
              deliveryLat: String(deliveryLocation.lat),
              deliveryLng: String(deliveryLocation.lng),
            },
          });
        } catch (fcmErr) {
          console.warn('[placeOrderWithDispatch] FCM error:', fcmErr.message);
        }
      }

      if (idempotencyKey) {
        const expireAt = new Date();
        expireAt.setHours(expireAt.getHours() + IDEMPOTENCY_TTL_HOURS);
        await db.collection('idempotency_keys').doc(idempotencyKey).set({
          orderId,
          result,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: admin.firestore.Timestamp.fromDate(expireAt),
        });
      }

      console.log('[placeOrderWithDispatch] Success orderId=', orderId, 'driverAssigned=', driverAssigned);
      return result;
    } catch (txErr) {
      const msg = txErr.message || '';
      if (msg === 'DRIVER_TAKEN' || msg === 'DRIVER_NOT_FOUND') {
        const err = {
          success: false,
          code: 'NO_DRIVERS_AVAILABLE',
          message: 'No delivery partners are available right now. Please try again in a few minutes.',
        };
        console.log('[placeOrderWithDispatch] Driver taken/not found, returning NO_DRIVERS_AVAILABLE');
        return err;
      }
      console.error('[placeOrderWithDispatch] Transaction error:', txErr);
      return {
        success: false,
        code: 'VALIDATION_ERROR',
        message: 'Failed to create order. Please try again.',
      };
    }
  });

// =========================
// PAUTOS Dispatcher
// =========================

const PAUTOS_ORDERS = 'pautos_orders';
const PAUTOS_RIDER_TIMEOUT_SEC = 60;

/**
 * Get assignedDriverIds for the zone containing delivery location.
 * Returns { driverIds, zoneId } or null if no zone matches.
 */
async function _getPautosZoneDriverIds(deliveryLat, deliveryLng) {
  const db = getDb();
  const zonesSnap = await db.collection('service_areas').get();
  if (zonesSnap.empty) return null;
  for (const doc of zonesSnap.docs) {
    const z = doc.data();
    const ids = z.assignedDriverIds || [];
    if (!ids.length) continue;
    if (z.boundaryType === 'radius') {
      const cLat = _asNumber(z.centerLat);
      const cLng = _asNumber(z.centerLng);
      const rKm = _asNumber(z.radiusKm);
      if (!cLat || !cLng || rKm <= 0) continue;
      if (!deliveryLat || !deliveryLng) continue;
      const dist = _distanceMeters(
        { lat: cLat, lng: cLng },
        { lat: deliveryLat, lng: deliveryLng },
      );
      if (dist <= rKm * 1000) {
        return { driverIds: ids, zoneId: doc.id };
      }
    }
  }
  return null;
}

function _extractPautosDeliveryLocation(data) {
  const addr = data?.address;
  if (!addr || !addr.location) return { lat: 0, lng: 0 };
  return {
    lat: _asNumber(addr.location.latitude),
    lng: _asNumber(addr.location.longitude),
  };
}

/**
 * PAUTOS Dispatcher: assigns rider when pautos_orders doc is created with status Request Posted.
 */
exports.pautosDispatcher = functions
  .region('us-central1')
  .firestore.document(`${PAUTOS_ORDERS}/{orderId}`)
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const data = snap.data() || {};
    const status = String(data.status || '');
    if (status !== 'Request Posted') {
      console.log(`[PAUTOS Dispatcher] Skipping ${orderId}: status=${status}`);
      return null;
    }
    if (data.driverID) {
      console.log(`[PAUTOS Dispatcher] Skipping ${orderId}: already has driver`);
      return null;
    }

    try {
      const db = getDb();
      const deliveryLoc = _extractPautosDeliveryLocation(data);
      if (!deliveryLoc.lat && !deliveryLoc.lng) {
        console.log(`[PAUTOS Dispatcher] No delivery location for ${orderId}`);
        return null;
      }

      const zoneMatch = await _getPautosZoneDriverIds(deliveryLoc.lat, deliveryLoc.lng);
      const zoneDriverIds = zoneMatch ? zoneMatch.driverIds : null;

      const driversSnap = await db.collection('users')
        .where('role', '==', 'driver')
        .get();

      const excludedIds = new Set(data?.dispatch?.excludedDriverIds || []);
      const driverScores = [];

      for (const doc of driversSnap.docs) {
        const driver = { id: doc.id, ...doc.data() };
        if (excludedIds.has(driver.id)) continue;
        if (driver.pautosEligible === false) continue;
        if (!_isDriverEligibleBase(driver)) continue;
        if (driver.suspended === true) continue;

        if (zoneDriverIds && zoneDriverIds.length > 0) {
          if (!zoneDriverIds.includes(driver.id)) continue;
        }

        const activeOrders = _activeOrdersCount(driver);
        if (activeOrders >= MAX_ACTIVE_ORDERS_PER_RIDER) continue;

        const driverLoc = _extractDriverLocation(driver);
        if (!driverLoc.lat && !driverLoc.lng) continue;

        const distanceKm = _distanceMeters(driverLoc, deliveryLoc) / 1000;
        const completedToday = _asNumber(driver.completedToday) || 0;
        const fairnessScore = 100 - Math.min(completedToday * 5, 50);
        const score = distanceKm * 2 + (100 - fairnessScore) * 0.1 + activeOrders * 3;

        driverScores.push({
          driverId: driver.id,
          driverName: `${driver.firstName || ''} ${driver.lastName || ''}`.trim(),
          fcmToken: driver.fcmToken || driver.fcmTokens?.[0],
          phoneNumber: driver.phoneNumber || '',
          distance: distanceKm,
          score,
        });
      }

      if (driverScores.length === 0) {
        console.log(`[PAUTOS Dispatcher] No eligible riders for ${orderId}`);
        await snap.ref.update({
          dispatchStatus: 'no_drivers_available',
          dispatchAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return null;
      }

      driverScores.sort((a, b) => a.score - b.score);
      const best = driverScores[0];
      const riderDeadline = _addSeconds(_nowTimestamp(), PAUTOS_RIDER_TIMEOUT_SEC);

      await db.runTransaction(async (tx) => {
        const orderSnap = await tx.get(snap.ref);
        const current = orderSnap.data() || {};
        if (current.driverID) throw new Error('Order already assigned');
        tx.update(snap.ref, {
          driverID: best.driverId,
          driverName: best.driverName,
          driverPhone: best.phoneNumber || '',
          status: 'Driver Assigned',
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
          assignmentMethod: 'dispatcher',
          'dispatch.riderAcceptDeadline': riderDeadline,
          'dispatch.excludedDriverIds': [],
          dispatchStatus: 'success',
        });
        const driverRef = db.collection('users').doc(best.driverId);
        tx.update(driverRef, {
          pautosOrderRequestData: admin.firestore.FieldValue.arrayUnion(orderId),
        });
      });

      const shoppingPreview = (data.shoppingList || '').toString().substring(0, 80);
      if (best.fcmToken) {
        try {
          await getMessaging().send({
            token: best.fcmToken,
            notification: {
              title: 'New PAUTOS Assignment',
              body: shoppingPreview || `Shopping request. Budget: ${data.maxBudget || ''}`,
            },
            data: {
              type: 'pautos_assignment',
              orderId: String(orderId),
            },
          });
          console.log(`[PAUTOS Dispatcher] FCM sent to rider ${best.driverId}`);
        } catch (fcmErr) {
          console.error(`[PAUTOS Dispatcher] FCM error:`, fcmErr);
        }
      }

      await db.collection('pautos_assignments_log').add({
        orderId,
        driverId: best.driverId,
        driverName: best.driverName,
        assignedAt: admin.firestore.FieldValue.serverTimestamp(),
        assignmentMethod: 'dispatcher',
        deliveryLat: deliveryLoc.lat,
        deliveryLng: deliveryLoc.lng,
      });

      console.log(`[PAUTOS Dispatcher] Assigned ${orderId} to ${best.driverId}`);
      return { success: true, driverId: best.driverId };
    } catch (err) {
      console.error(`[PAUTOS Dispatcher] Error:`, err);
      return null;
    }
  });

/**
 * Callable: reject PAUTOS assignment and re-assign to next rider.
 */
exports.pautosRejectAndReassign = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');
    const { orderId, reason } = data || {};
    if (!orderId || typeof orderId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    const riderId = context.auth.uid;
    const db = getDb();
    const orderRef = db.collection(PAUTOS_ORDERS).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new functions.https.HttpsError('not-found', 'Order not found');
    const orderData = orderSnap.data() || {};
    if (orderData.driverID !== riderId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your assignment');
    }
    if (orderData.status !== 'Driver Assigned') {
      throw new functions.https.HttpsError('failed-precondition', 'Order not pending acceptance');
    }

    const excludedIds = [...(orderData.dispatch?.excludedDriverIds || []), riderId];
    await db.runTransaction(async (tx) => {
      tx.update(orderRef, {
        driverID: admin.firestore.FieldValue.delete(),
        driverName: admin.firestore.FieldValue.delete(),
        driverPhone: admin.firestore.FieldValue.delete(),
        status: 'Request Posted',
        'dispatch.excludedDriverIds': excludedIds,
      });
      const riderRef = db.collection('users').doc(riderId);
      tx.update(riderRef, {
        pautosOrderRequestData: admin.firestore.FieldValue.arrayRemove(orderId),
      });
    });

    const deliveryLoc = _extractPautosDeliveryLocation(orderData);
    const zoneMatch = await _getPautosZoneDriverIds(deliveryLoc.lat, deliveryLoc.lng);
    const zoneDriverIds = zoneMatch ? zoneMatch.driverIds : null;

    const driversSnap = await db.collection('users').where('role', '==', 'driver').get();
    const excludeSet = new Set(excludedIds);
    const driverScores = [];

    for (const doc of driversSnap.docs) {
      const driver = { id: doc.id, ...doc.data() };
      if (excludeSet.has(driver.id)) continue;
      if (driver.pautosEligible === false) continue;
      if (!_isDriverEligibleBase(driver)) continue;

      if (zoneDriverIds && zoneDriverIds.length > 0 && !zoneDriverIds.includes(driver.id)) continue;

      const activeOrders = _activeOrdersCount(driver);
      if (activeOrders >= MAX_ACTIVE_ORDERS_PER_RIDER) continue;

      const driverLoc = _extractDriverLocation(driver);
      if (!driverLoc.lat && !driverLoc.lng) continue;

      const distanceKm = _distanceMeters(driverLoc, deliveryLoc) / 1000;
      const completedToday = _asNumber(driver.completedToday) || 0;
      const fairnessScore = 100 - Math.min(completedToday * 5, 50);
      driverScores.push({
        driverId: driver.id,
        driverName: `${driver.firstName || ''} ${driver.lastName || ''}`.trim(),
        fcmToken: driver.fcmToken || driver.fcmTokens?.[0],
        phoneNumber: driver.phoneNumber || '',
        distance: distanceKm,
        score: distanceKm * 2 + (100 - fairnessScore) * 0.1 + activeOrders * 3,
      });
    }

    if (driverScores.length > 0) {
      driverScores.sort((a, b) => a.score - b.score);
      const best = driverScores[0];
      const riderDeadline = _addSeconds(_nowTimestamp(), PAUTOS_RIDER_TIMEOUT_SEC);
      await orderRef.update({
        driverID: best.driverId,
        driverName: best.driverName,
        driverPhone: best.phoneNumber || '',
        status: 'Driver Assigned',
        assignedAt: admin.firestore.FieldValue.serverTimestamp(),
        assignmentMethod: 'dispatcher',
        'dispatch.riderAcceptDeadline': riderDeadline,
        'dispatch.excludedDriverIds': excludedIds,
      });
      await db.collection('users').doc(best.driverId).update({
        pautosOrderRequestData: admin.firestore.FieldValue.arrayUnion(orderId),
      });
      const shoppingPreview = (orderData.shoppingList || '').toString().substring(0, 80);
      if (best.fcmToken) {
        try {
          await getMessaging().send({
            token: best.fcmToken,
            notification: {
              title: 'New PAUTOS Assignment',
              body: shoppingPreview || `Shopping request`,
            },
            data: { type: 'pautos_assignment', orderId: String(orderId) },
          });
        } catch (e) { console.error('[PAUTOS] FCM error:', e); }
      }
    }

    return { success: true };
  });

/**
 * Callable: Admin manual PAUTOS assignment. Assigns a specific rider to a
 * PAUTOS order. Requires auth (admin only - caller should enforce).
 */
exports.pautosManualAssign = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');
    const { orderId, driverId } = data || {};
    if (!orderId || typeof orderId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    if (!driverId || typeof driverId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'driverId required');
    }
    const db = getDb();
    const orderRef = db.collection(PAUTOS_ORDERS).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new functions.https.HttpsError('not-found', 'Order not found');
    const orderData = orderSnap.data() || {};
    if (orderData.driverID) {
      throw new functions.https.HttpsError('failed-precondition', 'Order already assigned');
    }
    if (orderData.status !== 'Request Posted') {
      throw new functions.https.HttpsError('failed-precondition', 'Order not in Request Posted status');
    }

    const riderSnap = await db.collection('users').doc(driverId).get();
    if (!riderSnap.exists) throw new functions.https.HttpsError('not-found', 'Driver not found');
    const rider = riderSnap.data() || {};
    const riderName = `${rider.firstName || ''} ${rider.lastName || ''}`.trim() || 'Rider';
    const riderPhone = rider.phoneNumber || '';
    const fcmToken = rider.fcmToken || rider.fcmTokens?.[0];

    const riderDeadline = _addSeconds(_nowTimestamp(), PAUTOS_RIDER_TIMEOUT_SEC);
    await orderRef.update({
      driverID: driverId,
      driverName: riderName,
      driverPhone: riderPhone,
      status: 'Driver Assigned',
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      assignmentMethod: 'manual',
      'dispatch.riderAcceptDeadline': riderDeadline,
    });
    await db.collection('users').doc(driverId).update({
      pautosOrderRequestData: admin.firestore.FieldValue.arrayUnion(orderId),
    });

    const shoppingPreview = (orderData.shoppingList || '').toString().substring(0, 80);
    if (fcmToken) {
      try {
        await getMessaging().send({
          token: fcmToken,
          notification: { title: 'New PAUTOS Assignment', body: shoppingPreview || 'Shopping request' },
          data: { type: 'pautos_assignment', orderId: String(orderId) },
        });
      } catch (e) { console.error('[PAUTOS] FCM error:', e); }
    }

    await db.collection('pautos_assignments_log').add({
      orderId,
      driverId,
      status: 'manual_assigned',
      assignmentMethod: 'manual',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  });

/**
 * PAUTOS Compute Billing: Firestore trigger when actualItemCost is set and totalAmount is not.
 * Computes deliveryFee, serviceFee, totalAmount from PAUTOS_SETTINGS and New_DeliveryCharge.
 */
exports.pautosComputeBilling = functions
  .region('us-central1')
  .firestore.document(`${PAUTOS_ORDERS}/{orderId}`)
  .onUpdate(async (change, context) => {
    const orderId = context.params.orderId;
    const after = change.after.data() || {};
    const actualItemCost = _asNumber(after.actualItemCost);
    const totalAmount = after.totalAmount;
    if (actualItemCost <= 0 || totalAmount != null) return null;

    try {
      const db = getDb();
      const pautosSnap = await db.collection('settings').doc('PAUTOS_SETTINGS').get();
      const pautosData = pautosSnap.exists ? pautosSnap.data() : {};
      const serviceFeePercent = _asNumber(pautosData.serviceFeePercent) || 10;
      const useDistanceDeliveryFee = pautosData.useDistanceDeliveryFee !== false;
      const flatDeliveryFee = _asNumber(pautosData.flatDeliveryFee) || 0;

      let deliveryFee = 0;
      if (useDistanceDeliveryFee) {
        const pautosBase = _asNumber(pautosData.deliveryBaseFee);
        const pautosPerKm = _asNumber(pautosData.deliveryPerKm);
        const pautosMinKm = _asNumber(pautosData.minimumDistanceKm);
        let baseCharge, perKm, thresholdKm;
        if (pautosBase > 0 || pautosPerKm > 0) {
          baseCharge = pautosBase || 0;
          perKm = pautosPerKm || 0;
          thresholdKm = pautosMinKm > 0 ? pautosMinKm : 1;
        } else {
          const deliverySnap = await db.collection('settings').doc('New_DeliveryCharge').get();
          const fallbackSnap = await db.collection('settings').doc('DeliveryCharge').get();
          const deliveryData = (deliverySnap.exists ? deliverySnap.data() : null) ||
            (fallbackSnap.exists ? fallbackSnap.data() : null) || {};
          baseCharge = _asNumber(deliveryData.baseDeliveryCharge) ||
            _asNumber(deliveryData.base_delivery_charge) || 0;
          perKm = _asNumber(deliveryData.deliveryChargePerKm) ||
            _asNumber(deliveryData.delivery_charge_per_km) || 0;
          thresholdKm = _asNumber(deliveryData.minimumDistanceKm) ||
            _asNumber(deliveryData.minimum_distance_km) || 1;
        }

        const deliveryLoc = _extractPautosDeliveryLocation(after);
        let distanceKm = 3;
        const driverId = after.driverID;
        if (driverId) {
          const driverSnap = await db.collection('users').doc(driverId).get();
          if (driverSnap.exists) {
            const loc = driverSnap.data()?.location;
            if (loc && (loc.latitude != null || loc.lat != null)) {
              const driverLat = _asNumber(loc.latitude ?? loc.lat);
              const driverLng = _asNumber(loc.longitude ?? loc.lng);
              if (driverLat || driverLng) {
                const distM = _distanceMeters(
                  { lat: driverLat, lng: driverLng },
                  { lat: deliveryLoc.lat || 0, lng: deliveryLoc.lng || 0 }
                );
                distanceKm = Math.max(0.1, distM / 1000);
              }
            }
          }
        }

        const effectiveThreshold = thresholdKm > 0 ? thresholdKm : 1;
        deliveryFee = distanceKm < effectiveThreshold
          ? baseCharge
          : baseCharge + (distanceKm * perKm);
        deliveryFee = Math.round(Math.max(0, deliveryFee) * 100) / 100;
      } else {
        deliveryFee = flatDeliveryFee;
      }

      const serviceFee = Math.round(actualItemCost * (serviceFeePercent / 100) * 100) / 100;
      const total = Math.round((actualItemCost + deliveryFee + serviceFee) * 100) / 100;

      await change.after.ref.update({
        deliveryFee,
        serviceFee,
        totalAmount: total,
      });
      console.log(`[PAUTOS Billing] ${orderId}: delivery=${deliveryFee}, service=${serviceFee}, total=${total}`);
    } catch (err) {
      console.error('[PAUTOS Billing] Error:', err);
    }
    return null;
  });

/**
 * PAUTOS Complete Order: Callable for rider to mark delivered and complete payment.
 * Validates driver, processes wallet deduct (if Wallet) and rider credit, updates status.
 */
exports.pautosCompleteOrder = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');
    const { orderId } = data || {};
    if (!orderId || typeof orderId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    const driverId = context.auth.uid;
    const db = getDb();
    const orderRef = db.collection(PAUTOS_ORDERS).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new functions.https.HttpsError('not-found', 'Order not found');
    const orderData = orderSnap.data() || {};
    if (orderData.driverID !== driverId) {
      throw new functions.https.HttpsError('permission-denied', 'Not your order');
    }
    if (orderData.status !== 'Delivering') {
      throw new functions.https.HttpsError('failed-precondition', 'Order must be Delivering');
    }

    const totalAmount = _asNumber(orderData.totalAmount);
    const actualItemCost = _asNumber(orderData.actualItemCost);
    const deliveryFee = _asNumber(orderData.deliveryFee);
    const serviceFee = _asNumber(orderData.serviceFee);
    const paymentMethod = String(orderData.paymentMethod || 'COD').toLowerCase();
    const authorID = orderData.authorID || '';

    if (totalAmount <= 0) {
      throw new functions.https.HttpsError('failed-precondition', 'Billing not yet computed');
    }

    if (paymentMethod === 'wallet') {
      const customerSnap = await db.collection('users').doc(authorID).get();
      if (!customerSnap.exists) throw new functions.https.HttpsError('not-found', 'Customer not found');
      const walletAmount = _asNumber(customerSnap.data()?.wallet_amount);
      if (walletAmount < totalAmount) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'INSUFFICIENT_WALLET_BALANCE'
        );
      }
    }

    const pautosSnap = await db.collection('settings').doc('PAUTOS_SETTINGS').get();
    const pautosData = pautosSnap.exists ? pautosSnap.data() : {};
    const overrideRiderPercent = _asNumber(pautosData.riderCommissionPercent);
    let platformCommissionPercent;
    if (overrideRiderPercent > 0 && overrideRiderPercent <= 100) {
      platformCommissionPercent = 100 - overrideRiderPercent;
    } else {
      const driverPerfSnap = await db.collection('settings').doc('driver_performance').get();
      const perfData = driverPerfSnap.exists ? driverPerfSnap.data() : {};
      const perfVal = _asNumber((await db.collection('users').doc(driverId).get()).data()?.driver_performance) || 75;
      const tier = perfVal >= 90 ? 'gold' : perfVal >= 75 ? 'silver' : 'bronze';
      const commKey = tier + '_commission_percent';
      platformCommissionPercent = _asNumber(perfData[commKey]) || 20;
    }
    const platformCommission = Math.round(deliveryFee * (platformCommissionPercent / 100) * 100) / 100;
    const riderEarning = Math.round((deliveryFee - platformCommission + actualItemCost) * 100) / 100;

    const customerRef = db.collection('users').doc(authorID);
    const driverRef = db.collection('users').doc(driverId);

    await db.runTransaction(async (tx) => {
      const freshOrder = await tx.get(orderRef);
      if (!freshOrder.exists) throw new Error('Order not found');
      const freshData = freshOrder.data() || {};
      if (freshData.status === 'Completed') throw new Error('ORDER_ALREADY_COMPLETED');
      if (freshData.driverID !== driverId) throw new Error('Not your order');

      if (paymentMethod === 'wallet') {
        const customerSnap = await tx.get(customerRef);
        if (!customerSnap.exists) throw new Error('Customer not found');
        const custData = customerSnap.data() || {};
        const walletAmount = _asNumber(custData.wallet_amount);
        if (walletAmount < totalAmount) throw new Error('INSUFFICIENT_WALLET_BALANCE');
        tx.update(customerRef, {
          wallet_amount: Math.round((walletAmount - totalAmount) * 100) / 100,
        });
        const walletRef = db.collection('wallet').doc();
        tx.set(walletRef, {
          user_id: authorID,
          order_id: orderId,
          amount: -totalAmount,
          date: admin.firestore.FieldValue.serverTimestamp(),
          payment_method: 'Wallet',
          payment_status: 'success',
          transactionUser: 'customer',
          isTopUp: false,
          walletType: 'amount',
          note: 'PAUTOS Order Payment',
        });
      }

      const driverSnap = await tx.get(driverRef);
      const driverData = driverSnap.exists ? driverSnap.data() : {};
      const currentEarning = _asNumber(driverData.wallet_amount);
      const currentCredit = _asNumber(driverData.wallet_credit);
      const newEarning = Math.round((currentEarning + riderEarning) * 100) / 100;
      const newCredit = Math.round((currentCredit + riderEarning) * 100) / 100;

      tx.update(driverRef, {
        wallet_amount: newEarning,
        wallet_credit: newCredit,
      });

      const creditLogRef = db.collection('wallet').doc();
      tx.set(creditLogRef, {
        user_id: driverId,
        order_id: orderId,
        amount: riderEarning,
        date: admin.firestore.FieldValue.serverTimestamp(),
        payment_method: paymentMethod === 'wallet' ? 'Wallet' : 'COD',
        payment_status: 'success',
        transactionUser: 'driver',
        isTopUp: true,
        walletType: 'credit',
        note: 'PAUTOS Delivery Credit',
      });

      tx.update(orderRef, {
        status: 'Completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    console.log(`[PAUTOS Complete] ${orderId} completed by ${driverId}`);
    return { success: true };
  });

async function _requirePautosAdmin(context) {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Must be signed in');
  const db = getDb();
  const callerDoc = await db.collection('users').doc(context.auth.uid).get();
  const role = (callerDoc.exists ? callerDoc.data() : {}).role || '';
  if (role !== 'admin' && role !== 'Admin') {
    throw new functions.https.HttpsError('permission-denied', 'Admin only');
  }
  return { uid: context.auth.uid, db };
}

/**
 * Callable: Get full PAUTOS order for admin dispute resolution.
 * Returns order, chat messages, substitution requests.
 */
exports.pautosGetOrderForAdmin = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const { uid, db } = await _requirePautosAdmin(context);
    const orderId = data?.orderId;
    if (!orderId || typeof orderId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    const orderRef = db.collection(PAUTOS_ORDERS).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }
    const order = { id: orderSnap.id, ...orderSnap.data() };

    const [chatSnap, subsSnap] = await Promise.all([
      db.collection('chat_driver').doc(orderId).collection('thread')
        .orderBy('createdAt', 'asc').get(),
      db.collection(PAUTOS_ORDERS).doc(orderId)
        .collection('substitution_requests').orderBy('createdAt', 'asc').get(),
    ]);

    const messages = chatSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const substitutions = subsSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

    return {
      order: _serializeForClient(order),
      messages,
      substitutions,
    };
  });

function _serializeForClient(obj) {
  if (obj == null) return obj;
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v && typeof v.toDate === 'function') {
      out[k] = { _seconds: v.seconds, _nanoseconds: v.nanoseconds };
    } else if (v && typeof v === 'object' && !Array.isArray(v)) {
      out[k] = _serializeForClient(v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

/**
 * Callable: Issue refund to customer for PAUTOS order. Admin-only.
 */
exports.pautosIssueRefund = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const { uid, db } = await _requirePautosAdmin(context);
    const { orderId, amount, reason } = data || {};
    if (!orderId || typeof orderId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    const amt = _asNumber(amount);
    if (amt <= 0) {
      throw new functions.https.HttpsError('invalid-argument', 'amount must be positive');
    }
    const orderSnap = await db.collection(PAUTOS_ORDERS).doc(orderId).get();
    if (!orderSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }
    const orderData = orderSnap.data() || {};
    const authorID = orderData.authorID || '';
    const callerDoc = await db.collection('users').doc(uid).get();
    const adminName = `${(callerDoc.data()?.firstName || '')} ${(callerDoc.data()?.lastName || '')}`.trim() || 'Admin';

    const customerRef = db.collection('users').doc(authorID);
    const customerSnap = await customerRef.get();
    if (!customerSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Customer not found');
    }
    const walletAmount = _asNumber(customerSnap.data()?.wallet_amount);
    const newBalance = Math.round((walletAmount + amt) * 100) / 100;

    await db.runTransaction(async (tx) => {
      tx.update(customerRef, { wallet_amount: newBalance });
      const walletRef = db.collection('wallet').doc();
      tx.set(walletRef, {
        user_id: authorID,
        order_id: orderId,
        amount: amt,
        date: admin.firestore.FieldValue.serverTimestamp(),
        payment_method: 'Wallet',
        payment_status: 'success',
        transactionUser: 'customer',
        isTopUp: true,
        walletType: 'amount',
        note: reason ? `PAUTOS Refund: ${String(reason).slice(0, 200)}` : 'PAUTOS Refund',
      });
      const disputeRef = db.collection('pautos_disputes').doc();
      tx.set(disputeRef, {
        orderId,
        action: 'refund',
        adminId: uid,
        adminName,
        amount: amt,
        note: reason || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { success: true };
  });

/**
 * Callable: Adjust rider earnings for PAUTOS order. Admin-only.
 */
exports.pautosAdjustRiderEarnings = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const { uid, db } = await _requirePautosAdmin(context);
    const { orderId, adjustmentAmount, reason } = data || {};
    if (!orderId || typeof orderId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    const adj = _asNumber(adjustmentAmount);
    if (adj === 0) {
      throw new functions.https.HttpsError('invalid-argument', 'adjustmentAmount cannot be zero');
    }
    const orderSnap = await db.collection(PAUTOS_ORDERS).doc(orderId).get();
    if (!orderSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }
    const orderData = orderSnap.data() || {};
    const driverID = orderData.driverID || '';
    if (!driverID) {
      throw new functions.https.HttpsError('failed-precondition', 'Order has no assigned rider');
    }
    const callerDoc = await db.collection('users').doc(uid).get();
    const adminName = `${(callerDoc.data()?.firstName || '')} ${(callerDoc.data()?.lastName || '')}`.trim() || 'Admin';

    const driverRef = db.collection('users').doc(driverID);
    const driverSnap = await driverRef.get();
    if (!driverSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Rider not found');
    }
    const currentAmount = _asNumber(driverSnap.data()?.wallet_amount);
    const newAmount = Math.round((currentAmount + adj) * 100) / 100;
    if (newAmount < 0) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Adjustment would result in negative rider balance',
      );
    }

    await db.runTransaction(async (tx) => {
      tx.update(driverRef, { wallet_amount: newAmount });
      const disputeRef = db.collection('pautos_disputes').doc();
      tx.set(disputeRef, {
        orderId,
        action: 'adjust_earnings',
        adminId: uid,
        adminName,
        amount: adj,
        note: reason || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return { success: true };
  });

/**
 * Callable: Add dispute note for PAUTOS order. Admin-only.
 */
exports.pautosAddDisputeNote = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const { uid, db } = await _requirePautosAdmin(context);
    const { orderId, note } = data || {};
    if (!orderId || typeof orderId !== 'string') {
      throw new functions.https.HttpsError('invalid-argument', 'orderId required');
    }
    const noteStr = typeof note === 'string' ? note.trim() : '';
    if (!noteStr) {
      throw new functions.https.HttpsError('invalid-argument', 'note required');
    }
    const orderSnap = await db.collection(PAUTOS_ORDERS).doc(orderId).get();
    if (!orderSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }
    const callerDoc = await db.collection('users').doc(uid).get();
    const adminName = `${(callerDoc.data()?.firstName || '')} ${(callerDoc.data()?.lastName || '')}`.trim() || 'Admin';

    await db.collection('pautos_disputes').add({
      orderId,
      action: 'note',
      adminId: uid,
      adminName,
      amount: null,
      note: noteStr,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  });

// =========================
// Rider-first dispatch (v1)
// =========================

const RIDER_FIRST_FLOW = 'rider_first_v1';
const MAX_ACTIVE_ORDERS_PER_RIDER = 2;
const MAX_DISPATCH_ATTEMPTS = 3;
const RIDER_ACCEPT_TIMEOUT_SECONDS = 60;
const RESTAURANT_CONFIRM_TIMEOUT_SECONDS = 300;
const STACK_RADIUS_METERS = 500;

function _nowTimestamp() {
  return admin.firestore.Timestamp.now();
}

function _addSeconds(ts, seconds) {
  return new admin.firestore.Timestamp(ts.seconds + seconds, ts.nanoseconds);
}

function _asNumber(v) {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function _extractRestaurantLocation(orderData) {
  const gp = orderData?.vendor?.g?.geopoint;
  const gpLat = gp ? _asNumber(gp.latitude ?? gp._latitude) : 0;
  const gpLng = gp ? _asNumber(gp.longitude ?? gp._longitude) : 0;
  return {
    lat:
      _asNumber(orderData?.vendor?.latitude) ||
      _asNumber(orderData?.vendor?.lat) ||
      gpLat ||
      0,
    lng:
      _asNumber(orderData?.vendor?.longitude) ||
      _asNumber(orderData?.vendor?.lng) ||
      gpLng ||
      0,
  };
}

function _extractDeliveryLocation(orderData) {
  return {
    lat:
      _asNumber(orderData?.address?.location?.latitude) ||
      _asNumber(orderData?.author?.location?.latitude) ||
      0,
    lng:
      _asNumber(orderData?.address?.location?.longitude) ||
      _asNumber(orderData?.author?.location?.longitude) ||
      0,
  };
}

function _extractDriverLocation(driver) {
  const loc =
    driver?.currentLocation ||
    driver?.driverLocation ||
    driver?.location ||
    null;

  if (!loc) return { lat: 0, lng: 0 };

  // GeoPoint
  if (typeof loc.latitude === 'number' && typeof loc.longitude === 'number') {
    return { lat: loc.latitude, lng: loc.longitude };
  }

  // Map-like
  if (typeof loc.lat === 'number' && typeof loc.lng === 'number') {
    return { lat: loc.lat, lng: loc.lng };
  }

  if (
    typeof loc._latitude === 'number' &&
    typeof loc._longitude === 'number'
  ) {
    return { lat: loc._latitude, lng: loc._longitude };
  }

  return { lat: 0, lng: 0 };
}

function _distanceMeters(a, b) {
  const R = 6371; // km
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const x =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(a.lat)) *
      Math.cos(toRad(b.lat)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
  return R * c * 1000;
}

// --- Road-network routing via Google Distance Matrix API ---

const GOOGLE_MAPS_API_KEY = 'AIzaSyBXNXXV60p-VYnIMD0mevMk8HeW9kSJnPs';
const ROUTE_CACHE_TTL_DAYS = 30;
const ROUTE_COORD_PRECISION = 3; // ~111 m grid

function _roundCoord(v) {
  const f = Math.pow(10, ROUTE_COORD_PRECISION);
  return Math.round(v * f) / f;
}

function _routeCacheKey(oLat, oLng, dLat, dLng) {
  return `${_roundCoord(oLat)},${_roundCoord(oLng)}->${_roundCoord(dLat)},${_roundCoord(dLng)}`;
}

async function _getRouteDataBatch(origin, destinations) {
  const db = getDb();
  const results = new Array(destinations.length).fill(null);
  const uncachedIndices = [];

  for (let i = 0; i < destinations.length; i++) {
    const dest = destinations[i];
    const key = _routeCacheKey(origin.lat, origin.lng, dest.lat, dest.lng);
    try {
      const doc = await db.collection('routes_cache').doc(key).get();
      if (doc.exists) {
        const d = doc.data();
        const now = admin.firestore.Timestamp.now();
        if (d.expiresAt && d.expiresAt.toMillis() > now.toMillis()) {
          results[i] = {
            roadDistanceKm: d.roadDistanceKm,
            durationMinutes: d.durationMinutes,
            isFallback: false,
          };
          continue;
        }
      }
    } catch (_) { /* cache miss */ }
    uncachedIndices.push(i);
  }

  if (uncachedIndices.length > 0) {
    try {
      const destParam = uncachedIndices
        .map(i => `${destinations[i].lat},${destinations[i].lng}`)
        .join('|');
      const url =
        `https://maps.googleapis.com/maps/api/distancematrix/json` +
        `?origins=${origin.lat},${origin.lng}` +
        `&destinations=${destParam}` +
        `&mode=driving&key=${GOOGLE_MAPS_API_KEY}`;

      const https = require('https');
      const body = await new Promise((resolve, reject) => {
        https.get(url, (res) => {
          let data = '';
          res.on('data', chunk => data += chunk);
          res.on('end', () => resolve(data));
        }).on('error', reject);
      });

      const json = JSON.parse(body);
      if (json.status === 'OK' && json.rows && json.rows[0]) {
        const elements = json.rows[0].elements;
        const now = admin.firestore.Timestamp.now();
        const expiresAt = admin.firestore.Timestamp.fromMillis(
          now.toMillis() + ROUTE_CACHE_TTL_DAYS * 86400000
        );
        const batch = db.batch();

        for (let j = 0; j < uncachedIndices.length; j++) {
          const idx = uncachedIndices[j];
          const el = elements[j];
          if (el && el.status === 'OK') {
            const km = el.distance.value / 1000;
            const mins = el.duration.value / 60;
            results[idx] = { roadDistanceKm: km, durationMinutes: mins, isFallback: false };
            const key = _routeCacheKey(
              origin.lat, origin.lng,
              destinations[idx].lat, destinations[idx].lng
            );
            batch.set(db.collection('routes_cache').doc(key), {
              originLat: _roundCoord(origin.lat),
              originLng: _roundCoord(origin.lng),
              destLat: _roundCoord(destinations[idx].lat),
              destLng: _roundCoord(destinations[idx].lng),
              roadDistanceKm: km,
              durationMinutes: mins,
              source: 'google_distance_matrix',
              createdAt: now,
              expiresAt,
            });
          }
        }
        await batch.commit();
      }
    } catch (err) {
      console.warn('[Routing] Distance Matrix API error:', err.message || err);
    }
  }

  for (let i = 0; i < results.length; i++) {
    if (!results[i]) {
      const dist = _distanceMeters(origin, destinations[i]) / 1000;
      results[i] = {
        roadDistanceKm: dist,
        durationMinutes: Math.max(dist / 0.5, 1),
        isFallback: true,
      };
    }
  }
  return results;
}

async function _getRouteDataSingle(origin, destination) {
  const arr = await _getRouteDataBatch(origin, [destination]);
  return arr[0];
}

function _activeOrdersCount(driverData) {
  const v = driverData?.inProgressOrderID;
  return Array.isArray(v) ? v.length : 0;
}

function _isSchemaV2Driver(driverData) {
  return Number(driverData?.statusSchemaVersion || 0) === 2;
}

function _getDriverMaxOrders(driverData, weights) {
  const w = weights || _dispatchWeightsCache || DEFAULT_DISPATCH_WEIGHTS;
  const rawMax = _asNumber(driverData?.maxOrders);
  if (rawMax && rawMax > 0) {
    return Math.max(1, Math.floor(rawMax));
  }
  return _calculateDynamicCapacity(driverData || {}, w);
}

function _isDriverEligibleCanonical(driverData, weights) {
  if (!driverData) return false;
  if (driverData.role !== 'driver') return false;
  if (driverData.isOnline !== true) return false;
  if (driverData.riderAvailability !== 'available') return false;
  if (driverData.suspended === true) return false;

  const activeOrders = _activeOrdersCount(driverData);
  const maxOrders = _getDriverMaxOrders(driverData, weights);
  return activeOrders < maxOrders;
}

function _isDriverEligibleBase(driverData) {
  if (!driverData) return false;
  if (_isSchemaV2Driver(driverData)) {
    return _isDriverEligibleCanonical(driverData);
  }

  const isSuspended =
    driverData.suspended === true ||
    String(driverData.attendanceStatus || '').toLowerCase() === 'suspended';
  if (isSuspended) return false;

  const isCheckedOutToday =
    driverData.checkedOutToday === true ||
    (driverData.todayCheckOutTime != null &&
      String(driverData.todayCheckOutTime || '').trim() !== '');
  if (isCheckedOutToday) return false;

  return true;
}

function _computeIsActiveForDispatch(driverData, activeOrdersCount, weights) {
  if (!_isDriverEligibleBase(driverData)) return false;

  const maxOrders = _getDriverMaxOrders(driverData, weights);
  return activeOrdersCount < maxOrders;
}

async function _logDispatchEvent({
  type,
  orderId,
  payload,
  riderId,
  batchId,
  factors,
  totalScore,
  scoringComponents,
  alternativeRiders,
  activeWeights,
}) {
  try {
    const now = new Date();
    const doc = {
      type,
      orderId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      decisionTime: admin.firestore.FieldValue.serverTimestamp(),
      source: 'functions',
    };

    if (riderId) doc.riderId = riderId;
    if (batchId) doc.batchId = batchId;

    if (factors) {
      doc.factors = factors;
    } else if (payload?.factors) {
      doc.factors = payload.factors;
    }

    if (totalScore != null) doc.totalScore = totalScore;
    if (scoringComponents) doc.scoringComponents = scoringComponents;
    if (alternativeRiders) doc.alternativeRiders = alternativeRiders;
    if (activeWeights) doc.activeWeights = activeWeights;

    if (!doc.factors) {
      doc.factors = {};
    }
    if (!doc.factors.timeOfDay) doc.factors.timeOfDay = `${now.getHours()}:00`;
    if (!doc.factors.dayOfWeek) doc.factors.dayOfWeek = now.getDay();
    if (!doc.factors.isPeakHour) {
      doc.factors.isPeakHour = _isPeakHour(
        activeWeights || _dispatchWeightsCache || DEFAULT_DISPATCH_WEIGHTS,
      );
    }

    if (payload) doc.payload = payload;
    doc.outcome = null;

    await getDb().collection('dispatch_events').add(doc);
  } catch (e) {
    console.error(`[RiderFirst] Failed to log event ${type}:`, e);
  }
}

async function _sendCustomerNotificationBestEffort(orderData, title, body) {
  try {
    const token =
      orderData?.author?.fcmToken ||
      orderData?.author?.notificationToken ||
      '';
    if (!token) return;
    await getMessaging().send({
      token,
      notification: { title, body },
      data: {
        type: 'order_update',
        orderId: String(orderData?.id || ''),
      },
    });
  } catch (e) {
    console.error('[RiderFirst] Failed to notify customer:', e);
  }
}

async function _sendRestaurantNotificationBestEffort(orderData, orderId) {
  try {
    const token = String(orderData?.vendor?.fcmToken || '');
    if (!token) return;
    const payload = { id: orderId, orderId, ...orderData };
    if (orderData?.scheduleTime) {
      payload.scheduleTime = orderData.scheduleTime;
    }
    const message = NotificationBuilder.buildOrderNotification(
      payload,
      'new_order',
      { token, includeActions: true }
    );
    if (orderData?.scheduleTime) {
      message.notification.title = 'Scheduled Order Placed';
      message.notification.body = 'A rider accepted an order. Please confirm within 5 minutes.';
    }
    await getMessaging().send(message);
  } catch (e) {
    console.error('[RiderFirst] Failed to notify restaurant:', e);
  }
}

async function _addDriverChatSystemMessage(orderId, status, customerId) {
  try {
    const db = getDb();
    const messageId = require('crypto').randomUUID();
    const statusMessages = {
      'Order Shipped': 'Your order is ready for pickup',
      'In Transit': 'Driver is on the way with your order',
      'Order Completed': 'Your order has been delivered. Thank you!',
    };
    const messageText = statusMessages[status] || `Order status updated: ${status}`;

    await db
      .collection('chat_driver')
      .doc(orderId)
      .collection('thread')
      .doc(messageId)
      .set({
        id: messageId,
        senderId: 'system',
        receiverId: customerId,
        orderId,
        message: messageText,
        messageType: 'system',
        senderType: 'system',
        orderStatus: status,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        readBy: {},
      });
  } catch (e) {
    console.error('[AUTO_READY] Error adding chat system message:', e);
  }
}

async function _sendPrepTimeReminder(orderId, orderData, minutesLeft) {
  try {
    let token = String(orderData?.vendor?.fcmToken || '');
    if (!token && orderData?.vendorID) {
      const vendorSnap = await getDb()
        .collection('vendors')
        .doc(orderData.vendorID)
        .get();
      token = String(vendorSnap.exists ? vendorSnap.data()?.fcmToken || '' : '');
    }
    if (!token) return;

    const payload = { id: orderId, orderId, minutesLeft, ...orderData };
    const message = NotificationBuilder.buildOrderNotification(
      payload,
      'prep_time_reminder',
      { token, includeActions: true }
    );
    await getMessaging().send(message);
    console.log(`[AUTO_READY] Reminder sent to restaurant for order ${orderId}`);
  } catch (e) {
    console.error('[AUTO_READY] Error sending prep time reminder:', e);
  }
}

async function _removeOrderRequestFromDriver(driverId, orderId) {
  if (!driverId) return;
  try {
    await getDb()
      .collection('users')
      .doc(driverId)
      .update({
        orderRequestData: admin.firestore.FieldValue.arrayRemove(orderId),
      });
  } catch (_) {
    // Best effort.
  }
}

async function _releaseDriverFromOrder(driverId, orderId) {
  if (!driverId) return;
  try {
    const db = getDb();
    await db.runTransaction(async (tx) => {
      const ref = db.collection('users').doc(driverId);
      const snap = await tx.get(ref);
      if (!snap.exists) return;

      const data = snap.data() || {};
      const current =
        Array.isArray(data.inProgressOrderID) ? data.inProgressOrderID : [];
      const next = current.filter((id) => String(id) !== String(orderId));
      const activeOrdersCount = next.length;

      const isActive = _computeIsActiveForDispatch(data, activeOrdersCount);
      const updatedData = { ...data, inProgressOrderID: next };
      const { riderAvailability, riderDisplayStatus } =
        _computeRiderStatus(updatedData);

      tx.update(ref, {
        inProgressOrderID: next,
        orderRequestData: admin.firestore.FieldValue.arrayRemove(orderId),
        isActive,
        riderAvailability,
        riderDisplayStatus,
      });
    });
  } catch (e) {
    console.error(
      `[RiderFirst] Failed releasing driver ${driverId} from ${orderId}:`,
      e
    );
  }
}

async function sendReassignmentNotification(driverId, orderId) {
  if (!driverId) return;
  try {
    const driverSnap = await getDb().collection('users').doc(driverId).get();
    const fcmToken = driverSnap.exists ? driverSnap.data()?.fcmToken : null;
    if (!fcmToken) return;
    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: 'Order Reassigned',
        body: 'An order was reassigned due to timeout.',
      },
      data: {
        type: 'order_reassigned',
        orderId: String(orderId),
      },
      android: {
        notification: {
          sound: 'reassign',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'reassign.wav',
          },
        },
      },
    });
  } catch (e) {
    console.error(
      `[sendReassignmentNotification] Failed for driver ${driverId} order ${orderId}:`,
      e
    );
  }
}

async function _recomputeDriverStatus(driverId) {
  if (!driverId) return;
  try {
    const db = getDb();
    const ref = db.collection('users').doc(driverId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const data = snap.data() || {};
    const activeOrdersCount = _activeOrdersCount(data);
    const isActive = _computeIsActiveForDispatch(data, activeOrdersCount);
    const { riderAvailability, riderDisplayStatus } = _computeRiderStatus(data);
    await ref.update({ isActive, riderAvailability, riderDisplayStatus });
  } catch (e) {
    console.error(`[RiderFirst] Failed to recompute driver status for ${driverId}:`, e);
  }
}

/**
 * Check zone capacity: count active riders assigned to a zone
 * whose locationUpdatedAt is within the last 5 minutes.
 * Returns { atCapacity, currentCount, maxRiders, zoneId, zoneName }
 */
async function _checkZoneCapacity(deliveryLat, deliveryLng) {
  const db = getDb();
  const zonesSnap = await db.collection('service_areas').get();
  if (zonesSnap.empty) return { atCapacity: false };

  let matchedZone = null;
  let matchedDoc = null;

  for (const doc of zonesSnap.docs) {
    const z = doc.data();
    const ids = z.assignedDriverIds || [];
    if (!ids.length) continue;

    if (z.boundaryType === 'radius') {
      const cLat = _asNumber(z.centerLat);
      const cLng = _asNumber(z.centerLng);
      const rKm = _asNumber(z.radiusKm);
      if (!cLat || !cLng || rKm <= 0) continue;
      if (!deliveryLat || !deliveryLng) continue;
      const dist = _distanceMeters(
        { lat: cLat, lng: cLng },
        { lat: deliveryLat, lng: deliveryLng },
      );
      if (dist <= rKm * 1000) {
        matchedZone = z;
        matchedDoc = doc;
        break;
      }
    } else if (z.boundaryType === 'fixed') {
      continue; // fixed zones match by locality, skip for lat/lng
    }
  }

  if (!matchedZone || !matchedDoc) return { atCapacity: false };
  const maxRiders = matchedZone.maxRiders;
  if (maxRiders == null || maxRiders === undefined) {
    return { atCapacity: false };
  }

  const assignedIds = matchedZone.assignedDriverIds || [];
  const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);
  const fiveMinAgoTs = admin.firestore.Timestamp.fromDate(fiveMinAgo);

  const driversSnap = await db
    .collection('users')
    .where('role', '==', 'driver')
    .get();

  let activeCount = 0;
  for (const dDoc of driversSnap.docs) {
    if (!assignedIds.includes(dDoc.id)) continue;
    const d = dDoc.data();
    if (_isSchemaV2Driver(d)) {
      if (d.isOnline !== true) continue;
      if (d.riderAvailability !== 'available' &&
          d.riderAvailability !== 'on_delivery' &&
          d.riderAvailability !== 'on_break') continue;
    } else if (d.checkedOutToday === true) {
      continue;
    }
    const locTs = d.locationUpdatedAt;
    if (locTs && locTs.toDate() > fiveMinAgo) {
      activeCount++;
    }
  }

  return {
    atCapacity: activeCount >= maxRiders,
    currentCount: activeCount,
    maxRiders: maxRiders,
    zoneId: matchedDoc.id,
    zoneName: matchedZone.name || matchedDoc.id,
  };
}

async function _pickBestDriverForOrder({
  orderId,
  orderData,
  excludeDriverIds,
}) {
  const db = getDb();
  const exclude = new Set(excludeDriverIds || []);
  const weights = await _loadDispatchWeights();

  const restaurantLocation = _extractRestaurantLocation(orderData);
  const deliveryLocation = _extractDeliveryLocation(orderData);
  const prepMinutes = _asNumber(
    orderData?.estimatedTimeToPrepare || orderData?.preparationTime || 0
  );

  const driversSnapshot = await db
    .collection('users')
    .where('role', '==', 'driver')
    .get();

  const drivers = [];
  for (const doc of driversSnapshot.docs) {
    const d = { id: doc.id, ...doc.data() };
    if (exclude.has(d.id)) continue;
    if (!_isDriverEligibleBase(d)) continue;

    const driverLocation = _extractDriverLocation(d);
    if (!driverLocation.lat || !driverLocation.lng) continue;

    const activeOrders = _activeOrdersCount(d);
    const effectiveCap = _calculateDynamicCapacity(d, weights);
    if (activeOrders >= effectiveCap) continue;

    const distanceToRestaurantMeters = _distanceMeters(
      driverLocation,
      restaurantLocation
    );
    const eta = calculateETA(driverLocation, restaurantLocation);
    const headingMatch = _calculateDriverHeading(d, driverLocation, restaurantLocation);
    const fairnessScore = await calculateFairnessScore(d.id);

    const unifiedScore = calculateCompositeScore({
      eta,
      mlAcceptanceProbability: 0.5,
      fairnessScore,
      headingMatch,
      currentOrders: activeOrders,
      restaurantPrepMinutes: prepMinutes,
      effectiveCapacity: effectiveCap,
    });

    drivers.push({
      driverId: d.id,
      driverData: d,
      driverLocation,
      activeOrders,
      multipleOrders: d.multipleOrders === true,
      distanceToRestaurantMeters,
      deliveryLocation,
      unifiedScore,
    });
  }

  // Tier 1: free riders sorted by unified score
  const free = drivers
    .filter((x) => x.activeOrders === 0)
    .sort((a, b) => a.unifiedScore - b.unifiedScore);
  if (free.length > 0) {
    const topFree = free.slice(0, 8);
    try {
      const routeResults = await Promise.all(
        topFree.map(d => _getRouteDataSingle(d.driverLocation, restaurantLocation))
      );
      for (let i = 0; i < topFree.length; i++) {
        const r = routeResults[i];
        topFree[i].routingSource = r.isFallback ? 'haversine' : 'google_distance_matrix';
        topFree[i].unifiedScore = calculateCompositeScore({
          eta: r.durationMinutes,
          mlAcceptanceProbability: 0.5,
          fairnessScore: topFree[i].unifiedScore,
          headingMatch: 0.5,
          currentOrders: 0,
          restaurantPrepMinutes: prepMinutes,
        });
        topFree[i].distanceToRestaurantMeters = r.roadDistanceKm * 1000;
      }
      topFree.sort((a, b) => a.unifiedScore - b.unifiedScore);
    } catch (e) {
      console.warn('[_pickBest] Road routing failed for free tier:', e.message || e);
    }
    return {
      selected: topFree[0],
      candidates: topFree.slice(0, 10),
      stackDecision: { usedStacking: false },
    };
  }

  // Tier 2: consider stacking (active_orders == 1) only if multipleOrders==true
  const maybeStack = drivers
    .filter((x) => x.activeOrders === 1 && x.multipleOrders)
    .sort((a, b) => a.unifiedScore - b.unifiedScore)
    .slice(0, 15);

  for (const candidate of maybeStack) {
    const inProgress = candidate.driverData?.inProgressOrderID;
    const currentOrderId =
      Array.isArray(inProgress) && inProgress.length > 0
        ? String(inProgress[0])
        : '';
    if (!currentOrderId) continue;

    try {
      const currentOrderSnap = await db
        .collection('restaurant_orders')
        .doc(currentOrderId)
        .get();
      if (!currentOrderSnap.exists) continue;

      const currentOrder = currentOrderSnap.data() || {};
      const sameRestaurant =
        String(currentOrder.vendorID || '') === String(orderData.vendorID || '');

      const currentDelivery = _extractDeliveryLocation(currentOrder);
      const deliveryDistance = _distanceMeters(
        currentDelivery,
        deliveryLocation
      );

      const nearEnough = deliveryDistance <= STACK_RADIUS_METERS;
      if (sameRestaurant || nearEnough) {
        return {
          selected: candidate,
          candidates: maybeStack.slice(0, 10),
          stackDecision: {
            usedStacking: true,
            sameRestaurant,
            deliveryDistanceMeters: Math.round(deliveryDistance),
            stackRadiusMeters: STACK_RADIUS_METERS,
          },
        };
      }
    } catch (e) {
      console.error(
        `[RiderFirst] Stack check failed for driver ${candidate.driverId}:`,
        e
      );
    }
  }

  return {
    selected: null,
    candidates: maybeStack.slice(0, 10),
    stackDecision: {
      usedStacking: true,
      result: 'no_compatible_stack_candidate',
      stackRadiusMeters: STACK_RADIUS_METERS,
    },
  };
}

async function _offerOrderToDriver({
  orderRef,
  orderId,
  orderData,
  driverId,
  attempt,
  candidates,
  stackDecision,
}) {
  const now = _nowTimestamp();
  const timeoutSec = await _getRiderTimeoutSeconds();
  const deadline = _addSeconds(now, timeoutSec);

  await orderRef.update({
    status: 'Driver Assigned',
    driverID: driverId,
    dispatchFlow: RIDER_FIRST_FLOW,
    'dispatch.flow': RIDER_FIRST_FLOW,
    'dispatch.stage': 'rider_offered',
    'dispatch.attempt': attempt,
    'dispatch.triedDriverIds': admin.firestore.FieldValue.arrayUnion(driverId),
    'dispatch.riderAcceptDeadline': deadline,
    'dispatch.restaurantConfirmDeadline': null,
    'dispatch.selectedDriverId': driverId,
    'dispatch.candidates': (candidates || []).map((c) => ({
      driverId: c.driverId,
      distanceToRestaurantMeters: Math.round(c.distanceToRestaurantMeters),
      activeOrders: c.activeOrders,
      multipleOrders: c.multipleOrders === true,
    })),
    'dispatch.stackDecision': stackDecision || null,
    'dispatch.timestamps.offeredAt': admin.firestore.FieldValue.serverTimestamp(),
  });

  await getDb()
    .collection('users')
    .doc(driverId)
    .set(
      {
        orderRequestData: admin.firestore.FieldValue.arrayUnion(orderId),
      },
      { merge: true }
    );

  await _logDispatchEvent({
    type: 'rider_offer_sent',
    orderId,
    payload: {
      attempt,
      driverId,
      stackDecision: stackDecision || null,
    },
  });
}

async function _cancelOrderWithReason({ orderRef, orderId, orderData, reason }) {
  await orderRef.update({
    status: 'Order Cancelled',
    cancelReason: reason || 'dispatch_failed',
    cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
    dispatchFlow: RIDER_FIRST_FLOW,
    'dispatch.stage': 'cancelled',
  });

  await _logDispatchEvent({
    type: 'dispatch_failed_attempts',
    orderId,
    payload: { reason: reason || 'dispatch_failed' },
  });

  await _sendCustomerNotificationBestEffort(
    orderData,
    'Order cancelled',
    'We could not find an available rider. Please try again shortly.'
  );
}

async function _tryDispatchOrFail({ orderRef, orderId, orderData, attempt }) {
  const tried = orderData?.dispatch?.triedDriverIds || [];
  const currentDriverId = String(orderData?.driverID || '');
  const exclude = Array.isArray(tried) ? tried.slice() : [];
  if (currentDriverId) exclude.push(currentDriverId);

  const { selected, candidates, stackDecision } = await _pickBestDriverForOrder({
    orderId,
    orderData,
    excludeDriverIds: exclude,
  });

  if (!selected) {
    await _cancelOrderWithReason({
      orderRef,
      orderId,
      orderData,
      reason: 'no_eligible_riders',
    });
    return;
  }

  await _offerOrderToDriver({
    orderRef,
    orderId,
    orderData,
    driverId: selected.driverId,
    attempt,
    candidates,
    stackDecision,
  });
}

exports.riderFirstDispatchOnCreate = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onCreate(async (snap, context) => {
    // DEPRECATED: This function previously implemented rider-first dispatch.
    // Now using restaurant-first model. Orders stay as 'Order Placed' and
    // are visible to restaurants immediately. Rider assignment happens via
    // autoDispatcher after restaurant accepts (status -> 'Order Accepted').
    return null;
  });

exports.riderFirstDispatchOnUpdate = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    // DEPRECATED: Rider-first update handler removed. Restaurant-first model
    // uses autoDispatcher for rider assignment after restaurant acceptance.
    // Retained: Restaurant rejection releases any assigned driver.
    const orderId = context.params.orderId;
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};
    const beforeStatus = String(beforeData.status || '');
    const afterStatus = String(afterData.status || '');

    if (beforeStatus !== 'Order Rejected' && afterStatus === 'Order Rejected') {
      const driverId = String(afterData.driverID || '');
      if (driverId) {
        await _releaseDriverFromOrder(driverId, orderId);
      }
      await _logDispatchEvent({
        type: 'restaurant_rejected',
        orderId,
        payload: { reason: 'rejected' },
      });
      await _sendCustomerNotificationBestEffort(
        afterData,
        'Restaurant unavailable',
        'The restaurant could not confirm your order.'
      );
      const rejectionReason = String(
        afterData.rejectionReason || 'restaurant_rejected'
      );
      await OrderRecoveryService.handleOrderFailure(
        { id: orderId, ...afterData },
        rejectionReason,
        { reason: rejectionReason, rejectedBy: 'restaurant' }
      );
    }
    return null;
  });

// =============================
// Handle driver rejection: wait then retrigger autoDispatcher
// =============================
exports.handleDriverRejection = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const orderId = context.params.orderId;
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};
    const beforeStatus = String(beforeData.status || '');
    const afterStatus = String(afterData.status || '');

    if (beforeStatus === 'Driver Rejected' || afterStatus !== 'Driver Rejected') {
      return null;
    }

    console.log(`[HandleDriverRejection] Driver rejected order ${orderId}`);

    const reason = String(afterData.driverRejectionReason || '');
    if (reason === 'restaurant_closed') {
      const rejectedDriverId = String(afterData.driverID || '');
      if (rejectedDriverId) {
        await _releaseDriverFromOrder(rejectedDriverId, orderId);
      }

      const evidenceUrl = String(afterData.driverRejectionEvidence || '');

      const adminsSnap = await getDb()
        .collection('users')
        .where('role', '==', 'admin')
        .get();

      const tokens = [];
      for (const doc of adminsSnap.docs) {
        const t = doc.data()?.fcmToken;
        if (t) tokens.push(t);
      }

      if (tokens.length > 0) {
        const body = evidenceUrl
          ? `Order ${orderId} – restaurant closed (photo attached)`
          : `Order ${orderId} – restaurant closed`;

        for (const token of tokens) {
          try {
            await getMessaging().send({
              token,
              notification: {
                title: 'Restaurant Closed Report',
                body,
              },
              data: {
                type: 'restaurant_closed',
                orderId,
                evidenceUrl: evidenceUrl || '',
              },
            });
          } catch (_) {}
        }
      }

      console.log(
        `[HandleDriverRejection] Order ${orderId} restaurant_closed, ` +
        `skipping retrigger, notified ${tokens.length} admin(s)`
      );
      return null;
    }

    const rejectedDriverId = String(afterData.driverID || '');
    const driverRejectionReason = String(afterData.driverRejectionReason || '');

    // Release the rejected driver from the order
    if (rejectedDriverId) {
      await _releaseDriverFromOrder(rejectedDriverId, orderId);
    }

    // Update assignments_log with rejection status and reason
    try {
      const assignSnap = await getDb()
        .collection('assignments_log')
        .where('driverId', '==', rejectedDriverId)
        .limit(50)
        .get();
      const match = assignSnap.docs.find((d) => {
        const d2 = d.data();
        return (d2.orderId || d2.order_id || '') === orderId;
      });
      if (match) {
        const updateData = {
          status: 'rejected',
          rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (driverRejectionReason) {
          updateData.rejectionReason = driverRejectionReason;
        }
        await match.ref.update(updateData);
      }
    } catch (assignErr) {
      console.warn(
        '[HandleDriverRejection] Failed to update assignments_log:',
        assignErr.message
      );
    }

    await _logDispatchEvent({
      type: 'driver_rejected_auto_retry',
      orderId,
      payload: { rejectedDriverId },
    });

    // Read configurable retry delay (default 20s)
    let retryDelaySeconds = 20;
    try {
      const weightsSnap = await getDb()
        .collection('config')
        .doc('dispatch_weights')
        .get();
      if (weightsSnap.exists) {
        const w = weightsSnap.data() || {};
        if (w.retryDelaySeconds && w.retryDelaySeconds > 0) {
          retryDelaySeconds = w.retryDelaySeconds;
        }
      }
    } catch (e) {
      console.warn('[HandleDriverRejection] Failed to load config, using default delay:', e.message);
    }

    await new Promise(resolve => setTimeout(resolve, retryDelaySeconds * 1000));

    // Re-read order to verify it's still in Driver Rejected status
    const orderSnap = await change.after.ref.get();
    if (!orderSnap.exists) return null;
    const currentData = orderSnap.data() || {};
    const currentStatus = String(currentData.status || '');

    if (currentStatus !== 'Driver Rejected') {
      console.log(`[HandleDriverRejection] Order ${orderId} status changed to '${currentStatus}' during delay, skipping retrigger`);
      return null;
    }

    // Set status back to 'Order Accepted' with excluded driver, triggering autoDispatcher
    await change.after.ref.update({
      status: 'Order Accepted',
      'dispatch.excludedDriverIds': admin.firestore.FieldValue.arrayUnion(rejectedDriverId),
      'dispatch.retryCount': admin.firestore.FieldValue.increment(1),
      'dispatch.lastRetriggerAt': admin.firestore.FieldValue.serverTimestamp(),
      'dispatch.lock': false,
      driverID: admin.firestore.FieldValue.delete(),
      assignedDriverName: admin.firestore.FieldValue.delete(),
    });

    console.log(`[HandleDriverRejection] Retriggered dispatch for order ${orderId}, excluded driver ${rejectedDriverId}`);
    return null;
  });

// =============================
// Update acceptance rate on rejection
// =============================
exports.updateAcceptanceRateOnRejection = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (before.status !== 'Driver Rejected' && after.status === 'Driver Rejected') {
      const riderId = String(after.driverID || after.driverId || '');
      if (!riderId) return null;

      console.log(`[AcceptanceRate] Recalculating for rider ${riderId} due to rejection`);

      const db = getDb();
      const assignmentsSnap = await db
        .collection('assignments_log')
        .where('driverId', '==', riderId)
        .orderBy('createdAt', 'desc')
        .limit(50)
        .get();

      let accepted = 0;
      let total = 0;
      assignmentsSnap.docs.forEach((doc) => {
        const status = doc.data().status;
        if (['accepted', 'rejected', 'timeout'].includes(status)) {
          total++;
          if (status === 'accepted') accepted++;
        }
      });

      const acceptanceRate = total > 0 ? (accepted / total) * 100 : 100;

      await db.collection('users').doc(riderId).update({
        acceptance_rate: Math.round(acceptanceRate * 10) / 10,
        lastAcceptanceUpdate: admin.firestore.FieldValue.serverTimestamp(),
        totalRejections: admin.firestore.FieldValue.increment(1),
        lastRejectionAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[AcceptanceRate] Updated to ${acceptanceRate.toFixed(1)}% for rider ${riderId}`);
    }
    return null;
  });

exports.riderFirstDispatchTimeouts = functions.pubsub
  .schedule('every 1 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = _nowTimestamp();
    const nowDate = new Date();

    // 0) One-time cleanup: reset any legacy 'Awaiting Rider' orders to 'Order Placed'
    const awaitingRiderSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Awaiting Rider')
      .limit(25)
      .get();

    for (const doc of awaitingRiderSnap.docs) {
      const orderId = doc.id;
      console.log(`[DispatchTimeouts] Resetting legacy Awaiting Rider order ${orderId} to Order Placed`);
      await doc.ref.update({
        status: 'Order Placed',
        'dispatch.stage': 'legacy_reset',
      });
      await _logDispatchEvent({
        type: 'legacy_awaiting_rider_reset',
        orderId,
        payload: { reason: 'restaurant_first_migration' },
      });
    }

    // Read configurable auto-cancel threshold
    let autoCancelMinutes = 15;
    try {
      const cfgSnap = await db.collection('config').doc('dispatch_weights').get();
      if (cfgSnap.exists) {
        const cfg = cfgSnap.data() || {};
        if (cfg.restaurantAutoCancelMinutes > 0) {
          autoCancelMinutes = cfg.restaurantAutoCancelMinutes;
        }
      }
    } catch (_) {}

    // 1) Restaurant reminder (10 min): orders in 'Order Placed' with no action
    const tenMinAgo = admin.firestore.Timestamp.fromDate(
      new Date(nowDate.getTime() - 10 * 60 * 1000)
    );
    const fifteenMinAgo = admin.firestore.Timestamp.fromDate(
      new Date(nowDate.getTime() - autoCancelMinutes * 60 * 1000)
    );

    const staleOrderSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Order Placed')
      .where('createdAt', '<=', tenMinAgo)
      .limit(25)
      .get();

    for (const doc of staleOrderSnap.docs) {
      const orderId = doc.id;
      const data = doc.data() || {};
      const createdAt = data.createdAt;
      if (!createdAt) continue;

      const createdDate = createdAt.toDate ? createdAt.toDate() : new Date(createdAt);
      const ageMs = nowDate.getTime() - createdDate.getTime();
      const ageMin = ageMs / (60 * 1000);

      // Auto-cancel after configured threshold
      if (ageMin >= autoCancelMinutes) {
        console.log(`[DispatchTimeouts] Auto-cancelling stale order ${orderId} (${Math.round(ageMin)} min)`);
        await doc.ref.update({
          status: 'Order Cancelled',
          cancelReason: 'restaurant_no_response',
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          'dispatch.stage': 'restaurant_no_response',
        });
        await _logDispatchEvent({
          type: 'restaurant_no_response_cancel',
          orderId,
          payload: { ageMinutes: Math.round(ageMin) },
        });
        await _sendCustomerNotificationBestEffort(
          data,
          'Order Cancelled',
          'The restaurant did not respond to your order. It has been cancelled.'
        );
        continue;
      }

      // 10-15 minutes: send reminder to restaurant (only once)
      if (!data?.dispatch?.restaurantReminderSent) {
        console.log(`[DispatchTimeouts] Sending restaurant reminder for order ${orderId} (${Math.round(ageMin)} min)`);
        await _sendRestaurantNotificationBestEffort(data, orderId);
        await doc.ref.update({
          'dispatch.restaurantReminderSent': true,
          'dispatch.restaurantReminderAt': admin.firestore.FieldValue.serverTimestamp(),
        });
        await _logDispatchEvent({
          type: 'restaurant_reminder_sent',
          orderId,
          payload: { ageMinutes: Math.round(ageMin) },
        });
      }
    }

    // 2) Rider accept timeouts (Driver Assigned > 60s - rider did not accept in time)
    const adminTimeoutSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Driver Assigned')
      .where('dispatch.riderAcceptDeadline', '<=', now)
      .limit(25)
      .get();

    for (const doc of adminTimeoutSnap.docs) {
      const orderId = doc.id;
      const data = doc.data() || {};

      const driverId = String(data.driverID || '');
      await _releaseDriverFromOrder(driverId, orderId);

      await doc.ref.update({
        status: 'Order Accepted',
        'dispatch.stage': 'admin_timeout_retrigger',
        'dispatch.lock': false,
        'dispatch.excludedDriverIds': admin.firestore.FieldValue.arrayUnion(driverId),
        'dispatch.retryCount': admin.firestore.FieldValue.increment(1),
        'dispatch.lastRetriggerAt': admin.firestore.FieldValue.serverTimestamp(),
        driverID: admin.firestore.FieldValue.delete(),
        assignedDriverName: admin.firestore.FieldValue.delete(),
      });

      await _logDispatchEvent({
        type: 'admin_dispatch_timeout_retrigger',
        orderId,
        payload: { driverId, action: 'set_order_accepted_for_redispatch' },
      });
      await sendReassignmentNotification(driverId, orderId);
    }

    // 4) Batch timeouts -- if any order in a batch timed out, release the whole batch
    const batchTimeoutSnap = await db
      .collection('order_batches')
      .where('status', '==', 'assigned')
      .limit(25)
      .get();

    for (const batchDoc of batchTimeoutSnap.docs) {
      const batch = batchDoc.data() || {};
      const orderIds = batch.orderIds || [];
      const driverId = String(batch.assignedDriverId || '');

      let anyTimedOut = false;
      for (const oid of orderIds) {
        const oSnap = await db.collection('restaurant_orders').doc(oid).get();
        const oData = oSnap.exists ? oSnap.data() : {};
        const deadline = oData?.dispatch?.riderAcceptDeadline;
        if (
          deadline &&
          deadline.seconds <= now.seconds &&
          oData.status === 'Driver Assigned'
        ) {
          anyTimedOut = true;
          break;
        }
      }

      if (!anyTimedOut) continue;

      for (const oid of orderIds) {
        await _releaseDriverFromOrder(driverId, oid);
        await sendReassignmentNotification(driverId, oid);
        await db.collection('restaurant_orders').doc(oid).update({
          status: 'Order Accepted',
          driverID: admin.firestore.FieldValue.delete(),
          'dispatch.stage': 'batch_timeout',
          'dispatch.lock': false,
        });
      }

      await batchDoc.ref.update({
        status: 'pending',
        assignedDriverId: null,
        assignedAt: null,
      });

      await _logDispatchEvent({
        type: 'batch_timeout',
        orderId: orderIds[0] || '',
        payload: { batchId: batchDoc.id, driverId, orderIds },
      });
    }

    return null;
  });

/**
 * Canonical rider inactivity monitor.
 * Single backend writer: sets rider offline after inactivity timeout.
 */
exports.monitorRiderInactivity = functions.pubsub
  .schedule('every 2 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const configSnap = await db
      .collection('config')
      .doc('rider_time_settings')
      .get();
    const config = configSnap.exists ? configSnap.data() : {};
    const inactivityTimeoutMinutes = _asNumber(
      config?.inactivityTimeoutMinutes,
    ) || 15;
    const excludeWithActiveOrders = config?.excludeWithActiveOrders !== false;
    const thresholdMs = inactivityTimeoutMinutes * 60 * 1000;
    const nowMs = Date.now();

    const ridersSnap = await db
      .collection('users')
      .where('role', '==', 'driver')
      .get();

    let forcedOffline = 0;
    for (const riderDoc of ridersSnap.docs) {
      const data = riderDoc.data() || {};
      if (!_isSchemaV2Driver(data)) continue;

      const avail = String(data.riderAvailability || 'offline');
      if (
        avail !== 'available' &&
        avail !== 'on_delivery' &&
        avail !== 'on_break'
      ) {
        continue;
      }
      if (data.isOnline !== true) continue;

      const activeOrders = _activeOrdersCount(data);
      if (excludeWithActiveOrders && activeOrders > 0) continue;

      const lastActRaw = data.lastActivityTimestamp;
      const locRaw = data.locationUpdatedAt;
      const lastActMs = lastActRaw?.toMillis
        ? lastActRaw.toMillis()
        : locRaw?.toMillis
          ? locRaw.toMillis()
          : 0;
      if (!lastActMs) continue;

      const inactiveMs = nowMs - lastActMs;
      if (inactiveMs < thresholdMs) continue;

      await riderDoc.ref.update({
        isOnline: false,
        riderAvailability: 'offline',
        riderDisplayStatus: '⚪ Offline',
        inactiveReason: 'timeout',
        lastSeen: admin.firestore.FieldValue.serverTimestamp(),
      });
      forcedOffline++;
    }

    if (forcedOffline > 0) {
      console.log(
        `[monitorRiderInactivity] Forced offline ${forcedOffline} rider(s)`,
      );
    }
    return null;
  });

// =============================
// Fast timeout checker (every 10s) - real-time release of expired assignments
// =============================
exports.riderAcceptDeadlineChecker = functions.pubsub
  .schedule('every 10 seconds')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const cfg = await _loadDispatchWeights();
    const tc = cfg.timeoutChecker || {};
    if (tc.enabled === false) {
      return null;
    }
    const batchSize = Math.min(500, Math.max(1, tc.batchSize || 50));
    const now = _nowTimestamp();
    const nowMs = now.toMillis ? now.toMillis() : now.seconds * 1000;

    const expiredSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Driver Assigned')
      .where('dispatch.riderAcceptDeadline', '<=', now)
      .limit(batchSize)
      .get();

    if (expiredSnap.empty) {
      return null;
    }

    const BATCH_COMMIT_SIZE = 20;
    const pending = [];

    for (const doc of expiredSnap.docs) {
      const orderId = doc.id;
      const data = doc.data() || {};
      const driverId = String(data.driverID || '');
      const deadline = data?.dispatch?.riderAcceptDeadline;
      const delaySeconds = deadline && deadline.toMillis
        ? Math.round((nowMs - deadline.toMillis()) / 1000)
        : null;

      await _releaseDriverFromOrder(driverId, orderId);

      pending.push({
        ref: doc.ref,
        orderId,
        driverId,
        delaySeconds,
      });
    }

    for (let i = 0; i < pending.length; i += BATCH_COMMIT_SIZE) {
      const chunk = pending.slice(i, i + BATCH_COMMIT_SIZE);
      const writeBatch = db.batch();
      for (const item of chunk) {
        writeBatch.update(item.ref, {
          status: 'Order Accepted',
          'dispatch.stage': 'fast_timeout_retrigger',
          'dispatch.lock': false,
          'dispatch.excludedDriverIds': admin.firestore.FieldValue.arrayUnion(item.driverId),
          'dispatch.retryCount': admin.firestore.FieldValue.increment(1),
          'dispatch.lastRetriggerAt': admin.firestore.FieldValue.serverTimestamp(),
          driverID: admin.firestore.FieldValue.delete(),
          assignedDriverName: admin.firestore.FieldValue.delete(),
        });
      }
      await writeBatch.commit();
    }

    for (const item of pending) {
      await _logDispatchEvent({
        type: 'fast_timeout_retrigger',
        orderId: item.orderId,
        payload: { driverId: item.driverId, delaySeconds: item.delaySeconds },
      });
      await sendReassignmentNotification(item.driverId, item.orderId);
    }

    console.log(`[FastTimeoutChecker] Processed ${pending.length} expired assignments`);
    return null;
  });

// =============================
// Monitor stuck orders (safety net)
// =============================
exports.monitorStuckOrders = functions.pubsub
  .schedule('every 2 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const sixtySecondsAgo = admin.firestore.Timestamp.fromDate(
      new Date(now.getTime() - 60 * 1000)
    );
    const threeMinutesAgo = admin.firestore.Timestamp.fromDate(
      new Date(now.getTime() - 3 * 60 * 1000)
    );

    // 1) Orders stuck in 'Driver Rejected' for >60 seconds
    const rejectedSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Driver Rejected')
      .where('statusChangedAt', '<=', sixtySecondsAgo)
      .limit(15)
      .get();

    for (const doc of rejectedSnap.docs) {
      const data = doc.data() || {};
      const driverId = String(data.driverID || '');
      console.log(`[MonitorStuckOrders] Unsticking rejected order ${doc.id}`);

      if (driverId) {
        await _releaseDriverFromOrder(driverId, doc.id);
      }

      await doc.ref.update({
        status: 'Order Accepted',
        'dispatch.stage': 'stuck_monitor_retrigger',
        'dispatch.lock': false,
        'dispatch.excludedDriverIds': driverId
          ? admin.firestore.FieldValue.arrayUnion(driverId)
          : admin.firestore.FieldValue.arrayUnion(),
        'dispatch.retryCount': admin.firestore.FieldValue.increment(1),
        driverID: admin.firestore.FieldValue.delete(),
        assignedDriverName: admin.firestore.FieldValue.delete(),
      });

      await _logDispatchEvent({
        type: 'stuck_order_retrigger',
        orderId: doc.id,
        payload: { source: 'driver_rejected_stuck', driverId },
      });
    }

    // 2) Orders in 'Order Accepted' with dispatch attempts but no driver for >3 min
    const unassignedSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Order Accepted')
      .where('dispatch.lastRetriggerAt', '<=', threeMinutesAgo)
      .limit(15)
      .get();

    for (const doc of unassignedSnap.docs) {
      const data = doc.data() || {};
      const attemptCount = data?.dispatch?.attemptCount || 0;
      if (attemptCount < 1) continue;
      if (data.driverID) continue;

      console.log(`[MonitorStuckOrders] Re-triggering unassigned order ${doc.id} (${attemptCount} attempts)`);

      await doc.ref.update({
        'dispatch.stage': 'stuck_monitor_retry',
        'dispatch.lastRetriggerAt': admin.firestore.FieldValue.serverTimestamp(),
        'dispatch.retryCount': admin.firestore.FieldValue.increment(1),
      });

      await _logDispatchEvent({
        type: 'stuck_order_retry',
        orderId: doc.id,
        payload: { source: 'unassigned_retry', attemptCount },
      });
    }

    return null;
  });

// =============================
// Auto-mark orders as ready when prep time has elapsed
// =============================
exports.autoMarkReadyOrders = functions.pubsub
  .schedule('every 2 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();
    const nowDate = now.toDate();
    let processedCount = 0;
    let errorCount = 0;

    console.log('[AUTO_READY] ===== STARTING AUTO-READY CHECK =====');
    console.log('[AUTO_READY] Time: ' + nowDate.toISOString());

    try {
      const ordersSnapshot = await db
        .collection('restaurant_orders')
        .where('status', '==', 'Driver Accepted')
        .limit(100)
        .get();

      console.log(`[AUTO_READY] Found ${ordersSnapshot.size} orders to check`);

      for (const doc of ordersSnapshot.docs) {
        try {
          const orderData = doc.data() || {};
          const orderId = doc.id;

          let readyTime;
          if (orderData.readyAt) {
            readyTime = orderData.readyAt.toDate
              ? orderData.readyAt.toDate()
              : new Date(orderData.readyAt._seconds * 1000);
          } else {
            const acceptedAt = orderData.acceptedAt;
            if (!acceptedAt) continue;
            const prepTimeStr =
              orderData.estimatedTimeToPrepare || '30 min';
            if (!orderData.estimatedTimeToPrepare) continue;
            const prepMinutes = parsePreparationMinutes(prepTimeStr);
            const acceptedDate = acceptedAt.toDate
              ? acceptedAt.toDate()
              : new Date(acceptedAt._seconds * 1000);
            readyTime = new Date(
              acceptedDate.getTime() + prepMinutes * 60000
            );
          }

          const minutesLeft = Math.round(
            (readyTime.getTime() - nowDate.getTime()) / 60000
          );

          // Send reminder if within threshold and not yet reminded
          if (
            minutesLeft > 0 &&
            !orderData?.dispatch?.prepTimeReminderSent
          ) {
            const vendorSnap = await db
              .collection('vendors')
              .doc(orderData.vendorID)
              .get();
            const vendorData = vendorSnap.exists
              ? vendorSnap.data()
              : {};
            const remindersEnabled =
              vendorData?.prepRemindersEnabled ?? true;
            const reminderMinutes = vendorData?.reminderMinutes ?? 5;

            if (
              remindersEnabled &&
              minutesLeft <= reminderMinutes
            ) {
              await _sendPrepTimeReminder(orderId, orderData, minutesLeft);
              await doc.ref.update({
                'dispatch.prepTimeReminderSent': true,
                'dispatch.prepTimeReminderAt':
                  admin.firestore.FieldValue.serverTimestamp(),
              });
            }
          }

          // Check if ready time has passed
          if (nowDate >= readyTime) {
            console.log(
              `[AUTO_READY] Order ${orderId} is ready - auto-marking`
            );

            await doc.ref.update({
              status: 'Order Shipped',
              shippedAt: admin.firestore.FieldValue.serverTimestamp(),
              autoMarkedReady: true,
              autoMarkedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            const customerId =
              orderData.author?.id || orderData.authorID || '';
            if (customerId) {
              await _addDriverChatSystemMessage(
                orderId,
                'Order Shipped',
                customerId
              );
            }

            processedCount++;
          }
        } catch (orderErr) {
          console.error(
            `[AUTO_READY] Error processing order ${doc.id}:`,
            orderErr
          );
          errorCount++;
        }
      }

      console.log('[AUTO_READY] ===== COMPLETED =====');
      console.log(
        `[AUTO_READY] Processed: ${processedCount}, Errors: ${errorCount}`
      );

      await db.collection('system_logs').add({
        type: 'auto_ready_check',
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        ordersChecked: ordersSnapshot.size,
        ordersMarked: processedCount,
        errors: errorCount,
      });
    } catch (err) {
      console.error('[AUTO_READY] Fatal error:', err);
      try {
        await getDb().collection('system_logs').add({
          type: 'auto_ready_error',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          error: err.message,
          stack: err.stack,
        });
      } catch (logErr) {
        console.error('[AUTO_READY] Failed to log error:', logErr);
      }
    }

    return null;
  });

// =============================
// Send prep time reminders to restaurants (every 5 min)
// =============================
exports.sendPrepTimeReminders = functions.pubsub
  .schedule('every 5 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();
    const nowDate = now.toDate();
    let reminderCount = 0;

    console.log('[REMINDER] ===== SENDING PREP TIME REMINDERS =====');

    try {
      const ordersSnapshot = await db
        .collection('restaurant_orders')
        .where('status', '==', 'Driver Accepted')
        .limit(50)
        .get();

      for (const doc of ordersSnapshot.docs) {
        try {
          const orderData = doc.data() || {};
          const orderId = doc.id;

          if (orderData.autoMarkedReady) continue;

          let readyTime;
          if (orderData.readyAt) {
            readyTime = orderData.readyAt.toDate
              ? orderData.readyAt.toDate()
              : new Date(orderData.readyAt._seconds * 1000);
          } else {
            const acceptedAt = orderData.acceptedAt;
            if (!acceptedAt) continue;
            if (!orderData.estimatedTimeToPrepare) continue;
            const prepMinutes = parsePreparationMinutes(
              orderData.estimatedTimeToPrepare
            );
            const acceptedDate = acceptedAt.toDate
              ? acceptedAt.toDate()
              : new Date(acceptedAt._seconds * 1000);
            readyTime = new Date(
              acceptedDate.getTime() + prepMinutes * 60000
            );
          }
          const minutesUntilReady = Math.round(
            (readyTime.getTime() - nowDate.getTime()) / 60000
          );

          if (
            minutesUntilReady < 3 ||
            minutesUntilReady > 5 ||
            orderData?.dispatch?.prepTimeReminderSent
          ) {
            continue;
          }

          const vendorSnap = await db
            .collection('vendors')
            .doc(orderData.vendorID)
            .get();
          const vendorData = vendorSnap.exists ? vendorSnap.data() : {};
          const remindersEnabled = vendorData?.prepRemindersEnabled ?? true;
          const reminderMinutesPref = vendorData?.reminderMinutes ?? 5;

          if (
            !remindersEnabled ||
            minutesUntilReady > reminderMinutesPref
          ) {
            continue;
          }

          await _sendPrepTimeReminder(orderId, orderData, minutesUntilReady);
          await doc.ref.update({
            'dispatch.prepTimeReminderSent': true,
            'dispatch.prepTimeReminderAt':
              admin.firestore.FieldValue.serverTimestamp(),
          });
          reminderCount++;
        } catch (orderErr) {
          console.error(
            `[REMINDER] Error processing order ${doc.id}:`,
            orderErr
          );
        }
      }

      console.log(
        `[REMINDER] ===== COMPLETED: ${reminderCount} reminders sent =====`
      );
    } catch (err) {
      console.error('[REMINDER] Fatal error:', err);
    }

    return null;
  });

// =============================
// Dispatch health monitor (every 5 min)
// =============================
exports.monitorDispatchHealth = functions.pubsub
  .schedule('every 5 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const thirtyMinAgo = admin.firestore.Timestamp.fromDate(
      new Date(now.getTime() - 30 * 60 * 1000)
    );
    const fiveMinAgo = admin.firestore.Timestamp.fromDate(
      new Date(now.getTime() - 5 * 60 * 1000)
    );

    try {
      // 1) Calculate dispatch success rate over last 30 min
      const eventsSnap = await db
        .collection('dispatch_events')
        .where('createdAt', '>=', thirtyMinAgo)
        .limit(200)
        .get();

      let totalDispatches = 0;
      let successfulDispatches = 0;
      const rejectionsByOrder = {};

      for (const doc of eventsSnap.docs) {
        const d = doc.data() || {};
        totalDispatches++;
        if (d?.outcome?.wasAccepted === true) {
          successfulDispatches++;
        }
        const oid = d.orderId || '';
        if (oid) {
          rejectionsByOrder[oid] = (rejectionsByOrder[oid] || 0) + 1;
        }
      }

      const successRate = totalDispatches > 0
        ? (successfulDispatches / totalDispatches) * 100
        : 100;

      // 2) Check for orders stuck in Driver Rejected >5 min
      const stuckSnap = await db
        .collection('restaurant_orders')
        .where('status', '==', 'Driver Rejected')
        .where('statusChangedAt', '<=', fiveMinAgo)
        .limit(10)
        .get();

      const stuckCount = stuckSnap.size;

      // 3) Check avg rejections per order
      const rejectionCounts = Object.values(rejectionsByOrder);
      const avgRejections = rejectionCounts.length > 0
        ? rejectionCounts.reduce((a, b) => a + b, 0) / rejectionCounts.length
        : 0;

      const needsAlert =
        successRate < 50 ||
        stuckCount > 0 ||
        avgRejections > 3;

      if (needsAlert) {
        console.log(
          `[DispatchHealth] ALERT: successRate=${Math.round(successRate)}% ` +
          `stuck=${stuckCount} avgRejections=${avgRejections.toFixed(1)}`
        );

        // Send FCM to all admin users
        const adminsSnap = await db
          .collection('users')
          .where('role', '==', 'admin')
          .get();

        const tokens = [];
        for (const doc of adminsSnap.docs) {
          const t = doc.data()?.fcmToken;
          if (t) tokens.push(t);
        }

        if (tokens.length > 0) {
          const alerts = [];
          if (successRate < 50) alerts.push(`Success rate: ${Math.round(successRate)}%`);
          if (stuckCount > 0) alerts.push(`${stuckCount} stuck orders`);
          if (avgRejections > 3) alerts.push(`Avg ${avgRejections.toFixed(1)} rejections/order`);

          for (const token of tokens) {
            try {
              await getMessaging().send({
                token,
                notification: {
                  title: 'Dispatch Health Alert',
                  body: alerts.join(' | '),
                },
                data: {
                  type: 'dispatch_health_alert',
                  successRate: String(Math.round(successRate)),
                  stuckOrders: String(stuckCount),
                },
              });
            } catch (_) {}
          }
        }
      }

      // Log health snapshot
      await db.collection('dispatch_health_snapshots').add({
        successRate: Math.round(successRate * 10) / 10,
        totalDispatches,
        successfulDispatches,
        stuckCount,
        avgRejectionsPerOrder: Math.round(avgRejections * 10) / 10,
        alertTriggered: needsAlert,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('[DispatchHealth] Error:', e);
    }

    return null;
  });

// =============================
// Order batching cron (Phase 3)
// =============================

const BATCH_MAX_DELIVERY_SPREAD_METERS = 3000;

exports.orderBatchingCron = functions.pubsub
  .schedule('every 1 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();

    const pendingSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Order Accepted')
      .limit(50)
      .get();

    if (pendingSnap.empty) return null;

    const weights = await _loadDispatchWeights();
    const candidates = [];
    for (const doc of pendingSnap.docs) {
      const d = doc.data() || {};
      if (d.driverID) continue;
      if (d?.batch?.batchId) continue;
      const rLoc = _extractRestaurantLocation(d);
      const dLoc = _extractDeliveryLocation(d);
      if (!rLoc.lat || !rLoc.lng) continue;
      candidates.push({
        id: doc.id,
        ref: doc.ref,
        data: d,
        restaurantLocation: rLoc,
        deliveryLocation: dLoc,
      });
    }

    if (candidates.length < 2) return null;

    const used = new Set();
    const batches = [];

    for (let i = 0; i < candidates.length; i++) {
      if (used.has(i)) continue;
      const anchor = candidates[i];
      const group = [anchor];
      used.add(i);

      for (let j = i + 1; j < candidates.length; j++) {
        if (used.has(j)) continue;
        const maxBatchSize = weights.baseCapacity || MAX_ACTIVE_ORDERS_PER_RIDER;
        if (group.length >= maxBatchSize) break;

        const other = candidates[j];
        const restaurantDist = _distanceMeters(
          anchor.restaurantLocation,
          other.restaurantLocation,
        );
        if (restaurantDist > STACK_RADIUS_METERS) continue;

        const deliveryDist = _distanceMeters(
          anchor.deliveryLocation,
          other.deliveryLocation,
        );
        if (deliveryDist > BATCH_MAX_DELIVERY_SPREAD_METERS) continue;

        group.push(other);
        used.add(j);
      }

      if (group.length >= 2) {
        batches.push(group);
      }
    }

    if (batches.length === 0) return null;

    for (const group of batches) {
      try {
        const orderIds = group.map((o) => o.id);
        const vendorIds = [
          ...new Set(group.map((o) => String(o.data.vendorID || ''))),
        ];

        let cLat = 0;
        let cLng = 0;
        for (const o of group) {
          cLat += o.restaurantLocation.lat;
          cLng += o.restaurantLocation.lng;
        }
        cLat /= group.length;
        cLng /= group.length;

        const stops = [];
        let seq = 1;
        for (const o of group) {
          stops.push({
            orderId: o.id,
            lat: o.restaurantLocation.lat,
            lng: o.restaurantLocation.lng,
            type: 'pickup',
            sequence: seq++,
          });
        }
        for (const o of group) {
          stops.push({
            orderId: o.id,
            lat: o.deliveryLocation.lat,
            lng: o.deliveryLocation.lng,
            type: 'delivery',
            sequence: seq++,
          });
        }

        let totalDist = 0;
        for (let k = 1; k < stops.length; k++) {
          totalDist += _distanceMeters(
            { lat: stops[k - 1].lat, lng: stops[k - 1].lng },
            { lat: stops[k].lat, lng: stops[k].lng },
          );
        }

        const batchRef = await db.collection('order_batches').add({
          orderIds,
          status: 'pending',
          restaurantCluster: { centerLat: cLat, centerLng: cLng, vendorIds },
          deliveryRoute: {
            stops,
            totalDistanceKm: Math.round(totalDist) / 1000,
          },
          assignedDriverId: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          assignedAt: null,
        });

        const batchId = batchRef.id;

        for (let idx = 0; idx < group.length; idx++) {
          await group[idx].ref.update({
            'batch.batchId': batchId,
            'batch.sequence': idx + 1,
            'batch.totalInBatch': group.length,
          });
        }

        const { selected, candidates: driverCandidates, stackDecision } =
          await _pickBestDriverForOrder({
            orderId: group[0].id,
            orderData: group[0].data,
            excludeDriverIds: [],
          });

        if (selected) {
          await _offerBatchToDriver({
            batchId,
            batchRef,
            group,
            driverId: selected.driverId,
            driverData: selected.driverData,
            candidates: driverCandidates,
            stackDecision,
          });
        }

        console.log(
          `[Batching] Created batch ${batchId} with ${orderIds.length} orders` +
          (selected ? `, assigned to ${selected.driverId}` : ', no driver available'),
        );
      } catch (e) {
        console.error('[Batching] Error creating batch:', e);
      }
    }

    return null;
  });

async function _offerBatchToDriver({
  batchId,
  batchRef,
  group,
  driverId,
  driverData,
  candidates,
  stackDecision,
}) {
  const now = _nowTimestamp();
  const timeoutSec = await _getRiderTimeoutSeconds();
  const deadline = _addSeconds(now, timeoutSec);

  for (let idx = 0; idx < group.length; idx++) {
    await group[idx].ref.update({
      status: 'Driver Assigned',
      driverID: driverId,
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      'dispatch.riderAcceptDeadline': deadline,
      'dispatch.lock': false,
      'batch.batchId': batchId,
      'batch.sequence': idx + 1,
      'batch.totalInBatch': group.length,
    });
  }

  await batchRef.update({
    status: 'assigned',
    assignedDriverId: driverId,
    assignedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await getDb()
    .collection('users')
    .doc(driverId)
    .set(
      {
        orderRequestData: admin.firestore.FieldValue.arrayUnion(
          ...group.map((o) => o.id),
        ),
      },
      { merge: true },
    );

  const fcmToken = driverData?.fcmToken;
  if (fcmToken) {
    try {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: `Batch Order (${group.length} stops)`,
          body: `You have been assigned ${group.length} orders for pickup and delivery.`,
        },
        data: {
          type: 'batch_order_assignment',
          batchId,
          orderCount: String(group.length),
        },
      });
    } catch (fcmErr) {
      console.error(`[Batching] FCM error for ${driverId}:`, fcmErr);
    }
  }

  const batchWeights = await _loadDispatchWeights();
  await _logDispatchEvent({
    type: 'batch_assigned',
    orderId: group[0].id,
    riderId: driverId,
    batchId,
    factors: {
      orderCount: group.length,
      riderCurrentOrders: 0,
    },
    alternativeRiders: (candidates || []).slice(0, 5).map((c) => ({
      riderId: c.driverId,
      score: c.compositeScore || 0,
      distance: c.distance || 0,
    })),
    activeWeights: {
      weightETA: batchWeights.weightETA,
      weightWorkload: batchWeights.weightWorkload,
      weightDirection: batchWeights.weightDirection,
      weightAcceptanceProb: batchWeights.weightAcceptanceProb,
      weightFairness: batchWeights.weightFairness,
    },
    payload: {
      batchId,
      orderIds: group.map((o) => o.id),
      driverId,
      orderCount: group.length,
    },
  });
}

/**
 * Calculate ETA based on distance between two locations
 * Uses simplified Haversine formula for straight-line distance
 * @param {Object} from - {lat, lng}
 * @param {Object} to - {lat, lng}
 * @returns {number} ETA in minutes
 */
function calculateETA(from, to) {
  const R = 6371; // Radius of Earth in km
  const dLat = toRad(to.lat - from.lat);
  const dLng = toRad(to.lng - from.lng);
  
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(from.lat)) * Math.cos(toRad(to.lat)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distanceKm = R * c;
  
  // Assume average speed of 30 km/h in city traffic
  const etaMinutes = (distanceKm / 30) * 60;
  
  return Math.max(etaMinutes, 1); // Minimum 1 minute
}

function toRad(degrees) {
  return degrees * (Math.PI / 180);
}

/**
 * Calculate acceptance probability using historical assignment data.
 * Replaces the previous stub with real weighted scoring.
 * @param {Object} driver - Driver data (must have .id)
 * @param {Object} order - Order data
 * @param {number} eta - Calculated ETA in minutes
 * @returns {Promise<number>} Acceptance probability (0-1)
 */
async function getMLAcceptanceProbability(driver, order, eta) {
  const cachedW = _dispatchWeightsCache || {};
  let baseRate = cachedW.baseAcceptanceRate || 0.7;

  try {
    const logs = await getDb()
      .collection('assignments_log')
      .where('driverId', '==', driver.id)
      .orderBy('createdAt', 'desc')
      .limit(20)
      .get();

    if (!logs.empty) {
      let accepted = 0;
      let recentRejects = 0;
      let countingStreak = true;

      for (const doc of logs.docs) {
        const s = String(doc.data().status || '');
        if (s === 'accepted') {
          accepted++;
          countingStreak = false;
        } else if (s === 'rejected' || s === 'timeout') {
          if (countingStreak) recentRejects++;
        } else {
          countingStreak = false;
        }
      }

      baseRate = accepted / logs.docs.length;
      if (recentRejects >= 2) baseRate *= 0.7;
    }
  } catch (_) {
    // Fall back to default base rate
  }

  const distancePenalty = Math.min(eta / 60, 0.3);
  const activeOrders = _activeOrdersCount(driver);
  const workloadPenalty = activeOrders * 0.15;

  const hour = new Date().getHours();
  const timeBonus = (hour >= 10 && hour <= 21) ? 0.05 : 0;

  return Math.max(0.05, Math.min(0.95,
    baseRate - distancePenalty - workloadPenalty + timeBonus
  ));
}

/**
 * Batch acceptance probability for multiple drivers.
 * Uses chunked 'in' queries instead of N individual queries.
 */
async function getMLAcceptanceProbabilityBatch(driverIds) {
  const cachedW = _dispatchWeightsCache || {};
  const cfgBaseRate = cachedW.baseAcceptanceRate || 0.7;
  const baseRates = {};
  for (const id of driverIds) baseRates[id] = cfgBaseRate;

  try {
    for (let i = 0; i < driverIds.length; i += 30) {
      const chunk = driverIds.slice(i, i + 30);
      const logs = await getDb()
        .collection('assignments_log')
        .where('driverId', 'in', chunk)
        .orderBy('createdAt', 'desc')
        .limit(20 * chunk.length)
        .get();

      const grouped = {};
      for (const doc of logs.docs) {
        const d = doc.data();
        const did = String(d.driverId || '');
        if (!grouped[did]) grouped[did] = [];
        if (grouped[did].length < 20) grouped[did].push(String(d.status || ''));
      }

      for (const [did, statuses] of Object.entries(grouped)) {
        let accepted = 0, recentRejects = 0, countingStreak = true;
        for (const s of statuses) {
          if (s === 'accepted') { accepted++; countingStreak = false; }
          else if (s === 'rejected' || s === 'timeout') { if (countingStreak) recentRejects++; }
          else { countingStreak = false; }
        }
        let rate = accepted / statuses.length;
        if (recentRejects >= 2) rate *= 0.7;
        baseRates[did] = rate;
      }
    }
  } catch (_) {}

  return baseRates;
}

/**
 * Batch fairness scores using pre-aggregated completedToday field.
 */
function calculateFairnessScoreBatch(drivers) {
  const scores = {};
  for (const d of drivers) {
    const completed = d.completedToday || 0;
    scores[d.id] = Math.min(completed * 5, 100);
  }
  return scores;
}

/**
 * Calculate fairness score based on driver's completed orders
 * Lower score = driver deserves more orders (fairness)
 * @param {string} driverId
 * @returns {Promise<number>} Fairness score (0-100)
 */
async function calculateFairnessScore(driverId) {
  try {
    // Get orders completed by this driver today
    const todayStart = new admin.firestore.Timestamp(
      Math.floor(new Date().setHours(0, 0, 0, 0) / 1000),
      0
    );

    const ordersSnapshot = await getDb().collection('restaurant_orders')
      .where('driverID', '==', driverId)
      .where('status', 'in', ['Order Completed', 'completed'])
      .where('deliveredAt', '>=', todayStart)
      .get();

    const completedToday = ordersSnapshot.size;

    // Lower score for drivers with fewer completed orders
    // Scale: 0-20 orders -> score 0-100
    const fairnessScore = Math.min(completedToday * 5, 100);

    return fairnessScore;
  } catch (error) {
    console.error(`[AutoDispatcher] Error calculating fairness score:`, error);
    return 50; // Default middle score on error
  }
}

// --- Dispatch weights cache (60s TTL) ---
let _dispatchWeightsCache = null;
let _dispatchWeightsCacheTime = 0;
const WEIGHTS_CACHE_TTL_MS = 60000;

const DEFAULT_DISPATCH_WEIGHTS = {
  weightETA: 0.35,
  weightWorkload: 0.20,
  weightDirection: 0.15,
  weightAcceptanceProb: 0.20,
  weightFairness: 0.10,
  prepAlignmentPenaltyBase: 0.05,
  prepAlignmentPenaltyPeak: 0.10,
  peakHourStart: 11,
  peakHourEnd: 14,
  peakHourStart2: 17,
  peakHourEnd2: 21,
  maxActiveOrdersPerRider: 2,
  riderTimeoutSeconds: 60,
  dynamicCapacityEnabled: true,
  baseCapacity: 2,
  peakCapacityReduction: 1,
  complexityThresholdItems: 5,
  complexityThresholdHeavy: 8,
  longDistanceThresholdKm: 5.0,
  performanceBoostThreshold: 90.0,
  performancePenaltyThreshold: 65.0,
  weatherCondition: 'normal',
  timeoutChecker: {
    enabled: true,
    frequencySeconds: 10,
    batchSize: 50,
  },
};

async function _loadDispatchWeights() {
  const now = Date.now();
  if (_dispatchWeightsCache && (now - _dispatchWeightsCacheTime) < WEIGHTS_CACHE_TTL_MS) {
    return _dispatchWeightsCache;
  }
  try {
    const doc = await getDb().collection('config').doc('dispatch_weights').get();
    if (doc.exists) {
      _dispatchWeightsCache = { ...DEFAULT_DISPATCH_WEIGHTS, ...doc.data() };
    } else {
      _dispatchWeightsCache = { ...DEFAULT_DISPATCH_WEIGHTS };
    }
  } catch (_) {
    _dispatchWeightsCache = _dispatchWeightsCache || { ...DEFAULT_DISPATCH_WEIGHTS };
  }
  _dispatchWeightsCacheTime = now;
  return _dispatchWeightsCache;
}

async function _getRiderTimeoutSeconds() {
  const w = await _loadDispatchWeights();
  return Math.max(30, Math.min(180, (w.riderTimeoutSeconds ?? 60)));
}

function _isPeakHour(w) {
  const hour = new Date().getHours();
  return (hour >= w.peakHourStart && hour < w.peakHourEnd) ||
         (hour >= w.peakHourStart2 && hour < w.peakHourEnd2);
}

// --- Dynamic capacity helpers ---

function _calculateDynamicCapacity(driverData, w) {
  const multipleOrders = driverData?.multipleOrders === true;
  if (!multipleOrders) return 1;
  if (!w.dynamicCapacityEnabled) return w.maxActiveOrdersPerRider || 2;

  let cap = w.baseCapacity || 2;

  if (_isPeakHour(w)) cap -= (w.peakCapacityReduction || 1);

  const perf = _asNumber(driverData?.driver_performance) || 0;
  if (perf >= (w.performanceBoostThreshold || 90)) cap += 1;
  else if (perf < (w.performancePenaltyThreshold || 65)) cap -= 1;

  const weather = w.weatherCondition || 'normal';
  if (weather === 'rain') cap -= 1;
  else if (weather === 'storm') cap -= 2;

  return Math.max(1, Math.min(4, cap));
}

function _orderComplexityWeight(orderData, w) {
  const products = orderData?.products;
  let itemCount = 1;
  if (Array.isArray(products)) itemCount = products.length;
  else if (orderData?.orderItemCount) itemCount = Number(orderData.orderItemCount) || 1;

  const heavy = w.complexityThresholdHeavy || 8;
  const complex = w.complexityThresholdItems || 5;
  if (itemCount >= heavy) return 2.0;
  if (itemCount >= complex) return 1.5;
  return 1.0;
}

function _distanceWeight(distanceKm, w) {
  const threshold = w.longDistanceThresholdKm || 5.0;
  return distanceKm > threshold ? 1.5 : 1.0;
}

// --- Unified rider status computation ---

function _computeRiderStatus(driverData, weights) {
  const w = weights || _dispatchWeightsCache || DEFAULT_DISPATCH_WEIGHTS;
  const isV2 = _isSchemaV2Driver(driverData);

  if (driverData.suspended === true ||
      String(driverData.attendanceStatus || '').toLowerCase() === 'suspended') {
    return { riderAvailability: 'offline', riderDisplayStatus: '🔴 Suspended' };
  }

  if (isV2) {
    if (driverData.isOnline !== true) {
      return { riderAvailability: 'offline', riderDisplayStatus: '⚪ Offline' };
    }
    if (driverData.riderAvailability === 'on_break') {
      return { riderAvailability: 'on_break', riderDisplayStatus: '⏸ On Break' };
    }
  } else {
    const isCheckedOut = driverData.checkedOutToday === true ||
      (driverData.todayCheckOutTime != null &&
       String(driverData.todayCheckOutTime || '').trim() !== '');
    if (isCheckedOut) {
      return { riderAvailability: 'offline', riderDisplayStatus: '⚫ Checked Out' };
    }
    if (driverData.riderAvailability === 'on_break') {
      return { riderAvailability: 'on_break', riderDisplayStatus: '⏸ On Break' };
    }
    if (driverData.checkedInToday !== true || driverData.isOnline !== true) {
      return { riderAvailability: 'offline', riderDisplayStatus: '⚪ Offline' };
    }
  }

  const activeOrders = _activeOrdersCount(driverData);
  if (activeOrders > 0) {
    const cap = _getDriverMaxOrders(driverData, w);
    if (activeOrders >= cap) {
      return { riderAvailability: 'on_delivery', riderDisplayStatus: '🟡 On Delivery' };
    }
    return { riderAvailability: 'available', riderDisplayStatus: '🟡 On Delivery' };
  }
  return { riderAvailability: 'available', riderDisplayStatus: '🟢 Available' };
}

/**
 * Compute heading match using cosine similarity of movement vs target vectors.
 * Returns 0.5 (neutral) when previous location is unavailable.
 */
function _calculateDriverHeading(driverData, driverLocation, restaurantLocation) {
  const prev = driverData?.previousLocation || driverData?.lastLocation;
  if (!prev) return 0.5;

  const prevLat = _asNumber(prev.latitude || prev.lat);
  const prevLng = _asNumber(prev.longitude || prev.lng);
  if (!prevLat && !prevLng) return 0.5;

  const moveDx = driverLocation.lng - prevLng;
  const moveDy = driverLocation.lat - prevLat;
  const targetDx = restaurantLocation.lng - driverLocation.lng;
  const targetDy = restaurantLocation.lat - driverLocation.lat;

  const dot = moveDx * targetDx + moveDy * targetDy;
  const magMove = Math.sqrt(moveDx * moveDx + moveDy * moveDy);
  const magTarget = Math.sqrt(targetDx * targetDx + targetDy * targetDy);

  if (magMove === 0 || magTarget === 0) return 0.5;

  const cosine = Math.max(-1, Math.min(1, dot / (magMove * magTarget)));
  return (cosine + 1) / 2;
}

/**
 * Unified composite score (lower is better). Mirrors DispatchScoringService.
 */
function calculateCompositeScore({ eta, mlAcceptanceProbability, fairnessScore, headingMatch, currentOrders, restaurantPrepMinutes, effectiveCapacity }) {
  const w = _dispatchWeightsCache || DEFAULT_DISPATCH_WEIGHTS;
  const maxOrders = effectiveCapacity || w.maxActiveOrdersPerRider || 2;

  const etaFactor = Math.min(eta / 30, 2.0);
  const workloadFactor = (currentOrders || 0) / maxOrders;
  const directionFactor = 1.0 - Math.max(0, Math.min(1, headingMatch || 0.5));
  const acceptanceFactor = 1.0 - Math.max(0, Math.min(1, mlAcceptanceProbability));
  const fairnessFactor = Math.min(fairnessScore / 100, 1.0);

  let prepPenalty = 0;
  const prepMin = restaurantPrepMinutes || 0;
  if (prepMin > 0 && eta < prepMin) {
    prepPenalty = Math.min((prepMin - eta) / 15, 1.0);
  }
  const isPeak = _isPeakHour(w);
  const prepWeight = isPeak ? w.prepAlignmentPenaltyPeak : w.prepAlignmentPenaltyBase;

  return (etaFactor * w.weightETA) +
         (workloadFactor * w.weightWorkload) +
         (directionFactor * w.weightDirection) +
         (acceptanceFactor * w.weightAcceptanceProb) +
         (fairnessFactor * w.weightFairness) +
         (prepPenalty * prepWeight);
}

/**
 * Auto-Collect Scheduled Cloud Function
 * 
 * Runs every hour to check and execute scheduled auto-collections for drivers
 * - Checks all drivers with auto-collect enabled
 * - Validates schedule time matches current hour
 * - Prevents duplicate collections within the same hour
 * - Executes collection if conditions are met
 */
exports.autoCollectScheduled = functions.pubsub
  .schedule('every 1 hours')
  .timeZone('Asia/Manila')
  .onRun(async (context) => {
    try {
      console.log('[AutoCollect] Starting scheduled auto-collection check');

      const now = new Date();
      const currentHour = now.getHours();
      const currentMinute = now.getMinutes();
      const currentHourString = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}-${String(currentHour).padStart(2, '0')}`;

      // Get all drivers with auto-collect enabled
      const driversSnapshot = await getDb().collection('users')
        .where('role', '==', 'driver')
        .get();

      if (driversSnapshot.empty) {
        console.log('[AutoCollect] No drivers found');
        return null;
      }

      let processedCount = 0;
      let successCount = 0;
      let skippedCount = 0;
      let errorCount = 0;

      for (const driverDoc of driversSnapshot.docs) {
        try {
          const driver = { id: driverDoc.id, ...driverDoc.data() };
          const autoCollectSettings = driver.autoCollectSettings;

          // Skip if auto-collect is not enabled
          if (!autoCollectSettings || !autoCollectSettings.enabled) {
            continue;
          }

          processedCount++;

          const scheduleTime = autoCollectSettings.scheduleTime || '';
          if (!scheduleTime) {
            console.log(`[AutoCollect] Driver ${driver.id} has no schedule time`);
            skippedCount++;
            continue;
          }

          // Parse schedule time (HH:mm format)
          const timeParts = scheduleTime.split(':');
          if (timeParts.length !== 2) {
            console.log(`[AutoCollect] Invalid schedule time format for driver ${driver.id}: ${scheduleTime}`);
            skippedCount++;
            continue;
          }

          const scheduleHour = parseInt(timeParts[0], 10);
          const scheduleMinute = parseInt(timeParts[1], 10);

          if (isNaN(scheduleHour) || isNaN(scheduleMinute)) {
            console.log(`[AutoCollect] Invalid schedule time values for driver ${driver.id}`);
            skippedCount++;
            continue;
          }

          // Check if current hour matches schedule hour
          if (currentHour !== scheduleHour) {
            continue; // Not time for this driver yet
          }

          // Check duplicate prevention - same hour
          const lastCollectionHour = autoCollectSettings.lastCollectionHour;
          if (lastCollectionHour === currentHourString) {
            console.log(`[AutoCollect] Driver ${driver.id} already collected this hour`);
            skippedCount++;
            continue;
          }

          // Get collection amount
          const amount = autoCollectSettings.amount || 0;
          if (amount <= 0) {
            console.log(`[AutoCollect] Invalid amount for driver ${driver.id}: ${amount}`);
            skippedCount++;
            continue;
          }

          // Check if collection is already in progress (lock check)
          if (driver.collectionInProgress === true) {
            const lockTimestamp = driver.collectionLockTimestamp;
            if (lockTimestamp) {
              const lockAge = (now.getTime() - lockTimestamp.toMillis()) / 1000 / 60; // minutes
              if (lockAge > 5) {
                // Stale lock - will be released in transaction
                console.log(`[AutoCollect] Driver ${driver.id} has stale lock, will attempt collection`);
              } else {
                console.log(`[AutoCollect] Driver ${driver.id} has active collection lock, skipping`);
                skippedCount++;
                continue;
              }
            } else {
              console.log(`[AutoCollect] Driver ${driver.id} has collection lock but no timestamp, skipping`);
              skippedCount++;
              continue;
            }
          }

          // Get driver wallet balance
          const walletAmount = driver.wallet_amount || 0;

          // Enhanced validation: ensure balance is non-negative
          if (walletAmount < 0) {
            console.log(`[AutoCollect] Invalid wallet state for driver ${driver.id}: balance is negative (${walletAmount})`);
            skippedCount++;
            continue;
          }

          // Validate sufficient balance
          if (walletAmount < amount) {
            console.log(`[AutoCollect] Insufficient balance for driver ${driver.id}. Available: ${walletAmount}, Required: ${amount}`);
            skippedCount++;
            continue;
          }

          // Execute collection
          const driverName = `${driver.firstName || ''} ${driver.lastName || ''}`.trim() || 'Unknown Driver';
          const collectionId = getDb().collection('driver_collections').doc().id;
          const nowTimestamp = admin.firestore.Timestamp.now();
          const driverRef = getDb().collection('users').doc(driver.id);

          // Capture wallet balances
          let walletBalanceBefore = 0;
          let walletBalanceAfter = 0;

          try {
            // Use transaction for atomicity
            await getDb().runTransaction(async (transaction) => {
              const driverSnap = await transaction.get(driverRef);

              if (!driverSnap.exists) {
                throw new Error('Driver not found');
              }

              const driverData = driverSnap.data();
              
              // Check and acquire lock within transaction
              const isLocked = driverData.collectionInProgress === true;
              const lockTimestamp = driverData.collectionLockTimestamp;
              
              if (isLocked && lockTimestamp) {
                const lockAge = (now.getTime() - lockTimestamp.toMillis()) / 1000 / 60; // minutes
                if (lockAge > 5) {
                  // Release stale lock and acquire new one
                  console.log(`[AutoCollect] Releasing stale lock for driver ${driver.id}`);
                } else {
                  throw new Error('Collection already in progress');
                }
              }

              // Acquire lock
              transaction.update(driverRef, {
                'collectionInProgress': true,
                'collectionLockTimestamp': admin.firestore.FieldValue.serverTimestamp(),
              });

              const currentWallet = driverData.wallet_amount || 0;

              // Enhanced validation: double-check balance in transaction
              if (currentWallet < 0) {
                throw new Error(`Invalid wallet state: balance is negative (${currentWallet})`);
              }

              // Store wallet balance before collection
              walletBalanceBefore = currentWallet;

              // Re-validate balance in transaction
              if (currentWallet < amount) {
                throw new Error(`Insufficient balance: ${currentWallet} < ${amount}`);
              }

              const newWalletAmount = currentWallet - amount;

              // Enhanced validation: prevent negative balance
              if (newWalletAmount < 0) {
                throw new Error(`Invalid balance calculation: ${currentWallet} - ${amount} = ${newWalletAmount}`);
              }

              // Store wallet balance after collection
              walletBalanceAfter = newWalletAmount;

              // Get existing collectionRequests array
              const collectionRequests = driverData.collectionRequests || [];

              // Create collection entry
              const collectionEntry = {
                id: collectionId,
                amount: amount,
                reason: 'Auto-collection',
                collectedBy: 'system',
                collectedByName: 'Auto-Collect System',
                createdAt: nowTimestamp,
                status: 'completed',
                collectionType: 'auto',
                isAutoCollection: true,
              };

              // Get current failed attempts count
              const failedAttempts = autoCollectSettings.failedAttempts || 0;

              // Update driver document with lock release and reset failed attempts on success
              transaction.update(driverRef, {
                wallet_amount: newWalletAmount,
                collectionRequests: [...collectionRequests, collectionEntry],
                'autoCollectSettings.lastCollectionAt': nowTimestamp,
                'autoCollectSettings.lastCollectionHour': currentHourString,
                'autoCollectSettings.updatedAt': nowTimestamp,
                'autoCollectSettings.failedAttempts': 0, // Reset on success
                'autoCollectSettings.lastFailureReason': null,
                'collectionInProgress': false,
                'collectionLockTimestamp': null,
                'lastCollectionCompletedAt': nowTimestamp,
              });
            });

            // Create collection document (outside transaction)
            // Records are immutable - created once, never updated
            await getDb().collection('driver_collections').doc(collectionId).set({
              collectionId: collectionId,
              driverId: driver.id,
              driverName: driverName,
              amount: amount,
              collectionType: 'auto',
              isAutoCollection: true,
              reason: 'Auto-collection',
              walletBalanceBefore: walletBalanceBefore,
              walletBalanceAfter: walletBalanceAfter,
              collectedBy: 'system',
              collectedByName: 'Auto-Collect System',
              createdAt: nowTimestamp,
              status: 'completed',
              immutable: true,
            });

            console.log(`[AutoCollect] Successfully collected ₱${amount} from driver ${driver.id} (${driverName})`);
            successCount++;

          } catch (error) {
            console.error(`[AutoCollect] Error processing driver ${driver.id}:`, error);
            
            // Release lock on error
            try {
              await driverRef.update({
                'collectionInProgress': false,
                'collectionLockTimestamp': null,
              });
            } catch (lockError) {
              console.error(`[AutoCollect] Error releasing lock for driver ${driver.id}:`, lockError);
            }

            // Track failed attempts and implement retry logic
            const failedAttempts = (autoCollectSettings.failedAttempts || 0) + 1;
            const maxRetries = 3;

            if (failedAttempts < maxRetries) {
              // Mark for retry on next hour
              await driverRef.update({
                'autoCollectSettings.failedAttempts': failedAttempts,
                'autoCollectSettings.lastFailedAt': admin.firestore.FieldValue.serverTimestamp(),
                'autoCollectSettings.lastFailureReason': error.message || error.toString(),
              });
              console.log(`[AutoCollect] Driver ${driver.id} marked for retry (attempt ${failedAttempts}/${maxRetries})`);
              skippedCount++; // Count as skipped, will retry next hour
            } else {
              // Disable auto-collect after max retries
              await driverRef.update({
                'autoCollectSettings.enabled': false,
                'autoCollectSettings.failedAttempts': failedAttempts,
                'autoCollectSettings.lastFailedAt': admin.firestore.FieldValue.serverTimestamp(),
                'autoCollectSettings.lastFailureReason': error.message || error.toString(),
                'autoCollectSettings.disabledReason': 'Too many failed attempts',
                'autoCollectSettings.disabledAt': admin.firestore.FieldValue.serverTimestamp(),
              });
              console.log(`[AutoCollect] Auto-collect disabled for driver ${driver.id} after ${maxRetries} failed attempts`);
              errorCount++;
            }
          }
        } catch (error) {
          console.error(error);
        }
      }

      console.log(`[AutoCollect] Completed. Processed: ${processedCount}, Success: ${successCount}, Skipped: ${skippedCount}, Errors: ${errorCount}`);
      return {
        processed: processedCount,
        success: successCount,
        skipped: skippedCount,
        errors: errorCount,
      };

    } catch (error) {
      console.error('[AutoCollect] Fatal error in scheduled function:', error);
      throw error;
    }
  });

/**
 * Send Happy Hour FCM Notifications
 * 
 * HTTP function to send push notifications to all active customers
 * about Happy Hour promotions
 * 
 * POST body: { title: string, body: string }
 * Returns: { success: boolean, sentCount: number, errorCount: number, errors: array }
 */
exports.handlePaymentFailure = handlePaymentFailure;

exports.sendHappyHourNotifications = functions.region('us-central1').https.onRequest(async (req, res) => {
  try {
    if (handleCors(req, res)) {
      return;
    }

    // Only allow POST requests
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed. Use POST.' });
      return;
    }

    const { title, body } = req.body;

    if (!title || !body) {
      res.status(400).json({ error: 'Title and body are required' });
      return;
    }

    console.log('[HappyHourNotifications] Starting notification broadcast');
    console.log('[HappyHourNotifications] Title:', title);
    console.log('[HappyHourNotifications] Body:', body);

    // Fetch all active customers with FCM tokens
    const usersSnapshot = await getDb().collection('users')
      .where('role', '==', 'customer')
      .where('active', '==', true)
      .get();

    console.log(`[HappyHourNotifications] Total users queried: ${usersSnapshot.size}`);

    if (usersSnapshot.empty) {
      console.log('[HappyHourNotifications] No active customers found');
      res.json({
        success: true,
        sentCount: 0,
        errorCount: 0,
        totalUsers: 0,
        message: 'No active customers found'
      });
      return;
    }

    // Collect valid FCM tokens
    const fcmTokens = [];
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      
      if (fcmToken && typeof fcmToken === 'string' && fcmToken.trim().length > 0) {
        fcmTokens.push(fcmToken);
      }
    }

    console.log(`[HappyHourNotifications] Users with valid FCM tokens: ${fcmTokens.length} out of ${usersSnapshot.size}`);

    if (fcmTokens.length === 0) {
      console.log('[HappyHourNotifications] No users with valid FCM tokens found');
      res.json({
        success: true,
        sentCount: 0,
        errorCount: 0,
        totalUsers: usersSnapshot.size,
        message: 'No users with valid FCM tokens found'
      });
      return;
    }

    console.log(`[HappyHourNotifications] Sending to ${fcmTokens.length} users`);

    // FCM allows up to 500 tokens per multicast message
    const BATCH_SIZE = 500;
    let sentCount = 0;
    let errorCount = 0;
    const errors = [];

    // Send in batches
    for (let i = 0; i < fcmTokens.length; i += BATCH_SIZE) {
      const batch = fcmTokens.slice(i, i + BATCH_SIZE);
      const batchNumber = Math.floor(i / BATCH_SIZE) + 1;
      
      try {
        console.log(`[HappyHourNotifications] Sending batch ${batchNumber} with ${batch.length} tokens`);
        
        // Create multicast message
        const message = {
          notification: {
            title: title,
            body: body,
          },
          data: {
            type: 'happy_hour',
            timestamp: Date.now().toString(),
          },
          tokens: batch,
        };

        const response = await getMessaging().sendEachForMulticast(message);
        
        sentCount += response.successCount;
        errorCount += response.failureCount;

        // Log errors if any with enhanced error codes
        if (response.failureCount > 0) {
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              const errorCode = resp.error?.code || 'UNKNOWN';
              const errorMessage = resp.error?.message || 'Unknown error';
              const tokenPreview = batch[idx].substring(0, 20);
              
              console.error(`[HappyHourNotifications] Token failure - Code: ${errorCode}, Message: ${errorMessage}, Token: ${tokenPreview}...`);
              
              errors.push({
                token: batch[idx],
                errorCode: errorCode,
                error: errorMessage
              });
            }
          });
        }

        console.log(`[HappyHourNotifications] Batch ${batchNumber}: ${response.successCount} sent, ${response.failureCount} failed`);
      } catch (batchError) {
        console.error(`[HappyHourNotifications] Error sending batch ${batchNumber}:`, batchError);
        errorCount += batch.length;
        errors.push({
          batch: batchNumber,
          error: batchError.message || 'Batch send failed',
          errorCode: batchError.code || 'BATCH_SEND_ERROR'
        });
      }
    }

    console.log(`[HappyHourNotifications] Completed: ${sentCount} sent, ${errorCount} failed out of ${fcmTokens.length} total`);

    res.json({
      success: true,
      sentCount: sentCount,
      errorCount: errorCount,
      totalUsers: fcmTokens.length,
      errors: errors.slice(0, 10) // Return first 10 errors to avoid payload size issues
    });

  } catch (error) {
    console.error('[HappyHourNotifications] Fatal error:', error);
    res.status(500).json({ 
      success: false,
      error: error.message || 'Failed to send notifications' 
    });
  }
});

/**
 * Send Broadcast FCM Notifications
 * 
 * HTTP function to send push notifications to all active customers
 * Supports Announcements, Information, and General notifications
 * 
 * POST body: { title: string, body: string, type: string, imageUrl?: string, deepLink?: string, targetScreen?: string }
 * Returns: { success: boolean, sentCount: number, errorCount: number, errors: array }
 */
exports.sendBroadcastNotifications = functions.region('us-central1').https.onRequest(async (req, res) => {
  try {
    if (handleCors(req, res)) {
      return;
    }

    // Only allow POST requests
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed. Use POST.' });
      return;
    }

    const { title, body, type, imageUrl, deepLink, targetScreen } = req.body;

    if (!title || !body || !type) {
      res.status(400).json({ error: 'Title, body, and type are required' });
      return;
    }

    // Validate notification type
    const validTypes = ['announcement', 'information', 'general'];
    if (!validTypes.includes(type)) {
      res.status(400).json({ error: `Type must be one of: ${validTypes.join(', ')}` });
      return;
    }

    console.log('[BroadcastNotifications] Starting notification broadcast');
    console.log('[BroadcastNotifications] Title:', title);
    console.log('[BroadcastNotifications] Body:', body);
    console.log('[BroadcastNotifications] Type:', type);
    if (imageUrl) console.log('[BroadcastNotifications] Image URL:', imageUrl);
    if (deepLink) console.log('[BroadcastNotifications] Deep Link:', deepLink);
    if (targetScreen) console.log('[BroadcastNotifications] Target Screen:', targetScreen);

    // Fetch all active customers with FCM tokens
    const usersSnapshot = await getDb().collection('users')
      .where('role', '==', 'customer')
      .where('active', '==', true)
      .get();

    console.log(`[BroadcastNotifications] Total users queried: ${usersSnapshot.size}`);

    if (usersSnapshot.empty) {
      console.log('[BroadcastNotifications] No active customers found');
      res.json({
        success: true,
        sentCount: 0,
        errorCount: 0,
        totalUsers: 0,
        message: 'No active customers found'
      });
      return;
    }

    // Collect valid FCM tokens
    const fcmTokens = [];
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const fcmToken = userData.fcmToken;
      
      if (fcmToken && typeof fcmToken === 'string' && fcmToken.trim().length > 0) {
        fcmTokens.push(fcmToken);
      }
    }

    console.log(`[BroadcastNotifications] Users with valid FCM tokens: ${fcmTokens.length} out of ${usersSnapshot.size}`);

    if (fcmTokens.length === 0) {
      console.log('[BroadcastNotifications] No users with valid FCM tokens found');
      res.json({
        success: true,
        sentCount: 0,
        errorCount: 0,
        totalUsers: usersSnapshot.size,
        message: 'No users with valid FCM tokens found'
      });
      return;
    }

    console.log(`[BroadcastNotifications] Sending to ${fcmTokens.length} users`);

    // FCM allows up to 500 tokens per multicast message
    const BATCH_SIZE = 500;
    let sentCount = 0;
    let errorCount = 0;
    const errors = [];

    // Send in batches
    for (let i = 0; i < fcmTokens.length; i += BATCH_SIZE) {
      const batch = fcmTokens.slice(i, i + BATCH_SIZE);
      const batchNumber = Math.floor(i / BATCH_SIZE) + 1;
      
      try {
        console.log(`[BroadcastNotifications] Sending batch ${batchNumber} with ${batch.length} tokens`);
        
        // Create multicast message
        const message = {
          notification: {
            title: title,
            body: body,
          },
          data: {
            type: type,
            timestamp: Date.now().toString(),
          },
          tokens: batch,
        };

        // Add image URL to notification if provided
        if (imageUrl && imageUrl.trim().length > 0) {
          message.notification.imageUrl = imageUrl.trim();
        }

        // Add deep link data if provided
        if (deepLink && deepLink.trim().length > 0) {
          message.data.deepLink = deepLink.trim();
        }

        // Add target screen if provided
        if (targetScreen && targetScreen.trim().length > 0) {
          message.data.targetScreen = targetScreen.trim();
        }

        const response = await getMessaging().sendEachForMulticast(message);
        
        sentCount += response.successCount;
        errorCount += response.failureCount;

        // Log errors if any with enhanced error codes
        if (response.failureCount > 0) {
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              const errorCode = resp.error?.code || 'UNKNOWN';
              const errorMessage = resp.error?.message || 'Unknown error';
              const tokenPreview = batch[idx].substring(0, 20);
              
              console.error(`[BroadcastNotifications] Token failure - Code: ${errorCode}, Message: ${errorMessage}, Token: ${tokenPreview}...`);
              
              errors.push({
                token: batch[idx],
                errorCode: errorCode,
                error: errorMessage
              });
            }
          });
        }

        console.log(`[BroadcastNotifications] Batch ${batchNumber}: ${response.successCount} sent, ${response.failureCount} failed`);
      } catch (batchError) {
        console.error(`[BroadcastNotifications] Error sending batch ${batchNumber}:`, batchError);
        errorCount += batch.length;
        errors.push({
          batch: batchNumber,
          error: batchError.message || 'Batch send failed',
          errorCode: batchError.code || 'BATCH_SEND_ERROR'
        });
      }
    }

    console.log(`[BroadcastNotifications] Completed: ${sentCount} sent, ${errorCount} failed out of ${fcmTokens.length} total`);

    res.json({
      success: true,
      sentCount: sentCount,
      errorCount: errorCount,
      totalUsers: fcmTokens.length,
      errors: errors.slice(0, 10) // Return first 10 errors to avoid payload size issues
    });

  } catch (error) {
    console.error('[BroadcastNotifications] Fatal error:', error);
    res.status(500).json({ 
      success: false,
      error: error.message || 'Failed to send notifications' 
    });
  }
});

/**
 * Core logic to process a notification job: query users by segment,
 * batch FCM sends, update stats. Callable from onCreate (immediate)
 * or from processScheduledNotificationJobs cron.
 *
 * @param {string} jobId - Document ID in notification_jobs
 * @param {admin.firestore.DocumentSnapshot} jobSnap - Job document snapshot
 */
async function processNotificationJobCore(jobId, jobSnap) {
  const job = jobSnap.data() || {};
  const kind = String(job.kind || '').trim();
  const payload = job.payload && typeof job.payload === 'object' ? job.payload : {};

  const jobRef = jobSnap.ref;
  const now = admin.firestore.FieldValue.serverTimestamp();

  if (kind !== 'broadcast' && kind !== 'happy_hour' && kind !== 'segment') {
    await jobRef.set(
      {
        status: 'failed',
        error: `Invalid kind: ${kind || '(empty)'}`,
        completedAt: now,
        updatedAt: now,
      },
      { merge: true }
    );
    return;
  }

  const title = String(payload.title || '').trim();
  const body = String(payload.body || '').trim();
  const type =
    kind === 'happy_hour'
      ? 'happy_hour'
      : String(payload.type || '').trim() || 'general';

  if (!title || !body) {
    await jobRef.set(
      {
        status: 'failed',
        error: 'Missing title/body in payload',
        completedAt: now,
        updatedAt: now,
      },
      { merge: true }
    );
    return;
  }

  // Check if job was cancelled before we started (e.g. admin cancelled quickly)
  const freshSnap = await jobRef.get();
  if (freshSnap.exists && (freshSnap.data() || {}).status === 'cancelled') {
    console.log(`[processNotificationJobCore] Job ${jobId} was cancelled, skipping`);
    return;
  }

  await jobRef.set(
    {
      status: 'in_progress',
      startedAt: now,
      updatedAt: now,
      sentCount: 0,
      errorCount: 0,
      processedCount: 0,
      totalUsers: 0,
      errors: [],
    },
    { merge: true }
  );

  try {
    const db = getDb();
    // Build query: all active customers, optionally filtered by segment
    let usersQuery = db
      .collection('users')
      .where('role', '==', 'customer')
      .where('active', '==', true);

    const segment = payload.segment;
    const segmentFilter = (
      kind === 'segment' &&
      segment &&
      typeof segment === 'string' &&
      segment.trim() !== '' &&
      segment.trim().toLowerCase() !== 'all'
    );
    if (segmentFilter) {
      usersQuery = usersQuery.where('segment', '==', segment.trim().toLowerCase());
    }
    usersQuery = usersQuery.orderBy('__name__');
    const FCM_BATCH_SIZE = 500;
    const USER_PAGE_SIZE = 200;
    let lastDoc = null;
    let totalUsers = 0;
    let sentCount = 0;
    let errorCount = 0;
    let processedCount = 0;
    let batchNumber = 0;
    const firstErrors = [];
    let tokenAccumulator = [];

    const buildMessage = (tokens) => {
      const msg = {
        notification: { title, body },
        data: { type, timestamp: Date.now().toString() },
        tokens,
      };
      if (payload.imageUrl && String(payload.imageUrl).trim().length > 0) {
        msg.notification.imageUrl = String(payload.imageUrl).trim();
      }
      if (payload.deepLink && String(payload.deepLink).trim().length > 0) {
        msg.data.deepLink = String(payload.deepLink).trim();
      }
      if (payload.targetScreen && String(payload.targetScreen).trim().length > 0) {
        msg.data.targetScreen = String(payload.targetScreen).trim();
      }
      return msg;
    };

    const sendTokenBatch = async (batch) => {
      if (batch.length === 0) return;
      batchNumber++;
      const message = buildMessage(batch);
      try {
        const resp = await getMessaging().sendEachForMulticast(message);
        sentCount += resp.successCount;
        errorCount += resp.failureCount;
        processedCount += batch.length;
        if (resp.failureCount > 0 && firstErrors.length < 10) {
          resp.responses.forEach((r, idx) => {
            if (firstErrors.length >= 10) return;
            if (!r.success) {
              firstErrors.push({
                token: batch[idx],
                errorCode: r.error?.code || 'UNKNOWN',
                error: r.error?.message || 'Unknown error',
              });
            }
          });
        }
      } catch (batchErr) {
        errorCount += batch.length;
        processedCount += batch.length;
        if (firstErrors.length < 10) {
          firstErrors.push({
            batch: batchNumber,
            errorCode: batchErr.code || 'BATCH_SEND_ERROR',
            error: batchErr.message || 'Batch send failed',
          });
        }
      }
    };

    await jobRef.set({
      totalUsers: 0,
      stats: {
        totalRecipients: 0,
        processedCount: 0,
        successfulDeliveries: 0,
        failedDeliveries: 0,
        currentBatchNumber: 0,
        totalBatches: 0,
        percentComplete: 0,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      batchStartedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: now,
    }, { merge: true });

    let hasMore = true;
    while (hasMore) {
      const batchSnap = await jobRef.get();
      if (batchSnap.exists && (batchSnap.data() || {}).status === 'cancelled') {
        console.log(`[processNotificationJobCore] Job ${jobId} cancelled, stopping`);
        break;
      }

      let pageQuery = usersQuery.limit(USER_PAGE_SIZE);
      if (lastDoc) pageQuery = pageQuery.startAfter(lastDoc);
      const usersSnapshot = await pageQuery.get();
      if (usersSnapshot.empty) {
        hasMore = false;
        break;
      }

      for (const userDoc of usersSnapshot.docs) {
        const tokens = _extractUserFcmTokensFromData(userDoc.data());
        for (const t of tokens) {
          tokenAccumulator.push(t);
          if (tokenAccumulator.length >= FCM_BATCH_SIZE) {
            await sendTokenBatch(tokenAccumulator);
            tokenAccumulator = [];
            const knownTotal = processedCount + tokenAccumulator.length;
            const pct = knownTotal > 0 ? Math.round((processedCount / knownTotal) * 100) : 0;
            await jobRef.set({
              totalUsers: processedCount,
              sentCount,
              errorCount,
              processedCount,
              errors: firstErrors,
              stats: {
                totalRecipients: processedCount,
                processedCount,
                successfulDeliveries: sentCount,
                failedDeliveries: errorCount,
                currentBatchNumber: batchNumber,
                totalBatches: batchNumber,
                percentComplete: pct,
                lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
        }
      }

      const knownTotal = processedCount + tokenAccumulator.length;
      if (knownTotal > 0) {
        const pct = Math.round((processedCount / knownTotal) * 100);
        await jobRef.set({
          totalUsers: knownTotal,
          sentCount,
          errorCount,
          processedCount,
          errors: firstErrors,
          stats: {
            totalRecipients: knownTotal,
            processedCount,
            successfulDeliveries: sentCount,
            failedDeliveries: errorCount,
            currentBatchNumber: batchNumber,
            totalBatches: batchNumber,
            percentComplete: pct,
            lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }

      lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];
      hasMore = usersSnapshot.size === USER_PAGE_SIZE;
    }

    if (tokenAccumulator.length > 0) {
      await sendTokenBatch(tokenAccumulator);
    }
    totalUsers = processedCount;
    await jobRef.set({
      status: 'completed',
      totalUsers,
      sentCount,
      errorCount,
      processedCount,
      errors: firstErrors,
      stats: {
        totalRecipients: totalUsers,
        processedCount,
        successfulDeliveries: sentCount,
        failedDeliveries: errorCount,
        currentBatchNumber: batchNumber,
        totalBatches: batchNumber,
        percentComplete: 100,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (error) {
    console.error(`[processNotificationJobCore] Fatal error jobId=${jobId}`, error);
    const code = error.code || (error.errorInfo && error.errorInfo.code);
    const msg = error.message || String(error);
    const isPermissionDenied =
      code === 'permission-denied' ||
      (typeof msg === 'string' && msg.toLowerCase().includes('permission'));
    const errorForUser = isPermissionDenied
      ? 'Firestore permission denied in Cloud Function. Grant the Functions '
      + 'service account (e.g. Project ID@appspot.gserviceaccount.com) the '
      + '"Cloud Datastore User" or "Editor" role in Google Cloud IAM.'
      : msg;
    await jobRef.set(
      {
        status: 'failed',
        error: errorForUser,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
}

/**
 * Background notification job processor (no HTTP, no web timeouts).
 *
 * Admin app creates a Firestore document in `notification_jobs/{jobId}`:
 * {
 *   kind: 'broadcast' | 'happy_hour' | 'segment',
 *   payload: { title, body, type?, imageUrl?, deepLink?, targetScreen? },
 *   createdAt: serverTimestamp(),
 *   status: 'queued' | 'scheduled'
 *   scheduledFor?: Timestamp  // when status is 'scheduled'
 * }
 *
 * This trigger sends notifications in batches. If scheduledFor exists and is
 * in the future, processing is deferred to processScheduledNotificationJobs.
 */
exports.processNotificationJob = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .firestore.document('notification_jobs/{jobId}')
  .onCreate(async (snap, context) => {
    const jobId = context.params.jobId;
    const job = snap.data() || {};
    const scheduledFor = job.scheduledFor;

    // Defer to cron if job is scheduled for the future
    if (scheduledFor && scheduledFor.toDate && scheduledFor.toDate() > new Date()) {
      console.log(`[processNotificationJob] Job ${jobId} scheduled for later, skipping`);
      return;
    }

    await processNotificationJobCore(jobId, snap);
  });

/**
 * Scheduled: Process due segment notification jobs every minute.
 * Queries notification_jobs where status='scheduled' and scheduledFor <= now,
 * atomically claims each, then processes via processNotificationJobCore.
 */
exports.processScheduledNotificationJobs = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 300, memory: '512MB' })
  .pubsub.schedule('* * * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();
    const dueSnap = await db.collection('notification_jobs')
      .where('status', '==', 'scheduled')
      .where('scheduledFor', '<=', now)
      .limit(10)
      .get();

    for (const doc of dueSnap.docs) {
      const claimed = await db.runTransaction(async (t) => {
        const snap = await t.get(doc.ref);
        const data = snap.data();
        if (data?.status !== 'scheduled') return false;
        t.update(doc.ref, {
          status: 'queued',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (!claimed) continue;
      await processNotificationJobCore(doc.id, doc);
    }
  });

/**
 * Scheduled: Process Ash scheduled notifications every minute.
 * Reads pending ash_scheduled_notifications, sends FCM, logs to history, marks sent.
 */
exports.processAshScheduledNotifications = functions.pubsub
  .schedule('* * * * *')
  .timeZone('Asia/Manila')
  .onRun(async (context) => {
    const now = admin.firestore.Timestamp.now();
    const db = getDb();

    const snapshot = await db.collection('ash_scheduled_notifications')
      .where('status', '==', 'pending')
      .where('scheduledFor', '<=', now)
      .limit(500)
      .get();

    if (snapshot.empty) {
      return null;
    }

    console.log(`[processAshScheduledNotifications] Processing ${snapshot.size} notifications`);

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const userId = String(data.userId || '');
      const title = String(data.title || '').trim();
      const body = String(data.body || '').trim();
      const type = String(data.type || '');
      const payloadData = data.data && typeof data.data === 'object' ? data.data : {};

      if (!userId || !title || !body) {
        await doc.ref.update({
          status: 'cancelled',
          error: 'Missing userId, title, or body',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        continue;
      }

      try {
        const tokens = await _getUserFcmTokens(db, userId);
        if (tokens.length === 0) {
          await doc.ref.update({
            status: 'cancelled',
            error: 'No FCM tokens for user',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          continue;
        }

        const notificationId = db.collection('ash_notification_history').doc().id;
        const fcmData = {
          type: type || 'ash_notification',
          notificationId,
          ...payloadData,
          scheduled: 'true',
        };
        Object.keys(fcmData).forEach(k => { fcmData[k] = String(fcmData[k]); });

        const messagePayload = {
          notification: { title, body },
          data: fcmData,
          android: { priority: 'high', notification: { sound: 'default' } },
          apns: { payload: { aps: { sound: 'default' } } },
        };
        const multicastMessage = { ...messagePayload, tokens };
        const resp = await getMessaging().sendEachForMulticast(multicastMessage);

        await db.collection('ash_notification_history').doc(notificationId).set({
          userId,
          type,
          title,
          body,
          data: payloadData,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          openedAt: null,
          actionTaken: null,
        });

        await doc.ref.update({
          status: 'sent',
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(
          `[processAshScheduledNotifications] Sent ${doc.id} to ${resp.successCount}/${tokens.length} devices`
        );
      } catch (e) {
        console.error(`[processAshScheduledNotifications] Error for ${doc.id}:`, e);
        await doc.ref.update({
          status: 'failed',
          error: String(e.message || e),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    return null;
  });

/**
 * Scheduled: Send Ash reorder reminders hourly (timezone-aware).
 * Runs every hour, sends at 10 AM user local time.
 * Filters by settings.ashReorderReminders, respects quiet hours.
 */
exports.sendReorderReminders = functions
  .region('us-central1')
  .pubsub.schedule('0 * * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();
    const oneDayAgo = new Date();
    oneDayAgo.setDate(oneDayAgo.getDate() - 1);
    const oneDayAgoTs = admin.firestore.Timestamp.fromDate(oneDayAgo);

    console.log('[sendReorderReminders] Checking for eligible users (timezone-aware)...');

    const usersSnapshot = await db
      .collection('users')
      .where('reorderEligible', '==', true)
      .where('lastOrderCompletedAt', '<=', oneDayAgoTs)
      .limit(1000)
      .get();

    let sentCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;

      if (userData.settings?.ashReorderReminders === false) continue;

      const userTimezone = userData.timezone || 'Asia/Manila';
      const userHour = TimezoneUtils.getCurrentHourInUserTimezone(userTimezone);
      if (userHour !== 10) continue;

      const settings = userData.settings || {};
      if (settings.quietHoursEnabled) {
        const quietStart = settings.quietHoursStart;
        const quietEnd = settings.quietHoursEnd;
        if (
          quietStart !== undefined &&
          quietEnd !== undefined &&
          TimezoneUtils.isWithinQuietHours(userTimezone, quietStart, quietEnd, 10)
        ) {
          continue;
        }
      }

      const canSend = await FrequencyManager.canSendNotification(userId, 'ash_reorder', db);
      if (!canSend) continue;

      const pref = userData.preferenceProfile || {};
      const lastOrderVendorId = pref.lastOrderVendorId;
      const lastOrderVendorName = pref.lastOrderVendorName || 'your favorite restaurant';
      const lastOrderProducts = pref.lastOrderProducts || [];
      const lastOrderedAt = pref.lastOrderedAt;

      if (!lastOrderVendorId) continue;

      const daysSinceLastOrder = lastOrderedAt
        ? Math.round((now.toDate() - lastOrderedAt.toDate()) / (1000 * 60 * 60 * 24))
        : 0;

      const milestoneDays = [7, 14, 21, 28, 30];
      if (!milestoneDays.includes(daysSinceLastOrder)) continue;

      const productName = lastOrderProducts[0]?.name || null;
      const notification = AshNotificationBuilder.buildAshNotification(
        'reorder',
        { ...userData, id: userId },
        {
          userId,
          restaurantName: lastOrderVendorName,
          vendorId: lastOrderVendorId,
          daysSinceLastOrder,
          productName,
          lastOrderProducts,
        }
      );
      const { title, body } = notification;

      const tokens = await _getUserFcmTokens(db, userId);
      if (tokens.length === 0) continue;

      const fcmData = { ...notification.data };
      Object.keys(fcmData).forEach((k) => { fcmData[k] = String(fcmData[k]); });

      try {
        const multicastMessage = {
          notification: { title, body },
          data: fcmData,
          tokens,
          android: { priority: 'high', notification: { sound: 'default' } },
          apns: { payload: { aps: { sound: 'default' } } },
        };
        await getMessaging().sendEachForMulticast(multicastMessage);

        await db.collection('ash_notification_history').doc(fcmData.notificationId).set({
          userId,
          type: 'ash_reorder',
          title,
          body,
          data: {
            vendorId: lastOrderVendorId,
            vendorName: lastOrderVendorName,
            daysSinceLastOrder,
          },
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          openedAt: null,
          actionTaken: null,
        });

        sentCount++;
        console.log(`[sendReorderReminders] Sent to user ${userId}`);
      } catch (e) {
        console.error(`[sendReorderReminders] Failed for user ${userId}:`, e);
      }
    }

    console.log(`[sendReorderReminders] Complete. Sent: ${sentCount}`);
    return null;
  });

/**
 * Scheduled: Smart Hunger Notifications at 10:30 AM, 2:30 PM, 5:00 PM Asia/Manila.
 * Sends window-specific notifications (lunch, snack, dinner) just before hunger windows.
 */
exports.sendSmartHungerReminders = functions
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .region('us-central1')
  .pubsub.schedule('0,30 * * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const currentHour = now.getHours();
    const currentMinute = now.getMinutes();

    let window = null;
    if (currentHour === 10 && currentMinute === 30) {
      window = 'lunch';
    } else if (currentHour === 14 && currentMinute === 30) {
      window = 'snack';
    } else if (currentHour === 17 && currentMinute === 0) {
      window = 'dinner';
    }

    if (!window) {
      return null;
    }

    console.log(`[sendSmartHungerReminders] Window: ${window} (${currentHour}:${currentMinute})`);

    const smartHungerConfigSnap = await db
      .collection('config')
      .doc('smart_hunger_settings')
      .get();
    const smartHungerConfig = smartHungerConfigSnap.exists
      ? (smartHungerConfigSnap.data() || {})
      : {};
    const isSmartHungerEnabled = smartHungerConfig.enabled !== false;
    if (!isSmartHungerEnabled) {
      console.log('[sendSmartHungerReminders] Disabled via admin config');
      return null;
    }
    const enabledWindows = smartHungerConfig.windows || {};
    if (enabledWindows[window] === false) {
      console.log(
        `[sendSmartHungerReminders] Window "${window}" disabled by admin config`,
      );
      return null;
    }
    const frequencyMode = smartHungerConfig.frequencyMode || 'recommended';
    const customMessages = smartHungerConfig.customMessages || {};

    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    const thirtyDaysAgoTs = admin.firestore.Timestamp.fromDate(thirtyDaysAgo);

    const usersSnapshot = await db
      .collection('users')
      .where('reorderEligible', '==', true)
      .where('lastOnlineTimestamp', '>=', thirtyDaysAgoTs)
      .limit(500)
      .get();

    console.log(`[sendSmartHungerReminders] Found ${usersSnapshot.size} eligible users`);

    let sentCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;

      const orderedToday = await HungerDetection.hasOrderedToday(
        db, userId, now
      );
      if (orderedToday) continue;

      const canSend = await FrequencyManager.canSendNotification(
        userId, 'ash_hunger', db
      );
      if (!canSend) continue;

      const settings = userData.settings || {};
      if (frequencyMode === 'less') {
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        const todayStartTs =
          admin.firestore.Timestamp.fromDate(todayStart);
        const todayHunger = await db
          .collection('ash_notification_history')
          .where('userId', '==', userId)
          .where('type', '==', 'ash_hunger')
          .where('sentAt', '>=', todayStartTs)
          .limit(1)
          .get();
        if (!todayHunger.empty) continue;
      }
      if (settings.quietHoursEnabled) {
        const quietStart = settings.quietHoursStart;
        const quietEnd = settings.quietHoursEnd;
        const userTimezone = userData.timezone || 'Asia/Manila';
        const userHour = TimezoneUtils.getCurrentHourInUserTimezone(
          userTimezone
        );
        if (
          quietStart !== undefined &&
          quietEnd !== undefined &&
          TimezoneUtils.isWithinQuietHours(
            userTimezone, quietStart, quietEnd, userHour
          )
        ) {
          continue;
        }
      }

      const pref = userData.preferenceProfile || {};
      const favoriteRestaurantIds = pref.favoriteRestaurants || [];
      let restaurantName = null;
      if (favoriteRestaurantIds.length > 0) {
        const vendorId = favoriteRestaurantIds[0];
        const vendorDoc = await db.collection('vendors').doc(vendorId).get();
        if (vendorDoc.exists) {
          const v = vendorDoc.data();
          restaurantName = v?.title || null;
        }
      }

      const content = AshNotificationBuilder.getSmartHungerContent(
        window,
        userData,
        {
          userId,
          restaurantName,
          customMessage: (customMessages[window] || '').toString(),
        }
      );

      const notificationId = `ash_hunger_${userId}_${Date.now()}`;
      const tokens = await _getUserFcmTokens(db, userId);
      if (tokens.length === 0) continue;

      const fcmData = {
        type: 'ash_hunger',
        notificationId,
        userId: String(userId),
        timestamp: new Date().toISOString(),
        ash: 'true',
        mealPeriod: String(window),
        hour: String(currentHour),
      };
      Object.keys(fcmData).forEach((k) => {
        fcmData[k] = String(fcmData[k]);
      });

      try {
        const multicastMessage = {
          notification: {
            title: content.title,
            body: content.body,
          },
          data: fcmData,
          tokens,
          android: { priority: 'high', notification: { sound: 'default' } },
          apns: { payload: { aps: { sound: 'default' } } },
        };
        await getMessaging().sendEachForMulticast(multicastMessage);

        await db.collection('ash_notification_history')
          .doc(notificationId)
          .set({
            userId,
            type: 'ash_hunger',
            window,
            title: content.title,
            body: content.body,
            data: {
              mealPeriod: window,
              hour: currentHour,
            },
            sentAt: admin.firestore.FieldValue.serverTimestamp(),
            openedAt: null,
            actionTaken: null,
          });

        sentCount++;
        console.log(`[sendSmartHungerReminders] Sent to user ${userId}`);
      } catch (e) {
        console.error(
          `[sendSmartHungerReminders] Failed for user ${userId}:`, e
        );
      }
    }

    console.log(`[sendSmartHungerReminders] Complete. Sent: ${sentCount}`);
    return null;
  });

// Legacy - replaced by sendSmartHungerReminders
// exports.sendHungerReminders = functions
//   .region('us-central1')
//   .pubsub.schedule('0 8,12,18 * * *')
//   .timeZone('Asia/Manila')
//   .onRun(async () => {
//     const db = getDb();
//     const now = new Date();
//     const currentHour = now.getHours();
//     const currentPeriod = HungerDetection.getMealPeriod(now);
//     console.log(`[sendHungerReminders] Checking at ${currentPeriod}...`);
//     const thirtyDaysAgo = new Date();
//     thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
//     const thirtyDaysAgoTs = admin.firestore.Timestamp.fromDate(thirtyDaysAgo);
//     const usersSnapshot = await db
//       .collection('users')
//       .where('settings.ashHungerReminders', '==', true)
//       .where('reorderEligible', '==', true)
//       .where('lastOnlineTimestamp', '>=', thirtyDaysAgoTs)
//       .limit(500)
//       .get();
//     let sentCount = 0;
//     for (const userDoc of usersSnapshot.docs) {
//       const userData = userDoc.data();
//       const userId = userDoc.id;
//       const shouldSend = await HungerDetection.shouldSendHungerReminder(
//         db, userId, userData, now
//       );
//       if (!shouldSend) continue;
//       const hungerContent = await HungerDetection.generateHungerContent(
//         db, userId, userData
//       );
//       const restaurantName =
//         hungerContent.suggestedRestaurant?.title || 'your favorite restaurant';
//       const productName = hungerContent.suggestedProduct?.name || null;
//       const notification = AshNotificationBuilder.buildAshNotification(
//         'hunger', { ...userData, id: userId },
//         { userId, restaurantName, productName,
//           suggestion: productName || 'something tasty',
//           mealPeriod: currentPeriod }
//       );
//       const tokens = await _getUserFcmTokens(db, userId);
//       if (tokens.length === 0) continue;
//       const fcmData = {
//         ...notification.data,
//         mealPeriod: String(currentPeriod),
//         hour: String(currentHour),
//       };
//       Object.keys(fcmData).forEach((k) => { fcmData[k] = String(fcmData[k]); });
//       try {
//         await getMessaging().sendEachForMulticast({
//           notification: { title: notification.title, body: notification.body },
//           data: fcmData, tokens,
//           android: { priority: 'high', notification: { sound: 'default' } },
//           apns: { payload: { aps: { sound: 'default' } } },
//         });
//         await db.collection('ash_notification_history')
//           .doc(fcmData.notificationId).set({
//             userId, type: 'ash_hunger', title: notification.title,
//             body: notification.body,
//             data: {
//               mealPeriod: currentPeriod, hour: currentHour,
//               suggestedProduct: hungerContent.suggestedProduct || null,
//               suggestedRestaurant: hungerContent.suggestedRestaurant || null,
//             },
//             sentAt: admin.firestore.FieldValue.serverTimestamp(),
//             openedAt: null, actionTaken: null,
//           });
//         sentCount++;
//       } catch (e) {
//         console.error(`[sendHungerReminders] Failed for user ${userId}:`, e);
//       }
//     }
//     console.log(`[sendHungerReminders] Complete. Sent: ${sentCount}`);
//     return null;
//   });

/**
 * Scheduled: Process cart recovery - find abandoned carts, schedule reminders.
 * Runs every 30 minutes. Carts abandoned 2+ hours get ash_cart reminder.
 */
exports.processCartRecovery = functions
  .region('us-central1')
  .pubsub.schedule('*/30 * * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();
    const twoHoursAgo = new Date();
    twoHoursAgo.setHours(twoHoursAgo.getHours() - 2);
    const twoHoursAgoTs = admin.firestore.Timestamp.fromDate(twoHoursAgo);

    console.log('[processCartRecovery] Checking for abandoned carts...');

    const cartsSnapshot = await db.collection('user_carts')
      .where('itemCount', '>', 0)
      .where('lastModified', '<=', twoHoursAgoTs)
      .limit(500)
      .get();

    let reminderCount = 0;

    for (const cartDoc of cartsSnapshot.docs) {
      const cartData = cartDoc.data();
      const userId = cartDoc.id;
      const items = cartData.items || [];
      const vendorGroups = cartData.vendorGroups || {};
      const totalValue = cartData.totalValue || 0;

      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) continue;

      const userData = userDoc.data() || {};
      const settings = userData.settings || {};
      if (settings.ashCartReminders === false) continue;

      const oneDayAgo = new Date();
      oneDayAgo.setDate(oneDayAgo.getDate() - 1);
      const recentHistory = await db.collection('ash_notification_history')
        .where('userId', '==', userId)
        .where('type', '==', 'ash_cart')
        .where('sentAt', '>=', admin.firestore.Timestamp.fromDate(oneDayAgo))
        .limit(1)
        .get();

      if (!recentHistory.empty) continue;

      const canSend = await FrequencyManager.canSendNotification(userId, 'ash_cart', db);
      if (!canSend) continue;

      const primaryVendorId = Object.keys(vendorGroups)[0] ||
        (items[0]?.vendorId) || '';
      let vendorName = 'your favorite restaurant';

      if (primaryVendorId) {
        const vendorDoc = await db.collection('vendors').doc(primaryVendorId).get();
        if (vendorDoc.exists && vendorDoc.data()?.title) {
          vendorName = vendorDoc.data().title;
        }
      }

      const productNames = [...new Set(items.slice(0, 3).map(i => i.name).filter(Boolean))];
      const itemCount = items.length;

      const cartNotification = AshNotificationBuilder.buildAshNotification(
        'cart',
        { ...userData, id: userId },
        {
          userId,
          restaurantName: vendorName,
          itemCount,
          productNames: productNames.join(', '),
        }
      );
      let { title, body } = cartNotification;

      const userTimezone = userData.timezone || 'Asia/Manila';
      const userHour = TimezoneUtils.getCurrentHourInUserTimezone(userTimezone);
      if (userHour >= 11 && userHour < 14) {
        body += ' Perfect for lunch!';
      } else if (userHour >= 18 && userHour < 21) {
        body += ' Great for dinner!';
      }

      let quietStart;
      let quietEnd;
      if (settings.quietHoursEnabled) {
        quietStart = settings.quietHoursStart;
        quietEnd = settings.quietHoursEnd;
      }
      const scheduledFor = TimezoneUtils.getNextValidSendTime(
        userTimezone, 10, quietStart, quietEnd
      );

      try {
        await db.collection('ash_scheduled_notifications').add({
          userId,
          type: 'ash_cart',
          title,
          body,
          data: {
            vendorId: String(primaryVendorId),
            vendorName: String(vendorName),
            itemCount: String(itemCount),
            totalValue: String(totalValue),
            cartId: cartDoc.id,
          },
          scheduledFor: admin.firestore.Timestamp.fromDate(scheduledFor),
          status: 'pending',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          timezone: userData.timezone || 'Asia/Manila',
        });

        await db.collection('cart_recovery_analytics').add({
          userId,
          cartValue: totalValue,
          itemCount,
          vendorCount: Object.keys(vendorGroups).length,
          reminderType: 'ash_cart',
          scheduledAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        reminderCount++;
        console.log(`[processCartRecovery] Scheduled for user ${userId}`);
      } catch (e) {
        console.error(`[processCartRecovery] Error for ${userId}:`, e);
      }
    }

    console.log(`[processCartRecovery] Complete. Scheduled: ${reminderCount}`);
    return null;
  });

/**
 * Scheduled: Clean up abandoned carts older than 7 days.
 */
exports.cleanupAbandonedCarts = functions
  .region('us-central1')
  .pubsub.schedule('0 0 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    const sevenDaysAgoTs = admin.firestore.Timestamp.fromDate(sevenDaysAgo);

    console.log('[cleanupAbandonedCarts] Cleaning up old carts...');

    const oldCarts = await db.collection('user_carts')
      .where('lastModified', '<=', sevenDaysAgoTs)
      .limit(500)
      .get();

    let deletedCount = 0;
    const batch = db.batch();

    for (const doc of oldCarts.docs) {
      batch.delete(doc.ref);
      deletedCount++;
    }

    if (deletedCount > 0) {
      await batch.commit();
    }

    console.log(`[cleanupAbandonedCarts] Deleted: ${deletedCount}`);
    return null;
  });

/**
 * Scheduled: Update trending products every 6 hours.
 * Aggregates order counts from last 24h, stores in trending_products collection.
 */
exports.updateTrendingProducts = functions
  .region('us-central1')
  .pubsub.schedule('0 */6 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const oneDayAgo = new Date();
    oneDayAgo.setDate(oneDayAgo.getDate() - 1);
    const oneDayAgoTs = admin.firestore.Timestamp.fromDate(oneDayAgo);

    const ordersSnapshot = await db
      .collection('restaurant_orders')
      .where('createdAt', '>=', oneDayAgoTs)
      .where('status', 'in', ['Order Completed', 'order completed', 'completed', 'Completed'])
      .get();

    const productCounts = {};
    for (const doc of ordersSnapshot.docs) {
      const order = doc.data();
      const vendorId = order.vendorID || order.vendor?.id || '';
      const vendorName = order.vendor?.title || '';
      const cuisine = (order.vendor?.categoryTitle || 'other').toString();
      const products = order.products || [];
      for (const product of products) {
        const productId = (product.id || product['id'] || '').toString().split('~')[0];
        if (!productId) continue;
        if (!productCounts[productId]) {
          productCounts[productId] = {
            count: 0,
            name: product.name || '',
            vendorId,
            vendorName,
            cuisine,
          };
        }
        productCounts[productId].count += product.quantity || 1;
      }
    }

    const trending = Object.entries(productCounts)
      .map(([productId, data]) => ({
        productId,
        name: data.name,
        vendorId: data.vendorId,
        vendorName: data.vendorName,
        cuisine: data.cuisine,
        orderCount: data.count,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      }))
      .sort((a, b) => b.orderCount - a.orderCount)
      .slice(0, 100);

    const batch = db.batch();
    const oldSnap = await db.collection('trending_products').get();
    oldSnap.docs.forEach((d) => batch.delete(d.ref));

    trending.forEach((item) => {
      const ref = db.collection('trending_products').doc(item.productId);
      batch.set(ref, item);
    });

    await batch.commit();
    console.log(`[updateTrendingProducts] Updated ${trending.length} trending products`);
    return null;
  });

/**
 * Scheduled: Update optimal send times from engagement analytics.
 * Runs at 3 AM every Sunday.
 */
exports.updateOptimalSendTimes = functions
  .region('us-central1')
  .pubsub.schedule('0 3 * * 0')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    await EngagementAnalytics.batchUpdateOptimalTimes(db);
    return null;
  });

/**
 * Helper: Generate a personalized recommendation for a user.
 */
async function generateRecommendation(db, userId, mealPeriod, pref, favoriteProducts, favoriteRestaurants, cuisinePrefs) {
  const types = [
    'new_from_favorite_restaurant',
    'item_similar_to_favorite',
    'trending_in_favorite_cuisine',
    'time_based_from_preferred_restaurant',
    'popular_in_area',
  ];

  for (const type of types) {
    try {
      if (type === 'new_from_favorite_restaurant') {
        for (const vendorId of (favoriteRestaurants || []).slice(0, 3)) {
          const vendorDoc = await db.collection('vendors').doc(vendorId).get();
          if (!vendorDoc.exists) continue;
          const vendor = vendorDoc.data();
          const fourteenDaysAgo = new Date();
          fourteenDaysAgo.setDate(fourteenDaysAgo.getDate() - 14);
          try {
            const newSnap = await db.collection('vendor_products')
              .where('vendorID', '==', vendorId)
              .where('publish', '==', true)
              .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(fourteenDaysAgo))
              .limit(5)
              .get();
            if (!newSnap.empty) {
              const doc = newSnap.docs[0];
              const product = doc.data();
              return {
                type: 'new_item',
                title: `New at ${vendor.title}`,
                body: `Try their new ${product.name || 'item'} – just added!`,
                vendorId,
                productId: doc.id,
                reason: 'new_item',
              };
            }
          } catch (_) { /* createdAt may not exist, skip */ }
        }
      } else if (type === 'item_similar_to_favorite' && favoriteProducts && favoriteProducts.length > 0) {
        const fav = favoriteProducts[Math.floor(Math.random() * Math.min(3, favoriteProducts.length))];
        const favId = fav.id || fav;
        const candidates = [];
        try {
          const q1 = await db.collection('item_similarities')
            .where('item1', '==', favId)
            .orderBy('similarity', 'desc')
            .limit(3)
            .get();
          q1.docs.forEach((d) => {
            const d_ = d.data();
            candidates.push({ similarity: d_.similarity, otherId: d_.item2 });
          });
        } catch (_) {}
        try {
          const q2 = await db.collection('item_similarities')
            .where('item2', '==', favId)
            .orderBy('similarity', 'desc')
            .limit(3)
            .get();
          q2.docs.forEach((d) => {
            const d_ = d.data();
            candidates.push({ similarity: d_.similarity, otherId: d_.item1 });
          });
        } catch (_) {}
        if (candidates.length > 0) {
          candidates.sort((a, b) => b.similarity - a.similarity);
          const similarProductId = candidates[0].otherId;
          const productDoc = await db.collection('vendor_products').doc(similarProductId).get();
          if (productDoc.exists) {
            const product = productDoc.data();
            const vendorDoc = await db.collection('vendors').doc(product.vendorID || '').get();
            const vendorName = vendorDoc.exists ? vendorDoc.data().title : 'a restaurant';
            const favName = (typeof fav === 'object' && fav.name) ? fav.name : 'your favorites';
            return {
              type: 'similar_item',
              title: 'You might also like',
              body: `Since you liked ${favName}, try ${product.name || 'this'} from ${vendorName}!`,
              vendorId: product.vendorID || '',
              productId: similarProductId,
              reason: 'similar_item',
            };
          }
        }
      } else if (type === 'trending_in_favorite_cuisine' && cuisinePrefs && Object.keys(cuisinePrefs).length > 0) {
        const topCuisines = Object.entries(cuisinePrefs)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 2)
          .map(([c]) => c);
        for (const cuisine of topCuisines) {
          try {
            const snap = await db.collection('trending_products')
              .where('cuisine', '==', cuisine)
              .orderBy('orderCount', 'desc')
              .limit(1)
              .get();
            if (!snap.empty) {
              const t = snap.docs[0].data();
              return {
                type: 'trending',
                title: 'Trending now',
                body: `${t.name || 'Something'} is trending in ${cuisine} cuisine!`,
                vendorId: t.vendorId || '',
                productId: t.productId || snap.docs[0].id,
                reason: 'trending',
              };
            }
          } catch (_) {}
        }
      } else if (type === 'time_based_from_preferred_restaurant' && favoriteRestaurants && favoriteRestaurants.length > 0) {
        const vendorId = favoriteRestaurants[Math.floor(Math.random() * Math.min(2, favoriteRestaurants.length))];
        const vendorDoc = await db.collection('vendors').doc(vendorId).get();
        if (vendorDoc.exists) {
          const vendor = vendorDoc.data();
          const mealKeywords = {
            breakfast: ['silog', 'pancake', 'waffle', 'coffee', 'pastry', 'egg'],
            lunch: ['burger', 'sandwich', 'rice', 'meal', 'soup'],
            dinner: ['dinner', 'steak', 'pasta', 'grill', 'family'],
            late_night: ['snack', 'fries', 'drink', 'dessert'],
          };
          const keywords = mealKeywords[mealPeriod] || [];
          const productsSnap = await db.collection('vendor_products')
            .where('vendorID', '==', vendorId)
            .where('publish', '==', true)
            .limit(20)
            .get();
          const matching = productsSnap.docs.filter((doc) => {
            const name = (doc.data().name || '').toLowerCase();
            return keywords.some((k) => name.includes(k));
          });
          if (matching.length > 0) {
            const doc = matching[0];
            const product = doc.data();
            const mealLabel = mealPeriod.replace('_', ' ');
            return {
              type: 'time_based',
              title: `Perfect for ${mealLabel}`,
              body: `How about ${product.name || 'something'} from ${vendor.title || 'your favorite'}?`,
              vendorId,
              productId: doc.id,
              reason: 'time_based',
            };
          }
        }
      } else if (type === 'popular_in_area') {
        try {
          const snap = await db.collection('trending_products')
            .orderBy('orderCount', 'desc')
            .limit(1)
            .get();
          if (!snap.empty) {
            const t = snap.docs[0].data();
            return {
              type: 'popular',
              title: 'Popular near you',
              body: `Try ${t.name || 'this'} – everyone's ordering it!`,
              vendorId: t.vendorId || '',
              productId: t.productId || snap.docs[0].id,
              reason: 'popular',
            };
          }
        } catch (_) {}
      }
    } catch (e) {
      console.error(`[generateRecommendation] Error for type ${type}:`, e);
    }
  }
  return null;
}

/**
 * Scheduled: Send personalized recommendations hourly (timezone-aware).
 * Uses preferredTimes, optional optimalSendHour, A/B timing test.
 */
exports.sendPersonalizedRecommendations = functions
  .region('us-central1')
  .pubsub.schedule('0 * * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const threeDaysAgo = new Date();
    threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);
    const threeDaysAgoTs = admin.firestore.Timestamp.fromDate(threeDaysAgo);

    const usersSnapshot = await db.collection('users')
      .where('settings.ashRecommendations', '==', true)
      .where('reorderEligible', '==', true)
      .where('lastOrderCompletedAt', '>=', threeDaysAgoTs)
      .limit(500)
      .get();

    let sentCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      const userTimezone = userData.timezone || 'Asia/Manila';
      const userHour = TimezoneUtils.getCurrentHourInUserTimezone(userTimezone);

      let mealPeriod = 'lunch';
      if (userHour >= 5 && userHour < 11) mealPeriod = 'breakfast';
      else if (userHour >= 11 && userHour < 16) mealPeriod = 'lunch';
      else if (userHour >= 16 && userHour < 22) mealPeriod = 'dinner';
      else mealPeriod = 'late_night';

      const pref = userData.preferenceProfile || {};
      const preferredTimes = pref.preferredTimes || [];
      if (!preferredTimes.includes(mealPeriod)) continue;

      const settings = userData.settings || {};
      if (settings.quietHoursEnabled) {
        const quietStart = settings.quietHoursStart;
        const quietEnd = settings.quietHoursEnd;
        if (
          quietStart !== undefined &&
          quietEnd !== undefined &&
          TimezoneUtils.isWithinQuietHours(userTimezone, quietStart, quietEnd, userHour)
        ) {
          continue;
        }
      }

      const canSend = await FrequencyManager.canSendNotification(
        userId, 'ash_recommendation', db
      );
      if (!canSend) continue;

      const recentRecSnap = await db.collection('ash_notification_history')
        .where('userId', '==', userId)
        .where('type', '==', 'ash_recommendation')
        .where('sentAt', '>=', threeDaysAgoTs)
        .limit(1)
        .get();
      if (!recentRecSnap.empty) continue;

      const favoriteProducts = pref.favoriteProducts || [];
      const favoriteRestaurants = pref.favoriteRestaurants || [];
      const cuisinePrefs = pref.cuisinePreferences || {};

      if (favoriteProducts.length === 0 && favoriteRestaurants.length === 0) continue;

      const np = userData.notificationPreferences || {};
      let baseHour = np.optimalSendHour;
      if (baseHour === undefined || baseHour === null) {
        const periodHours = { breakfast: 8, lunch: 12, dinner: 18, late_night: 21 };
        baseHour = periodHours[mealPeriod] ?? 12;
      }

      const sendHour = await ABTestingService.getSendHourForVariant(
        userId, 'recommendation_timing_test', baseHour, db
      );
      if (userHour !== sendHour) continue;

      const variant = await ABTestingService.assignUserToVariant(
        userId, 'recommendation_timing_test', db
      );

      const rec = await generateRecommendation(
        db, userId, mealPeriod, pref, favoriteProducts, favoriteRestaurants, cuisinePrefs
      );
      if (!rec) continue;

      let vendorName = 'a restaurant';
      let productName = 'this';
      if (rec.vendorId) {
        const vDoc = await db.collection('vendors').doc(rec.vendorId).get();
        if (vDoc.exists) vendorName = vDoc.data()?.title || vendorName;
      }
      if (rec.productId) {
        const pDoc = await db.collection('vendor_products').doc(rec.productId).get();
        if (pDoc.exists) productName = pDoc.data()?.name || productName;
      }

      const notification = AshNotificationBuilder.buildAshNotification(
        'recommendation',
        { ...userData, id: userId },
        {
          userId,
          restaurantName: vendorName,
          productName,
          vendorId: rec.vendorId,
          productId: rec.productId,
        }
      );
      const recFcmData = {
        type: 'ash_recommendation',
        notificationId: notification.data.notificationId,
        recommendationType: String(rec.type || ''),
        vendorId: String(rec.vendorId || ''),
        productId: String(rec.productId || ''),
        reason: String(rec.reason || ''),
        mealPeriod: String(mealPeriod),
        abTest: 'recommendation_timing_test',
        abVariant: String(variant),
      };
      Object.keys(recFcmData).forEach((k) => { recFcmData[k] = String(recFcmData[k]); });

      const tokens = await _getUserFcmTokens(db, userId);
      if (tokens.length === 0) continue;

      try {
        await getMessaging().sendEachForMulticast({
          notification: { title: notification.title, body: notification.body },
          data: recFcmData,
          tokens,
          android: { priority: 'high', notification: { sound: 'default' } },
          apns: { payload: { aps: { sound: 'default' } } },
        });

        await db.collection('ash_notification_history').doc(recFcmData.notificationId).set({
          userId,
          type: 'ash_recommendation',
          recommendationType: rec.type,
          title: notification.title,
          body: notification.body,
          data: {
            vendorId: rec.vendorId,
            productId: rec.productId,
            reason: rec.reason,
            mealPeriod,
            abTest: 'recommendation_timing_test',
            abVariant: variant,
          },
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          openedAt: null,
          actionTaken: null,
        });

        sentCount++;
      } catch (e) {
        console.error(`[sendPersonalizedRecommendations] Failed for ${userId}:`, e);
      }
    }

    console.log(`[sendPersonalizedRecommendations] Sent: ${sentCount}`);
    return null;
  });

/**
 * Callable: Assign user to A/B test variant.
 * Requires Firebase Auth. Client calls with { testName }.
 */
exports.assignUserToVariant = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const userId = context.auth?.uid;
    if (!userId) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'User must be authenticated'
      );
    }
    const testName = data?.testName;
    if (!testName || typeof testName !== 'string') {
      return { variant: 'control' };
    }
    const db = getDb();
    const testDoc = await db.collection('ab_tests').doc(testName).get();
    if (!testDoc.exists) {
      return { variant: 'control' };
    }
    const test = testDoc.data() || {};
    const variants = test.variants || [];
    if (variants.length === 0) {
      return { variant: 'control' };
    }
    const assignmentId = `${testName}_${userId}`;
    const assignmentDoc = await db.collection('ab_assignments').doc(assignmentId).get();
    if (assignmentDoc.exists) {
      return { variant: assignmentDoc.data()?.variant || 'control' };
    }
    const rand = Math.random() * 100;
    let cumulative = 0;
    let assignedVariant = variants[0]?.name || 'control';
    for (const v of variants) {
      cumulative += Number(v.percentage) || 0;
      if (rand < cumulative) {
        assignedVariant = v.name || 'control';
        break;
      }
    }
    await db.collection('ab_assignments').doc(assignmentId).set({
      userId,
      testName,
      variant: assignedVariant,
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { variant: assignedVariant };
  });

/**
 * Callable: Get notification history for a user. Admin-only.
 * Params: { userId: string, limit?: number }
 * Returns: { notifications: [...] }
 */
exports.getNotificationHistory = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const callerId = context.auth.uid;
    const db = getDb();
    const callerDoc = await db.collection('users').doc(callerId).get();
    const callerData = callerDoc.data() || {};
    const role = callerData.role || callerData.userRole || '';
    const isAdmin = role === 'admin' || role === 'Admin';

    if (!isAdmin) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Admin only',
      );
    }

    const userId = data?.userId;
    if (!userId || typeof userId !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'userId is required',
      );
    }

    const limit = Math.min(Number(data?.limit) || 20, 100);
    const snapshot = await db
      .collection('ash_notification_history')
      .where('userId', '==', userId)
      .orderBy('sentAt', 'desc')
      .limit(limit)
      .get();

    return {
      notifications: snapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      })),
    };
  });

/**
 * Callable: Test Ash notification. Admin-only.
 * Sends a test Ash notification to a specific user.
 * Params: { userId, notificationType, contextData }
 */
exports.testAshNotification = functions
  .region('us-central1')
  .runWith({ memory: '512MB', timeoutSeconds: 120 })
  .https.onCall(async (data, context) => {
    console.log('🔥 testAshNotification CALLED ' + new Date().toISOString());
    console.log('[testAshNotification] Auth UID:', context.auth?.uid);
    console.log('[testAshNotification] Raw data (full):', JSON.stringify(data));
    console.log('[testAshNotification] data.userId:', data?.userId);
    console.log('[testAshNotification] data.notificationType:', data?.notificationType);
    console.log('[testAshNotification] data.contextData:', JSON.stringify(data?.contextData || {}));
    console.log('[testAshNotification] context.auth:', !!context.auth, 'uid:', context.auth?.uid);

    if (!context.auth) {
      console.error('[testAshNotification] No authentication');
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const callerId = context.auth.uid;
    console.log('[testAshNotification] Step 0: Getting DB and caller doc for', callerId);
    const db = getDb();
    let callerDoc;
    try {
      callerDoc = await db.collection('users').doc(callerId).get();
      console.log('[testAshNotification] Step 0: Caller doc exists:', callerDoc.exists);
    } catch (e) {
      console.error('[testAshNotification] Step 0 FAILED - get caller doc:', e?.message || e);
      console.error('[testAshNotification] Step 0 stack:', e?.stack);
      throw new functions.https.HttpsError(
        'internal',
        'Failed to verify admin. Check Firebase Console logs.',
        { cause: String(e), callerId },
      );
    }
    const callerData = callerDoc.exists ? callerDoc.data() : {};
    const role = callerData?.role || callerData?.userRole || '';
    const isAdmin = role === 'admin' || role === 'Admin';
    console.log('[testAshNotification] Caller role:', role, 'isAdmin:', isAdmin);

    if (!isAdmin) {
      console.error('[testAshNotification] Not admin');
      throw new functions.https.HttpsError(
        'permission-denied',
        'Admin only',
      );
    }

    const userId = data?.userId;
    const notificationType = data?.notificationType || 'reorder';
    const contextData = data?.contextData || {};
    console.log('[testAshNotification] userId:', userId, 'type:', notificationType);

    if (!userId || typeof userId !== 'string') {
      console.error('[testAshNotification] Missing or invalid userId');
      throw new functions.https.HttpsError(
        'invalid-argument',
        'userId is required',
      );
    }

    const allowedTypes = [
      'reorder',
      'cart',
      'hunger',
      'recommendation',
      'recovery',
      'payment_failed',
      'order_accepted',
      'order_ready',
    ];
    if (!allowedTypes.includes(notificationType)) {
      console.error('[testAshNotification] Invalid type:', notificationType);
      throw new functions.https.HttpsError(
        'invalid-argument',
        `Invalid notificationType. Allowed: ${allowedTypes.join(', ')}`,
      );
    }

    try {
      console.log('[testAshNotification] Step 1: Getting FCM tokens for userId:', userId);
      let tokens;
      try {
        tokens = await _getUserFcmTokens(db, userId);
        console.log('[testAshNotification] Step 1 OK: tokens found:', tokens?.length ?? 0);
      } catch (tokensErr) {
        console.error('[testAshNotification] Step 1 FAILED - _getUserFcmTokens:', tokensErr?.message || tokensErr);
        console.error('[testAshNotification] Step 1 stack:', tokensErr?.stack);
        throw tokensErr;
      }
      if (tokens.length === 0) {
        return {
          success: false,
          message: 'User has no valid FCM tokens',
          preview: null,
        };
      }

      console.log('[testAshNotification] Step 2: Getting user document for', userId);
      let userDoc;
      try {
        userDoc = await db.collection('users').doc(userId).get();
        console.log('[testAshNotification] Step 2 OK: userDoc.exists:', userDoc.exists);
      } catch (userErr) {
        console.error('[testAshNotification] Step 2 FAILED - get user doc:', userErr?.message || userErr);
        console.error('[testAshNotification] Step 2 stack:', userErr?.stack);
        throw userErr;
      }
      if (!userDoc.exists) {
        console.error('[testAshNotification] User not found:', userId);
        return {
          success: false,
          message: `User ${userId} not found`,
          preview: null,
        };
      }
      const userData = userDoc.data() || {};
      console.log('[testAshNotification] User data keys:', Object.keys(userData));
      console.log('[testAshNotification] User data (partial):', JSON.stringify({
        firstName: userData.firstName,
        displayName: userData.displayName,
        timezone: userData.timezone,
      }));

      const userForBuilder = {
        id: userId,
        userID: userId,
        firstName: userData.firstName || userData.displayName || '',
        displayName: userData.displayName || userData.firstName || '',
        settings: userData.settings || {},
        timezone: userData.timezone || 'Asia/Manila',
      };

      let title;
      let body;
      let ashData = {};

      console.log('[testAshNotification] Step 3: Building notification, type:', notificationType);
      console.log('[testAshNotification] Step 3: contextData:', JSON.stringify(contextData));
      if (contextData.overrideTitle || contextData.overrideBody) {
        title = contextData.overrideTitle || 'Test notification';
        body = contextData.overrideBody || 'Test body';
        ashData = {
          type: `ash_${notificationType}`,
          notificationId: `test_${userId}_${Date.now()}`,
          userId: String(userId),
          timestamp: new Date().toISOString(),
          ash: 'true',
        };
      } else {
        try {
          console.log('[testAshNotification] Step 3: Calling AshNotificationBuilder.buildAshNotification');
          const built = AshNotificationBuilder.buildAshNotification(
            notificationType,
            userForBuilder,
            contextData,
          );
          title = built.title;
          body = built.body;
          ashData = built.data || {};
          console.log('[testAshNotification] Step 3 OK: built title/body');
        } catch (buildErr) {
          console.error('[testAshNotification] Step 3 FAILED - AshNotificationBuilder:', buildErr?.message || buildErr);
          console.error('[testAshNotification] Step 3 stack:', buildErr?.stack);
          return {
            success: false,
            message: `Build failed: ${buildErr.message}`,
            preview: null,
          };
        }
      }
      console.log('[testAshNotification] Title:', title);
      console.log('[testAshNotification] Body:', body?.substring?.(0, 80) || body);

      console.log('[testAshNotification] Step 4: Sending FCM to token (length:', tokens[0]?.length || 0, ')');
      let messageId;
      try {
        messageId = await _sendFcmToToken(
          tokens[0],
          title,
          body,
          ashData,
        );
        console.log('[testAshNotification] Step 4 OK: messageId=', messageId);
      } catch (fcmErr) {
        console.error('[testAshNotification] Step 4 FAILED - FCM send:', fcmErr?.message || fcmErr);
        console.error('[testAshNotification] Step 4 stack:', fcmErr?.stack);
        return {
          success: false,
          message: `FCM failed: ${fcmErr.message || String(fcmErr)}`,
          preview: { title, body },
        };
      }

      console.log('[testAshNotification] Step 5: Writing analytics to ash_notification_history');

      try {
        await db.collection('ash_notification_history').add({
          userId,
          type: notificationType,
          title,
          body,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          result: { messageId },
          source: 'test',
        });
        console.log('[testAshNotification] Step 5 OK: Analytics logged');
      } catch (historyErr) {
        console.warn('[testAshNotification] Step 5 FAILED (non-fatal):', historyErr?.message || historyErr);
        console.warn('[testAshNotification] Step 5 stack:', historyErr?.stack);
      }

      console.log('[testAshNotification] ========== DONE success ==========');
      return {
        success: true,
        message: `Notification sent (messageId: ${messageId})`,
        preview: { title, body },
      };
    } catch (e) {
      console.error('[testAshNotification] ========== TOP-LEVEL CATCH ==========');
      console.error('[testAshNotification] Error:', e?.message || e);
      console.error('[testAshNotification] Error name:', e?.name);
      console.error('[testAshNotification] Stack:', e?.stack);
      return {
        success: false,
        message: e.message || String(e),
        preview: null,
      };
    }
  });

/**
 * Minimal test function to verify Firestore access and role query.
 */
exports.testSearchBasic = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    console.log('🧪 TEST FUNCTION STARTED');
    console.log('Auth UID:', context.auth?.uid);

    const db = getDb();

    console.log('Test 1: Simple collection access');
    const test1 = await db.collection('users').limit(1).get();
    console.log('Test 1 passed, size:', test1.size);

    console.log('Test 2: Query with role filter');
    const test2 = await db
      .collection('users')
      .where('role', '==', 'customer')
      .limit(1)
      .get();
    console.log('Test 2 passed, size:', test2.size);

    return {
      success: true,
      test1: test1.size,
      test2: test2.size,
      auth: context.auth?.uid,
    };
  });

/**
 * Super simple test - no Firestore, no dependencies. Verifies callable works.
 */
exports.testSearchSimple = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    console.log('✅✅✅ SIMPLE TEST FUNCTION CALLED ✅✅✅');
    console.log('Time:', new Date().toISOString());
    console.log('Auth UID:', context.auth?.uid);

    return {
      success: true,
      message: 'Function is working!',
      timestamp: Date.now(),
    };
  });

/**
 * Step-by-step search - tests Firestore queries incrementally.
 */
exports.searchUsersStepByStep = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    console.log('🔵 STEP 1: Function started');

    try {
      const db = getDb();
      console.log('🔵 STEP 2: Firestore obtained');

      const q = (data?.query && data.query.trim) ? data.query.trim() : '';
      console.log('🔵 STEP 3: Query:', q);

      if (!q || q.length < 3) {
        console.log('🔵 STEP 4: Query too short, returning empty');
        return { users: [] };
      }

      console.log('🔵 STEP 5: Trying simple query');
      const simpleQuery = await db.collection('users').limit(1).get();
      console.log('✅ Simple query worked, found:', simpleQuery.size);

      console.log('🔵 STEP 6: Trying role filter');
      const roleQuery = await db
        .collection('users')
        .where('role', '==', 'customer')
        .limit(1)
        .get();
      console.log('✅ Role filter worked, found:', roleQuery.size);

      return {
        success: true,
        simple: simpleQuery.size,
        role: roleQuery.size,
        message: 'All basic queries work',
      };
    } catch (error) {
      console.error('💥 CRASH:', error);
      throw new functions.https.HttpsError('internal', error.message);
    }
  });

/**
 * Ping for Ash Notification Tester connectivity check.
 * Returns success with timestamp. No auth required for basic reachability.
 */
exports.pingAshTester = functions
  .region('us-central1')
  .https.onCall(() => {
    console.log('[pingAshTester] CALLED ' + new Date().toISOString());
    return { success: true, timestamp: new Date().toISOString() };
  });

/**
 * Minimal ping - zero dependencies. Use to verify callable connectivity.
 */
exports.pingTestMinimal = functions
  .region('us-central1')
  .https.onCall(() => {
    console.log('[pingTestMinimal] CALLED ' + new Date().toISOString());
    return { ok: true, t: Date.now() };
  });

/**
 * Search users for Ash Notification Tester (admin-only).
 * Returns minimal fields to avoid OOM on low-memory clients.
 * Heavily logged for debugging.
 *
 * Params: { query: string } (min 3 chars)
 * Returns: { results: [{ id, name, email, hasToken }] }
 */
exports.searchUsersForAshTester = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    console.log('🚀🚀🚀 SEARCH FUNCTION STARTED 🚀🚀🚀');
    console.log('Timestamp:', new Date().toISOString());
    console.log('Auth present:', !!context.auth);
    console.log('Auth UID:', context.auth?.uid);
    console.log('Raw data received:', JSON.stringify(data));

    if (!context.auth) {
      console.log('❌ Auth missing, throwing unauthenticated');
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const db = getDb();
    console.log('✅ Firestore instance obtained');

    const callerId = context.auth.uid;
    const callerDoc = await db.collection('users').doc(callerId).get();
    const callerData = callerDoc.data() || {};
    const role = callerData.role || callerData.userRole || '';
    const isAdmin = role === 'admin' || role === 'Admin';
    console.log('Caller role:', role, 'isAdmin:', isAdmin);

    if (!isAdmin) {
      console.log('❌ Not admin, throwing permission-denied');
      throw new functions.https.HttpsError(
        'permission-denied',
        'Admin only',
      );
    }

    const q = (typeof data?.query === 'string' ? data.query.trim() : '') || '';
    console.log('Search query after trim:', JSON.stringify(q));

    if (!q || q.length < 3) {
      console.log('Query too short, returning empty results');
      return { results: [] };
    }

    function hasFcmToken(d) {
      const arr = d.fcmTokens;
      if (Array.isArray(arr) && arr.length > 0) {
        return arr.some((t) => typeof t === 'string' && t.trim().length > 0);
      }
      const single = d.fcmToken;
      return single && typeof single === 'string' && single.trim().length > 0;
    }

    function toResult(doc) {
      const d = doc.data() || {};
      const firstName = d.firstName || '';
      const lastName = d.lastName || '';
      const name = `${firstName} ${lastName}`.trim() || 'Unknown';
      return {
        id: doc.id,
        name,
        email: d.email || '',
        hasToken: hasFcmToken(d),
      };
    }

    const suffix = q + '\uf8ff';
    const limit = 20;
    const seenIds = new Set();
    const results = [];

    try {
      console.log(`Executing queries for: "${q}" with suffix "${suffix}"`);

      console.log('1. Testing email query...');
      let emailSnap;
      try {
        emailSnap = await db
          .collection('users')
          .where('role', '==', 'customer')
          .where('email', '>=', q)
          .where('email', '<=', suffix)
          .limit(limit)
          .get();
        console.log(`✅ Email query succeeded, found: ${emailSnap.size}`);
      } catch (emailError) {
        console.error('❌ Email query FAILED:', emailError);
        console.error('Email error stack:', emailError.stack);
        throw emailError;
      }

      console.log('2. Testing firstName query...');
      let firstNameSnap;
      try {
        firstNameSnap = await db
          .collection('users')
          .where('role', '==', 'customer')
          .where('firstName', '>=', q)
          .where('firstName', '<=', suffix)
          .limit(limit)
          .get();
        console.log(`✅ FirstName query succeeded, found: ${firstNameSnap.size}`);
      } catch (firstNameError) {
        console.error('❌ FirstName query FAILED:', firstNameError);
        console.error('FirstName error stack:', firstNameError.stack);
        throw firstNameError;
      }

      console.log('3. Testing lastName query...');
      let lastNameSnap;
      try {
        lastNameSnap = await db
          .collection('users')
          .where('role', '==', 'customer')
          .where('lastName', '>=', q)
          .where('lastName', '<=', suffix)
          .limit(limit)
          .get();
        console.log(`✅ LastName query succeeded, found: ${lastNameSnap.size}`);
      } catch (lastNameError) {
        console.error('❌ LastName query FAILED:', lastNameError);
        console.error('LastName error stack:', lastNameError.stack);
        throw lastNameError;
      }

      console.log('Combining results (users with FCM tokens only)...');
      for (const doc of emailSnap.docs) {
        if (!seenIds.has(doc.id)) {
          const r = toResult(doc);
          if (r.hasToken) {
            seenIds.add(doc.id);
            results.push(r);
          }
        }
      }
      for (const doc of firstNameSnap.docs) {
        if (seenIds.has(doc.id)) continue;
        const r = toResult(doc);
        if (r.hasToken) {
          seenIds.add(doc.id);
          results.push(r);
        }
        if (results.length >= limit) break;
      }
      for (const doc of lastNameSnap.docs) {
        if (seenIds.has(doc.id)) continue;
        const r = toResult(doc);
        if (r.hasToken) {
          seenIds.add(doc.id);
          results.push(r);
        }
        if (results.length >= limit) break;
      }

      if (
        results.length < limit &&
        q.length >= 20 &&
        /^[a-zA-Z0-9_-]+$/.test(q)
      ) {
        const docSnap = await db.collection('users').doc(q).get();
        if (docSnap.exists) {
          const d = docSnap.data() || {};
          if (
            d.role === 'customer' &&
            hasFcmToken(d) &&
            !seenIds.has(docSnap.id)
          ) {
            results.push(toResult(docSnap));
          }
        }
      }

      console.log(`✅ Total users with tokens: ${results.length}`);
      console.log('🚀 SEARCH FUNCTION COMPLETED SUCCESSFULLY 🚀');
      return { results };
    } catch (error) {
      console.error('💥💥💥 SEARCH FUNCTION CRASHED 💥💥💥');
      console.error('Error name:', error.name);
      console.error('Error message:', error.message);
      console.error('Error code:', error.code);
      console.error('Error details:', error.details);
      console.error('Stack trace:', error.stack);

      try {
        await getDb().collection('function_errors').add({
          function: 'searchUsersForAshTester',
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          query: data?.query,
          auth: context.auth?.uid,
          error: {
            name: error.name,
            message: error.message,
            code: error.code,
            stack: error.stack,
          },
        });
        console.log('✅ Error logged to Firestore');
      } catch (logError) {
        console.error('❌ Could not log error to Firestore:', logError);
      }

      const isIndexError =
        error.code === 9 ||
        (error.message && /index|FAILED_PRECONDITION/i.test(error.message));

      if (isIndexError) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Missing Firestore indexes. Please add the required indexes.',
          {
            requiredIndexes: [
              { fields: ['role', 'email'] },
              { fields: ['role', 'firstName'] },
              { fields: ['role', 'lastName'] },
            ],
            firestoreError: error.message,
          }
        );
      }

      throw new functions.https.HttpsError(
        'internal',
        `Search failed: ${error.message}`,
        { originalError: error.message, errorCode: error.code }
      );
    }
  });

/**
 * Diagnose Ash Tester search queries (admin-only).
 * Runs simplified Firestore queries to isolate which combination fails.
 *
 * Returns: { results: [{ name, passed, error? }] }
 */
exports.diagnoseAshTesterSearch = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const callerId = context.auth.uid;
    const db = getDb();
    const callerDoc = await db.collection('users').doc(callerId).get();
    const callerData = callerDoc.data() || {};
    const role = callerData.role || callerData.userRole || '';
    const isAdmin = role === 'admin' || role === 'Admin';

    if (!isAdmin) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Admin only',
      );
    }

    const results = [];
    const q = 'aaa';

    try {
      const snap1 = await db
        .collection('users')
        .where('role', '==', 'customer')
        .limit(1)
        .get();
      results.push({ name: 'Simple (role only)', passed: true, count: snap1.size });
    } catch (e) {
      results.push({
        name: 'Simple (role only)',
        passed: false,
        error: e.message || String(e),
      });
    }

    try {
      const snap2 = await db
        .collection('users')
        .where('role', '==', 'customer')
        .where('email', '>=', q)
        .where('email', '<=', q + '\uf8ff')
        .limit(1)
        .get();
      results.push({
        name: 'Role + email prefix',
        passed: true,
        count: snap2.size,
      });
    } catch (e) {
      results.push({
        name: 'Role + email prefix',
        passed: false,
        error: e.message || String(e),
      });
    }

    try {
      const snap3 = await db
        .collection('users')
        .where('role', '==', 'customer')
        .where('firstName', '>=', q)
        .where('firstName', '<=', q + '\uf8ff')
        .limit(1)
        .get();
      results.push({
        name: 'Role + firstName prefix',
        passed: true,
        count: snap3.size,
      });
    } catch (e) {
      results.push({
        name: 'Role + firstName prefix',
        passed: false,
        error: e.message || String(e),
      });
    }

    try {
      const snap4 = await db
        .collection('users')
        .where('role', '==', 'customer')
        .where('lastName', '>=', q)
        .where('lastName', '<=', q + '\uf8ff')
        .limit(1)
        .get();
      results.push({
        name: 'Role + lastName prefix',
        passed: true,
        count: snap4.size,
      });
    } catch (e) {
      results.push({
        name: 'Role + lastName prefix',
        passed: false,
        error: e.message || String(e),
      });
    }

    return { results };
  });

/**
 * Send Individual FCM Notification
 * 
 * HTTP function to send push notification to a single user
 * 
 * POST body: { 
 *   title: string, 
 *   body: string, 
 *   token: string,
 *   data?: object,
 *   imageUrl?: string,
 *   deepLink?: string
 * }
 * Returns: { success: boolean, messageId?: string, error?: string }
 */
exports.sendIndividualNotification = functions.region('us-central1').https.onRequest(async (req, res) => {
  try {
    if (handleCors(req, res)) {
      return;
    }

    // Only allow POST requests
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed. Use POST.' });
      return;
    }

    const { title, body, token, data, imageUrl, deepLink } = req.body;

    if (!title || !body || !token) {
      res.status(400).json({ error: 'Title, body, and token are required' });
      return;
    }

    console.log('[IndividualNotification] Sending to token:', token.substring(0, 20) + '...');
    console.log('[IndividualNotification] Title:', title);
    console.log('[IndividualNotification] Body:', body);

    const response = await _sendFcmToToken(token, title, body, data || {}, {
      imageUrl,
      deepLink,
    });

    console.log('[IndividualNotification] Successfully sent:', response);

    res.json({
      success: true,
      messageId: response,
    });

  } catch (error) {
    console.error('[IndividualNotification] Error:', error);
    res.status(500).json({ 
      success: false,
      error: error.message || 'Failed to send notification' 
    });
  }
});

/**
 * Firestore Trigger: Send order status notification to customer
 *
 * Triggered on restaurant_orders/{orderId} document updates when status changes.
 * Sends FCM with title/body based on new status and data payload for deep linking.
 */
exports.sendOrderStatusNotification = functions
  .region('us-central1')
  .firestore.document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const orderId = String(context.params.orderId || '');
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};
    const beforeStatus = String(beforeData.status || '');
    const afterStatus = String(afterData.status || '');

    if (beforeStatus === afterStatus) return null;

    // Refund gift cards when order is cancelled
    if (afterStatus === 'Order Cancelled') {
      const breakdown = afterData.giftCardBreakdown;
      if (Array.isArray(breakdown) && breakdown.length > 0) {
        const db = getDb();
        const refundHelper = giftCardFunctions._refundGiftCardForOrder;
        for (const entry of breakdown) {
          const cardId = entry?.cardId;
          const amount = Number(entry?.amount);
          if (cardId && !isNaN(amount) && amount > 0) {
            try {
              await refundHelper(db, cardId, amount, orderId);
              console.log(`[sendOrderStatusNotification] Gift card refunded: cardId=${cardId} amount=${amount}`);
            } catch (e) {
              console.error(`[sendOrderStatusNotification] Gift card refund failed:`, e);
            }
          }
        }
      }
    }

    const customerId = String(
      afterData.authorID ||
        afterData.authorId ||
        afterData.customerId ||
        afterData.customerID ||
        (afterData.author && afterData.author.id) ||
        ''
    );
    if (!customerId) {
      console.log(
        `[sendOrderStatusNotification] Skip: missing customerId. orderId=${orderId}`
      );
      return null;
    }

    const db = getDb();
    const customerDoc = await db.collection('users').doc(customerId).get();
    const userData = customerDoc.exists ? customerDoc.data() || {} : {};
    const restaurantName =
      afterData.vendor?.title || 'the restaurant';

    const statusToType = {
      'Order Placed': 'order_placed',
      'Order Accepted': 'order_accepted',
      'Driver Assigned': 'rider_assigned',
      'Driver Accepted': 'preparing',
      'Order Shipped': 'order_ready',
      'In Transit': 'on_the_way',
      'Order Completed': 'order_delivered',
      'Driver Rejected': 'finding_rider',
      'Order Cancelled': 'order_cancelled',
      'Order Rejected': 'order_rejected',
      'Payment Failed': 'payment_failed_status',
    };
    const ashType = statusToType[afterStatus];
    let title = 'Order Update';
    let body = 'Your order status has been updated.';

    if (ashType) {
      const notification = AshNotificationBuilder.buildAshNotification(
        ashType,
        { ...userData, id: customerId },
        { restaurantName, userId: customerId }
      );
      title = notification.title;
      body = notification.body;
    } else {
      title = 'Order Update';
      body = 'Your order status has been updated.';
    }
    const customerTokens = await _getUserFcmTokens(db, customerId);

    if (customerTokens.length === 0) {
      console.log(
        `[sendOrderStatusNotification] Skip: no FCM token. orderId=${orderId} customerId=${customerId}`
      );
      return null;
    }

    try {
      const messagePayload = {
        notification: { title, body },
        data: {
          type: 'order_update',
          orderId: String(orderId),
          status: String(afterStatus),
          customerId: String(customerId),
        },
        android: {
          priority: 'high',
          notification: { sound: 'default' },
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
      };

      const multicastMessage = { ...messagePayload, tokens: customerTokens };
      const resp = await getMessaging().sendEachForMulticast(multicastMessage);
      console.log(
        `[sendOrderStatusNotification] Sent. orderId=${orderId} status=${afterStatus} ${resp.successCount}/${customerTokens.length}`
      );
    } catch (e) {
      console.error(
        `[sendOrderStatusNotification] Failed for orderId=${orderId}:`,
        e
      );
    }
    return null;
  });

/**
 * Firestore Trigger: Award referral credits on order completion
 *
 * Triggered on restaurant_orders/{orderId} document updates.
 * Runs only when status transitions to 'Order Completed'.
 *
 * This implements the same logic as the legacy client-side transaction
 * (Customer FireStoreUtils.processReferralCompletion) but server-side to avoid
 * overlapping client transactions that can crash Android.
 *
 * Idempotency: referral_credits/{customerId}_{orderId}
 */
exports.awardReferralCreditsOnOrderCompletion = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const orderId = String(context.params.orderId || '');
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};

    const beforeStatus = String(beforeData.status || '');
    const afterStatus = String(afterData.status || '');

    if (!(beforeStatus !== 'Order Completed' && afterStatus === 'Order Completed')) {
      return null;
    }

    const customerId = String(
      afterData.authorID ||
        afterData.authorId ||
        afterData.customerId ||
        afterData.customerID ||
        ''
    );

    if (!customerId) {
      console.log(
        `[awardReferralCreditsOnOrderCompletion] Skip: missing customerId. orderId=${orderId}`
      );
      return null;
    }

    const db = getDb();

    try {
      await db.runTransaction(async (transaction) => {
        const referralCreditRef = db
          .collection('referral_credits')
          .doc(`${customerId}_${orderId}`);

        const referralCreditSnap = await transaction.get(referralCreditRef);
        if (referralCreditSnap.exists) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: already credited. customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const customerRef = db.collection('users').doc(customerId);
        const customerSnap = await transaction.get(customerRef);
        if (!customerSnap.exists) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: customer not found. customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const customer = customerSnap.data() || {};
        const referredBy = String(customer.referredBy || '').trim();
        const hasCompletedFirstOrder = customer.hasCompletedFirstOrder === true;

        if (!referredBy || hasCompletedFirstOrder) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: not eligible (no referrer or already completed first order). customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const pendingReferralRef = db.collection('pending_referrals').doc(customerId);
        const pendingReferralSnap = await transaction.get(pendingReferralRef);
        if (!pendingReferralSnap.exists) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: no pending referral record. customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const pendingReferral = pendingReferralSnap.data() || {};
        if (pendingReferral.isProcessed === true) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: pending referral already processed. customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const referrerId = String(pendingReferral.referrerId || '').trim();
        if (!referrerId) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: pending referral missing referrerId. customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const settingsRef = db.collection('settings').doc('referral_amount');
        const settingsSnap = await transaction.get(settingsRef);
        const referralAmountRaw = settingsSnap.exists
          ? settingsSnap.data()?.referralAmount
          : null;
        const referralAmountValue = Number(referralAmountRaw || 0);

        if (!Number.isFinite(referralAmountValue) || referralAmountValue <= 0) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: invalid referralAmount. value=${referralAmountRaw} customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const referrerRef = db.collection('users').doc(referrerId);
        const referrerSnap = await transaction.get(referrerRef);
        if (!referrerSnap.exists) {
          console.log(
            `[awardReferralCreditsOnOrderCompletion] Skip: referrer not found. referrerId=${referrerId} customerId=${customerId} orderId=${orderId}`
          );
          return;
        }

        const referrer = referrerSnap.data() || {};
        const previousWalletAmount = Number(referrer.wallet_amount || 0);
        const newWalletAmount = previousWalletAmount + referralAmountValue;

        const customerName = `${String(customer.firstName || '').trim()} ${String(
          customer.lastName || ''
        ).trim()}`.trim();
        const referrerName = `${String(referrer.firstName || '').trim()} ${String(
          referrer.lastName || ''
        ).trim()}`.trim();

        // 1) Mark pending referral processed
        transaction.update(pendingReferralRef, {
          isProcessed: true,
          status: 'earned',
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
          processedOrderId: orderId,
        });

        // 2) Mark customer's first order completed
        transaction.update(customerRef, {
          hasCompletedFirstOrder: true,
          firstOrderCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
          firstOrderId: orderId,
        });

        // 3) Increment referrer's wallet
        transaction.update(referrerRef, {
          wallet_amount: newWalletAmount,
        });

        // 4) Idempotency record (and UI data)
        transaction.set(referralCreditRef, {
          customerId: customerId,
          referrerId: referrerId,
          orderId: orderId,
          amount: referralAmountValue,
          type: 'referral_bonus',
          status: 'completed',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          customerName: customerName,
          referrerName: referrerName,
        });

        // 5) Audit record
        const auditRef = db.collection('referral_transactions').doc();
        transaction.set(auditRef, {
          id: auditRef.id,
          referrerId: referrerId,
          customerId: customerId,
          orderId: orderId,
          amount: referralAmountValue,
          type: 'referral_bonus',
          status: 'completed',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          customerName: customerName,
          referrerName: referrerName,
          previousWalletAmount: previousWalletAmount,
          newWalletAmount: newWalletAmount,
        });

        console.log(
          `[awardReferralCreditsOnOrderCompletion] Success. referrerId=${referrerId} customerId=${customerId} orderId=${orderId} amount=${referralAmountValue}`
        );
      });
    } catch (error) {
      console.error(
        `[awardReferralCreditsOnOrderCompletion] Error. customerId=${customerId} orderId=${orderId}:`,
        error
      );
    }

    return null;
  });

/**
 * Firestore Trigger: Award loyalty token on order completion
 *
 * Triggered on restaurant_orders/{orderId} document updates.
 * Runs only when status transitions to 'Order Completed'.
 * Idempotency: loyalty_credits/{customerId}_{orderId}
 */
exports.awardLoyaltyTokenOnOrderCompletion = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const orderId = String(context.params.orderId || '');
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};

    const beforeStatus = String(beforeData.status || '');
    const afterStatus = String(afterData.status || '');

    if (
      !(
        beforeStatus !== 'Order Completed' &&
        afterStatus === 'Order Completed'
      )
    ) {
      return null;
    }

    const customerId = String(
      afterData.authorID ||
        afterData.authorId ||
        afterData.customerId ||
        afterData.customerID ||
        ''
    );

    if (!customerId) {
      console.log(
        `[awardLoyaltyTokenOnOrderCompletion] Skip: missing customerId. orderId=${orderId}`
      );
      return null;
    }

    const db = getDb();

    try {
      const configSnap = await db
        .collection('settings')
        .doc('loyaltyConfig')
        .get();
      if (!configSnap.exists) {
        console.log(
          `[awardLoyaltyTokenOnOrderCompletion] Skip: no loyaltyConfig. orderId=${orderId}`
        );
        return null;
      }

      const config = configSnap.data() || {};
      if (!config.enabled) {
        console.log(
          `[awardLoyaltyTokenOnOrderCompletion] Skip: loyalty disabled. orderId=${orderId}`
        );
        return null;
      }

      const tokensPerOrder = Number(config.tokensPerOrder || 1);
      const tz = (config.cycles && config.cycles.timezone) || 'Asia/Manila';

      const loyaltyCreditRef = db
        .collection('loyalty_credits')
        .doc(`${customerId}_${orderId}`);

      const creditSnap = await loyaltyCreditRef.get();
      if (creditSnap.exists) {
        console.log(
          `[awardLoyaltyTokenOnOrderCompletion] Skip: already credited. customerId=${customerId} orderId=${orderId}`
        );
        return null;
      }

      const orderDate =
        afterData.deliveredAt ||
        afterData.createdAt ||
        admin.firestore.FieldValue.serverTimestamp();
      let orderDateForCycle = new Date();
      if (orderDate && typeof orderDate.toDate === 'function') {
        orderDateForCycle = orderDate.toDate();
      } else if (orderDate && orderDate.seconds != null) {
        orderDateForCycle = new Date(orderDate.seconds * 1000);
      }

      const calculatedCycle = loyaltyHelpers.getCurrentCycle(
        orderDateForCycle,
        config
      );

      const customerRef = db.collection('users').doc(customerId);
      const customerSnap = await customerRef.get();
      if (!customerSnap.exists) {
        console.log(
          `[awardLoyaltyTokenOnOrderCompletion] Skip: customer not found. customerId=${customerId} orderId=${orderId}`
        );
        return null;
      }

      const customer = customerSnap.data() || {};
      let loyalty = customer.loyalty || {};
      const currentCycle = loyalty.currentCycle || '';
      let tokensThisCycle = Number(loyalty.tokensThisCycle || 0);
      let lifetimeTokens = Number(loyalty.lifetimeTokens || 0);
      let previousCycle = loyalty.previousCycle || null;
      let previousTier = loyalty.previousTier || null;
      let previousTokens = loyalty.previousTokens ?? null;
      let tierHistory = Array.isArray(loyalty.tierHistory)
        ? [...loyalty.tierHistory]
        : [];
      let rewardsClaimed = Array.isArray(loyalty.rewardsClaimed)
        ? loyalty.rewardsClaimed
        : [];

      if (currentCycle && currentCycle !== calculatedCycle) {
        previousCycle = currentCycle;
        previousTier = loyalty.currentTier || 'bronze';
        previousTokens = tokensThisCycle;
        tokensThisCycle = 0;
      }

      tokensThisCycle += tokensPerOrder;
      lifetimeTokens += tokensPerOrder;

      const previousTierName = loyalty.currentTier || 'bronze';
      const newTier = loyaltyHelpers.getTierFromTokens(tokensThisCycle, config);

      if (newTier !== previousTierName) {
        tierHistory.push({
          tier: newTier,
          achievedAt: admin.firestore.FieldValue.serverTimestamp(),
          cycle: calculatedCycle,
        });
      }

      const { start, end } = loyaltyHelpers.getCycleDateRange(
        calculatedCycle,
        tz
      );

      const loyaltyUpdate = {
        currentCycle: calculatedCycle,
        cycleStartDate: admin.firestore.Timestamp.fromDate(start),
        cycleEndDate: admin.firestore.Timestamp.fromDate(end),
        tokensThisCycle,
        currentTier: newTier,
        lifetimeTokens,
        rewardsClaimed,
        tierHistory,
      };
      if (previousCycle != null) loyaltyUpdate.previousCycle = previousCycle;
      if (previousTier != null) loyaltyUpdate.previousTier = previousTier;
      if (previousTokens != null)
        loyaltyUpdate.previousTokens = previousTokens;

      await db.runTransaction(async (transaction) => {
        transaction.update(customerRef, { loyalty: loyaltyUpdate });
        transaction.set(loyaltyCreditRef, {
          customerId,
          orderId,
          tokens: tokensPerOrder,
          cycle: calculatedCycle,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });

      console.log(
        `[awardLoyaltyTokenOnOrderCompletion] Success. customerId=${customerId} orderId=${orderId} tokens=${tokensPerOrder} tier=${newTier}`
      );

      if (newTier !== previousTierName) {
        try {
          const customerTokens = await _getUserFcmTokens(db, customerId);
          if (customerTokens.length > 0) {
            const tierDisplay = newTier.charAt(0).toUpperCase() + newTier.slice(1);
            const messagePayload = {
              notification: {
                title: 'Level Up!',
                body: `Congratulations! You're now a ${tierDisplay} member!`,
              },
              data: {
                type: 'loyalty_tier_up',
                newTier,
                customerId,
              },
              android: {
                priority: 'high',
                notification: { sound: 'default' },
              },
              apns: {
                payload: { aps: { sound: 'default' } },
              },
            };
            const multicastMessage = {
              ...messagePayload,
              tokens: customerTokens,
            };
            await getMessaging().sendEachForMulticast(multicastMessage);
            console.log(
              `[awardLoyaltyTokenOnOrderCompletion] Tier-up FCM sent. customerId=${customerId} newTier=${newTier}`
            );
          }
        } catch (fcmErr) {
          console.error(
            `[awardLoyaltyTokenOnOrderCompletion] FCM failed:`,
            fcmErr
          );
        }
      }
    } catch (error) {
      console.error(
        `[awardLoyaltyTokenOnOrderCompletion] Error. customerId=${customerId} orderId=${orderId}:`,
        error
      );
    }

    return null;
  });

/**
 * Callable: claimLoyaltyReward
 * Validates claim, adds to rewardsClaimed, applies wallet credit if applicable.
 */
exports.claimLoyaltyReward = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Must be authenticated',
      );
    }

    const userId = context.auth.uid;
    const rewardId = (data?.rewardId || '').toString().trim();
    if (!rewardId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'rewardId required',
      );
    }

    const db = getDb();

    const configSnap = await db
      .collection('settings')
      .doc('loyaltyConfig')
      .get();
    if (!configSnap.exists) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Loyalty program not configured',
      );
    }

    const config = configSnap.data() || {};
    if (!config.enabled) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Loyalty program is disabled',
      );
    }

    const userRef = db.collection('users').doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'User not found',
      );
    }

    const user = userSnap.data() || {};
    const loyalty = user.loyalty || {};
    const currentTier = loyalty.currentTier || 'bronze';
    const currentCycle = loyalty.currentCycle || '';
    const rewardsClaimed = Array.isArray(loyalty.rewardsClaimed)
      ? [...loyalty.rewardsClaimed]
      : [];

    if (!currentCycle) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'No active loyalty cycle',
      );
    }

    const benefit = _resolveBenefitForRewardId(rewardId, currentTier, config);
    if (!benefit) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Reward not available for your tier',
      );
    }

    const alreadyClaimed = rewardsClaimed.some(
      (r) => r.rewardId === rewardId && r.cycle === currentCycle
    );
    if (alreadyClaimed) {
      throw new functions.https.HttpsError(
        'already-exists',
        'Reward already claimed this cycle',
      );
    }

    const tz = (config.cycles && config.cycles.timezone) || 'Asia/Manila';
    const { end } = loyaltyHelpers.getCycleDateRange(currentCycle, tz);
    const expiresAt = admin.firestore.Timestamp.fromDate(end);

    const newReward = {
      rewardId,
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      cycle: currentCycle,
      expiresAt,
      orderId: null,
    };

    const benefitType = benefit.type || '';
    let walletCreditAmount = 0;
    if (benefitType === 'wallet_credit' && benefit.amount != null) {
      walletCreditAmount = Number(benefit.amount) || 0;
    }

    await db.runTransaction(async (transaction) => {
      rewardsClaimed.push(newReward);
      const loyaltyUpdate = {
        ...loyalty,
        rewardsClaimed,
      };

      const updateData = { loyalty: loyaltyUpdate };
      if (walletCreditAmount > 0) {
        const prevWallet = Number(user.wallet_amount || 0);
        updateData.wallet_amount = prevWallet + walletCreditAmount;
      }

      transaction.update(userRef, updateData);
    });

    return {
      success: true,
      rewardId,
      walletCredit: walletCreditAmount,
    };
  });

function _resolveBenefitForRewardId(rewardId, tier, config) {
  const benefitsConfig = config.benefits || {};
  const benefits = _getAllBenefitsForTier(tier, benefitsConfig);
  for (const b of benefits) {
    const bid = _benefitToRewardId(b);
    if (bid === rewardId) return b;
  }
  return null;
}

function _getAllBenefitsForTier(tier, benefitsConfig) {
  const result = [];
  const list = benefitsConfig[tier];
  if (!Array.isArray(list)) return result;
  for (const item of list) {
    if (item && typeof item === 'object') {
      if (item.type === 'inherits' && item.from) {
        result.push(..._getAllBenefitsForTier(item.from, benefitsConfig));
      } else {
        result.push(item);
      }
    }
  }
  return result;
}

function _benefitToRewardId(b) {
  const type = (b.type || '').toString();
  if (type === 'free_delivery') return 'free_delivery';
  if (type === 'wallet_credit') {
    const amt = b.amount != null ? b.amount : 50;
    return `wallet_credit_${amt}`;
  }
  if (type === 'badge') return `badge_${b.name || 'vip'}`;
  return type;
}

// ============================================================
// Phase 4D: Enrich dispatch_events when an order is completed
// ============================================================

exports.orderCompletionEnrichment = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change) => {
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};

    // Track restaurant prep time: Order Accepted -> Order Shipped
    if (
      beforeData.status !== 'Order Shipped' &&
      afterData.status === 'Order Shipped'
    ) {
      try {
        const vendorId = afterData.vendorID || afterData.vendor?.id || '';
        const acceptedAt = afterData.acceptedAt;
        if (vendorId && acceptedAt) {
          const toMs = (ts) => {
            if (!ts) return null;
            if (ts._seconds != null) return ts._seconds * 1000;
            if (ts.seconds != null) return ts.seconds * 1000;
            if (ts.toMillis) return ts.toMillis();
            return null;
          };
          const acceptedMs = toMs(acceptedAt);
          const shippedMs = Date.now();
          if (acceptedMs) {
            const actualPrepMinutes = Math.round(
              (shippedMs - acceptedMs) / 60000
            );
            if (actualPrepMinutes > 0 && actualPrepMinutes < 180) {
              const statsRef = getDb()
                .collection('vendors')
                .doc(vendorId)
                .collection('restaurant_stats')
                .doc('prep_times');
              const statsSnap = await statsRef.get();
              const stats = statsSnap.exists ? statsSnap.data() : {};
              const recent = Array.isArray(stats.recentPrepTimes)
                ? stats.recentPrepTimes
                : [];
              recent.push(actualPrepMinutes);
              const trimmed = recent.slice(-50);
              const avg =
                trimmed.reduce((a, b) => a + b, 0) / trimmed.length;
              await statsRef.set(
                {
                  averagePrepTimeMinutes: Math.round(avg * 10) / 10,
                  totalOrdersTracked:
                    admin.firestore.FieldValue.increment(1),
                  lastUpdatedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                  recentPrepTimes: trimmed,
                },
                { merge: true }
              );
              console.log(
                `[PrepTimeTracking] Vendor ${vendorId}: prep=${actualPrepMinutes}m avg=${Math.round(avg)}m`
              );
            }
          }
        }
      } catch (prepErr) {
        console.error('[PrepTimeTracking] Error:', prepErr);
      }

      // Send FCM to rider when food is ready for pickup
      try {
        const orderId = change.after.id;
        const driverId = String(afterData.driverID || '');
        if (driverId) {
          const driverSnap = await getDb().collection('users').doc(driverId).get();
          const fcmToken = driverSnap.exists ? driverSnap.data()?.fcmToken : null;
          const vendor = afterData.vendor || {};
          const restaurantName = (vendor.title || 'Restaurant').toString().trim();
          if (fcmToken) {
            await getMessaging().send({
              token: fcmToken,
              notification: {
                title: 'Food Ready for Pickup',
                body: `Your order from ${restaurantName} is now ready!`,
              },
              data: {
                type: 'food_ready',
                orderId: String(orderId),
              },
            });
            console.log(`[FoodReadyFCM] Sent to rider ${driverId} for order ${orderId}`);
          } else {
            console.log(`[FoodReadyFCM] No FCM token for rider ${driverId}`);
          }
        }
      } catch (fcmErr) {
        console.error('[FoodReadyFCM] Error:', fcmErr);
      }
    }

    if (beforeData.status === 'Order Completed') return null;
    if (afterData.status !== 'Order Completed') return null;

    const orderId = change.after.id;
    const db = getDb();

    try {
      const assignedAt = afterData.assignedAt;
      const pickedUpAt = afterData.pickedUpAt;
      const deliveredAt = afterData.deliveredAt;

      const toMs = (ts) => {
        if (!ts) return null;
        if (ts._seconds != null) return ts._seconds * 1000;
        if (ts.seconds != null) return ts.seconds * 1000;
        if (ts.toMillis) return ts.toMillis();
        return null;
      };

      const assignedMs = toMs(assignedAt);
      const pickedMs = toMs(pickedUpAt);
      const deliveredMs = toMs(deliveredAt);

      let pickupWaitMin = null;
      if (assignedMs && pickedMs) {
        pickupWaitMin = Math.round((pickedMs - assignedMs) / 60000);
      }

      let deliveryMin = null;
      if (pickedMs && deliveredMs) {
        deliveryMin = Math.round((deliveredMs - pickedMs) / 60000);
      }

      let totalMin = null;
      if (assignedMs && deliveredMs) {
        totalMin = Math.round((deliveredMs - assignedMs) / 60000);
      }

      const ON_TIME_THRESHOLD_MINUTES = 45;
      const wasOnTime =
        totalMin != null ? totalMin <= ON_TIME_THRESHOLD_MINUTES : null;

      const driverEarnings = _asNumber(afterData.driverEarnings || 0);

      let customerRating = null;
      try {
        const reviewSnap = await db
          .collection('foods_review')
          .where('orderid', '==', orderId)
          .limit(1)
          .get();
        if (!reviewSnap.empty) {
          customerRating = _asNumber(
            reviewSnap.docs[0].data().rating || 0,
          );
        }
      } catch (_) {}

      const eventsSnap = await db
        .collection('dispatch_events')
        .where('orderId', '==', orderId)
        .limit(10)
        .get();

      if (eventsSnap.empty) return null;

      const enrichData = {
        'outcome.actualPickupWaitMinutes': pickupWaitMin,
        'outcome.actualDeliveryMinutes': deliveryMin,
        'outcome.wasOnTime': wasOnTime,
        'outcome.customerRating': customerRating,
        'outcome.riderEarnings': driverEarnings,
        'outcome.completedAt':
          admin.firestore.FieldValue.serverTimestamp(),
      };

      for (const doc of eventsSnap.docs) {
        const eventData = doc.data() || {};
        const predictedEta = eventData?.factors?.etaMinutes;
        const routingSrc = eventData?.factors?.routingSource || 'haversine';
        const etaAccuracy = {};
        if (predictedEta != null && pickupWaitMin != null) {
          etaAccuracy.predictedEtaMinutes = predictedEta;
          etaAccuracy.actualTravelMinutes = pickupWaitMin;
          etaAccuracy.errorMinutes = Math.abs(predictedEta - pickupWaitMin);
          etaAccuracy.wasRoutingUsed = routingSrc === 'google_distance_matrix';
        }
        const update = { ...enrichData };
        if (Object.keys(etaAccuracy).length > 0) {
          update.etaAccuracy = etaAccuracy;
        }
        await doc.ref.update(update);
      }

      console.log(
        `[CompletionEnrichment] Enriched ${eventsSnap.size} events for ${orderId}` +
          ` (pickup=${pickupWaitMin}m delivery=${deliveryMin}m onTime=${wasOnTime})`,
      );

      const riderId = String(afterData.driverID || '');
      if (riderId) {
        await getDb().collection('users').doc(riderId).update({
          completedToday: admin.firestore.FieldValue.increment(1),
        });
        await _recalculateRiderPerformance(riderId);
      }
    } catch (e) {
      console.error(
        `[CompletionEnrichment] Error for order ${orderId}:`,
        e,
      );
    }

    return null;
  });

// ============================================================
// Phase 4E/F: Daily dispatch analytics + weight auto-tuning
// ============================================================

const WEIGHT_KEYS = [
  'weightETA',
  'weightWorkload',
  'weightDirection',
  'weightAcceptanceProb',
  'weightFairness',
];
const FACTOR_TO_WEIGHT = {
  etaMinutes: 'weightETA',
  riderCurrentOrders: 'weightWorkload',
  riderHeadingMatch: 'weightDirection',
  predictedAcceptanceProb: 'weightAcceptanceProb',
};
const MAX_DAILY_ADJUSTMENT = 0.10;
const MIN_SAMPLE_SIZE = 10;

exports.dailyDispatchAnalytics = functions.pubsub
  .schedule('0 3 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    yesterday.setHours(0, 0, 0, 0);
    const endOfYesterday = new Date(yesterday);
    endOfYesterday.setHours(23, 59, 59, 999);

    // Reset completedToday for all drivers at start of day
    try {
      const driversSnap = await db
        .collection('users')
        .where('role', '==', 'driver')
        .get();
      const batch = db.batch();
      let batchCount = 0;
      for (const doc of driversSnap.docs) {
        batch.update(doc.ref, { completedToday: 0 });
        batchCount++;
        if (batchCount >= 500) break;
      }
      if (batchCount > 0) await batch.commit();
      console.log(`[DailyAnalytics] Reset completedToday for ${batchCount} drivers`);
    } catch (resetErr) {
      console.error('[DailyAnalytics] Failed to reset completedToday:', resetErr);
    }

    const dateStr =
      yesterday.toISOString().slice(0, 10);

    try {
      const eventsSnap = await db
        .collection('dispatch_events')
        .where(
          'createdAt',
          '>=',
          admin.firestore.Timestamp.fromDate(yesterday),
        )
        .where(
          'createdAt',
          '<=',
          admin.firestore.Timestamp.fromDate(endOfYesterday),
        )
        .limit(500)
        .get();

      if (eventsSnap.empty) {
        console.log('[DailyAnalytics] No events for', dateStr);
        return null;
      }

      const events = eventsSnap.docs.map((d) => ({
        id: d.id,
        ref: d.ref,
        ...d.data(),
      }));

      // --- Aggregate stats ---
      let totalDispatches = events.length;
      let accepted = 0;
      let totalResponseTime = 0;
      let responseCount = 0;
      let totalDeliveryTime = 0;
      let deliveryCount = 0;
      let onTimeCount = 0;
      let onTimeTotal = 0;
      let batchCount = 0;

      for (const e of events) {
        if (e.batchId) batchCount++;
        const out = e.outcome || {};
        if (out.wasAccepted === true) accepted++;
        if (typeof out.responseTimeSeconds === 'number') {
          totalResponseTime += out.responseTimeSeconds;
          responseCount++;
        }
        if (typeof out.actualDeliveryMinutes === 'number') {
          totalDeliveryTime += out.actualDeliveryMinutes;
          deliveryCount++;
        }
        if (out.wasOnTime != null) {
          onTimeTotal++;
          if (out.wasOnTime === true) onTimeCount++;
        }
      }

      // --- Bayesian weight adjustment ---
      const currentWeights = await _loadDispatchWeights();
      const weightsBefore = {};
      for (const k of WEIGHT_KEYS) {
        weightsBefore[k] = currentWeights[k] || 0;
      }

      const eventsWithOutcome = events.filter(
        (e) => e.outcome && e.outcome.wasAccepted != null,
      );
      const sampleSize = eventsWithOutcome.length;

      let weightsAfter = { ...weightsBefore };
      let adjusted = false;

      if (sampleSize >= MIN_SAMPLE_SIZE) {
        const successful = eventsWithOutcome.filter(
          (e) =>
            e.outcome.wasAccepted === true &&
            e.outcome.wasOnTime !== false,
        );
        const unsuccessful = eventsWithOutcome.filter(
          (e) =>
            e.outcome.wasAccepted === false ||
            e.outcome.wasOnTime === false,
        );

        if (successful.length > 0 && unsuccessful.length > 0) {
          const avgFactor = (arr, key) => {
            let sum = 0;
            let cnt = 0;
            for (const e of arr) {
              const v = e.factors?.[key];
              if (typeof v === 'number') {
                sum += v;
                cnt++;
              }
            }
            return cnt > 0 ? sum / cnt : null;
          };

          for (const [factorKey, weightKey] of Object.entries(
            FACTOR_TO_WEIGHT,
          )) {
            const avgSuccess = avgFactor(successful, factorKey);
            const avgFail = avgFactor(unsuccessful, factorKey);
            if (avgSuccess == null || avgFail == null) continue;
            if (avgFail === 0 && avgSuccess === 0) continue;

            const diff = avgFail - avgSuccess;
            const magnitude =
              Math.abs(diff) /
              Math.max(Math.abs(avgSuccess), Math.abs(avgFail), 1);

            let adjustment = 0;
            if (diff > 0) {
              adjustment = Math.min(magnitude * 0.5, MAX_DAILY_ADJUSTMENT);
            } else if (diff < 0) {
              adjustment = -Math.min(
                magnitude * 0.5,
                MAX_DAILY_ADJUSTMENT,
              );
            }

            weightsAfter[weightKey] = Math.max(
              0.01,
              weightsBefore[weightKey] * (1 + adjustment),
            );
          }

          // Re-normalize so weights sum to 1.0
          let sum = 0;
          for (const k of WEIGHT_KEYS) sum += weightsAfter[k];
          if (sum > 0) {
            for (const k of WEIGHT_KEYS) {
              weightsAfter[k] = Math.round(
                (weightsAfter[k] / sum) * 10000,
              ) / 10000;
            }
          }

          adjusted = true;
        }
      }

      // --- 4F: Retrospective alternativeRiders analysis ---
      for (const e of eventsWithOutcome) {
        const out = e.outcome || {};
        const wasUnsuccessful =
          out.wasAccepted === false || out.wasOnTime === false;
        if (!wasUnsuccessful) continue;
        if (!Array.isArray(e.alternativeRiders)) continue;
        if (e.alternativeRiders.length === 0) continue;

        const selectedScore = e.totalScore;
        if (selectedScore == null) continue;

        const updates = {};
        let needsUpdate = false;
        for (let i = 0; i < e.alternativeRiders.length; i++) {
          const alt = e.alternativeRiders[i];
          if (
            typeof alt.score === 'number' &&
            alt.score < selectedScore
          ) {
            updates[`alternativeRiders.${i}.wouldHaveBeenBetter`] =
              true;
            needsUpdate = true;
          }
        }
        if (needsUpdate) {
          try {
            await e.ref.update(updates);
          } catch (_) {}
        }
      }

      // --- Save updated weights ---
      if (adjusted) {
        await db
          .collection('config')
          .doc('dispatch_weights')
          .set(
            {
              ...weightsAfter,
              updatedAt:
                admin.firestore.FieldValue.serverTimestamp(),
              updatedBy: 'daily_analytics',
            },
            { merge: true },
          );

        // Clear cache so next dispatch uses new weights
        _dispatchWeightsCache = null;
        _dispatchWeightsCacheTime = 0;
      }

      // --- Log weight history ---
      await db.collection('config_weights_history').add({
        date: dateStr,
        timestamp:
          admin.firestore.FieldValue.serverTimestamp(),
        weightsBefore,
        weightsAfter,
        adjusted,
        sampleSize,
        successfulCount: eventsWithOutcome.filter(
          (e) =>
            e.outcome?.wasAccepted === true &&
            e.outcome?.wasOnTime !== false,
        ).length,
        unsuccessfulCount: eventsWithOutcome.filter(
          (e) =>
            e.outcome?.wasAccepted === false ||
            e.outcome?.wasOnTime === false,
        ).length,
      });

      // --- Write daily aggregates ---
      await db
        .collection('dispatch_analytics_daily')
        .doc(dateStr)
        .set({
          date: dateStr,
          totalDispatches,
          successRate:
            totalDispatches > 0
              ? Math.round((accepted / totalDispatches) * 10000) /
                100
              : 0,
          avgResponseTime:
            responseCount > 0
              ? Math.round(totalResponseTime / responseCount)
              : 0,
          avgDeliveryTime:
            deliveryCount > 0
              ? Math.round(
                  (totalDeliveryTime / deliveryCount) * 10,
                ) / 10
              : 0,
          onTimeRate:
            onTimeTotal > 0
              ? Math.round(
                  (onTimeCount / onTimeTotal) * 10000,
                ) / 100
              : 0,
          batchRate:
            totalDispatches > 0
              ? Math.round(
                  (batchCount / totalDispatches) * 10000,
                ) / 100
              : 0,
          weightsBefore,
          weightsAfter,
          sampleSize,
          avgCustomerWaitMinutes:
            deliveryCount > 0
              ? Math.round(
                  (totalDeliveryTime / deliveryCount + (totalResponseTime / Math.max(responseCount, 1)) / 60) * 10,
                ) / 10
              : 0,
          avgRejectionsPerOrder:
            totalDispatches > 0
              ? Math.round(
                  ((totalDispatches - accepted) / Math.max(accepted, 1)) * 10,
                ) / 10
              : 0,
          avgDispatchLatencySeconds:
            responseCount > 0
              ? Math.round(totalResponseTime / responseCount)
              : 0,
          createdAt:
            admin.firestore.FieldValue.serverTimestamp(),
        });

      console.log(
        `[DailyAnalytics] ${dateStr}: ${totalDispatches} dispatches, ` +
          `${Math.round((accepted / Math.max(totalDispatches, 1)) * 100)}% accepted, ` +
          `adjusted=${adjusted} (sample=${sampleSize})`,
      );
    } catch (e) {
      console.error('[DailyAnalytics] Error:', e);
    }

    // --- Rider status consistency check ---
    try {
      await _ensureWeightsLoaded();
      const allDriversSnap = await db.collection('users')
        .where('role', '==', 'driver')
        .get();
      let fixed = 0;
      let staleLocationWarnings = 0;
      const auditBatch = db.batch();
      const thirtyMinAgo = Date.now() - 30 * 60 * 1000;

      for (const doc of allDriversSnap.docs) {
        const data = doc.data() || {};
        const expected = _computeRiderStatus(data);
        const currentAvail = data.riderAvailability || '';

        if (currentAvail !== expected.riderAvailability) {
          auditBatch.set(
            db.collection('status_audit').doc(),
            {
              driverId: doc.id,
              before: {
                riderAvailability: currentAvail,
                riderDisplayStatus: data.riderDisplayStatus || '',
              },
              after: expected,
              fixedAt: admin.firestore.FieldValue.serverTimestamp(),
              reason: 'daily_consistency_check',
            },
          );
          auditBatch.update(doc.ref, {
            riderAvailability: expected.riderAvailability,
            riderDisplayStatus: expected.riderDisplayStatus,
          });
          fixed++;
        }

        if (expected.riderAvailability === 'available') {
          const locTs = data.locationUpdatedAt;
          if (locTs && locTs.toMillis && locTs.toMillis() < thirtyMinAgo) {
            staleLocationWarnings++;
          }
        }
      }

      if (fixed > 0) await auditBatch.commit();
      console.log(
        `[DailyAnalytics] Status consistency: checked=${allDriversSnap.size} `
        + `fixed=${fixed} staleLocationWarnings=${staleLocationWarnings}`,
      );
    } catch (statusErr) {
      console.warn('[DailyAnalytics] Status consistency check error:', statusErr.message || statusErr);
    }

    // Cleanup expired routes_cache entries
    try {
      const expiredSnap = await db
        .collection('routes_cache')
        .where('expiresAt', '<', admin.firestore.Timestamp.now())
        .limit(500)
        .get();
      if (!expiredSnap.empty) {
        const deleteBatch = db.batch();
        expiredSnap.docs.forEach((d) => deleteBatch.delete(d.ref));
        await deleteBatch.commit();
        console.log(`[DailyAnalytics] Cleaned ${expiredSnap.size} expired route cache entries`);
      }
    } catch (cacheErr) {
      console.warn('[DailyAnalytics] Route cache cleanup error:', cacheErr.message || cacheErr);
    }

    return null;
  });

// --- Callable: Release order due to rider accept timeout (Admin client timeout) ---
exports.releaseOrderDueToTimeout = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const orderId = data?.orderId;
    if (!orderId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'orderId required',
      );
    }
    const db = getDb();
    const orderSnap = await db.collection('restaurant_orders').doc(orderId).get();
    if (!orderSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Order not found');
    }
    const orderData = orderSnap.data() || {};
    if (orderData.status !== 'Driver Assigned') {
      return { success: false, reason: 'already_handled' };
    }
    const deadline = orderData?.dispatch?.riderAcceptDeadline;
    if (!deadline || deadline.toMillis() > Date.now()) {
      return { success: false, reason: 'deadline_not_passed' };
    }
    const driverId = String(orderData.driverID || '');
    console.log(`[releaseOrderDueToTimeout] Processing order ${orderId}`);
    await _releaseDriverFromOrder(driverId, orderId);
    await sendReassignmentNotification(driverId, orderId);
    await orderSnap.ref.update({
      status: 'Order Accepted',
      'dispatch.stage': 'admin_client_timeout',
      'dispatch.lock': false,
      'dispatch.excludedDriverIds': admin.firestore.FieldValue.arrayUnion(
        driverId,
      ),
      'dispatch.retryCount': admin.firestore.FieldValue.increment(1),
      driverID: admin.firestore.FieldValue.delete(),
      assignedDriverName: admin.firestore.FieldValue.delete(),
    });
    await _logDispatchEvent({
      type: 'admin_client_timeout',
      orderId,
      payload: { driverId },
    });
    return { success: true };
  });

// --- One-time migration: backfill riderAvailability + riderDisplayStatus ---
exports.migrateRiderStatus = functions.https.onRequest(async (req, res) => {
  try {
    const db = getDb();
    await _ensureWeightsLoaded();
    const driversSnap = await db.collection('users')
      .where('role', '==', 'driver')
      .get();

    let updated = 0;
    const batchSize = 400;
    let writeBatch = db.batch();
    let inBatch = 0;

    for (const doc of driversSnap.docs) {
      const data = doc.data() || {};
      const { riderAvailability, riderDisplayStatus } = _computeRiderStatus(data);
      writeBatch.update(doc.ref, { riderAvailability, riderDisplayStatus });
      updated++;
      inBatch++;

      if (inBatch >= batchSize) {
        await writeBatch.commit();
        console.log(`[Migration] Committed ${updated} riders so far`);
        writeBatch = db.batch();
        inBatch = 0;
      }
    }

    if (inBatch > 0) await writeBatch.commit();
    res.json({ success: true, driversUpdated: updated });
  } catch (err) {
    console.error('[Migration] Error:', err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * One-time callable to fix riderAvailability for drivers affected by the
 * migration bug (incorrectly set to on_delivery when they have spare capacity).
 * Only updates drivers where current riderAvailability differs from computed.
 */
exports.fixRiderAvailabilityCallable = functions.region('us-central1')
  .https.onCall(async (data, context) => {
    const db = getDb();
    await _loadDispatchWeights();
    const limit = Math.min(
      Math.max(parseInt(data?.limit || '500', 10) || 500, 1),
      2000,
    );

    const driversSnap = await db.collection('users')
      .where('role', '==', 'driver')
      .limit(limit)
      .get();

    let fixed = 0;
    const weights = await _loadDispatchWeights();

    for (const doc of driversSnap.docs) {
      const driverData = doc.data() || {};
      const expected = _computeRiderStatus(driverData, weights);
      const current = String(driverData.riderAvailability || '');
      if (current !== expected.riderAvailability) {
        await doc.ref.update({
          riderAvailability: expected.riderAvailability,
          riderDisplayStatus: expected.riderDisplayStatus,
        });
        fixed++;
      }
    }

    return {
      success: true,
      processed: driversSnap.size,
      fixed,
      limit,
    };
  });

/**
 * Firestore trigger: recompute riderAvailability when inProgressOrderID changes.
 * Catches missed updates from other code paths.
 */
exports.onDriverInProgressOrderIDChange = functions.firestore
  .document('users/{driverId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const beforeIds = JSON.stringify(before?.inProgressOrderID || []);
    const afterIds = JSON.stringify(after?.inProgressOrderID || []);
    if (beforeIds === afterIds) return null;

    const weights = await _loadDispatchWeights();
    const expected = _computeRiderStatus(after, weights);
    const current = String(after?.riderAvailability || '');
    if (current !== expected.riderAvailability) {
      await change.after.ref.update({
        riderAvailability: expected.riderAvailability,
        riderDisplayStatus: expected.riderDisplayStatus,
      });
    }
    return null;
  });

// ============================================================
// Rider Performance Recalculation (server-side weighted formula)
// ============================================================

async function _loadPerformanceTierConfig() {
  const db = getDb();
  try {
    const doc = await db.collection('config').doc('performance_tiers').get();
    if (doc.exists) {
      const d = doc.data() || {};
      return {
        goldThreshold: _asNumber(d.gold_threshold) || 90,
        silverThreshold: _asNumber(d.silver_threshold) || 75,
        bronzeThreshold: _asNumber(d.bronze_threshold) || 60,
      };
    }
  } catch (_) {}
  return { goldThreshold: 90, silverThreshold: 75, bronzeThreshold: 60 };
}

function _getTierName(score, config) {
  if (score >= config.goldThreshold) return 'Gold';
  if (score >= config.silverThreshold) return 'Silver';
  if (score >= config.bronzeThreshold) return 'Bronze';
  return 'Needs Improvement';
}

async function _recalculateRiderPerformance(riderId) {
  const db = getDb();

  // 1) Acceptance rate from last 50 assignments_log entries
  let acceptanceRate = 70.0;
  try {
    const logsSnap = await db
      .collection('assignments_log')
      .where('driverId', '==', riderId)
      .orderBy('timestamp', 'desc')
      .limit(50)
      .get();
    if (!logsSnap.empty) {
      let accepted = 0;
      let total = 0;
      for (const doc of logsSnap.docs) {
        const s = doc.data().status;
        if (s === 'accepted' || s === 'rejected' || s === 'timeout') {
          total++;
          if (s === 'accepted') accepted++;
        }
      }
      if (total > 0) {
        acceptanceRate = (accepted / total) * 100;
      }
    }
  } catch (e) {
    console.error(`[PerfRecalc] assignments_log error for ${riderId}:`, e);
  }

  // 2) Average customer rating from last 50 reviews (foods_review collection)
  let averageRating = 0;
  let hasRatings = false;
  try {
    const reviewsSnap = await db
      .collection('foods_review')
      .where('driverId', '==', riderId)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();
    if (!reviewsSnap.empty) {
      let sum = 0;
      let count = 0;
      for (const doc of reviewsSnap.docs) {
        const r = _asNumber(doc.data().rating);
        if (r > 0) {
          sum += r;
          count++;
        }
      }
      if (count > 0) {
        averageRating = sum / count;
        hasRatings = true;
      }
    }
  } catch (e) {
    console.error(`[PerfRecalc] foods_review error for ${riderId}:`, e);
  }

  // 3) Attendance score (existing driver_performance as attendance input)
  let attendanceScore = 75.0;
  try {
    const userDoc = await db.collection('users').doc(riderId).get();
    if (userDoc.exists) {
      const ud = userDoc.data() || {};
      attendanceScore = _asNumber(ud.attendance_score);
      if (attendanceScore <= 0) {
        attendanceScore = _asNumber(ud.driver_performance) || 75.0;
      }
    }
  } catch (e) {
    console.error(`[PerfRecalc] user read error for ${riderId}:`, e);
  }

  // 4) Weighted formula: 40% acceptance + 30% rating + 30% attendance
  //    Rating normalized to 0-100 (rating / 5 * 100)
  const normalizedRating = hasRatings ? (averageRating / 5) * 100 : 75.0;
  const driverPerformance = Math.min(
    100,
    Math.max(
      50,
      0.4 * acceptanceRate +
        0.3 * normalizedRating +
        0.3 * attendanceScore,
    ),
  );

  // 5) Determine tier
  const tierConfig = await _loadPerformanceTierConfig();
  const performanceTier = _getTierName(driverPerformance, tierConfig);

  // 6) Write back to user document
  await db
    .collection('users')
    .doc(riderId)
    .update({
      driver_performance: Math.round(driverPerformance * 10) / 10,
      acceptance_rate: Math.round(acceptanceRate * 10) / 10,
      average_rating: Math.round(averageRating * 100) / 100,
      attendance_score: Math.round(attendanceScore * 10) / 10,
      performance_tier: performanceTier,
      performance_breakdown: {
        acceptanceRate: Math.round(acceptanceRate * 10) / 10,
        averageRating: Math.round(averageRating * 100) / 100,
        attendanceScore: Math.round(attendanceScore * 10) / 10,
        lastCalculated:
          admin.firestore.FieldValue.serverTimestamp(),
      },
    });

  console.log(
    `[PerfRecalc] ${riderId}: acceptance=${acceptanceRate.toFixed(1)}%` +
      ` rating=${averageRating.toFixed(2)} attendance=${attendanceScore.toFixed(1)}` +
      ` => ${driverPerformance.toFixed(1)}% (${performanceTier})`,
  );
}

// Trigger: recalculate when a customer review is created (foods_review)
// Also sends FCM to restaurant (vendor) and rider when review is created.
exports.onReviewCreated = functions.firestore
  .document('foods_review/{reviewId}')
  .onCreate(async (snap, context) => {
    const reviewId = context.params.reviewId;
    const data = snap.data() || {};
    const riderId = String(data.driverId || '');
    const vendorId = String(data.VendorId || data.vendorId || '');
    const rating = (data.rating != null) ? Number(data.rating) : 0;
    const comment = String(data.comment || '').substring(0, 80);

    try {
      if (riderId) {
        await _recalculateRiderPerformance(riderId);
        console.log(`[onReviewCreated] Recalculated performance for rider ${riderId}`);
      }
    } catch (e) {
      console.error('[onReviewCreated] Error recalculating rider perf:', e);
    }

    const db = getDb();
    const messaging = getMessaging();

    // Notify restaurant (vendor)
    if (vendorId) {
      try {
        const vendorTokens = await _getVendorFcmTokens(db, vendorId);
        const title = 'New review';
        const body = rating > 0
          ? `${rating}★${comment ? `: ${comment}` : ''}`
          : (comment || 'New customer feedback');
        for (const token of vendorTokens) {
          try {
            await messaging.send({
              token,
              notification: { title, body },
              data: {
                type: 'new_review',
                reviewId,
                vendorId,
                rating: String(rating),
                timestamp: Date.now().toString(),
              },
              android: { priority: 'high' },
              apns: { payload: { aps: { sound: 'default' } } },
            });
          } catch (err) {
            console.warn('[onReviewCreated] FCM to vendor failed:', err.message);
          }
        }
        if (vendorTokens.length > 0) {
          console.log(`[onReviewCreated] Sent FCM to vendor ${vendorId}`);
        }
      } catch (e) {
        console.error('[onReviewCreated] Error notifying vendor:', e);
      }
    }

    // Notify rider
    if (riderId) {
      try {
        const riderTokens = await _getUserFcmTokens(db, riderId);
        const title = 'New rating';
        const body = rating > 0
          ? `${rating}★${comment ? `: ${comment}` : ''}`
          : 'You received new feedback';
        for (const token of riderTokens) {
          try {
            await messaging.send({
              token,
              notification: { title, body },
              data: {
                type: 'new_rider_review',
                reviewId,
                driverId: riderId,
                rating: String(rating),
                timestamp: Date.now().toString(),
              },
              android: { priority: 'high' },
              apns: { payload: { aps: { sound: 'default' } } },
            });
          } catch (err) {
            console.warn('[onReviewCreated] FCM to rider failed:', err.message);
          }
        }
        if (riderTokens.length > 0) {
          console.log(`[onReviewCreated] Sent FCM to rider ${riderId}`);
        }
      } catch (e) {
        console.error('[onReviewCreated] Error notifying rider:', e);
      }
    }

    return null;
  });

// Trigger: notify admins when a review is flagged
exports.onReviewFlagged = functions.firestore
  .document('foods_review/{reviewId}')
  .onUpdate(async (change, context) => {
    const after = change.after.data() || {};
    const before = change.before.data() || {};
    const wasFlagged = (before.flaggedBy || []).length > 0 || (before.status === 'flagged');
    const isFlagged = (after.flaggedBy || []).length > 0 || (after.status === 'flagged');
    if (wasFlagged || !isFlagged) return null;

    const reviewId = context.params.reviewId;
    const db = getDb();
    const adminsSnap = await db.collection('users').where('role', '==', 'admin').get();
    const tokens = [];
    for (const doc of adminsSnap.docs) {
      const t = doc.data()?.fcmToken;
      if (t && typeof t === 'string' && t.trim()) tokens.push(t.trim());
    }
    if (tokens.length === 0) return null;

    const rating = (after.rating != null) ? Number(after.rating) : 0;
    const body = `Review flagged: ${rating}★ – ${String(after.comment || '').substring(0, 50)}`;
    const msg = {
      notification: { title: 'Review flagged', body },
      data: {
        type: 'review_flagged',
        reviewId,
        timestamp: Date.now().toString(),
      },
      tokens,
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    };
    try {
      await getMessaging().sendEachForMulticast(msg);
      console.log(`[onReviewFlagged] Notified ${tokens.length} admin(s)`);
    } catch (e) {
      console.error('[onReviewFlagged] FCM error:', e);
    }
    return null;
  });

// Trigger: recalculate when an attendance record is written
exports.onAttendanceRecorded = functions.firestore
  .document('users/{riderId}/attendance_history/{date}')
  .onCreate(async (snap, context) => {
    const riderId = context.params.riderId;
    if (!riderId) return null;
    try {
      await _recalculateRiderPerformance(riderId);
    } catch (e) {
      console.error('[onAttendanceRecorded] Error:', e);
    }
    return null;
  });

// ============================================================
// Weekly Performance Normalization (regression toward baseline)
// ============================================================

exports.weeklyPerformanceNormalization = functions.pubsub
  .schedule('0 4 * * 0')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const REGRESSION_RATE = 0.1;
    const BASELINE = 85.0;

    try {
      const ridersSnap = await db
        .collection('users')
        .where('role', '==', 'driver')
        .get();

      if (ridersSnap.empty) {
        console.log('[WeeklyNorm] No riders found');
        return null;
      }

      const tierConfig = await _loadPerformanceTierConfig();
      let updated = 0;
      const batchSize = 400;
      let batch = db.batch();
      let inBatch = 0;

      for (const doc of ridersSnap.docs) {
        const data = doc.data() || {};
        const current =
          _asNumber(data.driver_performance) || 75;

        const normalized =
          current + (BASELINE - current) * REGRESSION_RATE;
        const clamped = Math.min(100, Math.max(50, normalized));
        const rounded = Math.round(clamped * 10) / 10;

        if (Math.abs(rounded - current) >= 0.1) {
          batch.update(doc.ref, {
            driver_performance: rounded,
            performance_tier: _getTierName(rounded, tierConfig),
          });
          updated++;
          inBatch++;

          if (inBatch >= batchSize) {
            await batch.commit();
            batch = db.batch();
            inBatch = 0;
          }
        }
      }

      if (inBatch > 0) await batch.commit();

      console.log(
        `[WeeklyNorm] Normalized ${updated} riders toward ${BASELINE}`,
      );
    } catch (e) {
      console.error('[WeeklyNorm] Error:', e);
    }

    return null;
  });

// ============================================================
// One-time Migration: seed performance fields for all riders
// ============================================================

exports.migratePerformanceFields = functions
  .runWith({ timeoutSeconds: 540, memory: '256MB' })
  .https.onRequest(async (req, res) => {
    const db = getDb();
    try {
      const ridersSnap = await db
        .collection('users')
        .where('role', '==', 'driver')
        .get();

      if (ridersSnap.empty) {
        return res.json({ success: true, migrated: 0 });
      }

      const tierConfig = await _loadPerformanceTierConfig();
      let migrated = 0;

      for (const doc of ridersSnap.docs) {
        const data = doc.data() || {};
        const riderId = doc.id;
        const currentPerf =
          _asNumber(data.driver_performance) || 75;

        let acceptanceRate = 70;
        try {
          const logsSnap = await db
            .collection('assignments_log')
            .where('driverId', '==', riderId)
            .orderBy('timestamp', 'desc')
            .limit(50)
            .get();
          if (!logsSnap.empty) {
            let accepted = 0;
            let total = 0;
            for (const ld of logsSnap.docs) {
              const s = ld.data().status;
              if (
                s === 'accepted' ||
                s === 'rejected' ||
                s === 'timeout'
              ) {
                total++;
                if (s === 'accepted') accepted++;
              }
            }
            if (total > 0) {
              acceptanceRate = (accepted / total) * 100;
            }
          }
        } catch (_) {}

        let averageRating = 0;
        let hasRatings = false;
        try {
          const reviewsSnap = await db
            .collection('foods_review')
            .where('driverId', '==', riderId)
            .orderBy('createdAt', 'desc')
            .limit(50)
            .get();
          if (!reviewsSnap.empty) {
            let sum = 0;
            let count = 0;
            for (const rd of reviewsSnap.docs) {
              const r = _asNumber(rd.data().rating);
              if (r > 0) {
                sum += r;
                count++;
              }
            }
            if (count > 0) {
              averageRating = sum / count;
              hasRatings = true;
            }
          }
        } catch (_) {}

        const attendanceScore = currentPerf;
        const normalizedRating = hasRatings
          ? (averageRating / 5) * 100
          : 75;
        const newPerf = Math.min(
          100,
          Math.max(
            50,
            0.4 * acceptanceRate +
              0.3 * normalizedRating +
              0.3 * attendanceScore,
          ),
        );
        const rounded = Math.round(newPerf * 10) / 10;

        await doc.ref.update({
          driver_performance: rounded,
          acceptance_rate:
            Math.round(acceptanceRate * 10) / 10,
          average_rating:
            Math.round(averageRating * 100) / 100,
          attendance_score:
            Math.round(attendanceScore * 10) / 10,
          performance_tier:
            _getTierName(rounded, tierConfig),
          performance_breakdown: {
            acceptanceRate:
              Math.round(acceptanceRate * 10) / 10,
            averageRating:
              Math.round(averageRating * 100) / 100,
            attendanceScore:
              Math.round(attendanceScore * 10) / 10,
            lastCalculated:
              admin.firestore.FieldValue.serverTimestamp(),
          },
        });

        migrated++;
      }

      const tierDoc = await db
        .collection('config')
        .doc('performance_tiers')
        .get();
      if (!tierDoc.exists) {
        await db
          .collection('config')
          .doc('performance_tiers')
          .set({
            gold_threshold: 90,
            silver_threshold: 75,
            bronze_threshold: 60,
            createdAt:
              admin.firestore.FieldValue.serverTimestamp(),
          });
      }

      const settingsDoc = await db
        .collection('settings')
        .doc('driver_performance')
        .get();
      if (settingsDoc.exists) {
        const sd = settingsDoc.data() || {};
        const updates = {};
        if (sd.Platinum != null && sd.Bronze == null) {
          updates.Bronze = sd.Platinum;
        }
        if (sd.incentive_platinum != null &&
            sd.incentive_bronze == null) {
          updates.incentive_bronze = sd.incentive_platinum;
        }
        if (sd.silver != null && sd.Silver == null) {
          updates.Silver = sd.silver;
        }
        if (Object.keys(updates).length > 0) {
          updates.migratedAt =
            admin.firestore.FieldValue.serverTimestamp();
          await settingsDoc.ref.update(updates);
        }
      }

      console.log(
        `[Migration] Migrated ${migrated} riders`,
      );
      res.json({ success: true, migrated });
    } catch (err) {
      console.error('[Migration] Error:', err);
      res.status(500).json({ error: err.message });
    }
  });

/**
 * One-time migration: Update all orders with status "Driver Pending" to "Driver Accepted".
 * Run after deploying the Driver Pending removal. Safe to run multiple times.
 */
exports.migrateDriverPendingToAccepted = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    setCors(res);
    if (handleCors(req, res)) return;

    try {
      const db = getDb();
      const snap = await db
        .collection('restaurant_orders')
        .where('status', '==', 'Driver Pending')
        .get();

      let count = 0;
      const batchSize = 500;
      const batches = [];

      for (const doc of snap.docs) {
        batches.push(
          doc.ref.update({
            status: 'Driver Accepted',
            'migration.driverPendingToAcceptedAt':
              admin.firestore.FieldValue.serverTimestamp(),
          })
        );
        count++;
      }

      if (count > 0) {
        for (let i = 0; i < batches.length; i += batchSize) {
          const chunk = batches.slice(i, i + batchSize);
          await Promise.all(chunk);
        }
      }

      console.log(
        `[Migration] Updated ${count} orders from Driver Pending to Driver Accepted`
      );
      res.json({ updated: count });
    } catch (err) {
      console.error('[Migration] migrateDriverPendingToAccepted error:', err);
      res.status(500).json({ error: err.message });
    }
  });

// --- Bundle Deals ---

/**
 * On restaurant_orders create: validate bundle lines (active bundle, correct price).
 * Reject order if any bundle is invalid; otherwise update bundle analytics.
 */
exports.validateBundleOrder = functions
  .region('us-central1')
  .firestore.document('restaurant_orders/{orderId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const data = snap.data() || {};
    const products = data.products || [];
    if (!Array.isArray(products) || products.length === 0) return null;

    const db = getDb();
    const orderRef = snap.ref;
    const bundleIds = [...new Set(
      products
        .map((p) => (p && p.bundleId) ? p.bundleId : null)
        .filter(Boolean)
    )];

    for (const bundleId of bundleIds) {
      const bundleSnap = await db.collection('bundles').doc(bundleId).get();
      if (!bundleSnap.exists) {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Bundle no longer available',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateBundleOrder] Order ${orderId} rejected: bundle ${bundleId} not found`);
        return null;
      }
      const bundle = bundleSnap.data() || {};
      if (bundle.status !== 'active') {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Bundle is no longer active',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateBundleOrder] Order ${orderId} rejected: bundle ${bundleId} not active`);
        return null;
      }

      const bundleItems = bundle.items || [];
      const bundlePrice = Number(bundle.bundlePrice) || 0;
      const linesWithBundle = products.filter((p) => p && p.bundleId === bundleId);
      let linesTotal = 0;
      for (const line of linesWithBundle) {
        const qty = typeof line.quantity === 'number' ? line.quantity : parseInt(line.quantity, 10) || 0;
        const price = typeof line.price === 'number' ? line.price : parseFloat(String(line.price || 0)) || 0;
        linesTotal += qty * price;
      }
      const tolerance = 0.02;
      if (Math.abs(linesTotal - bundlePrice) > tolerance) {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Bundle price mismatch',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateBundleOrder] Order ${orderId} rejected: bundle ${bundleId} price mismatch ${linesTotal} vs ${bundlePrice}`);
        return null;
      }
    }

    // Update analytics for each bundle in the order
    for (const bundleId of bundleIds) {
      try {
        const linesWithBundle = products.filter((p) => p && p.bundleId === bundleId);
        let revenue = 0;
        for (const line of linesWithBundle) {
          const qty = typeof line.quantity === 'number' ? line.quantity : parseInt(line.quantity, 10) || 0;
          const price = typeof line.price === 'number' ? line.price : parseFloat(String(line.price || 0)) || 0;
          revenue += qty * price;
        }
        const batch = db.batch();
        const analyticsRef = db.collection('bundle_analytics').doc(bundleId);
        const bundleRef = db.collection('bundles').doc(bundleId);
        batch.set(analyticsRef, {
          purchaseCount: admin.firestore.FieldValue.increment(1),
          revenue: admin.firestore.FieldValue.increment(revenue),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        batch.update(bundleRef, {
          totalPurchasesCount: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await batch.commit();
      } catch (e) {
        console.warn(`[validateBundleOrder] Analytics update failed for bundle ${bundleId}:`, e);
      }
    }
    return null;
  });

/**
 * On restaurant_orders create: set expiresAt and send FCM to restaurant.
 */
exports.onOrderCreatedSetExpiresAt = functions
  .region('us-central1')
  .firestore.document('restaurant_orders/{orderId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const data = snap.data() || {};
    const vendorId = String(data.vendorID || data.vendorId || data.vendor?.id || '');
    if (!vendorId) {
      console.log(`[onOrderCreatedSetExpiresAt] No vendorId for order ${orderId}`);
      return null;
    }

    const db = getDb();
    const vendorSnap = await db.collection('vendors').doc(vendorId).get();
    const vendorData = vendorSnap.exists ? vendorSnap.data() : {};
    const settings = vendorData.acceptanceSettings || {};
    const timerSeconds = Math.min(300, Math.max(60, settings.timerSeconds || 180));
    const expiresAt = new Date(Date.now() + timerSeconds * 1000);

    await snap.ref.update({
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
      acceptanceTimerSeconds: timerSeconds,
    });

    const fcmToken = vendorData.fcmToken || (data.vendor && data.vendor.fcmToken);
    if (fcmToken) {
      try {
        const payload = { id: orderId, orderId, vendor: data.vendor || vendorData, ...data };
        const message = NotificationBuilder.buildOrderNotification(
          payload,
          'new_order',
          { token: fcmToken, includeActions: true }
        );
        await getMessaging().send(message);
        console.log(`[onOrderCreatedSetExpiresAt] FCM sent to vendor for order ${orderId}`);
      } catch (e) {
        console.error(`[onOrderCreatedSetExpiresAt] FCM failed:`, e);
      }
    }

    return null;
  });

/**
 * On restaurant_orders create: send SMS to restaurant if it has no device.
 * One-way notification only. Admin will accept/reject on behalf of restaurant.
 */
exports.sendOrderSMSNotification = functions
  .region('us-central1')
  .firestore.document('restaurant_orders/{orderId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const data = snap.data() || {};
    const orderRef = snap.ref;

    const vendorId = String(data.vendorID || data.vendorId || data.vendor?.id || '');
    if (!vendorId) {
      console.log(`[sendOrderSMSNotification] No vendorId for order ${orderId}`);
      return null;
    }

    const db = getDb();
    const settingsSnap = await db
      .collection('vendors')
      .doc(vendorId)
      .collection('settings')
      .doc('order_config')
      .get();

    const settings = settingsSnap.exists ? settingsSnap.data() : {};
    const hasDevice = settings.hasDevice !== false;
    const contactNumber = (settings.contactNumber || '').toString().trim();

    if (hasDevice || !contactNumber) {
      return null;
    }

    const orderSnap = await orderRef.get();
    const latest = orderSnap.exists ? orderSnap.data() : {};
    if (String(latest.status || '') === 'Order Rejected') {
      console.log(`[sendOrderSMSNotification] Order ${orderId} already rejected, skip SMS`);
      return null;
    }

    const products = latest.products || latest.productList || [];
    const total = latest.vendorTotal ?? latest.total ?? latest.amount ?? 0;
    const totalNum = typeof total === 'number' ? total : parseFloat(String(total)) || 0;
    const parts = [`[Lalago] New order #${orderId.substring(0, 12)}:`];
    for (const p of products) {
      if (p && (p.name || p.title)) {
        const qty = typeof p.quantity === 'number' ? p.quantity : parseInt(p.quantity, 10) || 1;
        const price = typeof p.price === 'number' ? p.price : parseFloat(String(p.price || 0)) || 0;
        parts.push(`${qty}x ${p.name || p.title} (₱${Math.round(price)})`);
      }
    }
    parts.push(`Total: ₱${Math.round(totalNum)}. Please prepare the food. Rider will be assigned soon.`);
    const body = parts.join(' ');

    try {
      const config = functions.config().sms || {};
      const accountSid = config.account_sid || process.env.TWILIO_ACCOUNT_SID;
      const authToken = config.auth_token || process.env.TWILIO_AUTH_TOKEN;
      const fromNumber = config.from_number || process.env.TWILIO_FROM_NUMBER;

      if (accountSid && authToken && fromNumber) {
        const twilio = require('twilio');
        const client = twilio(accountSid, authToken);
        let to = contactNumber.replace(/\D/g, '');
        if (to.startsWith('0')) to = '63' + to.substring(1);
        else if (!to.startsWith('63')) to = '63' + to;

        await client.messages.create({
          body,
          from: fromNumber,
          to: '+' + to,
        });
        console.log(`[sendOrderSMSNotification] SMS sent to ${to} for order ${orderId}`);
      } else {
        console.log('[sendOrderSMSNotification] Twilio not configured, skip SMS. Set sms.account_sid, sms.auth_token, sms.from_number');
      }
    } catch (e) {
      console.error(`[sendOrderSMSNotification] SMS failed for order ${orderId}:`, e);
    }

    await orderRef.update({
      smsSentAt: admin.firestore.FieldValue.serverTimestamp(),
      restaurantHasNoDevice: true,
    });

    return null;
  });

/**
 * Scheduled: check for pending no-device orders that exceeded timeout and auto-cancel.
 */
exports.pendingOrderTimeoutChecker = functions
  .region('us-central1')
  .pubsub.schedule('every 1 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();
    const ordersSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Order Placed')
      .where('restaurantHasNoDevice', '==', true)
      .get();

    for (const doc of ordersSnap.docs) {
      const data = doc.data();
      const smsSentAt = data.smsSentAt;
      if (!smsSentAt || !smsSentAt.toDate) continue;

      const vendorId = String(data.vendorID || data.vendorId || data.vendor?.id || '');
      let timeoutMinutes = 5;
      if (vendorId) {
        try {
          const settingsSnap = await db
            .collection('vendors')
            .doc(vendorId)
            .collection('settings')
            .doc('order_config')
            .get();
          const settings = settingsSnap.exists ? settingsSnap.data() : {};
          timeoutMinutes = Math.max(1, parseInt(settings.smsTimeoutMinutes, 10) || 5);
        } catch (_) {}
      }

      const sentAt = smsSentAt.toDate();
      const deadline = new Date(sentAt.getTime() + timeoutMinutes * 60 * 1000);
      if (new Date() < deadline) continue;

      try {
        await doc.ref.update({
          status: 'Order Cancelled',
          cancellationReason: 'admin_timeout',
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await db.collection('dispatch_events').add({
          type: 'admin_timeout_cancel',
          orderId: doc.id,
          vendorId,
          timeoutMinutes,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[pendingOrderTimeoutChecker] Order ${doc.id} auto-cancelled (timeout ${timeoutMinutes}m)`);
      } catch (e) {
        console.error(`[pendingOrderTimeoutChecker] Failed to cancel order ${doc.id}:`, e);
      }
    }

    return null;
  });

async function checkAndAutoPause(db, vendorId) {
  const vendorRef = db.collection('vendors').doc(vendorId);
  const vendorSnap = await vendorRef.get();
  if (!vendorSnap.exists) return;

  const vendor = vendorSnap.data();
  const metrics = vendor.acceptanceMetrics || {};
  const settings = vendor.acceptanceSettings || {};
  const consecutive = (metrics.consecutiveUnaccepted || 0);
  const threshold = settings.consecutiveMissesThreshold || 2;
  const autoPauseEnabled = settings.autoPauseEnabled !== false;

  if (consecutive < threshold || !autoPauseEnabled) return;

  const now = new Date();
  let autoUnpauseAt = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 6, 0, 0);
  if (autoUnpauseAt <= now) {
    autoUnpauseAt.setDate(autoUnpauseAt.getDate() + 1);
  }

  await vendorRef.update({
    autoPause: {
      isPaused: true,
      pausedAt: admin.firestore.FieldValue.serverTimestamp(),
      pauseReason: 'consecutive_unaccepted',
      autoUnpauseAt: admin.firestore.Timestamp.fromDate(autoUnpauseAt),
      pausedBy: 'system',
    },
  });

  await vendorRef.collection('pauseHistory').add({
    pausedAt: admin.firestore.FieldValue.serverTimestamp(),
    pauseReason: 'consecutive_unaccepted',
    consecutiveMisses: consecutive,
    autoUnpauseAt: admin.firestore.Timestamp.fromDate(autoUnpauseAt),
    resumedAt: null,
  });

  const fcmToken = vendor.fcmToken;
  if (fcmToken) {
    try {
      await getMessaging().send({
        token: fcmToken,
        notification: {
          title: 'Store Paused',
          body: `Your store has been paused due to ${consecutive} unaccepted orders.`,
        },
        data: {
          type: 'store_paused',
          reason: 'consecutive_unaccepted',
        },
      });
    } catch (e) {
      console.error('[checkAndAutoPause] FCM failed:', e);
    }
  }
}

/**
 * Scheduled: reject expired Order Placed orders and update vendor metrics.
 */
exports.acceptanceTimeoutChecker = functions
  .region('us-central1')
  .pubsub.schedule('* * * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();

    const expiredSnap = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Order Placed')
      .where('expiresAt', '<=', now)
      .limit(100)
      .get();

    for (const doc of expiredSnap.docs) {
      const data = doc.data();
      const vendorId = String(data.vendorID || data.vendorId || data.vendor?.id || '');

      try {
        await doc.ref.update({
          status: 'Order Rejected',
          rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
          rejectionReason: 'timeout',
        });

        await OrderRecoveryService.handleOrderFailure(
          { id: doc.id, ...data },
          'timeout',
          { reason: 'order_timeout' }
        );

        if (vendorId) {
          const vendorRef = db.collection('vendors').doc(vendorId);
          const vendorSnap = await vendorRef.get();
          if (vendorSnap.exists) {
            const v = vendorSnap.data();
            const metrics = v.acceptanceMetrics || {};
            const today = new Date().toISOString().slice(0, 10);
            const lastReset = metrics.lastResetDate || '';
            const updates = {
              'acceptanceMetrics.consecutiveUnaccepted': admin.firestore.FieldValue.increment(1),
              'acceptanceMetrics.lastUnacceptedAt': admin.firestore.FieldValue.serverTimestamp(),
              'acceptanceMetrics.totalUnacceptedToday': admin.firestore.FieldValue.increment(1),
            };
            if (lastReset !== today) {
              updates['acceptanceMetrics.lastResetDate'] = today;
              updates['acceptanceMetrics.totalUnacceptedToday'] = 1;
            }
            await vendorRef.update(updates);
            await checkAndAutoPause(db, vendorId);
          }
        }
        console.log(`[acceptanceTimeoutChecker] Order ${doc.id} rejected (timeout)`);
      } catch (e) {
        console.error(`[acceptanceTimeoutChecker] Failed for order ${doc.id}:`, e);
      }
    }

    return null;
  });

/**
 * Scheduled: auto-unpause vendors at 6 AM daily.
 */
exports.scheduledRestaurantUnpause = functions
  .region('us-central1')
  .pubsub.schedule('0 6 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = admin.firestore.Timestamp.now();

    const pausedSnap = await db
      .collection('vendors')
      .where('autoPause.isPaused', '==', true)
      .where('autoPause.autoUnpauseAt', '<=', now)
      .get();

    for (const doc of pausedSnap.docs) {
      try {
        await doc.ref.update({
          'autoPause.isPaused': false,
          'autoPause.resumedAt': admin.firestore.FieldValue.serverTimestamp(),
          'autoPause.resumedBy': 'auto',
        });

        const historySnap = await doc.ref
          .collection('pauseHistory')
          .where('resumedAt', '==', null)
          .limit(1)
          .get();

        for (const h of historySnap.docs) {
          await h.ref.update({
            resumedAt: admin.firestore.FieldValue.serverTimestamp(),
            resumedBy: 'auto',
          });
        }

        const vendor = doc.data();
        const fcmToken = vendor.fcmToken;
        if (fcmToken) {
          try {
            await getMessaging().send({
              token: fcmToken,
              notification: {
                title: 'Store Auto-Unpaused',
                body: 'Your store has been automatically unpaused and is now accepting orders.',
              },
            });
          } catch (_) {}
        }
        console.log(`[scheduledRestaurantUnpause] Unpaused vendor ${doc.id}`);
      } catch (e) {
        console.error(`[scheduledRestaurantUnpause] Failed for vendor ${doc.id}:`, e);
      }
    }

    return null;
  });

/**
 * Compute publicMetrics for a vendor from last 30 days of dailyMetrics.
 * Returns { badge, acceptanceRate, avgAcceptanceTimeSeconds, orderCountLast30Days, qualifiedAt }
 */
async function computePublicMetrics(db, vendorId, now) {
  const vendorRef = db.collection('vendors').doc(vendorId);
  const refs = [];
  for (let i = 0; i < 30; i++) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    refs.push(vendorRef.collection('dailyMetrics').doc(d.toISOString().slice(0, 10)));
  }
  const snaps = await db.getAll(...refs);

  let totalOrders = 0;
  let accepted = 0;
  let totalAcceptanceTime = 0;
  let acceptanceTimeCount = 0;

  for (const snap of snaps) {
    if (!snap.exists) continue;
    const data = snap.data();
    const t = data.totalOrders || 0;
    const a = data.accepted || 0;
    const avgTime = data.avgAcceptanceTimeSeconds || 0;
    totalOrders += t;
    accepted += a;
    if (a > 0 && avgTime > 0) {
      totalAcceptanceTime += avgTime * a;
      acceptanceTimeCount += a;
    }
  }

  const acceptanceRate = totalOrders > 0 ? (accepted / totalOrders) * 100 : 100;
  const avgAcceptanceTimeSeconds =
    acceptanceTimeCount > 0 ? totalAcceptanceTime / acceptanceTimeCount : 0;
  const qualifiedAt = now.toISOString().slice(0, 10);

  // Aggregate confirmation speed feedback from order_feedback
  let avgConfirmationSpeedRating = null;
  const feedbackSnap = await db
    .collection('order_feedback')
    .where('vendorId', '==', vendorId)
    .get();
  if (!feedbackSnap.empty) {
    let sum = 0;
    let count = 0;
    for (const d of feedbackSnap.docs) {
      const r = d.data().confirmationSpeedRating;
      if (typeof r === 'number' && r >= 1 && r <= 5) {
        sum += r;
        count++;
      }
    }
    if (count > 0) {
      avgConfirmationSpeedRating = Math.round((sum / count) * 10) / 10;
    }
  }

  let badge = null;
  if (totalOrders < 30) {
    badge = 'new';
  } else if (acceptanceRate > 98 && avgAcceptanceTimeSeconds < 45) {
    badge = 'fast';
  } else if (acceptanceRate > 90) {
    badge = 'reliable';
  } else if (acceptanceRate < 80) {
    badge = 'slow';
  }

  const result = {
    badge,
    acceptanceRate: Math.round(acceptanceRate * 10) / 10,
    avgAcceptanceTimeSeconds: Math.round(avgAcceptanceTimeSeconds * 10) / 10,
    orderCountLast30Days: totalOrders,
    qualifiedAt,
  };
  if (avgConfirmationSpeedRating != null) {
    result.avgConfirmationSpeedRating = avgConfirmationSpeedRating;
  }
  return result;
}

/**
 * Compute coordination metrics for a vendor from last 30 days of completed orders.
 * Returns { coordinationScore, avgRiderWaitSeconds, readyOnTimeRate } or null.
 */
async function computeCoordinationMetrics(db, vendorId, now) {
  const thirtyDaysAgo = new Date(now);
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

  const ordersSnap = await db
    .collection('restaurant_orders')
    .where('vendorID', '==', vendorId)
    .where('status', '==', 'Order Completed')
    .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
    .get();

  let totalWaitSeconds = 0;
  let ordersWithArrival = 0;
  let readyOnTimeCount = 0;
  let ordersWithReadyData = 0;

  const toMs = (ts) => {
    if (!ts) return null;
    if (ts._seconds != null) return ts._seconds * 1000;
    if (ts.seconds != null) return ts.seconds * 1000;
    if (ts.toMillis) return ts.toMillis();
    return null;
  };

  for (const doc of ordersSnap.docs) {
    const order = doc.data();
    const arrivedAt = order.coordination?.arrivedAtRestaurant;
    const pickedUpAt = order.pickedUpAt;
    const readyAt = order.readyAt;

    if (arrivedAt && pickedUpAt) {
      const arrivedMs = toMs(arrivedAt);
      const pickedMs = toMs(pickedUpAt);
      if (arrivedMs != null && pickedMs != null) {
        totalWaitSeconds += (pickedMs - arrivedMs) / 1000;
        ordersWithArrival++;
      }
    }

    if (readyAt && arrivedAt) {
      const readyMs = toMs(readyAt);
      const arrivedMs = toMs(arrivedAt);
      if (readyMs != null && arrivedMs != null) {
        if (readyMs <= arrivedMs) readyOnTimeCount++;
        ordersWithReadyData++;
      }
    }
  }

  const avgRiderWaitSeconds =
    ordersWithArrival > 0 ? totalWaitSeconds / ordersWithArrival : null;
  const readyOnTimeRate =
    ordersWithReadyData > 0
      ? (readyOnTimeCount / ordersWithReadyData) * 100
      : null;

  let coordinationScore = 100;
  if (avgRiderWaitSeconds != null) {
    if (avgRiderWaitSeconds > 300) {
      coordinationScore -= Math.min(30, (avgRiderWaitSeconds - 300) / 60);
    }
  }
  if (readyOnTimeRate != null) {
    coordinationScore = coordinationScore * 0.6 + readyOnTimeRate * 0.4;
  }
  coordinationScore = Math.max(0, Math.min(100, Math.round(coordinationScore)));

  return {
    coordinationScore,
    avgRiderWaitSeconds: avgRiderWaitSeconds != null
      ? Math.round(avgRiderWaitSeconds * 10) / 10
      : null,
    readyOnTimeRate: readyOnTimeRate != null
      ? Math.round(readyOnTimeRate * 10) / 10
      : null,
  };
}

/**
 * Scheduled: Send rider arrival warnings to restaurants (Phase 4.2).
 * Runs every 2 minutes. For orders with Driver Accepted/Order Shipped,
 * computes rider ETA to restaurant and sends 5-min and 2-min warnings.
 */
exports.sendRiderArrivalWarnings = functions
  .region('us-central1')
  .pubsub.schedule('every 2 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const twoHoursAgo = new Date(now.getTime() - 2 * 60 * 60 * 1000);

    const ordersSnap = await db
      .collection('restaurant_orders')
      .where('status', 'in', ['Driver Accepted', 'Order Shipped'])
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(twoHoursAgo))
      .get();

    for (const orderDoc of ordersSnap.docs) {
      try {
        const orderId = orderDoc.id;
        const order = orderDoc.data();
        const driverID = order.driverID;
        const vendorID = order.vendorID || order.vendor?.id;
        if (!driverID || !vendorID) continue;

        const coord = order.coordination || {};
        const restaurantNotifiedAt = coord.restaurantNotifiedAt;
        const riderArrivalNotifiedAt = coord.riderArrivalNotifiedAt;

        let restLat; let restLng;
        if (order.vendor && (order.vendor.latitude != null || order.vendor.latitude !== undefined)) {
          restLat = Number(order.vendor.latitude) || 0;
          restLng = Number(order.vendor.longitude) || 0;
        } else {
          const vendorSnap = await db.collection('vendors').doc(vendorID).get();
          if (!vendorSnap.exists) continue;
          const v = vendorSnap.data() || {};
          restLat = Number(v.latitude) || 0;
          restLng = Number(v.longitude) || 0;
        }

        const riderSnap = await db.collection('users').doc(driverID).get();
        if (!riderSnap.exists) continue;
        const riderData = riderSnap.data() || {};
        const loc = riderData.location;
        if (!loc) continue;
        const riderLat = loc.latitude != null ? Number(loc.latitude) : (loc.lat != null ? Number(loc.lat) : null);
        const riderLng = loc.longitude != null ? Number(loc.longitude) : (loc.lng != null ? Number(loc.lng) : null);
        if (riderLat == null || riderLng == null) continue;

        const eta = Math.ceil(calculateETA(
          { lat: riderLat, lng: riderLng },
          { lat: restLat, lng: restLng },
        ));

        const orderRef = db.collection('restaurant_orders').doc(orderId);

        if (eta <= 5 && !restaurantNotifiedAt) {
          let token = String(order.vendor?.fcmToken || '');
          if (!token) {
            const vendorSnap = await db.collection('vendors').doc(vendorID).get();
            token = String(vendorSnap.exists ? (vendorSnap.data()?.fcmToken || '') : '');
          }
          if (token) {
            const shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
            await getMessaging().send({
              token,
              notification: {
                title: 'Rider Arriving Soon',
                body: `Rider for order #${shortId} arriving in ~5 minutes`,
              },
              data: {
                type: 'rider_arrival_warning',
                orderId: String(orderId),
                minutes: '5',
              },
            });
          }
          await orderRef.update({
            'coordination.restaurantNotifiedAt': admin.firestore.FieldValue.serverTimestamp(),
            'coordination.notificationType': 'five_min_warning',
          });
        }

        if (eta <= 2 && !riderArrivalNotifiedAt) {
          let token = String(order.vendor?.fcmToken || '');
          if (!token) {
            const vendorSnap = await db.collection('vendors').doc(vendorID).get();
            token = String(vendorSnap.exists ? (vendorSnap.data()?.fcmToken || '') : '');
          }
          if (token) {
            const shortId = orderId.length > 8 ? orderId.substring(0, 8) : orderId;
            await getMessaging().send({
              token,
              notification: {
                title: 'Rider Arriving NOW',
                body: `Rider for order #${shortId} is ~2 min away`,
              },
              data: {
                type: 'rider_arrival_warning',
                orderId: String(orderId),
                minutes: '2',
              },
            });
          }
          await orderRef.update({
            'coordination.riderArrivalNotifiedAt': admin.firestore.FieldValue.serverTimestamp(),
            'coordination.notificationType': 'two_min_warning',
          });
        }
      } catch (e) {
        console.error(`[sendRiderArrivalWarnings] Error for order ${orderDoc.id}:`, e);
      }
    }
    return null;
  });

/**
 * Scheduled: compute daily restaurant metrics at 11:59 PM (Asia/Manila).
 */
exports.computeDailyRestaurantMetrics = functions
  .region('us-central1')
  .pubsub.schedule('59 23 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const dateStr = now.toISOString().slice(0, 10);
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
    const endOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);

    const vendorsSnap = await db.collection('vendors').get();

    for (const vendorDoc of vendorsSnap.docs) {
      const vendorId = vendorDoc.id;
      const vendorData = vendorDoc.data() || {};

      try {
        const ordersSnap = await db
          .collection('restaurant_orders')
          .where('vendorID', '==', vendorId)
          .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(startOfDay))
          .where('createdAt', '<=', admin.firestore.Timestamp.fromDate(endOfDay))
          .get();

        let total = 0;
        let accepted = 0;
        let missed = 0;
        let totalAcceptanceTime = 0;
        let acceptanceTimeCount = 0;

        for (const orderDoc of ordersSnap.docs) {
          const order = orderDoc.data();
          total++;

          const status = String(order.status || '').toLowerCase();
          if (status === 'order accepted') {
            accepted++;
            const acceptedAt = order.acceptedAt;
            const createdAt = order.createdAt;
            if (acceptedAt && createdAt) {
              const a = acceptedAt.toDate ? acceptedAt.toDate() : new Date(acceptedAt.seconds * 1000);
              const c = createdAt.toDate ? createdAt.toDate() : new Date(createdAt.seconds * 1000);
              totalAcceptanceTime += (a - c) / 1000;
              acceptanceTimeCount++;
            }
          }

          if (status === 'order rejected') missed++;
          if (status === 'order placed') {
            const expiresAt = order.expiresAt;
            if (expiresAt) {
              const exp = expiresAt.toDate ? expiresAt.toDate() : new Date(expiresAt.seconds * 1000);
              if (exp < now) missed++;
            }
          }
        }

        const acceptanceRate = total > 0 ? (accepted / total) * 100 : 100;
        const avgAcceptanceTime = acceptanceTimeCount > 0
          ? totalAcceptanceTime / acceptanceTimeCount
          : 0;

        const metrics = vendorData.acceptanceMetrics || {};
        const autoPause = vendorData.autoPause || {};

        await db
          .collection('vendors')
          .doc(vendorId)
          .collection('dailyMetrics')
          .doc(dateStr)
          .set({
            date: dateStr,
            totalOrders: total,
            accepted,
            missed,
            acceptanceRate,
            avgAcceptanceTimeSeconds: avgAcceptanceTime,
            consecutiveMisses: metrics.consecutiveUnaccepted || 0,
            wasPaused: autoPause.isPaused === true,
            computedAt: admin.firestore.FieldValue.serverTimestamp(),
          });

        // Compute publicMetrics from last 30 days of dailyMetrics
        const publicMetrics = await computePublicMetrics(db, vendorId, now);
        const coordMetrics = await computeCoordinationMetrics(db, vendorId, now);
        const vendorRef = db.collection('vendors').doc(vendorId);
        const currentData = (await vendorRef.get()).data() || {};
        const existingPublicMetrics = currentData.publicMetrics || {};
        const publicUpdates = {
          ...publicMetrics,
          overrideBadge: existingPublicMetrics.overrideBadge || null,
        };
        if (coordMetrics) {
          publicUpdates.coordinationScore = coordMetrics.coordinationScore;
          publicUpdates.avgRiderWaitSeconds = coordMetrics.avgRiderWaitSeconds;
          publicUpdates.readyOnTimeRate = coordMetrics.readyOnTimeRate;
          publicUpdates.coordinationLastUpdated =
            admin.firestore.FieldValue.serverTimestamp();
        }
        await vendorRef.update({
          publicMetrics: publicUpdates,
        });
      } catch (e) {
        console.error(`[computeDailyRestaurantMetrics] Failed for vendor ${vendorId}:`, e);
      }
    }

    console.log(`[computeDailyRestaurantMetrics] Completed for ${vendorsSnap.size} vendors`);
    return null;
  });

/**
 * Callable: Debug dailyMetrics vs restaurant_orders for a vendor.
 * Data: { vendorId: string }. Returns dailyMetrics coverage and direct order count.
 */
exports.debugVendorMetrics = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const db = getDb();
    const vendorId = (data && data.vendorId) || '';
    if (!vendorId) throw new functions.https.HttpsError('invalid-argument', 'vendorId required');

    const now = new Date();
    const thirtyDaysAgo = new Date(now);
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const directOrdersSnap = await db
      .collection('restaurant_orders')
      .where('vendorID', '==', vendorId)
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
      .get();

    const vendorRef = db.collection('vendors').doc(vendorId);
    const dailyDetails = [];
    let fromDailyTotal = 0;
    for (let i = 0; i < 30; i++) {
      const d = new Date(now);
      d.setDate(d.getDate() - i);
      const dateStr = d.toISOString().slice(0, 10);
      const snap = await vendorRef.collection('dailyMetrics').doc(dateStr).get();
      const t = snap.exists ? (snap.data().totalOrders || 0) : null;
      if (snap.exists && t != null) fromDailyTotal += t;
      dailyDetails.push({ date: dateStr, totalOrders: t, exists: snap.exists });
    }

    const pm = (await vendorRef.get()).data()?.publicMetrics || {};
    return {
      vendorId,
      directOrderCountLast30Days: directOrdersSnap.size,
      fromDailyMetricsTotal: fromDailyTotal,
      publicMetricsOrderCount: pm.orderCountLast30Days,
      daysWithDailyMetrics: dailyDetails.filter((d) => d.exists).length,
      dailyDetails: dailyDetails.filter((d) => d.exists),
    };
  });

/**
 * Callable: Backfill dailyMetrics for last N days from restaurant_orders.
 * Use when dailyMetrics was missing (e.g. job recently added). Run once per vendor or all.
 * Data: { vendorId?: string, days?: number } - vendorId optional, days defaults to 30.
 */
exports.backfillDailyMetrics = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const db = getDb();
    const vendorId = (data && data.vendorId) || null;
    const days = Math.min(90, Math.max(1, (data && data.days) || 30));
    const now = new Date();

    const vendorIds = vendorId
      ? [vendorId]
      : (await db.collection('vendors').get()).docs.map((d) => d.id);

    let backfilled = 0;
    for (const vid of vendorIds) {
      try {
        for (let i = 0; i < days; i++) {
          const d = new Date(now);
          d.setDate(d.getDate() - i);
          const dateStr = d.toISOString().slice(0, 10);
          const startOfDay = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0);
          const endOfDay = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59);

          const ordersSnap = await db
            .collection('restaurant_orders')
            .where('vendorID', '==', vid)
            .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(startOfDay))
            .where('createdAt', '<=', admin.firestore.Timestamp.fromDate(endOfDay))
            .get();

          let total = 0;
          let accepted = 0;
          let missed = 0;
          let totalAcceptanceTime = 0;
          let acceptanceTimeCount = 0;

          for (const orderDoc of ordersSnap.docs) {
            const order = orderDoc.data();
            total++;
            const status = String(order.status || '').toLowerCase();
            if (status === 'order accepted') {
              accepted++;
              const acceptedAt = order.acceptedAt;
              const createdAt = order.createdAt;
              if (acceptedAt && createdAt) {
                const a = acceptedAt.toDate ? acceptedAt.toDate() : new Date(acceptedAt.seconds * 1000);
                const c = createdAt.toDate ? createdAt.toDate() : new Date(createdAt.seconds * 1000);
                totalAcceptanceTime += (a - c) / 1000;
                acceptanceTimeCount++;
              }
            }
            if (status === 'order rejected') missed++;
            if (status === 'order placed') {
              const expiresAt = order.expiresAt;
              if (expiresAt) {
                const exp = expiresAt.toDate ? expiresAt.toDate() : new Date(expiresAt.seconds * 1000);
                if (exp < now) missed++;
              }
            }
          }

          const acceptanceRate = total > 0 ? (accepted / total) * 100 : 100;
          const avgAcceptanceTime = acceptanceTimeCount > 0 ? totalAcceptanceTime / acceptanceTimeCount : 0;

          const vendorDoc = await db.collection('vendors').doc(vid).get();
          const vendorData = vendorDoc.data() || {};
          const metrics = vendorData.acceptanceMetrics || {};
          const autoPause = vendorData.autoPause || {};

          await db
            .collection('vendors')
            .doc(vid)
            .collection('dailyMetrics')
            .doc(dateStr)
            .set({
              date: dateStr,
              totalOrders: total,
              accepted,
              missed,
              acceptanceRate,
              avgAcceptanceTimeSeconds: avgAcceptanceTime,
              consecutiveMisses: metrics.consecutiveUnaccepted || 0,
              wasPaused: autoPause.isPaused === true,
              computedAt: admin.firestore.FieldValue.serverTimestamp(),
              backfilled: true,
            });

          if (total > 0) backfilled++;
        }

        const publicMetrics = await computePublicMetrics(db, vid, now);
        const coordMetrics = await computeCoordinationMetrics(db, vid, now);
        const vendorRef = db.collection('vendors').doc(vid);
        const currentData = (await vendorRef.get()).data() || {};
        const existingPublicMetrics = currentData.publicMetrics || {};
        const publicUpdates = {
          ...publicMetrics,
          overrideBadge: existingPublicMetrics.overrideBadge || null,
        };
        if (coordMetrics) {
          publicUpdates.coordinationScore = coordMetrics.coordinationScore;
          publicUpdates.avgRiderWaitSeconds = coordMetrics.avgRiderWaitSeconds;
          publicUpdates.readyOnTimeRate = coordMetrics.readyOnTimeRate;
          publicUpdates.coordinationLastUpdated = admin.firestore.FieldValue.serverTimestamp();
        }
        await vendorRef.update({ publicMetrics: publicUpdates });
      } catch (e) {
        console.error(`[backfillDailyMetrics] Failed for vendor ${vid}:`, e);
        throw new functions.https.HttpsError('internal', `Backfill failed: ${e.message}`);
      }
    }

    return { vendorsProcessed: vendorIds.length, days, backfilled };
  });

/**
 * Scheduled: set status to 'inactive' for bundles whose endDate has passed.
 */
exports.deactivateExpiredBundles = functions
  .region('us-central1')
  .pubsub.schedule('every 1 hours')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const snap = await db
      .collection('bundles')
      .where('status', '==', 'active')
      .get();
    let count = 0;
    for (const doc of snap.docs) {
      const endDate = doc.get('endDate');
      if (!endDate) continue;
      const end = endDate.toDate ? endDate.toDate() : new Date(endDate.seconds * 1000);
      if (end < now) {
        await doc.ref.update({
          status: 'inactive',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
      }
    }
    if (count > 0) {
      console.log(`[deactivateExpiredBundles] Deactivated ${count} expired bundles`);
    }
    return null;
  });

// --- Add-on Promos ---

/**
 * On restaurant_orders create: validate add-on promo lines (active promo, correct price, same restaurant, max qty).
 * Reject order if any addon line is invalid; otherwise update addon analytics.
 */
exports.validateAddonOrder = functions
  .region('us-central1')
  .firestore.document('restaurant_orders/{orderId}')
  .onCreate(async (snap, context) => {
    const orderId = context.params.orderId;
    const data = snap.data() || {};
    if (data.status === 'Order Rejected') return null;
    const products = data.products || [];
    if (!Array.isArray(products) || products.length === 0) return null;

    const addonPromoIds = [...new Set(
      products
        .map((p) => (p && p.addonPromoId) ? p.addonPromoId : null)
        .filter(Boolean)
    )];
    if (addonPromoIds.length === 0) return null;

    const db = getDb();
    const orderRef = snap.ref;
    const orderVendorID = data.vendorID || data.vendorId || '';

    for (const addonPromoId of addonPromoIds) {
      const promoSnap = await db.collection('addon_promos').doc(addonPromoId).get();
      if (!promoSnap.exists) {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Add-on promo no longer available',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateAddonOrder] Order ${orderId} rejected: addon promo ${addonPromoId} not found`);
        return null;
      }
      const promo = promoSnap.data() || {};
      if (promo.status !== 'active') {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Add-on promo is no longer active',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateAddonOrder] Order ${orderId} rejected: addon promo ${addonPromoId} not active`);
        return null;
      }
      if (promo.restaurantId !== orderVendorID) {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Add-on promo restaurant mismatch',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateAddonOrder] Order ${orderId} rejected: addon promo ${addonPromoId} wrong restaurant`);
        return null;
      }

      const expectedAddonPrice = Number(promo.addonPrice) || 0;
      const maxQty = Number(promo.maxQuantityPerOrder) || 1;
      const linesWithAddon = products.filter((p) => p && p.addonPromoId === addonPromoId);
      let totalQty = 0;
      let linesTotal = 0;
      for (const line of linesWithAddon) {
        const qty = typeof line.quantity === 'number' ? line.quantity : parseInt(line.quantity, 10) || 0;
        const price = typeof line.price === 'number' ? line.price : parseFloat(String(line.price || 0)) || 0;
        totalQty += qty;
        linesTotal += qty * price;
      }
      if (totalQty > maxQty) {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Add-on quantity exceeds maximum allowed',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateAddonOrder] Order ${orderId} rejected: addon promo ${addonPromoId} qty ${totalQty} > max ${maxQty}`);
        return null;
      }
      const expectedTotal = expectedAddonPrice * totalQty;
      const tolerance = 0.02;
      if (totalQty > 0 && Math.abs(linesTotal - expectedTotal) > tolerance) {
        await orderRef.update({
          status: 'Order Rejected',
          rejectionReason: 'Add-on price mismatch',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`[validateAddonOrder] Order ${orderId} rejected: addon promo ${addonPromoId} price mismatch ${linesTotal} vs ${expectedTotal}`);
        return null;
      }
    }

    // Update analytics for each addon promo in the order
    for (const addonPromoId of addonPromoIds) {
      try {
        const linesWithAddon = products.filter((p) => p && p.addonPromoId === addonPromoId);
        let revenue = 0;
        for (const line of linesWithAddon) {
          const qty = typeof line.quantity === 'number' ? line.quantity : parseInt(line.quantity, 10) || 0;
          const price = typeof line.price === 'number' ? line.price : parseFloat(String(line.price || 0)) || 0;
          revenue += qty * price;
        }
        const batch = db.batch();
        const analyticsRef = db.collection('addon_promo_analytics').doc(addonPromoId);
        const promoRef = db.collection('addon_promos').doc(addonPromoId);
        batch.set(analyticsRef, {
          purchaseCount: admin.firestore.FieldValue.increment(1),
          revenue: admin.firestore.FieldValue.increment(revenue),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        batch.update(promoRef, {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await batch.commit();
      } catch (e) {
        console.warn(`[validateAddonOrder] Analytics update failed for addon promo ${addonPromoId}:`, e);
      }
    }
    return null;
  });

/**
 * Scheduled: set status to 'inactive' for addon promos whose endDate has passed.
 * Skips docs without endDate.
 */
exports.deactivateExpiredAddonPromos = functions
  .region('us-central1')
  .pubsub.schedule('every 1 hours')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = new Date();
    const snap = await db
      .collection('addon_promos')
      .where('status', '==', 'active')
      .get();
    let count = 0;
    for (const doc of snap.docs) {
      const endDate = doc.get('endDate');
      if (!endDate) continue;
      const end = endDate.toDate ? endDate.toDate() : new Date(endDate.seconds * 1000);
      if (end < now) {
        await doc.ref.update({
          status: 'inactive',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
      }
    }
    if (count > 0) {
      console.log(`[deactivateExpiredAddonPromos] Deactivated ${count} expired addon promos`);
    }
    return null;
  });

// Personalized discovery (GrabFood-style)
const { computeItemSimilarities } = require('./computeItemSimilarities');
const { computeUserPreferences } = require('./computeUserPreferences');
const HungerDetection = require('./hungerDetection');
exports.computeItemSimilarities = computeItemSimilarities;
exports.computeUserPreferences = computeUserPreferences;

// Multi-stage vector search for AI product search
const {
  onProductWrite,
  vectorSearchProducts,
} = require('./vectorSearch');
exports.onProductWrite = onProductWrite;
exports.vectorSearchProducts = vectorSearchProducts;

// Ash voice analytics
const {
  trackAshNotificationMetrics,
  analyzeAshVoice,
} = require('./ashVoiceAnalytics');
exports.trackAshNotificationMetrics = trackAshNotificationMetrics;
exports.analyzeAshVoice = analyzeAshVoice;

// Daily analytics aggregations
const {
  aggregateDailyNotifications,
  aggregateDailyUserMetrics,
  aggregateDailyRevenue,
} = require('./dailyAggregations');
const {
  updateUserSegments,
  manualUpdateUserSegments,
  runUserSegmentMigration,
  checkSegmentFields,
  debugUserSegmentation,
  fixSingleUnknownUser,
  migrateAllUserSegments,
  testFunctionWorks,
  debugSingleUser,
  checkNotificationAccess,
  testSegmentationNoNotifications,
  checkFirestorePermissions,
} = require('./updateUserSegments');
exports.aggregateDailyNotifications = aggregateDailyNotifications;
exports.aggregateDailyUserMetrics = aggregateDailyUserMetrics;
exports.aggregateDailyRevenue = aggregateDailyRevenue;
exports.updateUserSegments = updateUserSegments;
exports.manualUpdateUserSegments = manualUpdateUserSegments;
exports.runUserSegmentMigration = runUserSegmentMigration;
exports.checkSegmentFields = checkSegmentFields;
exports.debugUserSegmentation = debugUserSegmentation;
exports.fixSingleUnknownUser = fixSingleUnknownUser;
exports.migrateAllUserSegments = migrateAllUserSegments;
exports.testFunctionWorks = testFunctionWorks;
exports.debugSingleUser = debugSingleUser;
exports.checkNotificationAccess = checkNotificationAccess;
exports.testSegmentationNoNotifications =
  testSegmentationNoNotifications;
exports.checkFirestorePermissions = checkFirestorePermissions;

// Conversion attribution and LTV
const {
  trackOrderAttribution,
  calculateLTV,
} = require('./conversionAttribution');
exports.trackOrderAttribution = trackOrderAttribution;
exports.calculateLTV = calculateLTV;

// A/B test optimizer
const { evaluateABTests } = require('./abTestOptimizer');
exports.evaluateABTests = evaluateABTests;

// Export and reporting
const {
  generateCSVExport,
  scheduleWeeklyReport,
} = require('./exportService');
exports.generateCSVExport = generateCSVExport;
exports.scheduleWeeklyReport = scheduleWeeklyReport;

// Happy Hour auto-create notification job
const {
  checkHappyHourAndCreateJob,
} = require('./checkHappyHourAndCreateJob');
exports.checkHappyHourAndCreateJob = checkHappyHourAndCreateJob;

// Loyalty quarterly reset
const { resetLoyaltyCycles } = require('./resetLoyaltyCycles');
exports.resetLoyaltyCycles = resetLoyaltyCycles;

// Demand forecasting
const { aggregateForecastData } = require('./forecastAggregation');
const { generateDemandForecasts } = require('./demandForecasting');
const { generatePlatformForecast } = require('./platformForecast');
const { detectSlowDemand } = require('./detectSlowDemand');
const { calculatePromoImpact } = require('./calculatePromoImpact');
const { demandHealthAggregator } = require('./demandHealthAggregator');
exports.aggregateForecastData = aggregateForecastData;
exports.generateDemandForecasts = generateDemandForecasts;
exports.generatePlatformForecast = generatePlatformForecast;
exports.detectSlowDemand = detectSlowDemand;
exports.calculatePromoImpact = calculatePromoImpact;
exports.demandHealthAggregator = demandHealthAggregator;

// Driver performance analytics
const driverMetrics = require('./driverMetrics');
exports.processDriverMetrics = driverMetrics.processDriverMetrics;
exports.calculateDriverIncentives = driverMetrics.calculateDriverIncentives;

// Personalized loyalty offers
const personalizedOffers = require('./personalizedOffers');
exports.generatePersonalizedOffers = personalizedOffers.generatePersonalizedOffers;

// Data retention and privacy
const {
  cleanupOldData,
  anonymizeUserData,
} = require('./dataRetention');
exports.cleanupOldData = cleanupOldData;
exports.anonymizeUserData = anonymizeUserData;

// User role management (super admin only)
const {
  updateUserRole,
  batchUpdateUserRoles,
} = require('./userRoleManagement');
exports.updateUserRole = functions
  .region('us-central1')
  .https.onCall(async (data, context) =>
    updateUserRole(data, context, getDb),
  );
exports.batchUpdateUserRoles = functions
  .region('us-central1')
  .https.onCall(async (data, context) =>
    batchUpdateUserRoles(data, context, getDb),
  );

// Optional: Batched home screen data to reduce client Firestore round-trips.
// Implement getHomePageShowCategory, getBanners, getActiveCoupons, getBundleDeals,
// getNearbyRestaurantsFirstPage to match Customer Firestore schema.
exports.getHomeScreenInitialData = functions.https.onCall(async (data, context) => {
  const { userId, lat, lng } = data || {};
  const db = getDb();
  try {
    const [categories, banners, promos, bundles, restaurants] = await Promise.all([
      _getHomePageCategories(db),
      _getBanners(db),
      _getActiveCoupons(db, userId || null),
      _getBundleDeals(db),
      _getNearbyRestaurantsFirstPage(db, lat, lng, 20),
    ]);
    return { categories, banners, promos, bundles, restaurants };
  } catch (err) {
    console.error('[getHomeScreenInitialData] Error:', err);
    throw new functions.https.HttpsError('internal', err.message);
  }
});

async function _getHomePageCategories(db) {
  const snap = await db.collection('vendor_categories').limit(50).get();
  return snap.docs.map(d => ({ id: d.id, ...d.data() }));
}

async function _getBanners(db) {
  const snap = await db.collection('advertisements').limit(20).get();
  return snap.docs.map(d => ({ id: d.id, ...d.data() }));
}

async function _getActiveCoupons(db, userId) {
  const now = admin.firestore.Timestamp.now();
  const snap = await db.collection('coupons')
    .where('expireOfferDate', '>=', now)
    .limit(20)
    .get();
  return snap.docs.map(d => ({ id: d.id, ...d.data() }));
}

async function _getBundleDeals(db) {
  const snap = await db.collection('bundles').limit(20).get();
  return snap.docs.map(d => ({ id: d.id, ...d.data() }));
}

async function _getNearbyRestaurantsFirstPage(db, lat, lng, limit) {
  if (lat == null || lng == null) return [];
  const snap = await db.collection('vendors')
    .where('reststatus', '==', true)
    .limit(limit)
    .get();
  return snap.docs.map(d => ({ id: d.id, ...d.data() }));
}

