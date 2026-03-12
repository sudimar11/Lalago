/**
 * Builds FCM notification payloads with interactive action support.
 * Clients use the actions in data to show local notifications with action buttons.
 * FCM notification + data cannot add action buttons; clients build local notifications.
 */

/**
 * Get actions array for notification type.
 * Returns [{ id, title, icon?, destructive? }]
 */
function getActionsForType(type, orderData = {}) {
  const commonView = { id: 'view_order', title: 'View Order' };
  const commonRemind = { id: 'remind_later', title: 'Remind Later' };

  const typeActions = {
    new_order: [
      { id: 'accept_order', title: 'Accept', destructive: false },
      { id: 'decline_order', title: 'Decline', destructive: true },
    ],
    order: [
      { id: 'accept_order', title: 'Accept', destructive: false },
      { id: 'decline_order', title: 'Decline', destructive: true },
    ],
    order_update: [commonView],
    prep_time_reminder: [
      { id: 'mark_ready', title: 'Mark Ready', destructive: false },
      commonView,
    ],
    food_ready: [
      { id: 'confirm_delivery', title: 'Confirm Pickup', destructive: false },
      commonView,
    ],
    order_reassigned: [commonView],
    order_assignment: [commonView],
    ash_reorder: [
      { id: 'reorder', title: 'Reorder', destructive: false },
      commonRemind,
    ],
    ash_recommendation: [
      { id: 'view_order', title: 'View', destructive: false },
      commonRemind,
    ],
    ash_cart: [
      { id: 'view_order', title: 'View Cart', destructive: false },
      commonRemind,
    ],
    ash_hunger: [
      { id: 'view_order', title: 'Browse', destructive: false },
      commonRemind,
    ],
    chat_message: [
      { id: 'chat_reply', title: 'Reply', destructive: false },
      commonView,
    ],
    admin_driver_chat: [
      { id: 'chat_reply', title: 'Reply', destructive: false },
      commonView,
    ],
  };

  return typeActions[type] || [commonView, commonRemind];
}

function getTitle(type, orderData = {}) {
  const author = orderData?.author || {};
  const vendor = orderData?.vendor || {};
  const firstName = author.firstName || '';
  const restaurantName = vendor.title || 'Restaurant';
  const shortId = orderData?.id ? String(orderData.id).slice(-6) : '';

  const titles = {
    new_order: `New Order from ${firstName || 'Customer'}`,
    order: `New Order #${shortId}`,
    order_update: 'Order Update',
    prep_time_reminder: 'Preparation Time Almost Over',
    food_ready: 'Your order is ready!',
    order_reassigned: 'Order Reassigned',
    order_assignment: 'New Order Assignment',
    ash_reorder: 'Hungry again?',
    ash_recommendation: 'Recommended for you',
    ash_cart: 'Your cart is waiting',
    ash_hunger: 'Time to eat?',
    chat_message: 'New message about your order',
    admin_driver_chat: 'Admin',
  };
  return titles[type] || 'Notification from Lalago';
}

function getBody(type, orderData = {}) {
  const vendor = orderData?.vendor || {};
  const restaurantName = vendor.title || 'the restaurant';
  const totalAmount = orderData?.totalAmount ?? orderData?.author?.amount ?? 0;
  const shortId = orderData?.id ? String(orderData.id).slice(-6) : '';
  const minutesLeft = orderData?.minutesLeft ?? '';

  const bodies = {
    new_order: `Order #${shortId} - ₱${totalAmount}`,
    order: `You have a new order #${shortId}`,
    order_update: 'Your order status has been updated.',
    prep_time_reminder: `Order #${shortId} will be ready in ${minutesLeft} minutes. Please mark as ready.`,
    food_ready: `Your order from ${restaurantName} is now ready for pickup`,
    order_reassigned: 'An order was reassigned due to timeout.',
    order_assignment: `You have been assigned order #${shortId}`,
    ash_reorder: `Ready to order from ${restaurantName} again?`,
    ash_recommendation: 'Tap to see personalized recommendations',
    ash_cart: 'Don\'t forget to complete your order',
    ash_hunger: 'Browse restaurants near you',
    chat_message: orderData?.lastMessage || 'Tap to reply',
    admin_driver_chat: orderData?.lastMessage || 'New message',
  };
  return bodies[type] || 'Tap to open';
}

function getChannelForType(type) {
  const channels = {
    new_order: 'new_order_channel',
    order: 'order_notifications',
    order_update: 'order_status',
    prep_time_reminder: 'prep_reminders',
    food_ready: 'order_notifications',
    order_reassigned: 'order_reassigned',
    order_assignment: 'order_notifications',
    chat_message: 'chat_messages',
    admin_driver_chat: 'chat_messages',
  };
  return channels[type] || 'default_notifications';
}

/**
 * Build FCM message payload with actions for interactive notifications.
 * @param {object} orderData - Order/vendor data for titles/bodies
 * @param {string} type - Notification type (new_order, prep_time_reminder, etc.)
 * @param {object} options - { token?, tokens?, includeActions, priority, category }
 * @returns {object} FCM message suitable for getMessaging().send() or sendEachForMulticast()
 */
function buildOrderNotification(orderData, type, options = {}) {
  const {
    includeActions = true,
    priority = 'high',
    category = 'order_notification',
    token,
    tokens,
  } = options;

  const orderId = String(orderData?.id || orderData?.orderId || '');
  const notificationId = `${type}_${orderId}_${Date.now()}`;
  const actions = includeActions ? getActionsForType(type, orderData) : [];

  const baseData = {
    type,
    orderId,
    targetId: orderId,
    notificationId,
    sentAt: new Date().toISOString(),
  };

  if (orderData?.totalAmount != null) baseData.orderAmount = String(orderData.totalAmount);
  const vendor = orderData?.vendor || {};
  if (vendor.title) baseData.restaurantName = String(vendor.title);
  const author = orderData?.author || {};
  if (author.firstName) baseData.customerName = String(author.firstName);
  if (orderData?.minutesLeft != null) baseData.minutesLeft = String(orderData.minutesLeft);

  if (includeActions && actions.length > 0) {
    baseData.action = type;
    baseData.actions = JSON.stringify(actions);
  }

  Object.keys(baseData).forEach((k) => {
    baseData[k] = String(baseData[k]);
  });

  const message = {
    notification: {
      title: getTitle(type, orderData),
      body: getBody(type, orderData),
    },
    data: baseData,
    android: {
      priority,
      notification: {
        channelId: getChannelForType(type),
        sound: 'default',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          category,
        },
      },
      headers: {
        'apns-priority': '10',
      },
    },
  };

  if (token) message.token = token;
  if (tokens && Array.isArray(tokens)) message.tokens = tokens;

  return message;
}

module.exports = {
  buildOrderNotification,
  getActionsForType,
  getTitle,
  getBody,
  getChannelForType,
};
