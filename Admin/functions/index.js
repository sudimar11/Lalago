const functions = require('firebase-functions');
const admin = require('firebase-admin');

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

      // Read customer token
      const customerSnap = await db.collection('users').doc(customerId).get();
      const customerToken = customerSnap.exists
        ? customerSnap.data()?.fcmToken
        : null;

      if (!customerToken) {
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

      const message = {
        token: customerToken,
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

      const resp = await getMessaging().send(message);
      console.log(
        `[notifyCustomerOnDriverChatMessage] Sent FCM for order ${orderId}: ${resp}`
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
          // Guard: rider-first flow handles dispatch itself.
          if (
            afterData?.dispatchFlow === 'rider_first_v1' ||
            afterData?.dispatch?.flow === 'rider_first_v1' ||
            afterData?.driverID
          ) {
            console.log(
              `[AI AutoDispatcher] Skipping order ${orderId} (rider-first or driver already assigned)`
            );
            return null;
          }

          console.log(`[AI AutoDispatcher] Processing order ${orderId} for automatic rider assignment`);

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

        const order = {
          id: orderId,
          ...afterData,
          restaurantLocation,
          deliveryLocation,
          createdAt: afterData.createdAt || admin.firestore.Timestamp.now(),
        };

        // 2. Find available drivers (using LalaGo-Restaurant field names)
        const driversSnapshot = await getDb().collection('users')
          .where('role', '==', 'driver')
          .where('isActive', '==', true)
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

        // 3. Calculate scores for each driver
        const driverScores = [];
        
        for (const driverDoc of driversSnapshot.docs) {
          const driver = { id: driverDoc.id, ...driverDoc.data() };
          
          // Get driver's current location from various possible fields
          const driverLocation = driver.currentLocation || 
                                 (driver.location ? { 
                                   lat: driver.location.latitude, 
                                   lng: driver.location.longitude 
                                 } : { lat: 0, lng: 0 });
          
          console.log(`[AI AutoDispatcher] Driver ${driver.id} location:`, driverLocation);
          
          // Calculate ETA (simplified: straight-line distance)
          const eta = calculateETA(
            driverLocation,
            order.restaurantLocation
          );

          // Get ML acceptance probability (stubbed for now)
          const mlAcceptanceProbability = await getMLAcceptanceProbability(
            driver,
            order,
            eta
          );

          // Get fairness score (based on completed orders today)
          const fairnessScore = await calculateFairnessScore(driver.id);

          // Calculate composite score
          // Lower is better: weighted sum of normalized metrics
          const compositeScore = calculateCompositeScore({
            eta,
            mlAcceptanceProbability,
            fairnessScore
          });

          driverScores.push({
            driverId: driver.id,
            driverName: `${driver.firstName || ''} ${driver.lastName || ''}`.trim(),
            fcmToken: driver.fcmToken,
            eta,
            mlAcceptanceProbability,
            fairnessScore,
            compositeScore
          });
        }

        // 4. Sort by composite score (lower is better)
        driverScores.sort((a, b) => a.compositeScore - b.compositeScore);

        const bestDriver = driverScores[0];
        
        console.log(`[AI AutoDispatcher] Best rider assigned by AI for order ${orderId}:`, {
          driverId: bestDriver.driverId,
          driverName: bestDriver.driverName,
          eta: bestDriver.eta,
          mlAcceptanceProbability: bestDriver.mlAcceptanceProbability,
          fairnessScore: bestDriver.fairnessScore,
          compositeScore: bestDriver.compositeScore
        });

        // 5. Assign rider to order using AI prescription (LalaGo-Restaurant pattern)
        await change.after.ref.update({
          driverID: bestDriver.driverId,
          driverDistance: bestDriver.distance,
          assignedDriverName: bestDriver.driverName,
          estimatedETA: bestDriver.eta,
          status: 'Driver Assigned',
          assignedAt: admin.firestore.FieldValue.serverTimestamp(),
          dispatchStatus: 'success',
          dispatchMethod: 'AI Auto-Dispatch',
          dispatchMetrics: {
            eta: bestDriver.eta,
            distance: bestDriver.distance,
            mlAcceptanceProbability: bestDriver.mlAcceptanceProbability,
            fairnessScore: bestDriver.fairnessScore,
            compositeScore: bestDriver.compositeScore,
            alternativeDriversCount: driverScores.length - 1
          }
        });

        // 6. Update driver status (following LalaGo-Restaurant pattern)
        await getDb().collection('users').doc(bestDriver.driverId).update({
          isActive: false,
          inProgressOrderID: admin.firestore.FieldValue.arrayUnion(orderId),
          lastAssignedAt: admin.firestore.FieldValue.serverTimestamp()
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

        console.log(`[AI AutoDispatcher] Successfully dispatched order ${orderId} to rider ${bestDriver.driverId} using AI prescription`);
        return { success: true, driverId: bestDriver.driverId };

      } catch (error) {
        console.error(`[AI AutoDispatcher] Error processing order ${orderId}:`, error);
        
        // Update order with error status
        await change.after.ref.update({
          status: 'Order Accepted',  // Keep status as Order Accepted on error
          dispatchStatus: 'error',
          dispatchError: error.message,
          dispatchAttemptedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return { success: false, error: error.message };
      }
    }

    return null;
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

function _activeOrdersCount(driverData) {
  const v = driverData?.inProgressOrderID;
  return Array.isArray(v) ? v.length : 0;
}

function _isDriverEligibleBase(driverData) {
  if (!driverData) return false;
  if (driverData.role !== 'driver') return false;
  if (driverData.isOnline !== true) return false;
  if (driverData.checkedInToday !== true) return false;

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

function _computeIsActiveForDispatch(driverData, activeOrdersCount) {
  if (!_isDriverEligibleBase(driverData)) return false;

  const multipleOrders = driverData?.multipleOrders === true;
  const hasCapacity =
    activeOrdersCount === 0 || (activeOrdersCount === 1 && multipleOrders);
  return hasCapacity;
}

async function _logDispatchEvent({ type, orderId, payload }) {
  try {
    await getDb().collection('dispatch_events').add({
      type,
      orderId,
      payload: payload || {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      source: 'functions',
    });
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
    await getMessaging().send({
      token,
      notification: {
        title: orderData?.scheduleTime ? 'Scheduled Order Placed' : 'New Order',
        body: 'A rider accepted an order. Please confirm within 5 minutes.',
      },
      data: {
        type: 'new_order',
        orderId: String(orderId),
      },
    });
  } catch (e) {
    console.error('[RiderFirst] Failed to notify restaurant:', e);
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

      tx.update(ref, {
        inProgressOrderID: next,
        orderRequestData: admin.firestore.FieldValue.arrayRemove(orderId),
        isActive,
      });
    });
  } catch (e) {
    console.error(
      `[RiderFirst] Failed releasing driver ${driverId} from ${orderId}:`,
      e
    );
  }
}

async function _recomputeDriverIsActive(driverId) {
  if (!driverId) return;
  try {
    const db = getDb();
    const ref = db.collection('users').doc(driverId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const data = snap.data() || {};
    const activeOrdersCount = _activeOrdersCount(data);
    const isActive = _computeIsActiveForDispatch(data, activeOrdersCount);
    await ref.update({ isActive });
  } catch (e) {
    console.error(`[RiderFirst] Failed to recompute isActive for ${driverId}:`, e);
  }
}

async function _pickBestDriverForOrder({
  orderId,
  orderData,
  excludeDriverIds,
}) {
  const db = getDb();
  const exclude = new Set(excludeDriverIds || []);

  const restaurantLocation = _extractRestaurantLocation(orderData);
  const deliveryLocation = _extractDeliveryLocation(orderData);

  const driversSnapshot = await db
    .collection('users')
    .where('role', '==', 'driver')
    .where('isOnline', '==', true)
    .where('checkedInToday', '==', true)
    .get();

  const drivers = [];
  for (const doc of driversSnapshot.docs) {
    const d = { id: doc.id, ...doc.data() };
    if (exclude.has(d.id)) continue;
    if (!_isDriverEligibleBase(d)) continue;

    const driverLocation = _extractDriverLocation(d);
    if (!driverLocation.lat || !driverLocation.lng) continue;

    const activeOrders = _activeOrdersCount(d);
    if (activeOrders >= MAX_ACTIVE_ORDERS_PER_RIDER) continue;

    const distanceToRestaurantMeters = _distanceMeters(
      driverLocation,
      restaurantLocation
    );

    drivers.push({
      driverId: d.id,
      driverData: d,
      driverLocation,
      activeOrders,
      multipleOrders: d.multipleOrders === true,
      distanceToRestaurantMeters,
      deliveryLocation,
    });
  }

  // Tier 1: nearest rider with active_orders == 0
  const free = drivers
    .filter((x) => x.activeOrders === 0)
    .sort((a, b) => a.distanceToRestaurantMeters - b.distanceToRestaurantMeters);
  if (free.length > 0) {
    return {
      selected: free[0],
      candidates: free.slice(0, 10),
      stackDecision: { usedStacking: false },
    };
  }

  // Tier 2: consider stacking (active_orders == 1) only if multipleOrders==true
  const maybeStack = drivers
    .filter((x) => x.activeOrders === 1 && x.multipleOrders)
    .sort((a, b) => a.distanceToRestaurantMeters - b.distanceToRestaurantMeters)
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
  const deadline = _addSeconds(now, RIDER_ACCEPT_TIMEOUT_SECONDS);

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
    const orderId = context.params.orderId;
    const orderData = snap.data() || {};

    try {
      // Only handle normal customer orders (status starts as "Order Placed").
      if (String(orderData.status || '') !== 'Order Placed') {
        return null;
      }

      // Skip future scheduled orders (dispatch at order-time, not creation-time).
      if (orderData.scheduleTime && orderData.scheduleTime.toDate) {
        const when = orderData.scheduleTime.toDate();
        if (when && when.getTime() > Date.now()) {
          return null;
        }
      }

      // Mark rider-first flow and hide from restaurant until rider accepts.
      await snap.ref.update({
        status: 'Awaiting Rider',
        dispatchFlow: RIDER_FIRST_FLOW,
        'dispatch.flow': RIDER_FIRST_FLOW,
        'dispatch.stage': 'created',
        'dispatch.attempt': 0,
        'dispatch.triedDriverIds': [],
        'dispatch.timestamps.createdAt':
          admin.firestore.FieldValue.serverTimestamp(),
      });

      const fresh = await snap.ref.get();
      const freshData = fresh.data() || {};

      await _tryDispatchOrFail({
        orderRef: snap.ref,
        orderId,
        orderData: freshData,
        attempt: 1,
      });
      return null;
    } catch (e) {
      console.error(`[RiderFirst] onCreate error for ${orderId}:`, e);
      return null;
    }
  });

exports.riderFirstDispatchOnUpdate = functions.firestore
  .document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const orderId = context.params.orderId;
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};

    const flow =
      afterData?.dispatchFlow ||
      afterData?.dispatch?.flow ||
      '';
    if (flow !== RIDER_FIRST_FLOW) return null;

    const beforeStatus = String(beforeData.status || '');
    const afterStatus = String(afterData.status || '');

    // Rider accepted: make order visible to restaurant and start 5m timer.
    if (beforeStatus !== 'Driver Accepted' && afterStatus === 'Driver Accepted') {
      const driverId = String(afterData.driverID || '');
      const now = _nowTimestamp();
      const deadline = _addSeconds(now, RESTAURANT_CONFIRM_TIMEOUT_SECONDS);

      await _removeOrderRequestFromDriver(driverId, orderId);
      await _recomputeDriverIsActive(driverId);

      await change.after.ref.update({
        status: 'Order Placed',
        'dispatch.stage': 'rider_accepted',
        'dispatch.restaurantConfirmDeadline': deadline,
        'dispatch.timestamps.riderAcceptedAt':
          admin.firestore.FieldValue.serverTimestamp(),
      });

      await _sendRestaurantNotificationBestEffort(afterData, orderId);
      await _logDispatchEvent({
        type: 'rider_accepted',
        orderId,
        payload: { driverId },
      });
      return null;
    }

    // Rider rejected: try next candidate (up to 3).
    if (beforeStatus !== 'Driver Rejected' && afterStatus === 'Driver Rejected') {
      const attempt = Number(afterData?.dispatch?.attempt || 1) + 1;
      const driverId = String(afterData.driverID || '');

      await _removeOrderRequestFromDriver(driverId, orderId);

      if (attempt > MAX_DISPATCH_ATTEMPTS) {
        await _cancelOrderWithReason({
          orderRef: change.after.ref,
          orderId,
          orderData: afterData,
          reason: 'max_attempts',
        });
        return null;
      }

      await change.after.ref.update({
        status: 'Awaiting Rider',
        'dispatch.stage': 'retrying',
        'dispatch.attempt': attempt - 1,
      });

      const fresh = await change.after.ref.get();
      await _tryDispatchOrFail({
        orderRef: change.after.ref,
        orderId,
        orderData: fresh.data() || {},
        attempt,
      });
      return null;
    }

    // Restaurant rejected: release rider and notify.
    if (beforeStatus !== 'Order Rejected' && afterStatus === 'Order Rejected') {
      const driverId = String(afterData.driverID || '');
      await _releaseDriverFromOrder(driverId, orderId);
      await _logDispatchEvent({
        type: 'restaurant_timeout_or_reject',
        orderId,
        payload: { reason: 'rejected' },
      });
      await _sendCustomerNotificationBestEffort(
        afterData,
        'Restaurant unavailable',
        'The restaurant could not confirm your order. Your rider was released.'
      );
      return null;
    }

    return null;
  });

exports.riderFirstDispatchTimeouts = functions.pubsub
  .schedule('every 1 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = getDb();
    const now = _nowTimestamp();

    // 1) Rider accept timeouts (60s)
    const riderTimeoutSnap = await db
      .collection('restaurant_orders')
      .where('dispatch.flow', '==', RIDER_FIRST_FLOW)
      .where('status', '==', 'Driver Assigned')
      .where('dispatch.riderAcceptDeadline', '<=', now)
      .limit(25)
      .get();

    for (const doc of riderTimeoutSnap.docs) {
      const orderId = doc.id;
      const data = doc.data() || {};
      const driverId = String(data.driverID || '');
      const attempt = Number(data?.dispatch?.attempt || 1) + 1;

      await _removeOrderRequestFromDriver(driverId, orderId);

      if (attempt > MAX_DISPATCH_ATTEMPTS) {
        await _cancelOrderWithReason({
          orderRef: doc.ref,
          orderId,
          orderData: data,
          reason: 'rider_timeout_max_attempts',
        });
        continue;
      }

      await _logDispatchEvent({
        type: 'rider_offer_timeout',
        orderId,
        payload: { driverId, attempt: attempt - 1 },
      });

      await doc.ref.update({
        status: 'Awaiting Rider',
        'dispatch.stage': 'timeout_retrying',
        'dispatch.attempt': attempt - 1,
      });

      const fresh = await doc.ref.get();
      await _tryDispatchOrFail({
        orderRef: doc.ref,
        orderId,
        orderData: fresh.data() || {},
        attempt,
      });
    }

    // 2) Restaurant confirm timeouts (5m)
    const restaurantTimeoutSnap = await db
      .collection('restaurant_orders')
      .where('dispatch.flow', '==', RIDER_FIRST_FLOW)
      .where('status', '==', 'Order Placed')
      .where('dispatch.restaurantConfirmDeadline', '<=', now)
      .limit(25)
      .get();

    for (const doc of restaurantTimeoutSnap.docs) {
      const orderId = doc.id;
      const data = doc.data() || {};
      const driverId = String(data.driverID || '');

      await _releaseDriverFromOrder(driverId, orderId);

      await doc.ref.update({
        status: 'Order Cancelled',
        cancelReason: 'restaurant_timeout',
        cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        'dispatch.stage': 'restaurant_timeout',
      });

      await _logDispatchEvent({
        type: 'restaurant_timeout_or_reject',
        orderId,
        payload: { reason: 'timeout' },
      });

      await _sendCustomerNotificationBestEffort(
        data,
        'Restaurant did not confirm',
        'The restaurant did not confirm in time. Your order was cancelled.'
      );
    }

    return null;
  });

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
 * Get ML acceptance probability from Vertex AI
 * STUBBED FOR NOW - Returns random probability
 * 
 * TODO: Integrate with Vertex AI model to predict driver acceptance
 * @param {Object} driver - Driver data
 * @param {Object} order - Order data
 * @param {number} eta - Calculated ETA
 * @returns {Promise<number>} Acceptance probability (0-1)
 */
async function getMLAcceptanceProbability(driver, order, eta) {
  // STUB: Return a simulated probability
  // In production, this would call Vertex AI with features like:
  // - Driver's historical acceptance rate
  // - Time of day
  // - Distance/ETA
  // - Driver's current location
  // - Order value
  // - Weather conditions
  // etc.
  
  // Simulate higher probability for shorter distances
  const baseProb = 0.7;
  const etaPenalty = Math.min(eta / 60, 0.3); // Max 30% penalty for long ETA
  const simulatedProb = baseProb - etaPenalty + (Math.random() * 0.2 - 0.1);
  
  return Math.max(0.1, Math.min(0.95, simulatedProb));
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

/**
 * Calculate composite score from multiple metrics
 * Lower score is better
 * @param {Object} metrics
 * @returns {number} Composite score
 */
function calculateCompositeScore({ eta, mlAcceptanceProbability, fairnessScore }) {
  // Normalize metrics to 0-100 scale
  const normalizedETA = Math.min(eta / 60 * 100, 100); // Normalize to 0-100 (60 min = 100)
  const normalizedML = (1 - mlAcceptanceProbability) * 100; // Invert so lower is better
  const normalizedFairness = fairnessScore; // Already 0-100
  
  // Weighted sum (weights should total 1.0)
  const weights = {
    eta: 0.5,          // 50% weight on proximity/speed
    ml: 0.3,           // 30% weight on acceptance probability
    fairness: 0.2      // 20% weight on fairness
  };
  
  const compositeScore = 
    (normalizedETA * weights.eta) +
    (normalizedML * weights.ml) +
    (normalizedFairness * weights.fairness);
  
  return compositeScore;
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
 * Background notification job processor (no HTTP, no web timeouts).
 *
 * Admin app creates a Firestore document in `notification_jobs/{jobId}`:
 * {
 *   kind: 'broadcast' | 'happy_hour',
 *   payload: { title, body, type?, imageUrl?, deepLink?, targetScreen? },
 *   createdAt: serverTimestamp(),
 *   status: 'queued'
 * }
 *
 * This trigger sends notifications in batches and updates progress fields:
 * sentCount, errorCount, processedCount, totalUsers, status.
 */
exports.processNotificationJob = functions
  .region('us-central1')
  .runWith({ timeoutSeconds: 540, memory: '256MB' })
  .firestore.document('notification_jobs/{jobId}')
  .onCreate(async (snap, context) => {
    const jobId = context.params.jobId;
    const job = snap.data() || {};
    const kind = String(job.kind || '').trim();
    const payload = job.payload && typeof job.payload === 'object' ? job.payload : {};
    // #region agent log
    fetch('http://127.0.0.1:7242/ingest/4503ab82-cc6d-4a10-828e-d233928c2cbf', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ location: 'functions/processNotificationJob:onCreate', message: 'triggered', data: { jobId, kind }, hypothesisId: 'H3', timestamp: Date.now() }) }).catch(() => {});
    // #endregion

    const jobRef = snap.ref;
    const now = admin.firestore.FieldValue.serverTimestamp();

    if (kind !== 'broadcast' && kind !== 'happy_hour') {
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
      // Fetch all active customers with FCM tokens
      const usersSnapshot = await getDb()
        .collection('users')
        .where('role', '==', 'customer')
        .where('active', '==', true)
        .get();

      const fcmTokens = [];
      for (const userDoc of usersSnapshot.docs) {
        const userData = userDoc.data();
        const fcmToken = userData.fcmToken;
        if (fcmToken && typeof fcmToken === 'string' && fcmToken.trim().length > 0) {
          fcmTokens.push(fcmToken.trim());
        }
      }

      const totalUsers = fcmTokens.length;
      await jobRef.set({ totalUsers: totalUsers, updatedAt: now }, { merge: true });
      // #region agent log
      fetch('http://127.0.0.1:7242/ingest/4503ab82-cc6d-4a10-828e-d233928c2cbf', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ location: 'functions/processNotificationJob:after_users', message: 'fcm_tokens', data: { totalUsers, userDocs: usersSnapshot.size }, hypothesisId: 'H3', timestamp: Date.now() }) }).catch(() => {});
      // #endregion

      if (totalUsers === 0) {
        await jobRef.set(
          {
            status: 'completed',
            completedAt: now,
            updatedAt: now,
          },
          { merge: true }
        );
        return;
      }

      const BATCH_SIZE = 500;
      let sentCount = 0;
      let errorCount = 0;
      let processedCount = 0;
      const firstErrors = [];

      for (let i = 0; i < fcmTokens.length; i += BATCH_SIZE) {
        const batch = fcmTokens.slice(i, i + BATCH_SIZE);
        const batchNumber = Math.floor(i / BATCH_SIZE) + 1;

        const message = {
          notification: { title: title, body: body },
          data: {
            type: type,
            timestamp: Date.now().toString(),
          },
          tokens: batch,
        };

        if (payload.imageUrl && String(payload.imageUrl).trim().length > 0) {
          message.notification.imageUrl = String(payload.imageUrl).trim();
        }
        if (payload.deepLink && String(payload.deepLink).trim().length > 0) {
          message.data.deepLink = String(payload.deepLink).trim();
        }
        if (payload.targetScreen && String(payload.targetScreen).trim().length > 0) {
          message.data.targetScreen = String(payload.targetScreen).trim();
        }

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
        } catch (batchError) {
          errorCount += batch.length;
          processedCount += batch.length;
          if (firstErrors.length < 10) {
            firstErrors.push({
              batch: batchNumber,
              errorCode: batchError.code || 'BATCH_SEND_ERROR',
              error: batchError.message || 'Batch send failed',
            });
          }
        }

        await jobRef.set(
          {
            sentCount: sentCount,
            errorCount: errorCount,
            processedCount: processedCount,
            errors: firstErrors,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }

      await jobRef.set(
        {
          status: 'completed',
          completedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (error) {
      console.error(`[processNotificationJob] Fatal error jobId=${jobId}`, error);
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

    // Create message object
    const message = {
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: {
        timestamp: Date.now().toString(),
      },
      android: {
        priority: 'high',
        notification: {
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

    // Add custom data if provided
    if (data && typeof data === 'object') {
      Object.keys(data).forEach(key => {
        // FCM data must be strings
        message.data[key] = String(data[key]);
      });
    }

    // Add image URL if provided
    if (imageUrl && typeof imageUrl === 'string' && imageUrl.trim().length > 0) {
      message.notification.imageUrl = imageUrl.trim();
    }

    // Add deep link if provided
    if (deepLink && typeof deepLink === 'string' && deepLink.trim().length > 0) {
      message.data.deepLink = deepLink.trim();
    }

    // Send notification
    const response = await getMessaging().send(message);

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

