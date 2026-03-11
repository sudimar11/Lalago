const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

/**
 * Calculate distance between two coordinates using Haversine formula
 * Returns distance in meters
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth's radius in meters
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRadians(degrees) {
  return degrees * (Math.PI / 180);
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

/**
 * Group orders by restaurant location proximity (500m radius)
 */
function groupByProximity(orders) {
  const groups = [];
  const processed = new Set();

  for (let i = 0; i < orders.length; i++) {
    if (processed.has(i)) continue;

    const order = orders[i];
    const orderData = order.data();
    const vendor = orderData.vendor;

    if (!vendor || !vendor.latitude || !vendor.longitude) {
      continue;
    }

    const lat = typeof vendor.latitude === 'number' 
      ? vendor.latitude 
      : parseFloat(vendor.latitude) || 0;
    const lng = typeof vendor.longitude === 'number' 
      ? vendor.longitude 
      : parseFloat(vendor.longitude) || 0;

    if (lat === 0 || lng === 0) continue;

    const group = {
      centerLat: lat,
      centerLng: lng,
      orders: [order],
      restaurantNames: new Set([vendor.title || vendor.id || 'Unknown']),
      timestamps: [orderData.createdAt],
    };

    processed.add(i);

    // Find nearby restaurants (within 500m)
    for (let j = i + 1; j < orders.length; j++) {
      if (processed.has(j)) continue;

      const otherOrder = orders[j];
      const otherData = otherOrder.data();
      const otherVendor = otherData.vendor;

      if (!otherVendor || !otherVendor.latitude || !otherVendor.longitude) {
        continue;
      }

      const otherLat = typeof otherVendor.latitude === 'number'
        ? otherVendor.latitude
        : parseFloat(otherVendor.latitude) || 0;
      const otherLng = typeof otherVendor.longitude === 'number'
        ? otherVendor.longitude
        : parseFloat(otherVendor.longitude) || 0;

      if (otherLat === 0 || otherLng === 0) continue;

      const distance = calculateDistance(lat, lng, otherLat, otherLng);

      if (distance <= 500) {
        // Within 500m, add to group
        group.orders.push(otherOrder);
        group.restaurantNames.add(
          otherVendor.title || otherVendor.id || 'Unknown'
        );
        group.timestamps.push(otherData.createdAt);
        processed.add(j);

        // Update center to average of all locations in group
        group.centerLat =
          (group.centerLat * (group.orders.length - 1) + otherLat) /
          group.orders.length;
        group.centerLng =
          (group.centerLng * (group.orders.length - 1) + otherLng) /
          group.orders.length;
      }
    }

    groups.push(group);
  }

  return groups;
}

/**
 * Determine time slot based on order timestamps
 */
function determineTimeSlot(timestamps) {
  if (!timestamps || timestamps.length === 0) return 'all';

  let lunchCount = 0;
  let dinnerCount = 0;
  let totalCount = 0;

  timestamps.forEach((ts) => {
    if (!ts) return;

    let date;
    if (ts.toDate) {
      date = ts.toDate();
    } else if (ts._seconds) {
      date = new Date(ts._seconds * 1000);
    } else if (ts instanceof Date) {
      date = ts;
    } else {
      return;
    }

    const hour = date.getHours();
    totalCount++;

    if (hour >= 11 && hour < 15) {
      lunchCount++;
    } else if (hour >= 17 && hour < 22) {
      dinnerCount++;
    }
  });

  if (totalCount === 0) return 'all';

  const lunchRatio = lunchCount / totalCount;
  const dinnerRatio = dinnerCount / totalCount;

  if (lunchRatio >= 0.6) {
    return 'lunch';
  } else if (dinnerRatio >= 0.6) {
    return 'dinner';
  } else {
    return 'all';
  }
}

/**
 * Calculate weight based on order count
 */
function calculateWeight(orderCount) {
  if (orderCount >= 31) return 5;
  if (orderCount >= 21) return 4;
  if (orderCount >= 11) return 3;
  if (orderCount >= 6) return 2;
  return 1;
}

/**
 * Calculate heat zones from location groups
 */
