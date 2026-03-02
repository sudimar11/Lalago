/**
 * Hunger detection and content generation for Ash hunger break reminders.
 * Receives db from callers; does not initialize admin.
 */

const ORDER_STATUSES_INDICATING_ORDER_EXISTS = [
  'Order Accepted',
  'Order Completed',
  'order completed',
  'completed',
  'Completed',
  'In Transit',
  'Order Shipped',
];

class HungerDetection {
  /**
   * Check if a user might be hungry based on their order patterns and current time.
   */
  static async shouldSendHungerReminder(db, userId, userData, currentTime) {
    const settings = userData.settings || {};
    if (settings.ashHungerReminders === false) return false;

    const pref = userData.preferenceProfile || {};
    const preferredTimes = pref.preferredTimes || [];
    const lastOrderedAt = pref.lastOrderedAt
      ? (pref.lastOrderedAt.toDate ? pref.lastOrderedAt.toDate() : new Date(pref.lastOrderedAt._seconds * 1000))
      : null;
    const orderFrequencyDays = pref.orderFrequencyDays || null;
    const totalOrders = pref.totalCompletedOrders || 0;

    if (totalOrders < 3) return false;

    const currentHour = currentTime.getHours();
    const currentPeriod = this.getMealPeriod(currentTime);

    const prefersThisPeriod = preferredTimes.includes(currentPeriod);

    let isDueForMeal = false;
    if (lastOrderedAt && orderFrequencyDays) {
      const daysSinceLastOrder =
        (currentTime - lastOrderedAt) / (1000 * 60 * 60 * 24);
      isDueForMeal =
        daysSinceLastOrder >= orderFrequencyDays * 0.8 && prefersThisPeriod;
    }

    const orderedToday = await this.hasOrderedToday(db, userId, currentTime);
    if (orderedToday) return false;

    const recentReminder = await this.hasRecentHungerReminder(
      db,
      userId,
      currentTime
    );
    if (recentReminder) return false;

    if (prefersThisPeriod && (isDueForMeal || currentHour > 12)) {
      return true;
    }

    if (totalOrders > 5 && this.isStandardMealTime(currentHour)) {
      return true;
    }

    return false;
  }

  static getMealPeriod(time) {
    const hour = time.getHours();
    if (hour >= 5 && hour < 11) return 'breakfast';
    if (hour >= 11 && hour < 16) return 'lunch';
    if (hour >= 16 && hour < 22) return 'dinner';
    return 'late_night';
  }

  static isStandardMealTime(hour) {
    return (
      (hour >= 7 && hour <= 9) ||
      (hour >= 12 && hour <= 14) ||
      (hour >= 18 && hour <= 20)
    );
  }

  static async hasOrderedToday(db, userId, currentTime) {
    const admin = require('firebase-admin');
    const startOfDay = new Date(currentTime);
    startOfDay.setHours(0, 0, 0, 0);
    const startTs = admin.firestore.Timestamp.fromDate(startOfDay);

    const orders = await db
      .collection('restaurant_orders')
      .where('authorID', '==', userId)
      .where('createdAt', '>=', startTs)
      .limit(10)
      .get();

    if (orders.empty) return false;
    for (const doc of orders.docs) {
      const d = doc.data();
      const aid = d.authorID || (d.author && d.author.id);
      if (aid !== userId) continue;
      const status = (d.status || '').toString();
      if (
        ORDER_STATUSES_INDICATING_ORDER_EXISTS.some((s) =>
          status.toLowerCase().includes(s.toLowerCase())
        )
      ) {
        return true;
      }
    }
    return false;
  }

  static async hasRecentHungerReminder(db, userId, currentTime) {
    const admin = require('firebase-admin');
    const threeHoursAgo = new Date(currentTime);
    threeHoursAgo.setHours(threeHoursAgo.getHours() - 3);
    const threeHoursAgoTs = admin.firestore.Timestamp.fromDate(threeHoursAgo);

    const reminders = await db
      .collection('ash_notification_history')
      .where('userId', '==', userId)
      .where('type', '==', 'ash_hunger')
      .where('sentAt', '>=', threeHoursAgoTs)
      .limit(1)
      .get();

    return !reminders.empty;
  }

  /**
   * Generate personalized hunger reminder content.
   * Returns { title, body, suggestedProduct?, suggestedRestaurant? }
   */
  static async generateHungerContent(db, userId, userData) {
    const pref = userData.preferenceProfile || {};
    const favoriteProducts = pref.favoriteProducts || [];
    const favoriteRestaurants = pref.favoriteRestaurants || [];
    const preferredTimes = pref.preferredTimes || [];
    const currentPeriod = this.getMealPeriod(new Date());

    const mealKeywords = {
      breakfast: [
        'silog',
        'pancake',
        'waffle',
        'coffee',
        'pastry',
        'egg',
        'breakfast',
        'tapsilog',
        'longsilog',
      ],
      lunch: [
        'burger',
        'sandwich',
        'rice',
        'meal',
        'soup',
        'lunch',
        'bento',
        'bowl',
      ],
      dinner: [
        'dinner',
        'steak',
        'pasta',
        'grill',
        'family',
        'platter',
        'share',
      ],
      late_night: [
        'snack',
        'fries',
        'drink',
        'dessert',
        'burger',
        'pizza',
        'wings',
      ],
    };

    const keywords = mealKeywords[currentPeriod] || [];
    let suggestedProduct = null;
    let suggestedRestaurant = null;
    let restaurantName = 'your favorite spot';

    for (const product of favoriteProducts.slice(0, 5)) {
      const productName = (product.name || '').toLowerCase();
      if (keywords.some((k) => productName.includes(k))) {
        suggestedProduct = product;
        break;
      }
    }

    if (!suggestedProduct && favoriteRestaurants.length > 0) {
      const randomRestaurantId =
        favoriteRestaurants[
          Math.floor(Math.random() * favoriteRestaurants.length)
        ];
      const vendorDoc = await db.collection('vendors').doc(randomRestaurantId).get();
      if (vendorDoc.exists) {
        suggestedRestaurant = vendorDoc.data();
        restaurantName = suggestedRestaurant.title || restaurantName;
      }
    }

    let title;
    let body;

    const hour = new Date().getHours();

    if (hour >= 5 && hour < 11) {
      title = 'Good morning!';
    } else if (hour >= 11 && hour < 14) {
      title = 'Hungry for lunch?';
    } else if (hour >= 14 && hour < 17) {
      title = 'Afternoon pick-me-up?';
    } else if (hour >= 17 && hour < 21) {
      title = 'Dinner time!';
    } else {
      title = 'Late night snack?';
    }

    const periodLabel = currentPeriod.replace('_', ' ');

    if (suggestedProduct) {
      body = `How about your favorite ${suggestedProduct.name}? Perfect for ${periodLabel}!`;
    } else if (suggestedRestaurant || restaurantName !== 'your favorite spot') {
      body = `Ready to order from ${restaurantName}? They have great options for ${periodLabel}.`;
    } else if (preferredTimes.includes(currentPeriod)) {
      body = `It's your usual ${periodLabel} time. What are you craving?`;
    } else {
      body = `Take a break and treat yourself! What sounds good right now?`;
    }

    return {
      title,
      body,
      suggestedProduct: suggestedProduct || undefined,
      suggestedRestaurant: suggestedRestaurant || undefined,
    };
  }
}

module.exports = HungerDetection;
