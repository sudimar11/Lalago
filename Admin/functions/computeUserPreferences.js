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

/** Fetch all-time completed order count for segmentation (totalOrders must be all-time). */
async function getAllTimeOrderStats(db, userId) {
  try {
    const snap = await db
      .collection(ORDERS)
      .where('authorID', '==', userId)
      .get();
    const completed = snap.docs
      .map((d) => d.data())
      .filter((o) =>
        COMPLETED_STATUSES.some((s) =>
          (o.status || '').toString().toLowerCase().includes(s.toLowerCase())
        )
      );
    const sorted = completed.sort((a, b) => {
      const dateA = a.createdAt?.toDate?.() || new Date(0);
      const dateB = b.createdAt?.toDate?.() || new Date(0);
      return dateB - dateA;
    });
    const lastOrder = sorted[0];
    return {
      totalCompletedOrdersAllTime: completed.length,
      lastOrderedAtAllTime: lastOrder?.createdAt || null,
    };
  } catch (e) {
    console.log('getAllTimeOrderStats error for', userId, e.message);
    return { totalCompletedOrdersAllTime: 0, lastOrderedAtAllTime: null };
  }
}

function calculateAverageOrderFrequency(orders) {
  if (!orders || orders.length < 2) return null;
  const sorted = [...orders].sort((a, b) => {
    const dateA = a.createdAt?.toDate?.() || new Date(0);
    const dateB = b.createdAt?.toDate?.() || new Date(0);
    return dateA - dateB;
  });
  let totalDays = 0;
  for (let i = 1; i < sorted.length; i++) {
    const dateA = sorted[i - 1].createdAt?.toDate?.() || new Date(0);
    const dateB = sorted[i].createdAt?.toDate?.() || new Date(0);
    const days = (dateB - dateA) / (1000 * 60 * 60 * 24);
    totalDays += days;
  }
  return Math.round(totalDays / (sorted.length - 1));
}

exports.computeUserPreferences = functions
  .region('us-central1')
  .pubsub.schedule('0 4 * * *')
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
      const allTimeStats = await getAllTimeOrderStats(db, userId);
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
        .map(([k]) => (k === 'lateNight' ? 'late_night' : k));

      const topRestaurants = Object.entries(favoriteRestaurants)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([id]) => id);

      const completedOrders = orders.sort((a, b) => {
        const dateA = a.createdAt?.toDate?.() || new Date(0);
        const dateB = b.createdAt?.toDate?.() || new Date(0);
        return dateB - dateA;
      });
      const lastCompletedOrder = completedOrders[0] || null;

      const lastOrderProducts = lastCompletedOrder?.products?.slice(0, 3)
        ?.map((p) => ({ id: p.id || '', name: p.name || '' }))
        .filter((p) => p.id || p.name) || [];

      const productPreferences = {};
      const categoryPreferences = {};

      for (const order of orders) {
        const products = order.products || [];
        const vendorId = order.vendorID;
        const vendorName = order.vendor?.title || '';
        for (const product of products) {
          const productId = (product.id || product['id'] || '')
            .toString()
            .split('~')[0];
          if (productId) {
            if (!productPreferences[productId]) {
              productPreferences[productId] = {
                count: 0,
                name: product.name || '',
                vendorId: vendorId || '',
                vendorName,
                categoryId: product.category_id || product.categoryID || '',
              };
            }
            productPreferences[productId].count +=
              product.quantity || 1;
          }
          const catId = product.category_id || product.categoryID;
          if (catId) {
            categoryPreferences[catId] =
              (categoryPreferences[catId] || 0) + 1;
          }
        }
      }

      const favoriteProducts = Object.entries(productPreferences)
        .map(([id, data]) => ({
          id,
          name: data.name,
          vendorId: data.vendorId,
          vendorName: data.vendorName,
          count: data.count,
        }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 10);

      const topCategories = Object.entries(categoryPreferences)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([categoryId, count]) => ({ categoryId, count }));

      const orderFrequencyDays = calculateAverageOrderFrequency(orders);
      const totalCompletedOrdersAllTime =
        allTimeStats.totalCompletedOrdersAllTime ?? totalOrders;
      const lastOrderedAtAllTime =
        allTimeStats.lastOrderedAtAllTime ?? lastCompletedOrder?.createdAt;

      const typicalHours = {};
      if (orders.length >= 2) {
        const lunchHours = orders
          .map((o) => {
            const createdAt = o.createdAt?.toDate?.() || new Date();
            const h = createdAt.getHours();
            return h >= 11 && h < 16 ? h : null;
          })
          .filter((h) => h !== null);
        const snackHours = orders
          .map((o) => {
            const createdAt = o.createdAt?.toDate?.() || new Date();
            const h = createdAt.getHours();
            return h >= 14 && h < 17 ? h : null;
          })
          .filter((h) => h !== null);
        const dinnerHours = orders
          .map((o) => {
            const createdAt = o.createdAt?.toDate?.() || new Date();
            const h = createdAt.getHours();
            return h >= 16 && h < 22 ? h : null;
          })
          .filter((h) => h !== null);

        const median = (arr) => {
          if (arr.length === 0) return null;
          const sorted = [...arr].sort((a, b) => a - b);
          const mid = Math.floor(sorted.length / 2);
          return sorted.length % 2
            ? sorted[mid]
            : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
        };

        const tl = median(lunchHours);
        const ts = median(snackHours);
        const td = median(dinnerHours);
        if (tl !== null) typicalHours.typicalLunchHour = tl;
        if (ts !== null) typicalHours.typicalSnackHour = ts;
        if (td !== null) typicalHours.typicalDinnerHour = td;
      }

      const preferenceProfile = {
        cuisinePreferences: cuisinePrefs,
        avgSpend: totalOrders > 0 ? totalSpend / totalOrders : 0,
        preferredTimes,
        favoriteRestaurants: topRestaurants,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
        lastOrderedAt: lastOrderedAtAllTime ?? lastCompletedOrder?.createdAt ?? null,
        lastOrderVendorId: lastCompletedOrder?.vendorID ?? null,
        lastOrderVendorName: lastCompletedOrder?.vendor?.title ?? null,
        lastOrderProducts,
        orderFrequencyDays,
        totalCompletedOrders: totalCompletedOrdersAllTime,
        favoriteProducts,
        topCategories,
        ...typicalHours,
      };

      const updateData = {
        preferenceProfile,
        totalCompletedOrders: totalCompletedOrdersAllTime,
        lastOrderCompletedAt: lastOrderedAtAllTime ?? lastCompletedOrder?.createdAt ?? null,
        reorderEligible: totalOrders >= 2,
        engagementScore: Math.round(
          totalOrders * 10 +
            totalSpend / 100 +
            (orderFrequencyDays ? 100 / orderFrequencyDays : 0),
        ),
        lastOrderRecencyDays: lastCompletedOrder
          ? Math.floor(
              (Date.now() -
                (lastCompletedOrder.createdAt?.toDate?.() || new Date())
                  .getTime()) /
                86400000,
            )
          : 999,
        orderFrequency:
          totalOrders > 0 && orderFrequencyDays
            ? 30 / orderFrequencyDays
            : 0,
        totalSpend,
      };

      try {
        await db.collection(USERS).doc(userId).update(updateData);
      } catch (e) {
        if (e.code === 5) {
          try {
            await db.collection(USERS).doc(userId).set(updateData, {
              merge: true,
            });
          } catch (_) {}
        }
      }
    }

    console.log(
      `Computed preferences for ${Object.keys(userOrderIds).length} users`
    );
  });