function calculateHeatZones(locationGroups) {
  const heatZones = [];

  locationGroups.forEach((group) => {
    const orderCount = group.orders.length;
    const weight = calculateWeight(orderCount);
    const timeSlot = determineTimeSlot(group.timestamps);
    const restaurantName =
      group.restaurantNames.size === 1
        ? Array.from(group.restaurantNames)[0]
        : `${Array.from(group.restaurantNames)[0]} (+${group.restaurantNames.size - 1})`;

    heatZones.push({
      lat: group.centerLat,
      lng: group.centerLng,
      weight: weight,
      timeSlot: timeSlot,
      orderCount: orderCount,
      restaurantName: restaurantName,
    });
  });

  return heatZones;
}

/**
 * Write heat zones to Firestore with batch operation
 */
async function writeHeatZones(heatZones) {
  const db = admin.firestore();
  const batch = db.batch();
  const collectionRef = db.collection('driver_heat_zones');

  // Delete all existing heat zones first
  const existingZones = await collectionRef.get();
  existingZones.forEach((doc) => {
    batch.delete(doc.ref);
  });

  // Add new heat zones
  heatZones.forEach((zone) => {
    const docRef = collectionRef.doc();
    batch.set(docRef, {
      lat: zone.lat,
      lng: zone.lng,
      weight: zone.weight,
      timeSlot: zone.timeSlot,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
      orderCount: zone.orderCount,
      restaurantName: zone.restaurantName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
}

/**
 * Main Cloud Function: Generate Heat Zones
 * HTTP trigger - call manually via POST request
 */
exports.generateHeatZones = functions.https.onRequest(async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  try {
    const db = admin.firestore();

    // 1. Calculate date range (last 30 days)
    const now = new Date();
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const timestamp = admin.firestore.Timestamp.fromDate(thirtyDaysAgo);

    console.log(
      `Querying orders from ${thirtyDaysAgo.toISOString()} to ${now.toISOString()}`
    );

    // 2. Query completed orders from last 30 days
    const ordersSnapshot = await db
      .collection('restaurant_orders')
      .where('status', '==', 'Order Completed')
      .where('createdAt', '>=', timestamp)
      .get();

    console.log(`Found ${ordersSnapshot.size} completed orders`);

    if (ordersSnapshot.size === 0) {
      return res.json({
        success: true,
        zonesCreated: 0,
        ordersProcessed: 0,
        message: 'No completed orders found in the last 30 days',
        dateRange: {
          from: thirtyDaysAgo.toISOString().split('T')[0],
          to: now.toISOString().split('T')[0],
        },
      });
    }

    // 3. Extract and group locations
    const locationGroups = groupByProximity(ordersSnapshot.docs);
    console.log(`Grouped into ${locationGroups.length} location groups`);

    // 4. Calculate weights and time slots
    const heatZones = calculateHeatZones(locationGroups);
    console.log(`Calculated ${heatZones.length} heat zones`);

    // 5. Write to Firestore (batch operation)
    await writeHeatZones(heatZones);
    console.log('Heat zones written to Firestore');

    // 6. Calculate breakdown by time slot
    const breakdown = {
      lunch: heatZones.filter((z) => z.timeSlot === 'lunch').length,
      dinner: heatZones.filter((z) => z.timeSlot === 'dinner').length,
      all: heatZones.filter((z) => z.timeSlot === 'all').length,
    };

    // 7. Return summary
    res.json({
      success: true,
      zonesCreated: heatZones.length,
      ordersProcessed: ordersSnapshot.size,
      dateRange: {
        from: thirtyDaysAgo.toISOString().split('T')[0],
        to: now.toISOString().split('T')[0],
      },
      breakdown: breakdown,
      weightDistribution: {
        weight1: heatZones.filter((z) => z.weight === 1).length,
        weight2: heatZones.filter((z) => z.weight === 2).length,
        weight3: heatZones.filter((z) => z.weight === 3).length,
        weight4: heatZones.filter((z) => z.weight === 4).length,
        weight5: heatZones.filter((z) => z.weight === 5).length,
      },
    });
  } catch (error) {
    console.error('Error generating heat zones:', error);
    res.status(500).json({
      success: false,
      error: error.message,
      stack: error.stack,
    });
  }
});

/**
 * HTTP Function: Send Individual FCM Notification
 * POST JSON: { title: string, body: string, token: string, data?: object }
 */
exports.sendIndividualNotification = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    // Enable CORS
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      return res.status(405).json({
        success: false,
        error: 'Method not allowed. Use POST.',
      });
    }

    try {
      const { title, body, token, data } = req.body;

      // Validate required fields
      if (!title || !body || !token) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: title, body, and token are required',
        });
      }

      // Build FCM message
      const message = {
        notification: {
          title: title,
          body: body,
        },
        token: token,
      };

      // Add data payload if provided
      if (data && typeof data === 'object') {
        message.data = {};
        // Convert all data values to strings (FCM requirement)
        for (const [key, value] of Object.entries(data)) {
          message.data[key] = String(value);
        }
      }

      // Send FCM notification
      const response = await admin.messaging().send(message);

      console.log(
        `[sendIndividualNotification] Successfully sent notification. MessageId: ${response.substring(0, 20)}...`
      );

      return res.json({
        success: true,
        messageId: response,
      });
    } catch (error) {
      console.error('[sendIndividualNotification] Error:', error);
      return res.status(500).json({
        success: false,
        error: error.message || 'Failed to send notification',
      });
    }
  });

