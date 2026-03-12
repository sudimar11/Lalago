/**
 * Order Recovery Service - Handles order failures and initiates recovery flow.
 * Logs failures, finds alternatives, schedules Ash notifications.
 */

const admin = require('firebase-admin');
const AshNotificationBuilder = require('./ashNotificationBuilder');

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

class OrderRecoveryService {
  /**
   * Handle order failure and initiate recovery
   */
  static async handleOrderFailure(orderData, failureType, failureDetails) {
    const db = getDb();
    const userId = orderData.authorID || orderData.authorId || orderData.customerId
      || (orderData.author && orderData.author.id) || '';
    const vendorID = orderData.vendorID || orderData.vendorId
      || (orderData.vendor && orderData.vendor.id) || '';
    const products = orderData.products || [];

    console.log(`[OrderRecovery] Handling failure: ${orderData.id}, type: ${failureType}`);

    // Log the failure
    await db.collection('order_failures').add({
      orderId: orderData.id,
      userId,
      vendorId: vendorID,
      failureType,
      failureDetails: failureDetails || {},
      products: products.map((p) => ({
        id: p.id || p['id'],
        name: p.name || p['name'],
        quantity: p.quantity || p['qty'] || 1,
        price: p.price || p['price'],
      })),
      totalAmount: orderData.totalAmount || orderData.total || 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const userDoc = await db.collection('users').doc(userId).get();
    const userSettings = (userDoc.exists && userDoc.data())?.settings || {};
    const autoRetry = userSettings.autoRetryFailedOrders === true;
    const allowAlternatives = userSettings.allowAlternativeSuggestions !== false;

    let alternatives = null;
    if (allowAlternatives) {
      alternatives = await this.findAlternatives(orderData, failureType);
    }

    await this.scheduleRecovery(userId, orderData, alternatives, failureType, autoRetry);

    return alternatives;
  }

  /**
   * Find alternatives based on failure type
   */
  static async findAlternatives(orderData, failureType) {
    const db = getDb();
    const vendorID = orderData.vendorID || orderData.vendorId
      || (orderData.vendor && orderData.vendor.id) || '';
    const products = orderData.products || [];

    const alternatives = {
      sameRestaurant: [],
      similarRestaurants: [],
      similarProducts: [],
      paymentMethods: [],
    };

    const primaryProduct = products[0];
    if (!primaryProduct) return alternatives;

    const rawId = primaryProduct.id || primaryProduct['id'];
    const productId = typeof rawId === 'string' ? rawId.split('~')[0] : null;

    // 1. For out of stock / item not available: alternatives from same restaurant
    if (['out_of_stock', 'item_not_available'].includes(failureType)) {
      try {
        const sameVendorSnap = await db.collection('vendor_products')
          .where('vendorID', '==', vendorID)
          .where('publish', '==', true)
          .limit(15)
          .get();

        const excludeId = productId || '';
        const items = sameVendorSnap.docs
          .filter((d) => d.id !== excludeId)
          .slice(0, 5)
          .map((d) => {
            const d_ = d.data();
            return {
              id: d.id,
              name: d_.name || '',
              price: d_.price || 0,
              photo: d_.photo || '',
              categoryId: d_.categoryID || '',
              vendorId: vendorID,
              similarity: 'same_restaurant',
            };
          });
        alternatives.sameRestaurant = items;
      } catch (e) {
        console.warn('[OrderRecovery] findAlternatives sameRestaurant:', e.message);
      }
    }

    // 2. Similar restaurants (same category, open)
    try {
      const vendorDoc = await db.collection('vendors').doc(vendorID).get();
      if (vendorDoc.exists) {
        const vendorData = vendorDoc.data() || {};
        const categoryId = vendorData.categoryID || vendorData.categoryId || '';

        const openVendorsSnap = await db.collection('vendors')
          .where('reststatus', '==', true)
          .limit(30)
          .get();

        let docs = openVendorsSnap.docs.filter((d) => d.id !== vendorID);
        if (categoryId) {
          docs = docs.filter((d) => (d.data().categoryID || d.data().categoryId) === categoryId);
        }
        docs = docs.slice(0, 5);

        alternatives.similarRestaurants = docs.map((d) => {
            const d_ = d.data();
            const reviewsCount = d_.reviewsCount || 0;
            const reviewsSum = d_.reviewsSum || 0;
            const rating = reviewsCount > 0 ? reviewsSum / reviewsCount : 0;
            return {
              id: d.id,
              name: d_.title || d_.name || '',
              cuisine: d_.categoryTitle || d_.category || '',
              rating,
              priceLevel: d_.restaurantCost || 0,
            };
          });
      }
    } catch (e) {
      console.warn('[OrderRecovery] findAlternatives similarRestaurants:', e.message);
    }

    // 3. item_similarities for product recommendations
    if (productId) {
      try {
        const candidates = [];
        const q1 = await db.collection('item_similarities')
          .where('item1', '==', productId)
          .orderBy('similarity', 'desc')
          .limit(5)
          .get();
        q1.docs.forEach((d) => {
          const d_ = d.data();
          candidates.push({ similarity: d_.similarity, otherId: d_.item2 });
        });

        const q2 = await db.collection('item_similarities')
          .where('item2', '==', productId)
          .orderBy('similarity', 'desc')
          .limit(5)
          .get();
        q2.docs.forEach((d) => {
          const d_ = d.data();
          candidates.push({ similarity: d_.similarity, otherId: d_.item1 });
        });

        if (candidates.length > 0) {
          candidates.sort((a, b) => (b.similarity || 0) - (a.similarity || 0));
          const ids = [...new Set(candidates.map((c) => c.otherId).slice(0, 5))];
          if (ids.length > 0) {
            const productSnap = await db.collection('vendor_products')
              .where(admin.firestore.FieldPath.documentId(), 'in', ids)
              .where('publish', '==', true)
              .get();

            alternatives.similarProducts = productSnap.docs.map((d) => {
              const d_ = d.data();
              const match = candidates.find((c) => c.otherId === d.id);
              return {
                id: d.id,
                name: d_.name || '',
                price: d_.price || 0,
                photo: d_.photo || '',
                vendorId: d_.vendorID || '',
                similarity: match ? match.similarity : 0.5,
              };
            });
          }
        }
      } catch (e) {
        console.warn('[OrderRecovery] findAlternatives similarProducts:', e.message);
      }
    }

    // 4. Payment failures: suggest COD
    if (failureType === 'payment_failed') {
      alternatives.paymentMethods = [{ type: 'cod', label: 'Cash on Delivery' }];
    }

    return alternatives;
  }

  /**
   * Schedule recovery notifications
   */
  static async scheduleRecovery(userId, orderData, alternatives, failureType, autoRetry) {
    const db = getDb();
    const now = new Date();

    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() || {} : {};
    const userTimezone = userData.timezone || 'Asia/Manila';
    const vendor = orderData.vendor || {};
    const vendorName = (typeof vendor === 'object' ? vendor.title || vendor.name : '') || 'the restaurant';

    const ashType = failureType === 'payment_failed' ? 'payment_failed' : 'recovery';
    const immediateNotif = AshNotificationBuilder.buildAshNotification(
      ashType,
      { ...userData, id: userId },
      { restaurantName: vendorName, userId, failureType }
    );

    const immediateTime = new Date(now.getTime() + 5 * 60 * 1000);

    await db.collection('ash_scheduled_notifications').add({
      userId,
      type: 'ash_order_recovery',
      subtype: failureType,
      title: immediateNotif.title,
      body: immediateNotif.body,
      data: {
        orderId: String(orderData.id || ''),
        failureType: String(failureType),
        alternatives: alternatives ? JSON.stringify(alternatives) : null,
        autoRetry: Boolean(autoRetry),
        vendorName: String(vendorName),
      },
      scheduledFor: admin.firestore.Timestamp.fromDate(immediateTime),
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      timezone: userTimezone,
    });

    if (!autoRetry) {
      const followUpNotif = AshNotificationBuilder.buildAshNotification(
        'recovery_followup',
        { ...userData, id: userId },
        { restaurantName: vendorName, userId }
      );
      const followUpTime = new Date(now.getTime() + 24 * 60 * 60 * 1000);
      await db.collection('ash_scheduled_notifications').add({
        userId,
        type: 'ash_order_recovery',
        subtype: 'follow_up',
        title: followUpNotif.title,
        body: followUpNotif.body,
        data: {
          orderId: String(orderData.id || ''),
          failureType: String(failureType),
          alternatives: alternatives ? JSON.stringify(alternatives) : null,
          followUp: true,
        },
        scheduledFor: admin.firestore.Timestamp.fromDate(followUpTime),
        status: 'pending',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        timezone: userTimezone,
      });
    }
  }

  static getRecoveryContent(failureType, vendorName, alternatives) {
    const templates = {
      payment_failed: {
        immediate: {
          title: 'Payment Failed',
          body: 'Your payment did not go through. Try another payment method or we can help you find alternatives.',
        },
        followUp: {
          body: `Still want to order from ${vendorName}? Your cart is waiting with alternative payment options.`,
        },
      },
      out_of_stock: {
        immediate: {
          title: 'Item Out of Stock',
          body: 'Some items are no longer available. We found similar alternatives for you.',
        },
        followUp: {
          body: `The items you wanted are still unavailable. Check out these similar options from ${vendorName}.`,
        },
      },
      item_not_available: {
        immediate: {
          title: 'Item Not Available',
          body: 'Some items could not be fulfilled. We found similar alternatives for you.',
        },
        followUp: {
          body: `Check out these similar options from ${vendorName}.`,
        },
      },
      restaurant_closed: {
        immediate: {
          title: 'Restaurant Closed',
          body: `${vendorName} is currently closed. Here are similar restaurants nearby.`,
        },
        followUp: {
          body: `Ready to order? ${vendorName} may be open now. Also check out these alternatives.`,
        },
      },
      too_busy: {
        immediate: {
          title: 'Restaurant Busy',
          body: `${vendorName} could not accept your order right now. Try these alternatives.`,
        },
        followUp: {
          body: 'Still craving that meal? Here are some restaurants that can deliver now.',
        },
      },
      distance_too_far: {
        immediate: {
          title: 'Delivery Distance',
          body: `${vendorName} is outside delivery range. Check out these nearby options.`,
        },
        followUp: {
          body: 'Found something else? These restaurants are closer and deliver now.',
        },
      },
      timeout: {
        immediate: {
          title: 'Order Timeout',
          body: `${vendorName} did not confirm your order in time. Here are some alternatives.`,
        },
        followUp: {
          body: 'Still hungry? Try ordering from these restaurants with faster confirmation.',
        },
      },
      restaurant_rejected: {
        immediate: {
          title: 'Order Unsuccessful',
          body: `Your order from ${vendorName} could not be completed. Here are alternatives.`,
        },
        followUp: {
          body: `Your order from ${vendorName} did not complete. Want to try again?`,
        },
      },
      technical_issues: {
        immediate: {
          title: 'Order Issue',
          body: `There was an issue with your order from ${vendorName}. Here are alternatives.`,
        },
        followUp: {
          body: `Still want to order? Try these restaurants.`,
        },
      },
    };

    return templates[failureType] || {
      immediate: {
        title: 'Order Failed',
        body: 'Your order did not go through. We found some alternatives for you.',
      },
      followUp: {
        body: `Your order from ${vendorName} did not complete. Want to try again?`,
      },
    };
  }

  static async autoRetryOrder(userId, orderData, failureType) {
    const db = getDb();
    if (failureType !== 'payment_failed') return false;

    const userDoc = await db.collection('users').doc(userId).get();
    const backupMethod = (userDoc.exists && userDoc.data())?.settings?.backupPaymentMethod;

    if (backupMethod) {
      console.log(`[OrderRecovery] Auto-retry order ${orderData.id} with backup payment`);
      await db.collection('retry_attempts').add({
        orderId: orderData.id,
        userId,
        failureType,
        backupMethod,
        attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    }
    return false;
  }
}

module.exports = OrderRecoveryService;
