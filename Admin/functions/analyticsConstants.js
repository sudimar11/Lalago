/**
 * Unified analytics constants for Ash across all Lalago apps.
 * Ensures consistency between Cloud Functions and client apps.
 */
const ANALYTICS = {
  COLLECTIONS: {
    NOTIFICATION_HISTORY: 'ash_notification_history',
    NOTIFICATION_ACTIONS: 'notification_actions',
    NOTIFICATION_AGGREGATES: 'notification_aggregates',
    ACTION_ANALYTICS: 'action_analytics',
    USER_ENGAGEMENT: 'user_engagement',
    CONVERSIONS: 'conversion_events',
    FUNNEL_STEPS: 'funnel_steps',
    LTV: 'customer_ltv',
    SEGMENT_METRICS: 'segment_metrics',
    AB_TEST_RESULTS: 'ab_test_results',
    DAILY_SNAPSHOTS: 'daily_analytics_snapshots',
    RESTAURANT_METRICS: 'restaurant_daily_metrics',
    DRIVER_METRICS: 'driver_daily_metrics',
    USER_DAILY_METRICS: 'user_daily_metrics',
    REVENUE_DAILY_METRICS: 'revenue_daily_metrics',
    LTV_AGGREGATES: 'ltv_aggregates',
    WEEKLY_REPORTS: 'weekly_reports',
  },

  EVENT_TYPES: {
    NOTIFICATION_SENT: 'notification_sent',
    NOTIFICATION_OPENED: 'notification_opened',
    NOTIFICATION_ACTION: 'notification_action',
    CART_ADD: 'cart_add',
    CART_VIEW: 'cart_view',
    CHECKOUT_START: 'checkout_start',
    CHECKOUT_COMPLETE: 'checkout_complete',
    ORDER_PLACED: 'order_placed',
    ORDER_COMPLETED: 'order_completed',
    ORDER_FAILED: 'order_failed',
    RECOVERY_ATTEMPT: 'recovery_attempt',
    RECOVERY_SUCCESS: 'recovery_success',
    RECOMMENDATION_CLICK: 'recommendation_click',
    RECOMMENDATION_CONVERT: 'recommendation_convert',
    SEARCH_QUERY: 'search_query',
    SEARCH_CLICK: 'search_click',
    APP_OPEN: 'app_open',
    APP_BACKGROUND: 'app_background',
  },

  SEGMENTS: {
    POWER_USER: 'power_user',
    REGULAR: 'regular',
    ACTIVE: 'active',
    NEW: 'new',
    INACTIVE: 'inactive',
    AT_RISK: 'at_risk',
    CHURNED: 'churned',
  },

  FUNNEL_STAGES: {
    CART_VIEW: 'cart_view',
    CHECKOUT_START: 'checkout_start',
    PAYMENT_SELECT: 'payment_select',
    ORDER_PLACE: 'order_place',
    ORDER_COMPLETE: 'order_complete',
  },

  TIME_RANGES: {
    TODAY: 'today',
    YESTERDAY: 'yesterday',
    LAST_7_DAYS: 'last_7_days',
    LAST_30_DAYS: 'last_30_days',
    LAST_90_DAYS: 'last_90_days',
    THIS_MONTH: 'this_month',
    LAST_MONTH: 'last_month',
  },

  COMPLETED_ORDER_STATUSES: [
    'Order Completed',
    'order completed',
    'completed',
    'Completed',
  ],
};

module.exports = ANALYTICS;