/**
 * Firestore Trigger: Notify customer when driver accepts order
 * Triggered on restaurant_orders/{orderId} updates
 */
exports.notifyCustomerOnDriverAssigned = functions
  .region('us-central1')
  .firestore.document('restaurant_orders/{orderId}')
  .onUpdate(async (change, context) => {
    const before = change.before;
    const after = change.after;
    const orderId = context.params.orderId;

    const beforeData = before.data();
    const afterData = after.data();

    // Check if driver was just assigned
    const beforeDriverId =
      beforeData.driverID || beforeData.driverId || null;
    const afterDriverId = afterData.driverID || afterData.driverId || null;

    // Exit if driver was already assigned or if no driver assigned now
    if (beforeDriverId || !afterDriverId) {
      return null;
    }

    // Check idempotency: only send if not already sent
    const lifecycleNotifs = afterData.customerLifecycleNotifs || {};
    if (lifecycleNotifs.driverAcceptedAt) {
      console.log(
        `[notifyCustomerOnDriverAssigned] Order ${orderId}: Notification already sent`
      );
      return null;
    }

    try {
      const db = admin.firestore();

      // Get customer ID and FCM tokens
      const customerId = afterData.authorID || afterData.authorId ||
        (afterData.author && (afterData.author.id || afterData.author.customerID)) || null;

      if (!customerId) {
        console.log(
          `[notifyCustomerOnDriverAssigned] Order ${orderId}: No customer ID`
        );
        return null;
      }

      const customerTokens = await _getUserFcmTokens(db, customerId);

      if (customerTokens.length === 0) {
        console.log(
          `[notifyCustomerOnDriverAssigned] Order ${orderId}: No FCM token found for customer`
        );
        return null;
      }

      // Send notification to all devices
      const messagePayload = {
        notification: {
          title: 'Driver Accepted',
          body: 'Driver accepted your order',
        },
        data: {
          type: 'order_update',
          orderId: orderId,
          status: afterData.status || 'Driver Accepted',
        },
      };
      const multicastMessage = { ...messagePayload, tokens: customerTokens };
      const resp = await admin.messaging().sendEachForMulticast(multicastMessage);
      console.log(
        `[notifyCustomerOnDriverAssigned] Order ${orderId}: Notification sent ${resp.successCount}/${customerTokens.length}`
      );

      // Write idempotency marker
      await after.ref.update({
        'customerLifecycleNotifs.driverAcceptedAt':
          admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(
        `[notifyCustomerOnDriverAssigned] Order ${orderId}: Idempotency marker written`
      );

      return null;
    } catch (error) {
      console.error(
        `[notifyCustomerOnDriverAssigned] Order ${orderId}: Error:`,
        error
      );
      return null;
    }
  });

/**
 * Firestore Trigger: Process driver location updates for lifecycle notifications
 * Triggered on users/{driverId} updates when location changes
 */
exports.processDriverLocationLifecycle = functions
  .region('us-central1')
  .firestore.document('users/{driverId}')
  .onUpdate(async (change, context) => {
    const before = change.before;
    const after = change.after;
    const driverId = context.params.driverId;

    const beforeData = before.data();
    const afterData = after.data();

    // Check if location actually changed
    const beforeLocation = beforeData.location || {};
    const afterLocation = afterData.location || {};

    const beforeLat = beforeLocation.latitude;
    const beforeLng = beforeLocation.longitude;
    const afterLat = afterLocation.latitude;
    const afterLng = afterLocation.longitude;

    // Exit early if location didn't change meaningfully
    if (
      beforeLat === afterLat &&
      beforeLng === afterLng &&
      beforeLat !== undefined &&
      beforeLng !== undefined
    ) {
      return null;
    }

    // Exit if no location data
    if (!afterLat || !afterLng) {
      return null;
    }

    // Check if driver has active orders
    const inProgressOrderIds = afterData.inProgressOrderID || [];
    if (!Array.isArray(inProgressOrderIds) || inProgressOrderIds.length === 0) {
      return null;
    }

    // Limit processing to max 3 orders
    const ordersToProcess = inProgressOrderIds.slice(0, 3);

    try {
      const db = admin.firestore();
      const batch = db.batch();

      for (const orderId of ordersToProcess) {
        if (!orderId) continue;

        try {
          const orderDoc = await db
            .collection('restaurant_orders')
            .doc(String(orderId))
            .get();

          if (!orderDoc.exists) {
            console.log(
              `[processDriverLocationLifecycle] Driver ${driverId}: Order ${orderId} not found`
            );
            continue;
          }

          const orderData = orderDoc.data();
          const orderRef = orderDoc.ref;

          // Verify driver matches
          const orderDriverId = orderData.driverID || orderData.driverId;
          if (orderDriverId !== driverId) {
            console.log(
              `[processDriverLocationLifecycle] Driver ${driverId}: Order ${orderId} assigned to different driver`
            );
            continue;
          }

          const orderStatus = orderData.status || '';
          const lifecycleNotifs = orderData.customerLifecycleNotifs || {};

          // Get driver acceptance location
          const driverAcceptLocation = orderData.driverLocation || {};
          const acceptLat = driverAcceptLocation.latitude;
          const acceptLng = driverAcceptLocation.longitude;

          // Get restaurant location
          const vendor = orderData.vendor || {};
          const restaurantLat = vendor.latitude;
          const restaurantLng = vendor.longitude;

          if (!restaurantLat || !restaurantLng) {
            console.log(
              `[processDriverLocationLifecycle] Driver ${driverId}: Order ${orderId} missing restaurant location`
            );
            continue;
          }

          // Calculate distances
          const distanceFromAccept = acceptLat && acceptLng
            ? calculateDistance(afterLat, afterLng, acceptLat, acceptLng)
            : Infinity;
          const distanceToRestaurant = calculateDistance(
            afterLat,
            afterLng,
            restaurantLat,
            restaurantLng
          );

          // Get customer info and tokens
          const author = orderData.author || {};
          const customerId = orderData.authorID || orderData.authorId ||
            author.id || author.customerID || null;
          const customerTokens = customerId
            ? await _getUserFcmTokens(db, customerId)
            : [];

          // A) "Driver is on the way to the restaurant"
          if (
            ['Driver Accepted', 'Order Shipped'].includes(
              orderStatus
            ) &&
            distanceFromAccept > 100 &&
            !lifecycleNotifs.onWayToRestaurantAt
          ) {
            if (customerTokens.length > 0) {
              try {
                const messagePayload = {
                  notification: {
                    title: 'Driver On The Way',
                    body: 'Driver is on the way to the restaurant',
                  },
                  data: {
                    type: 'order_update',
                    orderId: String(orderId),
                    status: orderStatus,
                  },
                };
                const multicastMessage = { ...messagePayload, tokens: customerTokens };
                await admin.messaging().sendEachForMulticast(multicastMessage);
                batch.update(orderRef, {
                  'customerLifecycleNotifs.onWayToRestaurantAt':
                    admin.firestore.FieldValue.serverTimestamp(),
                });

                console.log(
                  `[processDriverLocationLifecycle] Driver ${driverId}: Order ${orderId} - Sent "on way to restaurant" notification`
                );
              } catch (fcmError) {
                console.error(
                  `[processDriverLocationLifecycle] Error sending FCM for order ${orderId}:`,
                  fcmError
                );
              }
            }
          }

          // B) "Driver is at the restaurant"
          if (
            distanceToRestaurant <= 50 &&
            !lifecycleNotifs.arrivedRestaurantAt
          ) {
            if (customerTokens.length > 0) {
              try {
                const messagePayload = {
                  notification: {
                    title: 'Driver At Restaurant',
                    body: 'Driver is at the restaurant',
                  },
                  data: {
                    type: 'order_update',
                    orderId: String(orderId),
                    status: orderStatus,
                  },
                };
                const multicastMessage = { ...messagePayload, tokens: customerTokens };
                await admin.messaging().sendEachForMulticast(multicastMessage);
                batch.update(orderRef, {
                  'customerLifecycleNotifs.arrivedRestaurantAt':
                    admin.firestore.FieldValue.serverTimestamp(),
                });

                console.log(
                  `[processDriverLocationLifecycle] Driver ${driverId}: Order ${orderId} - Sent "arrived at restaurant" notification`
                );
              } catch (fcmError) {
                console.error(
                  `[processDriverLocationLifecycle] Error sending FCM for order ${orderId}:`,
                  fcmError
                );
              }
            }
          }

          // C) "Driver left the restaurant and is on the way"
          if (
            lifecycleNotifs.arrivedRestaurantAt &&
            distanceToRestaurant >= 80 &&
            !lifecycleNotifs.leftRestaurantAt
          ) {
            if (customerTokens.length > 0) {
              try {
                const messagePayload = {
                  notification: {
                    title: 'Driver On The Way',
                    body: 'Driver left the restaurant and is on the way',
                  },
                  data: {
                    type: 'order_update',
                    orderId: String(orderId),
                    status: 'In Transit',
                  },
                };
                const multicastMessage = { ...messagePayload, tokens: customerTokens };
                await admin.messaging().sendEachForMulticast(multicastMessage);

                // Update status to "In Transit" if not already; set pickedUpAt for pipeline metrics
                const updates = {
                  'customerLifecycleNotifs.leftRestaurantAt':
                    admin.firestore.FieldValue.serverTimestamp(),
                  pickedUpAt: admin.firestore.FieldValue.serverTimestamp(),
                };
                if (orderStatus !== 'In Transit') {
                  updates.status = 'In Transit';
                }

                batch.update(orderRef, updates);

                console.log(
                  `[processDriverLocationLifecycle] Driver ${driverId}: Order ${orderId} - Sent "left restaurant" notification and updated status`
                );
              } catch (fcmError) {
                console.error(
                  `[processDriverLocationLifecycle] Error sending FCM for order ${orderId}:`,
                  fcmError
                );
              }
            }
          }
        } catch (orderError) {
          console.error(
            `[processDriverLocationLifecycle] Error processing order ${orderId}:`,
            orderError
          );
          continue;
        }
      }

      // Commit all batch updates
      if (batch._writes.length > 0) {
        await batch.commit();
        console.log(
          `[processDriverLocationLifecycle] Driver ${driverId}: Committed ${batch._writes.length} updates`
        );
      }

      return null;
    } catch (error) {
      console.error(
        `[processDriverLocationLifecycle] Driver ${driverId}: Error:`,
        error
      );
      return null;
    }
  });

/**
 * HTTPS Callable: Check zone capacity for a rider before check-in.
 * Accepts { zoneId: string }
 * Returns { allowed, currentCount, maxRiders, utilizationPercentage }
 */
exports.checkZoneCapacity = functions
  .region('us-central1')
  .https.onCall(async (data, context) => {
    const zoneId = data.zoneId;
    if (!zoneId || typeof zoneId !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'zoneId is required and must be a string',
      );
    }

    const db = admin.firestore();
    const zoneDoc = await db
      .collection('service_areas')
      .doc(zoneId)
      .get();

    if (!zoneDoc.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        `Zone ${zoneId} not found`,
      );
    }

    const zoneData = zoneDoc.data();
    const maxRiders = zoneData.maxRiders;
    const assignedDriverIds = zoneData.assignedDriverIds || [];

    if (
      maxRiders === null ||
      maxRiders === undefined ||
      assignedDriverIds.length === 0
    ) {
      return {
        allowed: true,
        currentCount: 0,
        maxRiders: maxRiders || null,
        utilizationPercentage: 0,
      };
    }

    const fiveMinAgo = new Date(Date.now() - 5 * 60 * 1000);
    const driversSnap = await db
      .collection('users')
      .where('role', '==', 'driver')
      .get();

    let activeCount = 0;
    for (const dDoc of driversSnap.docs) {
      if (!assignedDriverIds.includes(dDoc.id)) continue;
      const d = dDoc.data();
      const isV2 = Number(d.statusSchemaVersion || 0) === 2;
      if (isV2) {
        if (d.isOnline !== true) continue;
        const avail = String(d.riderAvailability || 'offline');
        if (avail !== 'available' &&
            avail !== 'on_delivery' &&
            avail !== 'on_break') {
          continue;
        }
      } else if (d.checkedOutToday === true) {
        continue;
      }
      const locTs = d.locationUpdatedAt;
      if (locTs && locTs.toDate() > fiveMinAgo) {
        activeCount++;
      }
    }

    const utilizationPercentage =
      maxRiders > 0
        ? Math.min((activeCount / maxRiders) * 100, 100)
        : 0;

    return {
      allowed: activeCount < maxRiders,
      currentCount: activeCount,
      maxRiders: maxRiders,
      utilizationPercentage: utilizationPercentage,
    };
  });

