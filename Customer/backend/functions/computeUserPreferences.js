/**
 * Daily Cloud Function: Compute user preference profiles from order history.
 * Runs at 4 AM Asia/Manila.
 * Stores preferenceProfile in users document.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

const ORDERS = 'restaurant_orders';
const USERS = 'users';
const VENDORS = 'vendors';

const COMPLETED_STATUSES = [
  'Order Completed',
  'order completed',
  'completed',
  'Completed',
];

exports.computeUserPreferences = functions.pubsub
  .schedule('0 4 * * *')
  .timeZone('Asia/Manila')
  .onRun(async () => {
    const db = admin.firestore();
    const ninetyDaysAgo = new Date();
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

    const ordersSnap = await db
      .collection(ORDERS)
      .where('createdAt', '>=', ninetyDaysAgo)
      .get();

    const userOrderIds = {};
    for (const doc of ordersSnap.docs) {
      const data = doc.data();
      const authorId = data.authorID || data.author?.id;
      const status = (data.status || '').toString();
      if (!COMPLETED_STATUSES.some((s) => status.toLowerCase().includes(s.toLowerCase()))) {
        continue;
      }
      if (!authorId) continue;
      if (!userOrderIds[authorId]) userOrderIds[authorId] = [];
      userOrderIds[authorId].push({ id: doc.id, ...data });
    }

    for (const userId of Object.keys(userOrderIds)) {
      const orders = userOrderIds[userId];
      const cuisineCounts = {};
      let totalSpend = 0;
      const timeCounts = { breakfast: 0, lunch: 0, dinner: 0, lateNight: 0 };
      const favoriteRestaurants = {};

      for (const order of orders) {
        const vendorId = order.vendorID;
        if (vendorId) {
          try {
            const vendorDoc = await db.collection(VENDORS).doc(vendorId).get();
            if (vendorDoc.exists) {
              const vendor = vendorDoc.data();
              const cuisine = (vendor.categoryTitle || 'other').toString();
              cuisineCounts[cuisine] = (cuisineCounts[cuisine] || 0) + 1;
            }
          } catch (_) {}
        }

        const amount = order.totalAmount ?? 0;
        totalSpend += typeof amount === 'number' ? amount : parseFloat(amount) || 0;

        const createdAt = order.createdAt?.toDate?.() || new Date();
        const hour = createdAt.getHours();
        if (hour >= 5 && hour < 11) timeCounts.breakfast++;
        else if (hour >= 11 && hour < 16) timeCounts.lunch++;
        else if (hour >= 16 && hour < 22) timeCounts.dinner++;
        else timeCounts.lateNight++;

        if (vendorId) {
          favoriteRestaurants[vendorId] =
            (favoriteRestaurants[vendorId] || 0) + 1;
        }
      }

      const totalOrders = orders.length;
      const cuisinePrefs = {};
      for (const k of Object.keys(cuisineCounts)) {
        cuisinePrefs[k] = cuisineCounts[k] / totalOrders;
      }

      const preferredTimes = Object.entries(timeCounts)
        .filter(([, v]) => v / totalOrders > 0.2)
        .map(([k]) => k);

      const topRestaurants = Object.entries(favoriteRestaurants)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([id]) => id);

      try {
        await db.collection(USERS).doc(userId).update({
          preferenceProfile: {
            cuisinePreferences: cuisinePrefs,
            avgSpend: totalOrders > 0 ? totalSpend / totalOrders : 0,
            preferredTimes,
            favoriteRestaurants: topRestaurants,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          },
        });
      } catch (e) {
        if (e.code === 5) {
          try {
            await db.collection(USERS).doc(userId).set(
              {
                preferenceProfile: {
                  cuisinePreferences: cuisinePrefs,
                  avgSpend: totalOrders > 0 ? totalSpend / totalOrders : 0,
                  preferredTimes,
                  favoriteRestaurants: topRestaurants,
                  lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
                },
              },
              { merge: true }
            );
          } catch (_) {}
        }
      }
    }

    console.log(
      `Computed preferences for ${Object.keys(userOrderIds).length} users`
    );
  });
