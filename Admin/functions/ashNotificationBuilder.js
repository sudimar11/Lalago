/**
 * Ash Notification Builder - Builds notifications with Ash's personality.
 */

const AshVoice = require('./ashVoice');

function _substituteVariables(str, vars = {}) {
  if (!str || typeof str !== 'string') return str;
  let result = str;
  for (const [key, value] of Object.entries(vars)) {
    if (value != null && value !== '') {
      result = result.replace(
        new RegExp(`\\{${key}\\}`, 'gi'),
        String(value)
      );
    }
  }
  return result;
}

class AshNotificationBuilder {
  /**
   * Build a notification with Ash's personality
   */
  static buildAshNotification(type, userData, contextData = {}) {
    const firstName =
      userData?.firstName || userData?.displayName || null;
    const language =
      userData?.settings?.preferredLanguage || 'en';
    const timezone = userData?.timezone || 'Asia/Manila';
    const userId = userData?.id || userData?.userID || contextData.userId || '';

    const content = this._getContentForType(type, contextData);

    const title = AshVoice.getTitle(content.title, {
      type,
      language,
      includeAsh: content.includeAsh !== false,
      emoji: content.emoji !== false,
    });

    const body = AshVoice.getBody(content.body, {
      firstName,
      restaurantName: contextData.restaurantName,
      productName: contextData.productName,
      timeUntil: contextData.timeUntil,
      isUrgent: content.isUrgent || false,
      language,
      type,
    });

    const fullBody =
      content.includeSignOff ? `${body} ${AshVoice.signOff(language)}` : body;

    const notificationId = `${type}_${userId}_${Date.now()}`;

    const data = {
      type: `ash_${type}`,
      notificationId,
      userId: String(userId),
      timestamp: new Date().toISOString(),
      ash: 'true',
    };
    if (firstName) data.firstName = String(firstName);
    if (contextData.restaurantName)
      data.restaurantName = String(contextData.restaurantName);
    if (contextData.productName)
      data.productName = String(contextData.productName);
    if (contextData.orderId) data.orderId = String(contextData.orderId);
    if (contextData.amount != null) data.amount = String(contextData.amount);
    if (contextData.vendorId) data.vendorId = String(contextData.vendorId);
    if (contextData.productId) data.productId = String(contextData.productId);
    if (contextData.mealPeriod)
      data.mealPeriod = String(contextData.mealPeriod);
    if (contextData.daysSinceLastOrder != null)
      data.daysSinceLastOrder = String(contextData.daysSinceLastOrder);
    if (contextData.itemCount != null)
      data.itemCount = String(contextData.itemCount);
    if (contextData.failureType)
      data.failureType = String(contextData.failureType);

    Object.keys(data).forEach((k) => {
      data[k] = String(data[k]);
    });

    return {
      title,
      body: fullBody,
      data,
    };
  }

  /**
   * Get content templates for each notification type with variable substitution
   */
  static _getContentForType(type, context) {
    const {
      restaurantName = 'your favorite restaurant',
      productName,
      daysSinceLastOrder,
      vendorName,
      itemCount,
      totalValue,
      failureType,
      alternatives,
      customerName,
      amount,
      mealPeriod,
      suggestion,
    } = context;

    const rest = restaurantName || vendorName || 'your favorite restaurant';
    const vars = {
      days: daysSinceLastOrder,
      restaurant: rest,
      product: productName || 'something tasty',
      count: itemCount,
      amount,
      customer: customerName || 'Customer',
      suggestion: suggestion || productName || 'something tasty',
    };

    const templates = {
      reorder: {
        title: 'Time to reorder?',
        body: `It's been {days} days since your order from {restaurant}. Want the same again?`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      recommendation: {
        title: 'Something you might like',
        body: `Since you enjoyed {product}, I thought you'd like this from {restaurant}!`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      cart: {
        title: 'Your cart is waiting',
        body: `You left {count} items in your cart from {restaurant}. Ready to complete your order?`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      cart_urgent: {
        title: "Don't forget your order!",
        body: `Your cart from {restaurant} is still here. Items might sell out soon!`,
        includeSignOff: true,
        isUrgent: true,
        includeAsh: true,
        emoji: true,
      },
      hunger: {
        title: 'Time to eat?',
        body: `I noticed it's your usual meal time. How about {suggestion} from {restaurant}?`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      payment_failed: {
        title: "Payment didn't go through",
        body:
          "Don't worry, it happens! Your cart is safe. Want to try another payment method?",
        includeSignOff: true,
        isUrgent: true,
        includeAsh: true,
        emoji: true,
      },
      recovery: {
        title: "Let's try that again",
        body: `Your order from {restaurant} didn't complete. I found some alternatives for you.`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      recovery_followup: {
        title: 'Still want to order?',
        body: `Your cart from {restaurant} is waiting. Want to try again with another payment method?`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      order_accepted: {
        title: 'Order confirmed!',
        body: `Great news! {restaurant} has accepted your order.`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      order_ready: {
        title: 'Ready for pickup!',
        body: `Your order from {restaurant} is ready. Enjoy!`,
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      order_delivered: {
        title: 'Delivered!',
        body:
          'Your food has arrived. Hope you enjoy it! Let me know how it was.',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      order_placed: {
        title: 'Order received',
        body: 'Your order has been placed successfully!',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      rider_assigned: {
        title: 'Rider assigned',
        body: 'A rider has been assigned to your order.',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      preparing: {
        title: 'Preparing your order',
        body: '{restaurant} is now preparing your food.',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      on_the_way: {
        title: 'On the way',
        body: 'Your order is on the way! Track your rider.',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      finding_rider: {
        title: 'Finding another rider',
        body: 'Your order is being reassigned.',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      order_cancelled: {
        title: 'Order cancelled',
        body: 'Your order has been cancelled.',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      order_rejected: {
        title: 'Order unsuccessful',
        body: 'Your order could not be completed.',
        includeSignOff: true,
        isUrgent: false,
        includeAsh: true,
        emoji: true,
      },
      payment_failed_status: {
        title: 'Payment failed',
        body:
          "Your payment didn't go through. Please try another payment method.",
        includeSignOff: true,
        isUrgent: true,
        includeAsh: true,
        emoji: true,
      },
    };

    const template = templates[type] || {
      title: 'Update from Lalago',
      body: "Here's an update about your order.",
      includeSignOff: true,
      isUrgent: false,
      includeAsh: true,
      emoji: true,
    };

    return {
      ...template,
      title: _substituteVariables(template.title, {
        ...vars,
        restaurant: rest,
      }),
      body: _substituteVariables(template.body, {
        ...vars,
        restaurant: rest,
      }),
    };
  }

  /**
   * Add Ash's voice to an existing notification
   */
  static enhanceWithAsh(originalNotification, userData) {
    const { title, body, data } = originalNotification;
    const firstName = userData?.firstName || userData?.displayName;
    const language = userData?.settings?.preferredLanguage || 'en';

    const ashTitle = AshVoice.getTitle(title, { includeAsh: true });
    let ashBody = body;

    if (firstName && !body.includes(firstName)) {
      ashBody = `Hi ${firstName}! ${body}`;
    }

    return {
      ...originalNotification,
      title: ashTitle,
      body: ashBody,
      data: {
        ...data,
        ash: 'true',
        ashVersion: '1.0',
      },
    };
  }
}

module.exports = AshNotificationBuilder;