/**
 * Monitor rider inactivity and auto-logout riders who have been inactive
 * for longer than the configured threshold. Runs every 2 minutes.
 */
exports.monitorRiderInactivity = functions.pubsub
  .schedule('every 2 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    // Deprecated: canonical status writer moved to Admin/functions.
    // Keep this scheduled function as a no-op during rollout to avoid
    // duplicate status mutations from multiple codebases.
    console.log('[monitorRiderInactivity] no-op (moved to Admin/functions)');
    return null;
  });

/**
 * Scheduled cleanup: check each order in every rider's
 * inProgressOrderID array and remove entries whose actual
 * status is completed, cancelled, rejected, or missing.
 * Runs every 60 minutes.
 */
exports.cleanupStuckOrders = functions.pubsub
  .schedule('every 60 minutes')
  .timeZone('Asia/Manila')
  .onRun(async (context) => {
    const db = admin.firestore();
    const ridersSnap = await db
      .collection('users')
      .where('role', '==', 'driver')
      .get();

    const doneStatuses = [
      'Order Completed',
      'Order Cancelled',
      'Order Rejected',
      'Driver Rejected',
    ];

    let totalCleaned = 0;

    for (const rider of ridersSnap.docs) {
      const data = rider.data();
      const orders = data.inProgressOrderID || [];
      if (orders.length === 0) continue;

      const toRemove = [];

      for (const orderId of orders) {
        const orderDoc = await db
          .collection('restaurant_orders')
          .doc(orderId)
          .get();

        if (!orderDoc.exists) {
          toRemove.push(orderId);
          continue;
        }

        const status = orderDoc.data().status || '';
        if (doneStatuses.includes(status)) {
          toRemove.push(orderId);
        }
      }

      if (toRemove.length > 0) {
        await rider.ref.update({
          inProgressOrderID:
            admin.firestore.FieldValue.arrayRemove(toRemove),
        });
        totalCleaned += toRemove.length;
        console.log(
          `[CLEANUP] Rider ${rider.id}: removed ` +
          `${toRemove.length} stuck orders ` +
          `(${toRemove.join(', ')})`
        );
      }
    }

    if (totalCleaned > 0) {
      console.log(
        `[CLEANUP] Done – removed ${totalCleaned} ` +
        `stuck order(s) total`
      );
    } else {
      console.log('[CLEANUP] Done – no stuck orders');
    }

    return null;
  });

