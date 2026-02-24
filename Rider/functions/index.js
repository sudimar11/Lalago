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

      // Get customer FCM token
      let customerFcmToken = null;
      let customerId = null;

      // Try to get from order.author
      const author = afterData.author || {};
      customerFcmToken = author.fcmToken || null;
      customerId = author.id || author.customerID || null;

      // Fallback: read from users collection if token not in order
      if (!customerFcmToken && customerId) {
        try {
          const userDoc = await db.collection('users').doc(customerId).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            customerFcmToken = userData?.fcmToken || null;
            console.log(
              `[notifyCustomerOnDriverAssigned] Order ${orderId}: Retrieved FCM token from users collection`
            );
          }
        } catch (userError) {
          console.error(
            `[notifyCustomerOnDriverAssigned] Order ${orderId}: Error reading user doc:`,
            userError
          );
        }
      }

      if (!customerFcmToken) {
        console.log(
          `[notifyCustomerOnDriverAssigned] Order ${orderId}: No FCM token found for customer`
        );
        return null;
      }

      // Send notification
      const message = {
        notification: {
          title: 'Driver Accepted',
          body: 'Driver accepted your order',
        },
        token: customerFcmToken,
        data: {
          type: 'order_update',
          orderId: orderId,
          status: afterData.status || 'Driver Accepted',
        },
      };

      const messageId = await admin.messaging().send(message);
      console.log(
        `[notifyCustomerOnDriverAssigned] Order ${orderId}: Notification sent. MessageId: ${messageId.substring(0, 20)}...`
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

          // Get customer info
          const author = orderData.author || {};
          let customerFcmToken = author.fcmToken || null;
          const customerId = author.id || author.customerID || null;

          // A) "Driver is on the way to the restaurant"
          if (
            ['Driver Accepted', 'Order Shipped'].includes(
              orderStatus
            ) &&
            distanceFromAccept > 100 &&
            !lifecycleNotifs.onWayToRestaurantAt
          ) {
            // Fallback: get token from users collection if needed
            if (!customerFcmToken && customerId) {
              try {
                const userDoc = await db.collection('users').doc(customerId).get();
                if (userDoc.exists) {
                  customerFcmToken = userDoc.data()?.fcmToken || null;
                }
              } catch (err) {
                console.error(
                  `[processDriverLocationLifecycle] Error reading customer user:`,
                  err
                );
              }
            }

            if (customerFcmToken) {
              try {
                const message = {
                  notification: {
                    title: 'Driver On The Way',
                    body: 'Driver is on the way to the restaurant',
                  },
                  token: customerFcmToken,
                  data: {
                    type: 'order_update',
                    orderId: String(orderId),
                    status: orderStatus,
                  },
                };

                await admin.messaging().send(message);
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
            // Fallback: get token from users collection if needed
            if (!customerFcmToken && customerId) {
              try {
                const userDoc = await db.collection('users').doc(customerId).get();
                if (userDoc.exists) {
                  customerFcmToken = userDoc.data()?.fcmToken || null;
                }
              } catch (err) {
                console.error(
                  `[processDriverLocationLifecycle] Error reading customer user:`,
                  err
                );
              }
            }

            if (customerFcmToken) {
              try {
                const message = {
                  notification: {
                    title: 'Driver At Restaurant',
                    body: 'Driver is at the restaurant',
                  },
                  token: customerFcmToken,
                  data: {
                    type: 'order_update',
                    orderId: String(orderId),
                    status: orderStatus,
                  },
                };

                await admin.messaging().send(message);
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
            // Fallback: get token from users collection if needed
            if (!customerFcmToken && customerId) {
              try {
                const userDoc = await db.collection('users').doc(customerId).get();
                if (userDoc.exists) {
                  customerFcmToken = userDoc.data()?.fcmToken || null;
                }
              } catch (err) {
                console.error(
                  `[processDriverLocationLifecycle] Error reading customer user:`,
                  err
                );
              }
            }

            if (customerFcmToken) {
              try {
                const message = {
                  notification: {
                    title: 'Driver On The Way',
                    body: 'Driver left the restaurant and is on the way',
                  },
                  token: customerFcmToken,
                  data: {
                    type: 'order_update',
                    orderId: String(orderId),
                    status: 'In Transit',
                  },
                };

                await admin.messaging().send(message);

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
      if (d.checkedOutToday === true) continue;
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
 * for longer than the configured threshold. Runs every 5 minutes.
 */
exports.monitorRiderInactivity = functions.pubsub
  .schedule('every 5 minutes')
  .timeZone('Asia/Manila')
  .onRun(async (context) => {
    const db = admin.firestore();

    const configSnap = await db
      .collection('config')
      .doc('rider_time_settings')
      .get();
    const config = configSnap.exists ? configSnap.data() : {};
    const inactivityTimeoutMinutes = config.inactivityTimeoutMinutes ?? 15;
    const excludeWithActiveOrders = config.excludeWithActiveOrders !== false;
    const thresholdMs = inactivityTimeoutMinutes * 60 * 1000;

    const ridersSnap = await db
      .collection('users')
      .where('role', '==', 'driver')
      .get();

    const now = Date.now();
    let loggedOut = 0;

    for (const riderDoc of ridersSnap.docs) {
      const data = riderDoc.data();
      const avail = data.riderAvailability;
      if (avail !== 'available' && avail !== 'on_delivery') continue;

      const orders = data.inProgressOrderID || [];
      const hasActiveOrders = orders.length > 0;
      if (excludeWithActiveOrders && hasActiveOrders) continue;

      const lastActRaw = data.lastActivityTimestamp;
      const locRaw = data.locationUpdatedAt;
      const lastActTs = lastActRaw && lastActRaw.toDate
        ? lastActRaw.toDate()
        : lastActRaw;
      const locTs = locRaw && locRaw.toDate
        ? locRaw.toDate()
        : locRaw;
      const lastAct = lastActTs || locTs;
      if (!lastAct) continue;

      const lastActMs = lastAct instanceof Date
        ? lastAct.getTime()
        : (lastAct.toMillis ? lastAct.toMillis() : new Date(lastAct).getTime());
      const inactiveMs = now - lastActMs;
      if (inactiveMs < thresholdMs) continue;

      const inactiveMinutes = Math.round(inactiveMs / 60000);

      await db.collection('system_logs').add({
        type: 'auto_logout',
        riderId: riderDoc.id,
        reason: 'inactivity',
        inactiveMinutes,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      await riderDoc.ref.update({
        isOnline: false,
        riderAvailability: 'offline',
        riderDisplayStatus: 'Offline',
      });
      loggedOut++;
      console.log(
        `[Inactivity] Auto-logout rider ${riderDoc.id}, ` +
        `inactive ${inactiveMinutes} min`
      );
    }

    if (loggedOut > 0) {
      console.log(`[Inactivity] Done – auto-logged out ${loggedOut} rider(s)`);
    }
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