/**
 * Resolve recipient tokens for rider/restaurant communication notifications.
 */
async function _resolveCommunicationRecipients(db, orderId, senderType) {
  const orderDoc = await db.collection('restaurant_orders').doc(orderId).get();
  if (!orderDoc.exists) {
    return { tokens: [], recipientRole: null, recipientId: null };
  }
  const orderData = orderDoc.data() || {};
  const riderId = orderData.driverID || orderData.driverId || null;
  const vendorId = orderData.vendorID || (orderData.vendor || {}).id || null;

  let recipientRole = null;
  let recipientId = null;
  if (senderType === 'rider') {
    recipientRole = 'restaurant';
    recipientId = vendorId;
  } else if (senderType === 'restaurant') {
    recipientRole = 'rider';
    recipientId = riderId;
  }
  if (!recipientId) {
    return { tokens: [], recipientRole, recipientId };
  }
  const tokens = await _getUserFcmTokens(db, recipientId);
  return { tokens, recipientRole, recipientId };
}

/**
 * Legacy bridge: notify receiver when order_messages are written.
 */
exports.notifyOnOrderMessageWrite = functions
  .region('us-central1')
  .firestore.document('order_messages/{orderId}/messages/{messageId}')
  .onWrite(async (change, context) => {
    console.log(
      '[notifyOnOrderMessageWrite] disabled; Admin/functions handles legacy order_messages notifications'
    );
    return null;
    if (!change.after.exists) return null;
    const data = change.after.data() || {};
    const senderType = String(data.senderType || '');
    const messageText = String(data.messageText || data.text || 'New message');
    const orderId = context.params.orderId;
    const db = admin.firestore();

    const { tokens, recipientRole, recipientId } =
      await _resolveCommunicationRecipients(db, orderId, senderType);
    if (!tokens.length || !recipientRole || !recipientId) return null;

    const title =
      senderType === 'rider'
        ? `Driver update #${orderId.slice(0, 6)}`
        : `Restaurant update #${orderId.slice(0, 6)}`;

    const payload = {
      notification: {
        title,
        body: messageText,
      },
      data: {
        type: 'order_communication',
        orderId: String(orderId),
        target: 'communicationPanel',
        senderRole: senderType,
        recipientRole,
        messageId: context.params.messageId,
      },
      android: {
        priority: 'high',
      },
      apns: {
        headers: { 'apns-priority': '10' },
      },
      tokens,
    };

    const resp = await admin.messaging().sendEachForMulticast(payload);
    console.log(
      `[notifyOnOrderMessageWrite] order=${orderId} success=${resp.successCount}/${tokens.length}`
    );
    return null;
  });

/**
 * Canonical notifications for order_communications messages.
 */
exports.notifyOnOrderCommunicationMessage = functions
  .region('us-central1')
  .firestore.document('order_communications/{orderId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const orderId = context.params.orderId;
    const text = String(data.text || data.messageText || 'New message');
    const senderRole = String(data.senderRole || '');
    const receiverId = String(data.receiverId || '');

    if (!receiverId || !senderRole) return null;

    const db = admin.firestore();
    const tokens = await _getUserFcmTokens(db, receiverId);
    if (!tokens.length) return null;

    const title =
      senderRole === 'rider'
        ? `Driver message #${orderId.slice(0, 6)}`
        : `Restaurant message #${orderId.slice(0, 6)}`;
    const payload = {
      notification: { title, body: text },
      data: {
        type: 'order_communication',
        orderId: String(orderId),
        target: 'communicationThread',
        messageId: context.params.messageId,
        senderRole,
      },
      android: { priority: 'high' },
      apns: { headers: { 'apns-priority': '10' } },
      tokens,
    };
    const resp = await admin.messaging().sendEachForMulticast(payload);
    console.log(
      `[notifyOnOrderCommunicationMessage] order=${orderId} success=${resp.successCount}/${tokens.length}`
    );
    return null;
  });

/**
 * Keep isRead in sync when readBy/readAt/status is changed.
 */
exports.syncMessageReadState = functions
  .region('us-central1')
  .firestore.document('order_communications/{orderId}/messages/{messageId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};
    const beforeReadByCount = Object.keys(beforeData.readBy || {}).length;
    const afterReadByCount = Object.keys(afterData.readBy || {}).length;
    const statusChanged = (beforeData.status || '') !== (afterData.status || '');
    const readByChanged = beforeReadByCount !== afterReadByCount;

    if (!statusChanged && !readByChanged) return null;

    const shouldRead =
      afterData.status === 'read' ||
      afterReadByCount > 0 ||
      afterData.readAt != null;
    if (afterData.isRead === shouldRead) return null;

    await change.after.ref.set(
      {
        isRead: shouldRead,
        status: shouldRead ? 'read' : afterData.status || 'sent',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return null;
  });

/**
 * Validate issue state transitions in canonical issue flow.
 */
exports.validateIssueStateTransition = functions
  .region('us-central1')
  .firestore.document('order_communications/{orderId}/issues/{issueId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data() || {};
    const afterData = change.after.data() || {};
    const from = String(beforeData.state || '');
    const to = String(afterData.state || '');
    if (!from || !to || from === to) return null;

    const allowed = {
      opened: ['acknowledged', 'escalated', 'closed'],
      acknowledged: ['resolved', 'escalated', 'closed'],
      resolved: ['confirmed', 'opened', 'escalated', 'closed'],
      confirmed: ['closed'],
      escalated: ['resolved', 'closed'],
      closed: [],
    };
    const isAllowed = (allowed[from] || []).includes(to);
    if (!isAllowed) {
      await change.after.ref.set(
        {
          state: from,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      throw new Error(`Invalid issue state transition: ${from} -> ${to}`);
    }

    await change.after.ref.collection('transitions').add({
      from,
      to,
      actorRole: afterData.lastActorRole || 'system',
      actorId: afterData.lastActorId || '',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const orderId = context.params.orderId;
    const db = admin.firestore();
    const riderId = String(afterData.riderId || '');
    const restaurantId = String(afterData.restaurantId || '');

    const targetUser = to === 'resolved' || to === 'acknowledged'
      ? riderId
      : restaurantId;
    if (targetUser) {
      const tokens = await _getUserFcmTokens(db, targetUser);
      if (tokens.length) {
        await admin.messaging().sendEachForMulticast({
          notification: {
            title: `Issue ${to}`,
            body: `Order #${orderId.slice(0, 6)} issue is now ${to}`,
          },
          data: {
            type: 'order_issue_update',
            orderId: String(orderId),
            issueId: context.params.issueId,
            issueState: to,
            target: 'communicationPanel',
          },
          tokens,
        });
      }
    }
    return null;
  });

/**
 * Aggregate communication KPIs every 15 minutes.
 */
exports.aggregateCommunicationMetrics = functions.pubsub
  .schedule('every 15 minutes')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = admin.firestore();
    const since = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 24 * 60 * 60 * 1000)
    );

    const messagesSnap = await db
      .collectionGroup('messages')
      .where('createdAt', '>=', since)
      .get();
    const issuesSnap = await db
      .collectionGroup('issues')
      .where('createdAt', '>=', since)
      .get();

    let responsePairs = 0;
    let totalResponseMs = 0;
    const byOrder = {};
    messagesSnap.docs.forEach((doc) => {
      const d = doc.data() || {};
      const orderId = d.orderId || doc.ref.parent.parent.id;
      if (!orderId || !d.createdAt) return;
      if (!byOrder[orderId]) byOrder[orderId] = [];
      byOrder[orderId].push(d);
    });

    Object.values(byOrder).forEach((arr) => {
      arr.sort((a, b) => a.createdAt.toMillis() - b.createdAt.toMillis());
      for (let i = 1; i < arr.length; i++) {
        if (arr[i].senderRole !== arr[i - 1].senderRole) {
          totalResponseMs +=
            arr[i].createdAt.toMillis() - arr[i - 1].createdAt.toMillis();
          responsePairs++;
        }
      }
    });

    const avgResponseMs =
      responsePairs > 0 ? Math.round(totalResponseMs / responsePairs) : 0;
    const unresolvedIssues = issuesSnap.docs.filter((doc) => {
      const s = String((doc.data() || {}).state || '');
      return ['opened', 'acknowledged', 'resolved'].includes(s);
    }).length;

    const metricDocId = new Date().toISOString().substring(0, 16);
    await db.collection('communication_metrics').doc(metricDocId).set({
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      responsePairs,
      avgResponseMs,
      totalMessages24h: messagesSnap.size,
      totalIssues24h: issuesSnap.size,
      unresolvedIssues,
    });

    const thresholdMs = 10 * 60 * 1000;
    if (avgResponseMs > thresholdMs || unresolvedIssues > 20) {
      await db.collection('communication_alerts').add({
        type: 'kpi_threshold',
        avgResponseMs,
        unresolvedIssues,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return null;
  });

exports.sendCommunicationAlertWebhook = functions
  .region('us-central1')
  .firestore.document('communication_alerts/{alertId}')
  .onCreate(async (snap) => {
    const alert = snap.data() || {};
    const webhook = functions.config().alerts &&
      functions.config().alerts.webhook;
    if (!webhook) {
      console.log('[sendCommunicationAlertWebhook] webhook not configured');
      return null;
    }
    try {
      const resp = await fetch(webhook, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text: `Communication Alert: ${alert.type || 'unknown'}`,
          alert,
        }),
      });
      console.log(
        `[sendCommunicationAlertWebhook] status=${resp.status}`
      );
    } catch (e) {
      console.error('[sendCommunicationAlertWebhook] failed', e);
    }
    return null;
  });

exports.getCommunicationExperimentConfig = functions
  .region('us-central1')
  .https.onRequest(async (req, res) => {
    try {
      const rc = admin.remoteConfig();
      const tpl = await rc.getTemplate();
      const params = tpl.parameters || {};
      const output = {
        quick_reply_variant:
          (params.quick_reply_variant || {}).defaultValue?.value || 'control',
        comm_panel_layout_variant:
          (params.comm_panel_layout_variant || {}).defaultValue?.value ||
          'compact',
        notification_timing_strategy:
          (params.notification_timing_strategy || {}).defaultValue?.value ||
          'immediate',
      };
      return res.json({ success: true, data: output });
    } catch (e) {
      return res.status(500).json({ success: false, error: e.message });
    }
  });
